-- src/server/Services/InventoryService.luau
local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local PlotService = require(script.Parent.PlotService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))
local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChestConfig"))
local CombatService = require(script.Parent.CombatService)
local EquipmentService = require(script.Parent.EquipmentService)
local pendingGiftRequests = {}
local playerPendingGiftRequest = {}
local nextGiftRequestId = 0
local chestOpenLocks = setmetatable({}, { __mode = "k" })
local chestIAPIntents = setmetatable({}, { __mode = "k" })
local chestRng = Random.new()
local CHEST_IAP_INTENT_TTL = 300
local POTION_MUTATION_CHANCE = 0.15
local POTION_INTERACTION_MAX_DISTANCE = 35
local POTION_MUTATION_ANIMATION_SECONDS = 2.1
local potionUseLocks = setmetatable({}, { __mode = "k" })

-- 判断是否是南瓜保护罩类覆盖植物。
local function isPumpkinShieldPlant(plantId)
    local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
    return plantDetail and plantDetail.IsPumpkinShield == true
end

-- 通过配置里的模型名查找植物模型，兼容配置 ID 和资源命名不一致的植物。
local function findPlantModelTemplate(itemModelsFolder, plantId, plantDetail)
    if not itemModelsFolder then
        return nil
    end

    local modelName = (plantDetail and plantDetail.ModelName) or plantId
    return itemModelsFolder:FindFirstChild(modelName .. "_Plant")
        or itemModelsFolder:FindFirstChild(modelName)
        or itemModelsFolder:FindFirstChild(plantId .. "_Plant")
        or itemModelsFolder:FindFirstChild(plantId)
end

local function getDisplayItemName(itemType, realId)
    if itemType == "Seed" then
        local seedConfig = ItemConfig.Seeds[realId]
        return seedConfig and (seedConfig.Name or realId)
    elseif itemType == "Plant" then
        local plantConfig = ItemConfig.Plants[realId]
        return plantConfig and (plantConfig.Name or realId)
    end

    return nil
end

local function GetCombatEditCost(player)
    local plot = PlotService.GetPlayerPlot(player)
    local currentLevel = plot and plot:GetAttribute("CurrentLevel") or 1
    currentLevel = math.max(1, tonumber(currentLevel) or 1)
    return 100 + (currentLevel - 1) * 100
end

local function clearGiftRequest(requestId)
    local requestData = pendingGiftRequests[requestId]
    if not requestData then return nil end

    if playerPendingGiftRequest[requestData.sender] == requestId then
        playerPendingGiftRequest[requestData.sender] = nil
    end
    if playerPendingGiftRequest[requestData.target] == requestId then
        playerPendingGiftRequest[requestData.target] = nil
    end

    pendingGiftRequests[requestId] = nil
    return requestData
end

local function saveGiftTransferPlayer(player, context)
    local saved, saveErr = PlayerDataManager.ForceSave(player)
    if not saved and saveErr ~= "stale_session" then
        warn("[InventoryService] Failed to save gift transfer for " .. player.Name .. " after " .. tostring(context) .. ": " .. tostring(saveErr))
    end

    return saved, saveErr
end

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function snapshotGiftState(data)
    if type(data) ~= "table" then
        return nil
    end

    return {
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function snapshotInventoryTransactionState(data)
    if type(data) ~= "table" then
        return nil
    end

    return {
        Coins = data.Coins,
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function restoreGiftState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function restoreInventoryTransactionState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data.Coins = snapshot.Coins
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function saveInventoryTransaction(player, data, snapshot, context)
    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, context)
    if saveQueued then
        return true
    end

    warn("[InventoryService] Failed to queue save after " .. tostring(context) .. " for "
        .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))

    restoreInventoryTransactionState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = PlayerDataManager.RequestSave(player, "rollback " .. tostring(context))
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[InventoryService] Failed to queue rollback save after " .. tostring(context) .. " for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end

    return false, saveErr
end

local function rollbackGiftTransfer(sender, targetPlayer, senderData, receiverData, senderSnapshot, receiverSnapshot, requestId)
    restoreGiftState(senderData, senderSnapshot)
    restoreGiftState(receiverData, receiverSnapshot)
    fireInventoryUpdate(sender, senderData)
    fireInventoryUpdate(targetPlayer, receiverData)

    local senderRollbackSaved, senderRollbackErr = saveGiftTransferPlayer(sender, "gift sender rollback")
    local receiverRollbackSaved, receiverRollbackErr = saveGiftTransferPlayer(targetPlayer, "gift receiver rollback")

    if not (senderRollbackSaved and receiverRollbackSaved) then
        warn("[InventoryService] Gift rollback save failed for request " .. tostring(requestId)
            .. ": senderRollbackSaved=" .. tostring(senderRollbackSaved)
            .. ", senderRollbackErr=" .. tostring(senderRollbackErr)
            .. ", receiverRollbackSaved=" .. tostring(receiverRollbackSaved)
            .. ", receiverRollbackErr=" .. tostring(receiverRollbackErr))
    end
end


local function CleanUpGhostItems(data)
    if not data or not data.Hotbar then return false end
    local validHotbar = {}
    local changed = false

    for _, compositeId in ipairs(data.Hotbar) do
        local parts = string.split(compositeId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1

        local isValid = false
        if itemType == "Tool" or itemType == "System" then
            isValid = true
        elseif itemType == "Seed" and data.Inventory.Seeds then
            for _, seedData in ipairs(data.Inventory.Seeds) do
                if seedData.ID == realId and seedData.Quantity > 0 then
                    isValid = true; break
                end
            end
        elseif itemType == "Plant" and data.Inventory.Plants then
            for _, plantData in ipairs(data.Inventory.Plants) do
                if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl and plantData.Quantity > 0 then
                    isValid = true; break
                end
            end
        elseif itemType == "Chest" and data.Inventory.Chests then
            for _, chestData in ipairs(data.Inventory.Chests) do
                if chestData.ID == realId and chestData.Quantity > 0 then
                    isValid = true; break
                end
            end
        elseif itemType == "Item" and data.Inventory.Items then
            for _, itemData in ipairs(data.Inventory.Items) do
                if itemData.ID == realId and itemData.Quantity > 0 then
                    isValid = true; break
                end
            end
        end

        if isValid then
            table.insert(validHotbar, compositeId)
        else
            changed = true
        end
    end

    if changed then
        data.Hotbar = validHotbar
    end
    return changed
end

local function playerHasChest(data, chestId)
    if not data or not data.Inventory or not data.Inventory.Chests then
        return false
    end

    for _, chestData in ipairs(data.Inventory.Chests) do
        if chestData.ID == chestId and (tonumber(chestData.Quantity) or 0) > 0 then
            return true
        end
    end

    return false
end

local function getEquippedChestId(player)
    local character = player and player.Character
    local equippedId = character and character:GetAttribute("EquippedSeed")
    if type(equippedId) == "string" and string.sub(equippedId, 1, 6) == "Chest_" then
        return string.sub(equippedId, 7)
    end

    return nil
end

local function findFirstOwnedChest(data)
    if not data or not data.Inventory or not data.Inventory.Chests then
        return nil
    end

    for _, chestData in ipairs(data.Inventory.Chests) do
        if type(chestData.ID) == "string" and (tonumber(chestData.Quantity) or 0) > 0 then
            return chestData.ID
        end
    end

    return nil
end

local function getEquippedItemId(player)
    local character = player and player.Character
    local equippedId = character and character:GetAttribute("EquippedSeed")
    if type(equippedId) == "string" and string.sub(equippedId, 1, 5) == "Item_" then
        return string.sub(equippedId, 6)
    end

    return nil
end

local function getPlantSeedId(plantId, preferredSeedId)
    if type(preferredSeedId) == "string" then
        local preferredSeed = ItemConfig.Seeds and ItemConfig.Seeds[preferredSeedId]
        if preferredSeed and preferredSeed.YieldPlant == plantId then
            return preferredSeedId
        end
    end

    if type(plantId) ~= "string" or not ItemConfig.Seeds then
        return nil
    end

    for seedId, seedConfig in pairs(ItemConfig.Seeds) do
        if seedConfig and seedConfig.YieldPlant == plantId then
            return seedId
        end
    end

    return nil
end

local function getInstancePosition(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end

    if instance:IsA("Model") then
        local ok, pivot = pcall(function()
            return instance:GetPivot()
        end)
        if ok and typeof(pivot) == "CFrame" then
            return pivot.Position
        end

        local part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    elseif instance:IsA("BasePart") then
        return instance.Position
    end

    return nil
end

local function getPotionTargetInfo(player, targetPlant)
    if typeof(targetPlant) ~= "Instance" or not targetPlant:IsA("Model") or not targetPlant.Parent then
        return nil, "Move near a plant and press F to use this potion."
    end

    local plot = PlotService.GetPlayerPlot(player)
    if not plot or not targetPlant:IsDescendantOf(plot) then
        return nil, "Use potions on your own plants."
    end

    local character = player.Character
    local characterRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    local targetPosition = getInstancePosition(targetPlant)
    if not characterRoot or not targetPosition then
        return nil, "Move closer to the plant."
    end

    if (characterRoot.Position - targetPosition).Magnitude > POTION_INTERACTION_MAX_DISTANCE then
        return nil, "Move closer to the plant."
    end

    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return nil, "Data is still loading."
    end

    if targetPlant:GetAttribute("IsCombatPlant") then
        local lawnPart = targetPlant.Parent
        local gridName = targetPlant:GetAttribute("GridName") or (lawnPart and lawnPart.Name)
        if type(gridName) ~= "string" then
            return nil, "This plant cannot mutate."
        end
        local combatInfo = gridName and data.CombatPlants and data.CombatPlants[gridName]
        if not combatInfo then
            return nil, "This plant cannot mutate right now."
        end
        local isPumpkinShield = targetPlant:GetAttribute("IsPumpkinShield") == true
        local plantId = if isPumpkinShield
            then (targetPlant:GetAttribute("PlantId") or targetPlant.Name)
            else ((combatInfo and combatInfo.PlantId) or targetPlant.Name)
        local plantConfig = ItemConfig.Plants and ItemConfig.Plants[plantId]
        if plantConfig and plantConfig.NoMutation == true then
            return nil, "This plant cannot mutate."
        end

        local seedId = getPlantSeedId(plantId)

        if not seedId then
            return nil, "This plant has no seed and cannot mutate."
        end

        return {
            Kind = "Combat",
            Target = targetPlant,
            GridName = gridName,
            PlantId = plantId,
            SeedId = seedId,
            CurrentMutation = if isPumpkinShield
                then (tonumber(targetPlant:GetAttribute("MutationLevel")) or 1)
                else (tonumber(combatInfo and combatInfo.Mutation) or tonumber(targetPlant:GetAttribute("MutationLevel")) or 1),
        }
    end

    local soilName = targetPlant:GetAttribute("PlantedOn")
    if soilName then
        local plantedInfo = data.PlantedPlants and data.PlantedPlants[soilName]
        if not plantedInfo then
            return nil, "This plant cannot mutate right now."
        end
        local savedSeedId = plantedInfo and plantedInfo.SeedId
        local savedSeedConfig = savedSeedId and ItemConfig.Seeds and ItemConfig.Seeds[savedSeedId]
        local plantId = savedSeedConfig and savedSeedConfig.YieldPlant
            or targetPlant:GetAttribute("YieldPlant")
            or string.gsub(targetPlant.Name, "_Plant$", "")
        local seedId = getPlantSeedId(plantId, savedSeedId)

        if not seedId then
            return nil, "This plant has no seed and cannot mutate."
        end

        return {
            Kind = "Planted",
            Target = targetPlant,
            SoilName = soilName,
            PlantId = plantId,
            SeedId = seedId,
            CurrentMutation = tonumber(plantedInfo and plantedInfo.Mutation) or tonumber(targetPlant:GetAttribute("MutationLevel")) or 1,
        }
    end

    return nil, "This plant cannot mutate."
end

local function updatePlantMutationDisplay(targetPlant, mutationLevel)
    local statusLabel = targetPlant and targetPlant:FindFirstChild("StatusLabel", true)
    if not statusLabel or not statusLabel:IsA("TextLabel") then
        return
    end

    local mutationName = ItemConfig.MutationName and ItemConfig.MutationName[mutationLevel] or ""
    statusLabel.Text = (mutationLevel > 1 and mutationName ~= "") and mutationName or "Loading..."
end

local function applyPotionMutation(player, targetInfo, mutationLevel)
    local targetPlant = targetInfo and targetInfo.Target
    if not targetPlant or not targetPlant.Parent then
        return false, "Mutation failed: plant is gone."
    end

    local targetPlantConfig = ItemConfig.Plants and ItemConfig.Plants[targetInfo.PlantId]
    if targetPlantConfig and targetPlantConfig.NoMutation == true then
        return false, "This plant cannot mutate."
    end

    targetPlant:SetAttribute("MutationLevel", mutationLevel)
    EffectUtil.ApplyMutationEffects(targetPlant, mutationLevel)
    updatePlantMutationDisplay(targetPlant, mutationLevel)

    if targetInfo.Kind == "Combat" then
        local plantConfig = ItemConfig.Plants and ItemConfig.Plants[targetInfo.PlantId]
        local stats = ItemConfig.MutationStats and (ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1])
        if plantConfig and stats then
            local oldMaxHP = math.max(1, tonumber(targetPlant:GetAttribute("MaxHealth")) or tonumber(plantConfig.HP) or 300)
            local oldHP = math.max(0, tonumber(targetPlant:GetAttribute("Health")) or oldMaxHP)
            local hpRatio = math.clamp(oldHP / oldMaxHP, 0, 1)
            local newMaxHP = math.max(1, math.floor((tonumber(plantConfig.HP) or 300) * (tonumber(stats.HealthMul) or 1)))
            targetPlant:SetAttribute("MaxHealth", newMaxHP)
            targetPlant:SetAttribute("Health", math.max(1, math.floor(newMaxHP * hpRatio)))
        end

        PlayerDataManager.UpdateCombatPlantMutation(player, targetInfo.GridName, mutationLevel)
    elseif targetInfo.Kind == "Planted" then
        PlayerDataManager.UpdatePlantedPlantMutation(player, targetInfo.SoilName, mutationLevel)
    else
        return false, "This plant cannot mutate."
    end

    PlayerDataManager.UnlockMutation(player, targetInfo.PlantId, mutationLevel, true)
    return true
end

local function openChestInternal(player, chestId, options)
    options = options or {}

    if type(chestId) ~= "string" then
        return false, "Invalid chest."
    end

    local chestConfig = ChestConfig.GetChest(chestId)
    if not chestConfig then
        return false, "Unknown chest."
    end

    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading."
    end

    local shouldSaveImmediately = options.SkipImmediateSave ~= true
    local snapshot = nil
    if shouldSaveImmediately then
        if not PlayerDataManager.IsDataSafeToSave(player) then
            return false, "Save unavailable. Please try again."
        end
        snapshot = snapshotInventoryTransactionState(data)
    end

    if not playerHasChest(data, chestId) then
        return false, "You do not have this chest."
    end

    if options.RequireEquipped and getEquippedChestId(player) ~= chestId then
        return false, "Please hold this chest first."
    end

    local price = math.max(0, math.floor(tonumber(chestConfig.Price) or 0))
    if not options.SkipCoinCost and (tonumber(data.Coins) or 0) < price then
        return false, "Not enough Sun."
    end

    local rewardPlantId, mutationLevel = ChestConfig.RollReward(chestId, chestRng)
    mutationLevel = tonumber(mutationLevel) or 1
    if not rewardPlantId or not ItemConfig.Plants[rewardPlantId] then
        return false, "Chest reward is not configured."
    end

    local previousChestId = getEquippedChestId(player)
    local consumed = PlayerDataManager.ConsumeChest(player, chestId, 1)
    if not consumed then
        return false, "You do not have this chest."
    end

    if not options.SkipCoinCost then
        local spent = PlayerDataManager.ConsumeCoins(player, price)
        if not spent then
            PlayerDataManager.GiveChest(player, chestId, 1, false)
            return false, "Not enough Sun."
        end
    end

    PlayerDataManager.GivePlant(player, rewardPlantId, 1, mutationLevel, true)
    EquipmentService.UpdateHoldItem(player, nil)

    if shouldSaveImmediately then
        local saved = saveInventoryTransaction(player, data, snapshot, "chest open")
        if not saved then
            if previousChestId and playerHasChest(data, previousChestId) then
                EquipmentService.UpdateHoldItem(player, "Chest_" .. previousChestId)
            end
            return false, "Save failed. Please try again."
        end
    end

    return true, {
        ChestId = chestId,
        Price = price,
        RewardPlantId = rewardPlantId,
        MutationLevel = mutationLevel,
        PaidByIAP = options.SkipCoinCost == true,
    }
end

function InventoryService.OpenChestWithSun(player, chestId)
    return openChestInternal(player, chestId, {
        RequireEquipped = true,
        SkipCoinCost = false,
    })
end

function InventoryService.PrepareChestIAPPurchase(player, chestId)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading."
    end

    if type(chestId) ~= "string" or not ChestConfig.GetChest(chestId) then
        return false, "Unknown chest."
    end

    if not playerHasChest(data, chestId) then
        return false, "You do not have this chest."
    end

    if getEquippedChestId(player) ~= chestId then
        return false, "Please hold this chest first."
    end

    chestIAPIntents[player] = {
        ChestId = chestId,
        CreatedAt = os.clock(),
    }

    return true
end

function InventoryService.CompletePreparedChestIAPPurchase(player)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading.", "Retry"
    end

    if chestOpenLocks[player] then
        return false, "Please wait.", "Retry"
    end

    local chestId = nil
    local intent = chestIAPIntents[player]
    if intent and os.clock() - (tonumber(intent.CreatedAt) or 0) <= CHEST_IAP_INTENT_TTL then
        chestId = intent.ChestId
    end

    if not chestId or not playerHasChest(data, chestId) then
        chestId = getEquippedChestId(player)
    end

    if not chestId or not playerHasChest(data, chestId) then
        chestId = findFirstOwnedChest(data)
    end

    if not chestId then
        return false, "No chest is available.", "Retry"
    end

    chestOpenLocks[player] = true
    local ok, success, result = pcall(openChestInternal, player, chestId, {
        RequireEquipped = false,
        SkipCoinCost = true,
        SkipImmediateSave = true,
    })
    chestOpenLocks[player] = nil

    if not ok then
        warn("[InventoryService] Chest IAP open failed: " .. tostring(success))
        return false, "Chest opening failed.", "Retry"
    end

    if success then
        chestIAPIntents[player] = nil
        return true, result
    end

    return false, result, "Retry"
end

function InventoryService.Init()
    local equipItemRE = Instance.new("RemoteEvent")
    equipItemRE.Name = "EquipItemRE"
    equipItemRE.Parent = ReplicatedStorage

    local giftItemRE = ReplicatedStorage:FindFirstChild("GiftItemRE") or Instance.new("RemoteEvent")
    giftItemRE.Name = "GiftItemRE"
    giftItemRE.Parent = ReplicatedStorage

    local forceSelectRE = Instance.new("RemoteEvent")
    forceSelectRE.Name = "ForceSelectRE"
    forceSelectRE.Parent = ReplicatedStorage

    local removeHotbarRE = Instance.new("RemoteEvent")
    removeHotbarRE.Name = "RemoveHotbarRE"
    removeHotbarRE.Parent = ReplicatedStorage

    local usePotionRE = ReplicatedStorage:FindFirstChild("UsePotionRE") or Instance.new("RemoteEvent")
    usePotionRE.Name = "UsePotionRE"
    usePotionRE.Parent = ReplicatedStorage

    local prepareChestIAPPurchaseRE = ReplicatedStorage:FindFirstChild("PrepareChestIAPPurchaseRE") or Instance.new("RemoteEvent")
    prepareChestIAPPurchaseRE.Name = "PrepareChestIAPPurchaseRE"
    prepareChestIAPPurchaseRE.Parent = ReplicatedStorage
    prepareChestIAPPurchaseRE.OnServerEvent:Connect(function(player, chestId)
        InventoryService.PrepareChestIAPPurchase(player, chestId)
    end)

    local chestIAPOpenResultRE = ReplicatedStorage:FindFirstChild("ChestIAPOpenResultRE") or Instance.new("RemoteEvent")
    chestIAPOpenResultRE.Name = "ChestIAPOpenResultRE"
    chestIAPOpenResultRE.Parent = ReplicatedStorage

    local useChestRF = ReplicatedStorage:FindFirstChild("UseChestRF") or Instance.new("RemoteFunction")
    useChestRF.Name = "UseChestRF"
    useChestRF.Parent = ReplicatedStorage
    useChestRF.OnServerInvoke = function(player, chestId)
        if chestOpenLocks[player] then
            return false, "Please wait."
        end

        chestOpenLocks[player] = true
        local ok, success, result = pcall(InventoryService.OpenChestWithSun, player, chestId)
        chestOpenLocks[player] = nil

        if not ok then
            warn("[InventoryService] UseChestRF failed: " .. tostring(success))
            return false, "Chest opening failed."
        end

        return success, result
    end

    -- 战斗植物交换引擎 (E键)
    local swapCombatPlantRE = Instance.new("RemoteEvent")
    swapCombatPlantRE.Name = "SwapCombatPlantRE"
    swapCombatPlantRE.Parent = ReplicatedStorage

    local placePumpkinShieldRE = Instance.new("RemoteEvent")
    placePumpkinShieldRE.Name = "PlacePumpkinShieldRE"
    placePumpkinShieldRE.Parent = ReplicatedStorage

    -- 给已有战斗植物加南瓜保护罩，不替换原植物。
    placePumpkinShieldRE.OnServerEvent:Connect(function(player, targetPlantModel, equippedCompositeId, isCombatEdit)
        if not targetPlantModel or not targetPlantModel.Parent then return end
        if type(equippedCompositeId) ~= "string" then return end
        if not targetPlantModel:GetAttribute("IsCombatPlant") then return end
        if targetPlantModel:GetAttribute("IsPumpkinShield") == true then return end
        if targetPlantModel:GetAttribute("IsDead") == true or (tonumber(targetPlantModel:GetAttribute("Health")) or 0) <= 0 then return end

        local parts = string.split(equippedCompositeId, "_")
        if parts[1] ~= "Plant" then return end

        local shieldPlantId = parts[2]
        local shieldMutation = 1
        local shieldConfig = ItemConfig.Plants[shieldPlantId]
        if not (shieldConfig and isPumpkinShieldPlant(shieldPlantId)) then return end

        local gridPart = targetPlantModel.Parent
        if not gridPart or not gridPart:IsA("BasePart") then return end

        local myPlot = PlotService.GetPlayerPlot(player)
        local lawnFolder = myPlot and myPlot:FindFirstChild("Lawn")
        if not myPlot or not lawnFolder or gridPart.Parent ~= lawnFolder then return end
        if gridPart:GetAttribute("PumpkinShield") then return end

        local targetPlantId = targetPlantModel:GetAttribute("PlantId") or targetPlantModel.Name
        local targetPlantConfig = ItemConfig.Plants[targetPlantId]
        if targetPlantConfig and targetPlantConfig.DisallowPumpkinShield == true then
            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
            if showNotifRE then
                showNotifRE:FireClient(player, "Notice", "Pumpkin Shield cannot cover this plant.")
            end
            return
        end

        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

        local gridName = gridPart.Name
        local combatInfo = data.CombatPlants and data.CombatPlants[gridName]
        if not (combatInfo and combatInfo.PlantId == targetPlantId) then return end

        local hasShieldPlant = false
        local inventoryPlants = data.Inventory and data.Inventory.Plants
        if type(inventoryPlants) == "table" then
            for _, plantData in ipairs(inventoryPlants) do
                if plantData.ID == shieldPlantId and (tonumber(plantData.Mutation) or 1) == shieldMutation and (tonumber(plantData.Quantity) or 0) > 0 then
                    hasShieldPlant = true
                    break
                end
            end
        end
        if not hasShieldPlant then return end

        local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
        local shieldTemplate = findPlantModelTemplate(itemModelsFolder, shieldPlantId, shieldConfig)
        if not shieldTemplate then return end

        if myPlot:GetAttribute("IsLevelActive") then
            if not isCombatEdit then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then
                    showNotifRE:FireClient(player, "Notice", "Cannot add Pumpkin Shield during combat!")
                end
                return
            end

            local cost = GetCombatEditCost(player)
            if not PlayerDataManager.ConsumeCoins(player, cost) then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then
                    showNotifRE:FireClient(player, "Notice", "Not enough Sun! Need " .. tostring(cost) .. " Sun.")
                end
                return
            end
        end

        if not PlayerDataManager.ConsumePlant(player, shieldPlantId, 1, shieldMutation) then return end

        local maxHP = math.max(1, math.floor(tonumber(shieldConfig.HP) or 300))
        local shieldModel = CombatService.SpawnCombatPlant(gridPart, shieldPlantId, maxHP, maxHP, shieldMutation, {
            AsPumpkinShield = true,
        })
        if not shieldModel then
            PlayerDataManager.GivePlant(player, shieldPlantId, 1, shieldMutation, true)
            return
        end

        PlayerDataManager.AddCombatPumpkinShield(player, gridName, shieldPlantId, maxHP, shieldMutation)
    end)

    -- 接受 isCombatSwap 参数判定是否需要扣钱
    swapCombatPlantRE.OnServerEvent:Connect(function(player, oldPlantModel, equippedCompositeId, isCombatSwap)
        if not oldPlantModel or not oldPlantModel.Parent then return end
        if type(equippedCompositeId) ~= "string" then return end
        if not oldPlantModel:GetAttribute("IsCombatPlant") then return end
        if oldPlantModel:GetAttribute("IsPumpkinShield") == true then return end

        local parts = string.split(equippedCompositeId, "_")
        if parts[1] ~= "Plant" then return end

        local newPlantId = parts[2]
        local newMutLevel = tonumber(parts[3]) or 1
        local newPlantConfig = ItemConfig.Plants[newPlantId]
        if not newPlantConfig or newPlantConfig.IsThrowable or newPlantConfig.IsPumpkinShield == true then return end

        local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
        local newTemplate = findPlantModelTemplate(itemModelsFolder, newPlantId, newPlantConfig)
        if not newTemplate then return end

        local gridPart = oldPlantModel.Parent
        if not gridPart or not gridPart:IsA("BasePart") then return end

        local myPlot = PlotService.GetPlayerPlot(player)
        local lawnFolder = myPlot and myPlot:FindFirstChild("Lawn")
        if not myPlot or not lawnFolder or gridPart.Parent ~= lawnFolder then return end
        if gridPart:GetAttribute("PumpkinShield") and newPlantConfig.DisallowPumpkinShield == true then
            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
            if showNotifRE then
                showNotifRE:FireClient(player, "Notice", "Pumpkin Shield cannot cover this plant.")
            end
            return
        end

        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

        local gridName = gridPart.Name
        local combatInfo = data.CombatPlants and data.CombatPlants[gridName]
        if not combatInfo then return end
        if gridPart:GetAttribute("OccupiedBy") ~= oldPlantModel.Name then return end

        local oldPlantId = combatInfo.PlantId or oldPlantModel.Name
        local oldMutLevel = combatInfo.Mutation or oldPlantModel:GetAttribute("MutationLevel") or 1
        if oldPlantModel.Name ~= oldPlantId then return end

        -- Step 1: 按铲除/回收规则处理旧战斗植物
        if myPlot:GetAttribute("IsLevelActive") then
            if not isCombatSwap then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then
                    showNotifRE:FireClient(player, "Notice", "Cannot replace plants during combat!")
                end
                return
            end

            local cost = GetCombatEditCost(player)
            if not PlayerDataManager.ConsumeCoins(player, cost) then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then
                    showNotifRE:FireClient(player, "Notice", "Not enough Sun! Need " .. tostring(cost) .. " Sun.")
                end
                return
            end
        end

        PlayerDataManager.GivePlant(player, oldPlantId, 1, oldMutLevel)
        PlayerDataManager.RemoveCombatPlant(player, gridName)
        local hasPumpkinShield = gridPart:GetAttribute("PumpkinShield") ~= nil
        gridPart:SetAttribute("OccupiedBy", hasPumpkinShield and "PumpkinShield" or nil)
        local prompt = gridPart:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Enabled = true end
        oldPlantModel:Destroy()

        -- Step 2: 按普通部署规则消耗手中新植物并统一生成
        if not PlayerDataManager.ConsumePlant(player, newPlantId, 1, newMutLevel) then return end

        local baseMaxHP = newPlantConfig.HP or 300
        local stats = ItemConfig.MutationStats[newMutLevel] or ItemConfig.MutationStats[1]
        local maxHP = math.floor(baseMaxHP * stats.HealthMul)
        local newPlant = CombatService.SpawnCombatPlant(gridPart, newPlantId, maxHP, maxHP, newMutLevel)
        if not newPlant then return end

        PlayerDataManager.AddCombatPlant(player, gridName, newPlantId, maxHP, newMutLevel)
    end)


    removeHotbarRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if data and data.Hotbar then
            local found = false
            for i, id in ipairs(data.Hotbar) do
                if id == compositeId then
                    table.remove(data.Hotbar, i)
                    found = true
                    break
                end
            end
            if CleanUpGhostItems(data) or found then
                ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
            end
        end
    end)

    usePotionRE.OnServerEvent:Connect(function(player, itemId, targetPlant)
        if type(itemId) ~= "string" or itemId == "" then
            usePotionRE:FireClient(player, false, "Invalid potion.")
            return
        end

        if potionUseLocks[player] then
            usePotionRE:FireClient(player, false, "Potion is already working.")
            return
        end

        local itemDetail = ItemConfig.Items and ItemConfig.Items[itemId]
        if not itemDetail or itemDetail.ItemType ~= "MutationPotion" then
            usePotionRE:FireClient(player, false, "This item cannot be used.")
            return
        end

        if getEquippedItemId(player) ~= itemId then
            usePotionRE:FireClient(player, false, "Please hold this potion first.")
            return
        end

        local targetInfo, targetMessage = getPotionTargetInfo(player, targetPlant)
        if not targetInfo then
            usePotionRE:FireClient(player, false, targetMessage or "Select a plant first.")
            return
        end
        local targetPlantConfig = ItemConfig.Plants and ItemConfig.Plants[targetInfo.PlantId]
        if targetPlantConfig and targetPlantConfig.NoMutation == true then
            usePotionRE:FireClient(player, false, "This plant cannot mutate.")
            return
        end

        local mutationLevel = math.max(1, math.floor(tonumber(itemDetail.MutationLevel) or 1))
        if mutationLevel <= 1 then
            usePotionRE:FireClient(player, false, "This potion has no mutation.")
            return
        end

        if tonumber(targetInfo.CurrentMutation) == mutationLevel then
            usePotionRE:FireClient(player, false, "This plant already has this mutation.")
            return
        end

        if not PlayerDataManager.ConsumeItem(player, itemId, 1) then
            usePotionRE:FireClient(player, false, "You do not have this potion.")
            return
        end

        potionUseLocks[player] = true
        local willMutate = math.random() < POTION_MUTATION_CHANCE
        usePotionRE:FireClient(player, "AnimatePotionMutation", {
            Target = targetInfo.Target,
            SeedId = targetInfo.SeedId,
            PlantId = targetInfo.PlantId,
            DurationSeconds = POTION_MUTATION_ANIMATION_SECONDS,
        })
        usePotionRE:FireClient(player, false, "Potion used.")

        task.delay(POTION_MUTATION_ANIMATION_SECONDS, function()
            potionUseLocks[player] = nil
            if not player or not player.Parent then
                return
            end

            if not willMutate then
                usePotionRE:FireClient(player, false, "Mutation failed.")
                return
            end

            local success, message = applyPotionMutation(player, targetInfo, mutationLevel)
            if success then
                usePotionRE:FireClient(player, true, "Mutation succeeded!")
            else
                usePotionRE:FireClient(player, false, message or "Mutation failed.")
            end
        end)
    end)

    giftItemRE.OnServerEvent:Connect(function(player, action, arg1, arg2)
        local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")

        if action == "CreateRequest" then
            local targetPlayer = arg1
            local compositeId = arg2

            if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then return end
            if targetPlayer == player then return end
            if type(compositeId) ~= "string" or compositeId == "" then return end
            if playerPendingGiftRequest[player] or playerPendingGiftRequest[targetPlayer] then
                if showTipRE then
                    showTipRE:FireClient(player, "Gift request is busy right now")
                end
                giftItemRE:FireClient(player, "ClosePopup", nil, "Gift request is busy right now")
                return
            end

            local senderData = PlayerDataManager.GetPlayerData(player)
            local receiverData = PlayerDataManager.GetPlayerData(targetPlayer)
            if not senderData or not receiverData then
                giftItemRE:FireClient(player, "ClosePopup", nil, "Gift failed")
                return
            end

            local parts = string.split(compositeId, "_")
            local itemType = parts[1]
            local realId = parts[2]
            local mutLvl = tonumber(parts[3]) or 1
            local itemName = realId and getDisplayItemName(itemType, realId)

            if not realId or (itemType ~= "Seed" and itemType ~= "Plant") or not itemName then
                giftItemRE:FireClient(player, "ClosePopup", nil, "Gift failed")
                return
            end

            nextGiftRequestId += 1
            local requestId = tostring(nextGiftRequestId)
            pendingGiftRequests[requestId] = {
                sender = player,
                target = targetPlayer,
                compositeId = compositeId,
                itemType = itemType,
                realId = realId,
                mutLvl = mutLvl,
                itemName = itemName,
            }
            playerPendingGiftRequest[player] = requestId
            playerPendingGiftRequest[targetPlayer] = requestId

            giftItemRE:FireClient(player, "RequesterWaiting", requestId, targetPlayer.Name, itemName)
            giftItemRE:FireClient(targetPlayer, "ReceiveRequest", requestId, player.Name, itemName)
        elseif action == "CancelRequest" then
            local requestId = arg1
            local requestData = pendingGiftRequests[requestId]
            if not requestData or requestData.sender ~= player then return end

            clearGiftRequest(requestId)
            giftItemRE:FireClient(player, "ClosePopup", requestId, "Gift cancelled")
            giftItemRE:FireClient(requestData.target, "ClosePopup", requestId, "Gift cancelled")
        elseif action == "RespondRequest" then
            local requestId = arg1
            local accepted = arg2
            local requestData = pendingGiftRequests[requestId]
            if not requestData or requestData.target ~= player then return end

            if not accepted then
                clearGiftRequest(requestId)
                giftItemRE:FireClient(requestData.sender, "ClosePopup", requestId, "The other player declined the gift")
                giftItemRE:FireClient(player, "ClosePopup", requestId, "Gift declined")
                return
            end

            local sender = requestData.sender
            local targetPlayer = requestData.target
            local senderData = PlayerDataManager.GetPlayerData(sender)
            local receiverData = PlayerDataManager.GetPlayerData(targetPlayer)
            if not senderData or not receiverData then
                clearGiftRequest(requestId)
                giftItemRE:FireClient(sender, "ClosePopup", requestId, "Gift failed")
                giftItemRE:FireClient(targetPlayer, "ClosePopup", requestId, "Gift failed")
                return
            end
            if not PlayerDataManager.IsDataSafeToSave(sender) or not PlayerDataManager.IsDataSafeToSave(targetPlayer) then
                clearGiftRequest(requestId)
                giftItemRE:FireClient(sender, "ClosePopup", requestId, "Gift failed: save unavailable. Please try again later.")
                giftItemRE:FireClient(targetPlayer, "ClosePopup", requestId, "Gift failed: save unavailable.")
                return
            end

            local senderSnapshot = snapshotGiftState(senderData)
            local receiverSnapshot = snapshotGiftState(receiverData)

            local success = false
            if requestData.itemType == "Seed" then
                success = PlayerDataManager.ConsumeSeed(sender, requestData.realId, 1)
                if success then
                    PlayerDataManager.GiveSeed(targetPlayer, requestData.realId, 1, true)
                end
            else
                success = PlayerDataManager.ConsumePlant(sender, requestData.realId, 1, requestData.mutLvl)
                if success then
                    PlayerDataManager.GivePlant(targetPlayer, requestData.realId, 1, requestData.mutLvl)
                end
            end

            clearGiftRequest(requestId)

            if success then
                local senderSaved, senderSaveErr = saveGiftTransferPlayer(sender, "gift sender update")
                local receiverSaved, receiverSaveErr = saveGiftTransferPlayer(targetPlayer, "gift receiver update")

                if senderSaved and receiverSaved then
                    giftItemRE:FireClient(sender, "ClosePopup", requestId, "You gifted 1x " .. requestData.itemName .. " to " .. targetPlayer.Name)
                    giftItemRE:FireClient(targetPlayer, "ClosePopup", requestId, "You received 1x " .. requestData.itemName .. " from " .. sender.Name)
                else
                    warn("[InventoryService] Gift transfer save failed for request " .. tostring(requestId)
                        .. ": senderSaved=" .. tostring(senderSaved)
                        .. ", senderErr=" .. tostring(senderSaveErr)
                        .. ", receiverSaved=" .. tostring(receiverSaved)
                        .. ", receiverErr=" .. tostring(receiverSaveErr))
                    rollbackGiftTransfer(sender, targetPlayer, senderData, receiverData, senderSnapshot, receiverSnapshot, requestId)
                    giftItemRE:FireClient(sender, "ClosePopup", requestId, "Gift failed: save failed. Please try again later.")
                    giftItemRE:FireClient(targetPlayer, "ClosePopup", requestId, "Gift failed: save failed.")
                end
            else
                giftItemRE:FireClient(sender, "ClosePopup", requestId, "Gift failed: item not available")
                giftItemRE:FireClient(targetPlayer, "ClosePopup", requestId, "Gift failed")
            end
        end
    end)

    equipItemRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

        local cleaned = CleanUpGhostItems(data)
        if cleaned then
            ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
        end

        local parts = string.split(compositeId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1

        local hasItem = false
        if itemType == "Seed" then
            if data.Inventory.Seeds then
                for _, seedData in ipairs(data.Inventory.Seeds) do
                    if seedData.ID == realId and seedData.Quantity > 0 then
                        hasItem = true
                        break
                    end
                end
            end
        elseif itemType == "Plant" then
            if data.Inventory.Plants then
                for _, plantData in ipairs(data.Inventory.Plants) do
                    if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl and plantData.Quantity > 0 then
                        hasItem = true
                        break
                    end
                end
            end
        elseif itemType == "Chest" then
            if data.Inventory.Chests then
                for _, chestData in ipairs(data.Inventory.Chests) do
                    if chestData.ID == realId and chestData.Quantity > 0 then
                        hasItem = true
                        break
                    end
                end
            end
        elseif itemType == "Item" then
            if data.Inventory.Items then
                for _, itemData in ipairs(data.Inventory.Items) do
                    if itemData.ID == realId and itemData.Quantity > 0 and ItemConfig.Items and ItemConfig.Items[realId] then
                        hasItem = true
                        break
                    end
                end
            end
        end

        if hasItem then
            if not data.Hotbar then data.Hotbar = {} end
                local inHotbar = false
                for _, id in ipairs(data.Hotbar) do
                    if id == compositeId then inHotbar = true
                    break
                end
            end

            if inHotbar then
                forceSelectRE:FireClient(player, compositeId)
            else
                if #data.Hotbar < 10 then
                    table.insert(data.Hotbar, compositeId)
                    ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
                    forceSelectRE:FireClient(player, compositeId)
                 else
                    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                    if showNotifRE then
                        showNotifRE:FireClient(player, "Hotbar Full", "Please unequip some items from your hotbar first.")
                    end
                end
            end
        end
    end)

    print("Server: InventoryService loaded; seamless silent SwapPlant system online.")
end

return InventoryService

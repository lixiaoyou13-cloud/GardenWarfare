-- src/server/Services/InventoryService.luau
local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local PlotService = require(script.Parent.PlotService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
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
    local saved, saveErr = PlayerDataManager.ForceSave(player)
    if saved then
        return true
    end

    warn("[InventoryService] Failed to save " .. tostring(context) .. " for "
        .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))

    restoreInventoryTransactionState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = PlayerDataManager.ForceSave(player)
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[InventoryService] Failed to save rollback after " .. tostring(context) .. " for "
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

    -- 接受 isCombatSwap 参数判定是否需要扣钱
    swapCombatPlantRE.OnServerEvent:Connect(function(player, oldPlantModel, equippedCompositeId, isCombatSwap)
        if not oldPlantModel or not oldPlantModel.Parent then return end
        if type(equippedCompositeId) ~= "string" then return end
        if not oldPlantModel:GetAttribute("IsCombatPlant") then return end

        local parts = string.split(equippedCompositeId, "_")
        if parts[1] ~= "Plant" then return end

        local newPlantId = parts[2]
        local newMutLevel = tonumber(parts[3]) or 1
        local newPlantConfig = ItemConfig.Plants[newPlantId]
        if not newPlantConfig or newPlantConfig.IsThrowable then return end

        local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
        local newTemplate = itemModelsFolder and (itemModelsFolder:FindFirstChild(newPlantId .. "_Plant") or itemModelsFolder:FindFirstChild(newPlantId))
        if not newTemplate then return end

        local gridPart = oldPlantModel.Parent
        if not gridPart or not gridPart:IsA("BasePart") then return end

        local myPlot = PlotService.GetPlayerPlot(player)
        local lawnFolder = myPlot and myPlot:FindFirstChild("Lawn")
        if not myPlot or not lawnFolder or gridPart.Parent ~= lawnFolder then return end

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
        gridPart:SetAttribute("OccupiedBy", nil)
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

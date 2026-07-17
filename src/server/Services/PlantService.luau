-- src/server/Services/PlantService.luau
-- 职责：纯粹负责玩家互动(ProximityPrompt)、偷菜防守判定、数据加载、埋点击
local PlantService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService") -- 引入 CollectionService 用于雷达标签

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PassQuestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassQuestConfig"))
local PlotService = require(script.Parent.PlotService)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local EquipmentService = require(script.Parent.EquipmentService)
local CoinDropService = require(script.Parent.CoinDropService)

-- 引入拆分出的生命周期服务
local PlantGrowthService = require(script.Parent.PlantGrowthService)

local STEAL_SAVE_FIELDS = {
    "Inventory",
    "Hotbar",
    "PlantedPlants",
    "UnlockedMutations",
}
local STEALING_PLANT_ATTRIBUTE = "IsStealingPlant"
local STEAL_RESOLVING_ATTRIBUTE = "IsStealResolving"
local STEALING_USER_ID_ATTRIBUTE = "StealingUserId"
local HARVEST_RESOLVE_LOCK_TIMEOUT = 30
local resolvingHarvestSoils = {}
local MIN_SPEED_UP_BASE_PRICE = 100

-- 获取加速基础价格，避免占位 0 导致免费加速。
local function getSpeedUpBasePrice(seedDetail)
    local buyPrice = seedDetail and tonumber(seedDetail.BuyPrice)
    if not buyPrice or buyPrice <= 0 then
        return MIN_SPEED_UP_BASE_PRICE
    end
    return buyPrice
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

local function snapshotStealState(data)
    local snapshot = {}
    for _, fieldName in ipairs(STEAL_SAVE_FIELDS) do
        snapshot[fieldName] = cloneValue(data[fieldName])
    end
    return snapshot
end

local function restoreStealState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    for _, fieldName in ipairs(STEAL_SAVE_FIELDS) do
        data[fieldName] = cloneValue(snapshot[fieldName])
    end
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function notifyPlayer(player, message)
    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
    if showNotifRE and player and player.Parent then
        showNotifRE:FireClient(player, "Notice", message)
    end
end

-- 同一块土地同一时间只允许一个收获/偷菜结算流程，防止旧回调重复发奖。
local function getHarvestResolveKey(plot, soilName)
    if not plot or type(soilName) ~= "string" or soilName == "" then
        return nil
    end

    return tostring(plot:GetFullName()) .. ":" .. soilName
end

-- 检查土地是否正在结算收获或偷菜。
local function isHarvestResolving(plot, soilName)
    local key = getHarvestResolveKey(plot, soilName)
    return key ~= nil and resolvingHarvestSoils[key] ~= nil
end

-- 收获/偷菜结算期间锁住土地、模型和 Prompt，避免同一株植物被重复收获。
local function setHarvestResolvingLock(plot, soilName, targetPlant, prompt, locked)
    local key = getHarvestResolveKey(plot, soilName)
    if key then
        if locked == true then
            local token = os.clock()
            resolvingHarvestSoils[key] = token
            task.delay(HARVEST_RESOLVE_LOCK_TIMEOUT, function()
                if resolvingHarvestSoils[key] == token then
                    resolvingHarvestSoils[key] = nil
                end
            end)
        else
            resolvingHarvestSoils[key] = nil
        end
    end

    if targetPlant and targetPlant.Parent then
        targetPlant:SetAttribute(STEAL_RESOLVING_ATTRIBUTE, locked == true)
    end

    if prompt and prompt.Parent then
        prompt.Enabled = locked ~= true
    end
end

-- 清理偷菜读条状态，避免植物被主人收走后小偷仍保留可被击退状态。
local function clearStealingState(targetPlant, stealingPlayer)
    local stealingUserId = nil
    if targetPlant then
        stealingUserId = tonumber(targetPlant:GetAttribute(STEALING_USER_ID_ATTRIBUTE))
        targetPlant:SetAttribute("IsBeingStolen", false)
        targetPlant:SetAttribute(STEALING_USER_ID_ATTRIBUTE, nil)
        CollectionService:RemoveTag(targetPlant, "BeingStolen")
    end

    if not stealingPlayer and stealingUserId then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == stealingUserId then
                stealingPlayer = player
                break
            end
        end
    end

    if stealingPlayer then
        stealingPlayer:SetAttribute(STEALING_PLANT_ATTRIBUTE, false)
    end
end

-- 存档失败时把临时移走的植物放回场景，避免偷菜失败后植物丢失。
local function restoreStealResolvingPlant(targetPlant, originalParent)
    if targetPlant and not targetPlant.Parent and originalParent and originalParent.Parent then
        targetPlant.Parent = originalParent
    end
end

local function rollbackStealTransaction(thief, owner, thiefData, ownerData, thiefSnapshot, ownerSnapshot)
    restoreStealState(thiefData, thiefSnapshot)
    restoreStealState(ownerData, ownerSnapshot)
    fireInventoryUpdate(thief, thiefData)
    fireInventoryUpdate(owner, ownerData)

    local thiefRollbackSaved, thiefRollbackErr = PlayerDataManager.ForceSave(thief)
    local ownerRollbackSaved, ownerRollbackErr = PlayerDataManager.ForceSave(owner)
    if not thiefRollbackSaved and thiefRollbackErr ~= "stale_session" then
        warn("[PlantService] Failed to save thief rollback after steal: " .. tostring(thiefRollbackErr))
    end
    if not ownerRollbackSaved and ownerRollbackErr ~= "stale_session" then
        warn("[PlantService] Failed to save owner rollback after steal: " .. tostring(ownerRollbackErr))
    end
end

local function saveStealTransaction(thief, owner, thiefData, ownerData, thiefSnapshot, ownerSnapshot)
    local thiefSaved, thiefSaveErr = PlayerDataManager.ForceSave(thief)
    local ownerSaved, ownerSaveErr = PlayerDataManager.ForceSave(owner)
    if thiefSaved and ownerSaved then
        return true
    end

    warn("[PlantService] Steal save failed: thiefSaved=" .. tostring(thiefSaved)
        .. ", thiefErr=" .. tostring(thiefSaveErr)
        .. ", ownerSaved=" .. tostring(ownerSaved)
        .. ", ownerErr=" .. tostring(ownerSaveErr))
    rollbackStealTransaction(thief, owner, thiefData, ownerData, thiefSnapshot, ownerSnapshot)
    return false
end

function PlantService.Init()
    if not ReplicatedStorage:FindFirstChild("ShowNotificationRE") then
        local re = Instance.new("RemoteEvent")
        re.Name = "ShowNotificationRE"
        re.Parent = ReplicatedStorage
    end

    if not ReplicatedStorage:FindFirstChild("OpenInventoryRE") then
        local openInvRE = Instance.new("RemoteEvent")
        openInvRE.Name = "OpenInventoryRE"
        openInvRE.Parent = ReplicatedStorage
    end

    local plotsFolder = Workspace:WaitForChild("Plots")

    -- 1 处理玩家加入时间的数据还原
    Players.PlayerAdded:Connect(function(player)
        local data = PlayerDataManager.GetPlayerData(player)
        local waitLimit = 0

        while not data and waitLimit < 20 do
            task.wait(0.5)
            waitLimit += 1
            data = PlayerDataManager.GetPlayerData(player)
        end

        if not data then
            warn("[PlantRestore] Timed out waiting for player data; restore aborted.")
            return
        end

        local plot = nil
        for i = 1, 20 do
            plot = PlotService.GetPlayerPlot(player)
            if plot then break end
            task.wait(0.5)
        end
        if not plot then return end

        if not data.PlantedPlants then return end

        local soilsFolder = plot:FindFirstChild("Soils")
        local plantsFolder = plot:FindFirstChild("Plants")
        if not soilsFolder or not plantsFolder then return end

        for soilName, plantData in pairs(data.PlantedPlants) do
            local soil = soilsFolder:FindFirstChild(soilName)
            local itemDetail = ItemConfig.Seeds[plantData.SeedId]

            if soil and itemDetail then
                local prompt = soil:FindFirstChildOfClass("ProximityPrompt")
                local elapsed = os.time() - plantData.PlantedTime

                if elapsed >= itemDetail.GrowthTime then
                    if not plantData.HasDropped then
                        local dropPos = soil.Position + Vector3.new(0, 3, 0)
                        CoinDropService.DropCoins(player, dropPos, 5, itemDetail.Output or 20)
                        PlayerDataManager.MarkPlantAsDropped(player, soilName)
                    end

                    PlantGrowthService.SpawnMaturePlant(soil, itemDetail, plot, plantsFolder, plantData.Mutation)
                    if prompt then
                        prompt.Enabled = false

                        prompt.ActionText = "Harvest"
                        prompt.HoldDuration = 15 -- 还原数据时间，成熟的也是15秒长按
                        prompt.Enabled = true

                         task.delay(0.05, function()
                            if prompt and prompt.Parent then
                                prompt.Enabled = true
                            end
                        end)
                    end
                else
                    local newPlant = PlantGrowthService.CreateSeedling(plantData.SeedId, soil, itemDetail, plantData.PlantedTime, plot, plantsFolder)
                    if prompt then prompt.ActionText = "Speed up"; prompt.Enabled = true end
                    PlantGrowthService.StartPlantGrowth(player, plot, soil, itemDetail, newPlant, prompt, plantsFolder)
                end
            end
        end
    end)

    -- 2 初始化所有地块的交互按键
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not string.match(plot.Name, "Plot") then continue end

        local soilsFolder = plot:FindFirstChild("Soils")
        local plantsFolder = plot:FindFirstChild("Plants")

        if not soilsFolder or not plantsFolder then continue end

        for _, soil in ipairs(soilsFolder:GetChildren()) do
            if string.find(soil.Name, "Soil") and soil:IsA("BasePart") then
                local prompt = Instance.new("ProximityPrompt")
                prompt.Name = "PlantPrompt"
                prompt.ActionText = "Plant"
                prompt.ObjectText = "Soil"
                prompt.KeyboardKeyCode = Enum.KeyCode.E
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 8
                prompt.Parent = soil
                prompt.HoldDuration = 0.5
                if soil:GetAttribute("IsUnlocked") ~= true then
                    prompt.Enabled = false
                end

                soil:GetAttributeChangedSignal("IsUnlocked"):Connect(function()
                    if soil:GetAttribute("IsUnlocked") == true then
                        local targetPlant = nil
                        for _, plant in ipairs(plantsFolder:GetChildren()) do
                            if plant:GetAttribute("PlantedOn") == soil.Name then targetPlant = plant; break end
                        end
                        if not targetPlant then
                            prompt.ActionText = "Plant"
                            prompt.Enabled = true
                        end
                    else
                        prompt.Enabled = false
                    end
                end)

                -- 全新机制：基于原生 Prompt 的偷菜与防守系统

                -- 事件 1：手指按下的瞬间 (判定秒收与报警)
                prompt.PromptButtonHoldBegan:Connect(function(player)
                    if soil:GetAttribute("IsUnlocked") ~= true then return end
                    if isHarvestResolving(plot, soil.Name) then return end

                    local targetPlant = nil
                    for _, plant in ipairs(plantsFolder:GetChildren()) do
                        if plant:GetAttribute("PlantedOn") == soil.Name then targetPlant = plant; break end
                    end

                    if targetPlant and targetPlant:GetAttribute("IsMature") then
                        if targetPlant:GetAttribute(STEAL_RESOLVING_ATTRIBUTE) then return end

                        local myPlot = PlotService.GetPlayerPlot(player)
                        local isOwner = (myPlot == plot)
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")

                        if isOwner then
                            -- 主人专属特权：按下瞬间立刻秒收，不需要等15秒
                            setHarvestResolvingLock(plot, soil.Name, targetPlant, prompt, true)
                            clearStealingState(targetPlant)

                            local plantId = targetPlant.Name
                            local currentYield = targetPlant:GetAttribute("YieldCount") or 1
                            local mutLevel = targetPlant:GetAttribute("MutationLevel") or 1
                            local plantConfig = ItemConfig.Plants[plantId]
                            local plantName = plantConfig and plantConfig.Name or plantId
                            local mutPrefix = (mutLevel > 1) and ("[".. (ItemConfig.MutationName[mutLevel] or "Mutation") .."] ") or ""

                            PlayerDataManager.GivePlant(player, plantId, currentYield, mutLevel)
                            PlayerDataManager.UnlockMutation(player, plantId, mutLevel)
                            PlayerDataManager.RemovePlantedPlant(player, soil.Name)
                            PlayerDataManager.AddPassQuestProgress(player, PassQuestConfig.TaskIds.HarvestPlants, 1)
                            targetPlant:Destroy()

                            -- 收获后自转动装备
                            local compositeId = "Plant_" .. plantId .. "_" .. mutLevel
                            local playerData = PlayerDataManager.GetPlayerData(player)
                            if playerData then
                                if not playerData.Hotbar then playerData.Hotbar = {} end
                                local inHotbar = false
                                for _, id in ipairs(playerData.Hotbar) do
                                    if id == compositeId then inHotbar = true; break end
                                end

                                if not inHotbar and #playerData.Hotbar < 10 then
                                    table.insert(playerData.Hotbar, compositeId)
                                    local updateInvRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                                    if updateInvRE then updateInvRE:FireClient(player, playerData) end
                                end

                                local forceSelectRE = ReplicatedStorage:FindFirstChild("ForceSelectRE")
                                if forceSelectRE then
                                    forceSelectRE:FireClient(player, compositeId)
                                end
                            end

                            prompt.Enabled = false
                            prompt.ActionText = "Plant"
                            prompt.HoldDuration = 0.5 -- 地空了，种地时间恢复为0.5秒

                            local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                            if playObtainEffectRE then
                                -- 把多段文字合并成一句
                                local msg = "Gain: " .. currentYield .. "x " .. mutPrefix .. plantName
                                local playFullEffect = (tonumber(plantConfig and plantConfig.Quality) or 0) >= 4
                                playObtainEffectRE:FireClient(player, msg, playFullEffect)
                            end

                            task.delay(0.05, function()
                                setHarvestResolvingLock(plot, soil.Name, nil, prompt, false)
                            end)
                        else
                            -- 2. 小偷按下E，开始死死按住15秒
                            if targetPlant:GetAttribute("IsBeingStolen") then
                                if showNotifRE then showNotifRE:FireClient(player, "Notice", "Someone is already stealing this plant!") end
                                return
                            end

                            targetPlant:SetAttribute("IsBeingStolen", true)
                            targetPlant:SetAttribute(STEALING_USER_ID_ATTRIBUTE, player.UserId)
                            player:SetAttribute(STEALING_PLANT_ATTRIBUTE, true)
                            -- 给这颗植物打上被偷的专属标签，供客户端雷达扫描
                            CollectionService:AddTag(targetPlant, "BeingStolen")

                            if showNotifRE then showNotifRE:FireClient(player, "Notice", "Stealing started!\nHold E for 15 seconds.") end

                        end
                    end
                end)

                -- 事件 2：松手或被物理击飞导致强制中断
                prompt.PromptButtonHoldEnded:Connect(function(player)
                    if isHarvestResolving(plot, soil.Name) then
                        player:SetAttribute(STEALING_PLANT_ATTRIBUTE, false)
                        return
                    end

                    local targetPlant = nil
                    for _, plant in ipairs(plantsFolder:GetChildren()) do
                        if plant:GetAttribute("PlantedOn") == soil.Name then targetPlant = plant; break end
                    end
                    if targetPlant and targetPlant:GetAttribute("IsBeingStolen") then
                        local myPlot = PlotService.GetPlayerPlot(player)
                        if myPlot ~= plot then -- 小偷没扛住松手了，或者被击飞了

                            -- 避免延迟 0.1 秒判定，避开底层事件冲突
                            task.wait(0.1)
                            if not targetPlant or not targetPlant.Parent then return end
                            if targetPlant:GetAttribute(STEAL_RESOLVING_ATTRIBUTE) then return end

                            -- 中断时移除被偷标签和玩家偷菜状态。
                            clearStealingState(targetPlant, player)

                            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                            if showNotifRE then showNotifRE:FireClient(player, "Notice", "Stealing canceled!") end
                        end
                    end
                end)

                -- 事件 3：读条圆圈转满完成
                prompt.Triggered:Connect(function(player)
                    if soil:GetAttribute("IsUnlocked") ~= true then return end
                    if isHarvestResolving(plot, soil.Name) then return end

                    local myPlot = PlotService.GetPlayerPlot(player)
                    local isOwner = (myPlot == plot)

                    local targetPlant = nil
                    for _, plant in ipairs(plantsFolder:GetChildren()) do
                        if plant:GetAttribute("PlantedOn") == soil.Name then targetPlant = plant; break end
                    end

                    if targetPlant then
                        if targetPlant:GetAttribute("IsMature") then
                            -- 成熟逻辑：因为主人在按下瞬间就已经拿到了，所以能熬过 15 秒走到这里的只能是小偷
                            if targetPlant:GetAttribute(STEAL_RESOLVING_ATTRIBUTE) then return end

                            if not isOwner and targetPlant:GetAttribute("IsBeingStolen") then
                                setHarvestResolvingLock(plot, soil.Name, targetPlant, prompt, true)
                                -- 成功得手时移除被偷标签和玩家偷菜状态。
                                clearStealingState(targetPlant, player)

                                local plantId = targetPlant.Name
                                local currentYield = targetPlant:GetAttribute("YieldCount") or 1
                                local mutLevel = targetPlant:GetAttribute("MutationLevel") or 1
                                local plantConfig = ItemConfig.Plants[plantId]
                                local plantName = plantConfig and plantConfig.Name or plantId
                                local mutPrefix = (mutLevel > 1) and ("[".. (ItemConfig.MutationName[mutLevel] or "Mutation") .."] ") or ""

                                -- 发放奖励给小偷
                                local ownerId = targetPlant:GetAttribute("OwnerId") or 0
                                local ownerPlayer = nil
                                for _, p in ipairs(Players:GetPlayers()) do
                                    if p.UserId == ownerId then ownerPlayer = p; break end
                                end
                                local thiefData = PlayerDataManager.GetPlayerData(player)
                                local ownerData = ownerPlayer and PlayerDataManager.GetPlayerData(ownerPlayer)
                                if not ownerPlayer or not thiefData or not ownerData then
                                    setHarvestResolvingLock(plot, soil.Name, targetPlant, prompt, false)
                                    notifyPlayer(player, "Steal failed: owner data is unavailable.")
                                    return
                                end
                                if not PlayerDataManager.IsDataSafeToSave(player) or not PlayerDataManager.IsDataSafeToSave(ownerPlayer) then
                                    setHarvestResolvingLock(plot, soil.Name, targetPlant, prompt, false)
                                    notifyPlayer(player, "Steal failed: save unavailable. Please try again.")
                                    return
                                end

                                local thiefSnapshot = snapshotStealState(thiefData)
                                local ownerSnapshot = snapshotStealState(ownerData)
                                local originalPlantParent = targetPlant.Parent

                                -- 成功结算开始后先从场景移走，防止主人在存档等待时看到并二次收获。
                                targetPlant.Parent = nil

                                PlayerDataManager.GivePlant(player, plantId, currentYield, mutLevel)
                                PlayerDataManager.UnlockMutation(player, plantId, mutLevel)
                                PlayerDataManager.RemovePlantedPlant(ownerPlayer, soil.Name)

                                local stealSaved = saveStealTransaction(player, ownerPlayer, thiefData, ownerData, thiefSnapshot, ownerSnapshot)
                                if not stealSaved then
                                    restoreStealResolvingPlant(targetPlant, originalPlantParent)
                                    setHarvestResolvingLock(plot, soil.Name, targetPlant, prompt, false)
                                    notifyPlayer(player, "Steal failed: save failed. Please try again.")
                                    return
                                end

                                notifyPlayer(ownerPlayer, "Your " .. plantName .. " was stolen by " .. player.Name .. "!")

                                -- 扣除主人植物
                                local ownerId = targetPlant:GetAttribute("OwnerId") or 0
                                local ownerPlayer = nil
                                for _, p in ipairs(Players:GetPlayers()) do
                                    if p.UserId == ownerId then ownerPlayer = p; break end
                                end
                                if false and ownerPlayer then
                                    PlayerDataManager.RemovePlantedPlant(ownerPlayer, soil.Name)
                                    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                                    if showNotifRE then
                                        showNotifRE:FireClient(ownerPlayer, "Notice", "Your " .. plantName .. " was stolen by " .. player.Name .. "!")
                                    end
                                end

                                targetPlant:Destroy()

                                -- 小偷得手后自转动装备
                                local compositeId = "Plant_" .. plantId .. "_" .. mutLevel
                                local playerData = PlayerDataManager.GetPlayerData(player)
                                if playerData then
                                    if not playerData.Hotbar then playerData.Hotbar = {} end
                                    local inHotbar = false
                                    for _, id in ipairs(playerData.Hotbar) do
                                        if id == compositeId then inHotbar = true; break end
                                    end

                                    if not inHotbar and #playerData.Hotbar < 10 then
                                        table.insert(playerData.Hotbar, compositeId)
                                        local updateInvRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                                        if updateInvRE then updateInvRE:FireClient(player, playerData) end
                                    end

                                    local forceSelectRE = ReplicatedStorage:FindFirstChild("ForceSelectRE")
                                    if forceSelectRE then
                                        forceSelectRE:FireClient(player, compositeId)
                                    end
                                end

                                prompt.Enabled = false
                                prompt.ActionText = "Plant"
                                prompt.HoldDuration = 0.5

                                task.delay(0.05, function()
                                    setHarvestResolvingLock(plot, soil.Name, nil, prompt, false)
                                end)

                                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                                if showNotifRE then
                                    showNotifRE:FireClient(player, "Notice", "Steal Successful!\nYou stole: " .. currentYield .. "x " .. mutPrefix .. plantName)
                                end
                            end
                            return
                        else
                            -- 未成熟加速逻辑
                            if not isOwner then
                                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                                if showNotifRE then showNotifRE:FireClient(player, "Notice", "You cannot speed up other players' plants!") end
                                return
                            end

                            local currentPlantedTime = targetPlant:GetAttribute("PlantedTime") or os.time()
                            local growthTime = targetPlant:GetAttribute("GrowthTime")
                            local remaining = math.max(0, growthTime - (os.time() - currentPlantedTime))
                            if remaining > 0 then
                                local seedId = targetPlant.Name
                                local seedDetail = ItemConfig.Seeds[seedId]
                                local buyPrice = getSpeedUpBasePrice(seedDetail)

                                local cost = buyPrice * 2

                                if PlayerDataManager.ConsumeCoins(player, cost) then
                                    local newTime = os.time() - growthTime - 1
                                    targetPlant:SetAttribute("PlantedTime", newTime)
                                    PlayerDataManager.UpdatePlantedPlant(player, soil.Name, targetPlant.Name, newTime)
                                end
                            end
                            return
                        end
                    end

                    -- 种植物的逻辑
                    if not isOwner then
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then showNotifRE:FireClient(player, "Notice", "This is someone else's plot.\nYou cannot plant here!") end
                        return
                    end

                    local character = player.Character; if not character then return end
                    local equippedCompositeId = character:GetAttribute("EquippedSeed")

                    if not equippedCompositeId then
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then showNotifRE:FireClient(player, "Notice", "Please select a seed!") end
                        local openInvRE = ReplicatedStorage:FindFirstChild("OpenInventoryRE")
                        if openInvRE then openInvRE:FireClient(player) end
                        return
                    end

                    local parts = string.split(equippedCompositeId, "_")
                    local itemType = parts[1]
                    local realId = parts[2]

                    if itemType ~= "Seed" then
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then showNotifRE:FireClient(player, "Notice", "Mature plants cannot be planted directly!") end
                        return
                    end

                    if PlayerDataManager.ConsumeSeed(player, realId, 1) then
                        local data = PlayerDataManager.GetPlayerData(player)

                        local hasStock = false
                        if data and data.Inventory.Seeds then
                            for _, seedData in ipairs(data.Inventory.Seeds) do
                                if seedData.ID == realId and seedData.Quantity > 0 then hasStock = true; break end
                            end
                        end

                        if not hasStock then
                            EquipmentService.UpdateHoldItem(player, nil)
                            local holdItemRE = ReplicatedStorage:FindFirstChild("HoldItemRE")
                            if holdItemRE then holdItemRE:FireClient(player, nil) end
                        end

                        local itemDetail = ItemConfig.Seeds[realId]
                        if not itemDetail then return end

                        local plantedTime = os.time()
                        PlayerDataManager.UpdatePlantedPlant(player, soil.Name, realId, plantedTime)

                        local newPlant = PlantGrowthService.CreateSeedling(realId, soil, itemDetail, plantedTime, plot, plantsFolder)
                        if newPlant then
                            prompt.ActionText = "Speed up"
                            prompt.Enabled = true
                            PlantGrowthService.StartPlantGrowth(player, plot, soil, itemDetail, newPlant, prompt, plantsFolder)
                        end
                    end
                end)
            end
        end
    end

    -- 3 专门用于新手教程强制种植物的 RemoteEvent
    local tutorialPlantRE = ReplicatedStorage:FindFirstChild("TutorialPlantRE") or Instance.new("RemoteEvent")
    tutorialPlantRE.Name = "TutorialPlantRE"
    tutorialPlantRE.Parent = ReplicatedStorage

    tutorialPlantRE.OnServerEvent:Connect(function(player, lawnName, plantId)
        local plot = PlotService.GetPlayerPlot(player)
        if not plot then return end

        local lawnFolder = plot:FindFirstChild("Lawn")
        local plantsFolder = plot:FindFirstChild("Plants")
        local targetLawn = lawnFolder and lawnFolder:FindFirstChild(lawnName)

        local itemDetail = ItemConfig.Seeds[plantId] or ItemConfig.Seeds["Peashooter"]

        if targetLawn and itemDetail then
            local plantedTime = os.time()
            PlayerDataManager.UpdatePlantedPlant(player, lawnName, plantId, plantedTime)

            local newPlant = PlantGrowthService.CreateSeedling(plantId, targetLawn, itemDetail, plantedTime, plot, plantsFolder)
            if newPlant then
                local prompt = targetLawn:FindFirstChildOfClass("ProximityPrompt")
                PlantGrowthService.StartPlantGrowth(player, plot, targetLawn, itemDetail, newPlant, prompt, plantsFolder)
            end
        end
    end)
end

return PlantService

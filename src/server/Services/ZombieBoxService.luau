-- src/server/Services/ZombieBoxService.luau
local ZombieBoxService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local itemModels = ReplicatedStorage:WaitForChild("ItemModels")

-- 了双端死等的 Bug：使用 FindFirstChild，如果没有再创建
local zombieBoxRE = ReplicatedStorage:FindFirstChild("ZombieBoxRE")
if not zombieBoxRE then
    zombieBoxRE = Instance.new("RemoteEvent")
    zombieBoxRE.Name = "ZombieBoxRE"
    zombieBoxRE.Parent = ReplicatedStorage
end

local pendingBoxRewards = {}
local AUTO_OPEN_DISTANCE = 8
local PICKUP_ENABLE_DELAY = 0.9
local LEVEL_CHEST_REWARD_CHANCE = 1

local REWARD_SAVE_FIELDS = {
    "Coins",
    "Inventory",
    "Hotbar",
    "UnlockedMutations",
}

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

local function snapshotRewardState(data)
    local snapshot = {}
    for _, fieldName in ipairs(REWARD_SAVE_FIELDS) do
        snapshot[fieldName] = cloneValue(data[fieldName])
    end
    return snapshot
end

local function restoreRewardState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    for _, fieldName in ipairs(REWARD_SAVE_FIELDS) do
        data[fieldName] = cloneValue(snapshot[fieldName])
    end
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function sendTip(player, message)
    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE and player and player.Parent then
        showTipRE:FireClient(player, message)
    end
end

local function rollbackRewardGrant(player, data, snapshot, context)
    restoreRewardState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = PlayerDataManager.ForceSave(player)
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[ZombieBoxService] Failed to save rollback after " .. tostring(context)
            .. " for " .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end
end

local function grantRewardItem(player, rewardItem, context)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Reward failed: data is still loading."
    end
    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Reward failed: save unavailable. Please try again."
    end
    if type(rewardItem) ~= "table" then
        return false, "Reward failed: reward config is invalid."
    end

    local snapshot = snapshotRewardState(data)
    local granted = false

    if rewardItem.type == "Plant" and ItemConfig.Plants and ItemConfig.Plants[rewardItem.id] then
        PlayerDataManager.GivePlant(player, rewardItem.id, 1, 1)
        granted = true
    elseif rewardItem.type == "Seed" and ItemConfig.Seeds and ItemConfig.Seeds[rewardItem.id] then
        PlayerDataManager.GiveSeed(player, rewardItem.id, 1)
        granted = true
    elseif rewardItem.type == "Currency" and rewardItem.id == "CoinBox" then
        PlayerDataManager.GiveCoins(player, rewardItem.amount or 500)
        granted = true
    end

    if not granted then
        restoreRewardState(data, snapshot)
        fireInventoryUpdate(player, data)
        return false, "Reward failed: reward config is invalid."
    end

    local saved, saveErr = PlayerDataManager.RequestSave(player, context)
    if saved then
        return true
    end

    warn("[ZombieBoxService] Failed to queue save after " .. tostring(context) .. " for "
        .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))
    rollbackRewardGrant(player, data, snapshot, context)
    return false, "Reward failed: save unavailable. Please try again."
end

Players.PlayerRemoving:Connect(function(player)
    pendingBoxRewards[player.UserId] = nil
end)

local function getLevelChestId(levelId)
    levelId = math.max(1, tonumber(levelId) or 1)

    if levelId <= 30 then
        return "Chest1"
    elseif levelId <= 70 then
        return "Chest2"
    elseif levelId <= 120 then
        return "Chest3"
    end

    return "Chest4"
end

-- 1. 盲盒大类概率配置 (权重制)
local TYPE_WEIGHTS = {
    Seed = 90, -- 种子权重 65
    Plant = 10, -- 植物权重 20
    -- 以后想加新类型，只需解开注释并加上权重
    -- Prop = 10
    -- Currency = 5
}

-- 品质权重配置 (1星~5星)
local QUALITY_WEIGHTS = { [1] = 70, [2] = 20, [3] = 8, [4] = 2 }

local function buildRewardPool()
    local categorizedPool = {}

    local function buildPool(configDict, typeName)
        if not configDict then return end
        categorizedPool[typeName] = {}
        for id, data in pairs(configDict) do
            if typeName == "Plant" and data.ExcludeFromRandomPlantRewards then
                continue
            end

            local quality = data.Quality or 1
            if not categorizedPool[typeName][quality] then
                categorizedPool[typeName][quality] = {}
            end
            table.insert(categorizedPool[typeName][quality], { type = typeName, id = id })
        end
    end

    buildPool(ItemConfig.Plants, "Plant")
    buildPool(ItemConfig.Seeds, "Seed")

    categorizedPool.Currency = {
        [1] = { { type = "Currency", id = "CoinBox", amount = 500 } }
    }

    return categorizedPool
end

local function rollWeightedType(forcedType)
    if forcedType and TYPE_WEIGHTS[forcedType] then
        return forcedType
    end

    local totalTypeWeight = 0
    for _, weight in pairs(TYPE_WEIGHTS) do
        totalTypeWeight += math.max(0, tonumber(weight) or 0)
    end

    if totalTypeWeight <= 0 then
        return "Seed"
    end

    local typeRoll = math.random(1, totalTypeWeight)
    local currentTypeWeight = 0

    for typeName, weight in pairs(TYPE_WEIGHTS) do
        currentTypeWeight += math.max(0, tonumber(weight) or 0)
        if typeRoll <= currentTypeWeight then
            return typeName
        end
    end

    return "Seed"
end

local function rollWeightedQuality()
    local totalQualityWeight = 0
    for _, weight in pairs(QUALITY_WEIGHTS) do
        totalQualityWeight += math.max(0, tonumber(weight) or 0)
    end

    if totalQualityWeight <= 0 then
        return 1
    end

    local qualityRoll = math.random(1, totalQualityWeight)
    local currentQualityWeight = 0

    for quality = 1, 5 do
        currentQualityWeight += math.max(0, tonumber(QUALITY_WEIGHTS[quality]) or 0)
        if qualityRoll <= currentQualityWeight then
            return quality
        end
    end

    return 1
end

local function pickFromTypePool(categorizedPool, targetType, targetQuality)
    local typePool = categorizedPool[targetType]
    if not typePool then
        return nil
    end

    local qualityPool = typePool[targetQuality]
    if qualityPool and #qualityPool > 0 then
        return qualityPool[math.random(1, #qualityPool)]
    end

    local fallbackPool = typePool[1]
    if fallbackPool and #fallbackPool > 0 then
        return fallbackPool[math.random(1, #fallbackPool)]
    end

    for _, pool in pairs(typePool) do
        if type(pool) == "table" and #pool > 0 then
            return pool[math.random(1, #pool)]
        end
    end

    return nil
end

function ZombieBoxService.RollRewardItem(forcedType)
    local categorizedPool = buildRewardPool()
    local targetType = rollWeightedType(forcedType)
    local targetQuality = rollWeightedQuality()
    local rewardItem = pickFromTypePool(categorizedPool, targetType, targetQuality)

    if rewardItem then
        return {
            type = rewardItem.type,
            id = rewardItem.id,
            amount = rewardItem.amount,
        }
    end

    if forcedType == "Plant" then
        for plantId, plantDetail in pairs(ItemConfig.Plants or {}) do
            if plantDetail.ExcludeFromRandomPlantRewards then
                continue
            end

            return { type = "Plant", id = plantId }
        end
    end

    return { type = "Seed", id = "Peashooter" }
end

-- 监听客户端动画播完后发来的“给我发奖”请求
zombieBoxRE.OnServerEvent:Connect(function(player, action, finalItem)
    if action == "GiveReward" then
        local rewardQueue = pendingBoxRewards[player.UserId]
        finalItem = rewardQueue and table.remove(rewardQueue, 1)
        if rewardQueue and #rewardQueue <= 0 then
            pendingBoxRewards[player.UserId] = nil
        end
        if not finalItem then
            return
        end

        local granted, message = grantRewardItem(player, finalItem, "zombie box reward")
        if not granted then
            sendTip(player, message or "Reward failed. Please try again.")
        end
        return
    end

    if false then
        if pendingBoxes[player.UserId] and pendingBoxes[player.UserId] > 0 then
            pendingBoxes[player.UserId] -= 1

            -- 2. 真实发奖逻辑扩展
            if finalItem.type == "Plant" then
                PlayerDataManager.GivePlant(player, finalItem.id, 1, 1)

            elseif finalItem.type == "Seed" then
                PlayerDataManager.GiveSeed(player, finalItem.id, 1)

            elseif finalItem.type == "Prop" then
                -- 预留的道具发放接口
                -- PlayerDataManager.GiveItem(player, finalItem.id, 1)

            elseif finalItem.type == "Currency" then
                if finalItem.id == "CoinBox" then
                    PlayerDataManager.GiveCoins(player, finalItem.amount or 500)
                end
            end
        end
    end
end)

-- 这个就是你报错丢失的函数，必须确保它完整存在
function ZombieBoxService.SpawnBox(player, dropPos)
    -- 初始化池子

    -- 货币这种不需要星级的特殊物品，手动插入池子
        -- 1. 先抽奖大类
        -- 2. 再抽奖品质
        -- 3. 从对应大类和品质中随机选一个具体物品
            -- 降级拿1星保持底
        -- 极致兜底
    local finalItem = ZombieBoxService.RollRewardItem()

    local boxTemplate = itemModels:FindFirstChild("Box")
    if not boxTemplate then
        warn("[ZombieBoxService] ReplicatedStorage.ItemModels.Box is missing; cannot spawn scene box")
        return
    end

    local box = boxTemplate:Clone()
    box.Name = "ZombieRewardBox_" .. tostring(player.UserId)
    box:SetAttribute("OwnerId", player.UserId)
    box:SetAttribute("IsZombieRewardBox", true)

    local promptPart = nil
    if box:IsA("BasePart") then
        promptPart = box
        box.CFrame = CFrame.new(dropPos)
    elseif box:IsA("Model") then
        promptPart = box.PrimaryPart or box:FindFirstChildWhichIsA("BasePart", true)
        if promptPart and not box.PrimaryPart then
            box.PrimaryPart = promptPart
        end
        box:PivotTo(CFrame.new(dropPos))
    end

    if not promptPart then
        warn("[ZombieBoxService] Box model has no BasePart; cannot create interactive box")
        box:Destroy()
        return
    end

    local function weldToPromptPart(part)
        if part == promptPart then return end

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = promptPart
        weld.Part1 = part
        weld.Parent = promptPart
    end

    for _, descendant in ipairs(box:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = false
            descendant.CanCollide = true
            descendant.CanTouch = true
            descendant.CanQuery = true
            weldToPromptPart(descendant)
        end
    end

    promptPart.Anchored = false

    local opened = false
    local canOpen = false

    local function openBox(triggeringPlayer)
        if opened then return end
        if triggeringPlayer ~= player then return end
        if not triggeringPlayer.Parent then return end

        opened = true

        local boxPos = box:IsA("Model") and box:GetPivot().Position or promptPart.Position

        if not pendingBoxRewards[player.UserId] then pendingBoxRewards[player.UserId] = {} end
        table.insert(pendingBoxRewards[player.UserId], finalItem)

        zombieBoxRE:FireClient(player, "SpawnBox", boxPos, finalItem)

        if box and box.Parent then
            box:Destroy()
        end
    end

    box.Parent = Workspace

    -- 像阳光/金币一样，先给盲盒一个向外向上的初速度，让它以抛物线落到地上
    promptPart.AssemblyLinearVelocity = Vector3.new(
        math.random(-18, 18),
        math.random(18, 32),
        math.random(-18, 18)
    )
    promptPart.AssemblyAngularVelocity = Vector3.new(
        math.random(-6, 6),
        math.random(-8, 8),
        math.random(-6, 6)
    )

    task.delay(PICKUP_ENABLE_DELAY, function()
        if opened or not box or not box.Parent then return end

        canOpen = true

        -- 落地后固定，避免持续滚动导致玩家难以靠近自转动拾取
        for _, descendant in ipairs(box:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
            end
        end
    end)

    task.spawn(function()
        while not opened and box and box.Parent do
            if canOpen then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")

                if humanoid and humanoid.Health > 0 and rootPart then
                    local boxPos = box:IsA("Model") and box:GetPivot().Position or promptPart.Position
                    if (rootPart.Position - boxPos).Magnitude <= AUTO_OPEN_DISTANCE then
                        openBox(player)
                        break
                    end
                end
            end

            task.wait(0.15)
        end
    end)
end

function ZombieBoxService.AwardLevelChest(player, levelId, dropPos)
    if not player then return false end

    local data = PlayerDataManager.GetPlayerData(player)
    if not data or not PlayerDataManager.IsDataSafeToSave(player) then
        return false
    end

    local snapshot = snapshotRewardState(data)
    local chestId = getLevelChestId(levelId)
    local awarded = PlayerDataManager.GiveChest(player, chestId, 1, true)
    if not awarded then
        return false
    end

    local saved, saveErr = PlayerDataManager.RequestSave(player, "level chest reward")
    if not saved then
        warn("[ZombieBoxService] Failed to queue level chest reward save for " .. player.Name .. ": " .. tostring(saveErr))
        rollbackRewardGrant(player, data, snapshot, "level chest reward")
        return false
    end

    zombieBoxRE:FireClient(player, "LevelChestReward", dropPos, chestId)
    return true, chestId
end

-- return 必须在最底部
function ZombieBoxService.TryAwardLevelChest(player, levelId, dropPos)
    if math.random(1, 100) > LEVEL_CHEST_REWARD_CHANCE then
        return false
    end

    return ZombieBoxService.AwardLevelChest(player, levelId, dropPos)
end

return ZombieBoxService

local OnlineRewardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ZombieBoxService = require(script.Parent.ZombieBoxService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local OnlineRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OnlineRewardConfig"))

local sessionStartTimes = {}
local claimingPlayers = {}
local REFRESH_INTERVAL_SECONDS = 24 * 60 * 60

local function setRewardCycle(data, startedAt)
    startedAt = math.max(0, math.floor(tonumber(startedAt) or 0))
    if startedAt <= 0 then
        startedAt = os.time()
    end

    data.OnlineRewardCycleStartedAt = startedAt
    data.OnlineRewardRefreshAt = startedAt + REFRESH_INTERVAL_SECONDS
end

local function claimedTablesEqual(first, second)
    for key, value in pairs(first) do
        if second[key] ~= value then
            return false
        end
    end

    for key, value in pairs(second) do
        if first[key] ~= value then
            return false
        end
    end

    return true
end

local function normalizeRewardState(data)
    if type(data) ~= "table" then
        return nil, false
    end

    local now = os.time()
    local changed = false
    data.OnlineRewardCycleStartedAt = math.max(0, math.floor(tonumber(data.OnlineRewardCycleStartedAt) or 0))
    data.OnlineRewardRefreshAt = math.max(0, math.floor(tonumber(data.OnlineRewardRefreshAt) or 0))

    if type(data.OnlineRewardClaimed) ~= "table" then
        data.OnlineRewardClaimed = {}
        changed = true
    end

    local normalizedClaimed = {}
    for key, value in pairs(data.OnlineRewardClaimed) do
        if value == true then
            local rewardIndex = tonumber(key)
            if rewardIndex then
                normalizedClaimed[tostring(math.floor(rewardIndex))] = true
            end
        end
    end
    if not claimedTablesEqual(normalizedClaimed, data.OnlineRewardClaimed) then
        changed = true
    end
    data.OnlineRewardClaimed = normalizedClaimed

    if data.OnlineRewardRefreshAt <= 0 then
        if data.OnlineRewardCycleStartedAt <= 0 then
            data.OnlineRewardCycleStartedAt = now
        end
        setRewardCycle(data, data.OnlineRewardCycleStartedAt)
        changed = true
    end

    if data.OnlineRewardRefreshAt > 0 and now >= data.OnlineRewardRefreshAt then
        setRewardCycle(data, now)
        data.OnlineRewardClaimed = {}
        changed = true
    end

    return data.OnlineRewardClaimed, changed
end

local function saveRewardStateIfChanged(player, changed, context)
    if not changed then
        return
    end

    local saved, saveErr = PlayerDataManager.RequestSave(player, "online reward state normalization")
    if not saved and saveErr ~= "stale_session" then
        warn("[OnlineRewardService] Save failed after " .. tostring(context) .. " for " .. player.Name .. ": " .. tostring(saveErr))
    end
end

local function getSessionStartTime(player)
    local startedAt = sessionStartTimes[player.UserId]
    if not startedAt then
        startedAt = os.time()
        sessionStartTimes[player.UserId] = startedAt
    end

    return startedAt
end

local function getElapsedSeconds(player)
    -- Online reward unlocks use the current server session only.
    return math.max(0, os.time() - getSessionStartTime(player))
end

local function getOrCreateRemoteFunction(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function playObtainEffect(player, message)
    local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
    if playObtainEffectRE then
        playObtainEffectRE:FireClient(player, message, true)
    end
end

local ONLINE_REWARD_SNAPSHOT_FIELDS = {
    "Coins",
    "TotalSun",
    "Inventory",
    "Hotbar",
    "UnlockedMutations",
    "ExclusiveRollTickets",
    "OnlineRewardClaimed",
    "OnlineRewardCycleStartedAt",
    "OnlineRewardRefreshAt",
}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE:FireClient(player, data)
    end
end

local function snapshotOnlineRewardState(data)
    local snapshot = {}
    for _, fieldName in ipairs(ONLINE_REWARD_SNAPSHOT_FIELDS) do
        snapshot[fieldName] = cloneValue(data[fieldName])
    end
    return snapshot
end

local function restoreOnlineRewardState(data, snapshot)
    for _, fieldName in ipairs(ONLINE_REWARD_SNAPSHOT_FIELDS) do
        data[fieldName] = cloneValue(snapshot[fieldName])
    end
end

local function rollbackOnlineRewardClaim(player, data, snapshot)
    restoreOnlineRewardState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = PlayerDataManager.ForceSave(player)
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[OnlineRewardService] Rollback save failed for " .. player.Name .. ": " .. tostring(rollbackErr))
    end
end

local function addExclusiveRollTicket(player, data, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))

    data.ExclusiveRollTickets = math.max(0, math.floor(tonumber(data.ExclusiveRollTickets) or 0)) + amount

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE:FireClient(player, data)
    end

    return true, "Exclusive Roll x" .. tostring(amount)
end

local function grantReward(player, data, rewardConfig)
    local rewardType = rewardConfig.RewardType
    local amount = math.max(1, math.floor(tonumber(rewardConfig.Amount) or 1))

    if rewardType == "Coins" then
        local grantedAmount = PlayerDataManager.GiveCoins(player, amount) or amount
        return true, tostring(grantedAmount) .. " Sun"
    end

    if rewardType == "RandomSeed" then
        local rewardItem = ZombieBoxService.RollRewardItem("Seed")
        local seedId = rewardItem and rewardItem.id
        if not (seedId and ItemConfig.Seeds and ItemConfig.Seeds[seedId]) then
            return false, "Random seed reward config is empty."
        end

        local seedAmount = math.max(1, math.floor(tonumber(rewardItem.amount) or amount))
        PlayerDataManager.GiveSeed(player, seedId, seedAmount, true)
        local seedName = tostring((ItemConfig.Seeds[seedId] and ItemConfig.Seeds[seedId].Name) or seedId)
        return true, tostring(seedAmount) .. "x " .. seedName, "Congratulations, you obtained " .. tostring(seedAmount) .. "x " .. seedName
    end

    if rewardType == "RandomPlant" then
        local rewardItem = ZombieBoxService.RollRewardItem("Plant")
        local plantId = rewardItem and rewardItem.id
        if not (plantId and ItemConfig.Plants and ItemConfig.Plants[plantId]) then
            return false, "Random plant reward config is empty."
        end

        local plantAmount = math.max(1, math.floor(tonumber(rewardItem.amount) or amount))
        local mutation = math.max(1, math.floor(tonumber(rewardItem.Mutation) or 1))
        PlayerDataManager.GivePlant(player, plantId, plantAmount, mutation, true)
        local plantName = tostring((ItemConfig.Plants[plantId] and ItemConfig.Plants[plantId].Name) or plantId)
        return true, tostring(plantAmount) .. "x " .. plantName, "Congratulations, you obtained " .. tostring(plantAmount) .. "x " .. plantName
    end

    if rewardType == "Plant" then
        local plantId = rewardConfig.PlantId
        if not (plantId and ItemConfig.Plants and ItemConfig.Plants[plantId]) then
            return false, "Plant reward config not found."
        end

        local mutation = math.max(1, math.floor(tonumber(rewardConfig.Mutation) or 1))
        PlayerDataManager.GivePlant(player, plantId, amount, mutation, true)
        local plantName = tostring((ItemConfig.Plants[plantId] and ItemConfig.Plants[plantId].Name) or plantId)
        return true, tostring(amount) .. "x " .. plantName, "Congratulations, you obtained " .. tostring(amount) .. "x " .. plantName
    end

    if rewardType == "ExclusiveRollTicket" then
        return addExclusiveRollTicket(player, data, amount)
    end

    return false, "Unknown reward type."
end

local function buildState(player)
    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        return nil
    end

    local claimed, stateChanged = normalizeRewardState(data)
    saveRewardStateIfChanged(player, stateChanged, "normalizing reward state")
    local elapsed = getElapsedSeconds(player)
    local refreshAt = math.max(0, math.floor(tonumber(data.OnlineRewardRefreshAt) or 0))
    local rewardStates = {}

    for index, rewardConfig in ipairs(OnlineRewardConfig.Rewards or {}) do
        local requiredSeconds = math.max(0, math.floor(tonumber(rewardConfig.RequiredSeconds) or 0))
        local isClaimed = claimed[tostring(index)] == true
        rewardStates[index] = {
            Index = index,
            RequiredSeconds = requiredSeconds,
            RemainingSeconds = math.max(0, requiredSeconds - elapsed),
            CanClaim = not isClaimed and elapsed >= requiredSeconds,
            Claimed = isClaimed,
            DisplayName = rewardConfig.DisplayName or ("Reward " .. tostring(index)),
        }
    end

    return {
        ServerTime = os.time(),
        ElapsedSeconds = elapsed,
        RefreshActive = refreshAt > 0,
        RefreshRemainingSeconds = refreshAt > 0 and math.max(0, refreshAt - os.time()) or REFRESH_INTERVAL_SECONDS,
        RefreshDurationSeconds = REFRESH_INTERVAL_SECONDS,
        Rewards = rewardStates,
    }
end

local function claimReward(player, rewardIndex)
    rewardIndex = tonumber(rewardIndex)
    if not rewardIndex then
        return false, "Invalid reward.", buildState(player)
    end

    rewardIndex = math.floor(rewardIndex)
    local rewardConfig = OnlineRewardConfig.GetReward(rewardIndex)
    if not rewardConfig then
        return false, "Invalid reward.", buildState(player)
    end

    if claimingPlayers[player] then
        return false, "Claim is already processing.", buildState(player)
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Data is still loading.", nil
    end
    if not PlayerDataManager.IsDataSafeToSave(player) then
        claimingPlayers[player] = nil
        return false, "Data is still saving. Please try again later.", buildState(player)
    end

    local claimed = normalizeRewardState(data)
    local rewardKey = tostring(rewardIndex)
    if claimed[rewardKey] == true then
        claimingPlayers[player] = nil
        return false, "Reward already claimed.", buildState(player)
    end

    local requiredSeconds = math.max(0, math.floor(tonumber(rewardConfig.RequiredSeconds) or 0))
    if getElapsedSeconds(player) < requiredSeconds then
        claimingPlayers[player] = nil
        return false, "Reward is not ready.", buildState(player)
    end

    local snapshot = snapshotOnlineRewardState(data)
    local granted, rewardName, effectMessage = grantReward(player, data, rewardConfig)
    if not granted then
        restoreOnlineRewardState(data, snapshot)
        fireInventoryUpdate(player, data)
        claimingPlayers[player] = nil
        return false, rewardName or "Reward config is invalid.", buildState(player)
    end

    claimed[rewardKey] = true
    if data.OnlineRewardRefreshAt <= 0 then
        setRewardCycle(data, os.time())
    end

    local saved, saveErr = PlayerDataManager.ForceSave(player)
    if not saved then
        warn("[OnlineRewardService] Save failed after claim for " .. player.Name .. ": " .. tostring(saveErr))
        rollbackOnlineRewardClaim(player, data, snapshot)
        claimingPlayers[player] = nil
        return false, "Save failed. Please try again.", buildState(player)
    end

    if effectMessage then
        playObtainEffect(player, effectMessage)
    end
    claimingPlayers[player] = nil
    return true, "Claimed " .. tostring(rewardName) .. "!", buildState(player)
end

function OnlineRewardService.Init()
    local getStateRF = getOrCreateRemoteFunction(OnlineRewardConfig.StateRemoteName or "GetOnlineRewardStateRF")
    local claimRF = getOrCreateRemoteFunction(OnlineRewardConfig.ClaimRemoteName or "ClaimOnlineRewardRF")

    getStateRF.OnServerInvoke = function(player)
        return buildState(player)
    end

    claimRF.OnServerInvoke = function(player, rewardIndex)
        return claimReward(player, rewardIndex)
    end

    for _, player in ipairs(Players:GetPlayers()) do
        sessionStartTimes[player.UserId] = os.time()
    end

    Players.PlayerAdded:Connect(function(player)
        sessionStartTimes[player.UserId] = os.time()
        task.spawn(function()
            local data = PlayerDataManager.WaitForPlayerData(player, 20)
            if data then
                local _, stateChanged = normalizeRewardState(data)
                saveRewardStateIfChanged(player, stateChanged, "player join reward state normalization")
            end
        end)
    end)

    Players.PlayerRemoving:Connect(function(player)
        sessionStartTimes[player.UserId] = nil
        claimingPlayers[player] = nil
    end)

    print("Server: OnlineRewardService active.")
end

return OnlineRewardService

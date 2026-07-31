local LeaderboardSettlementService = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GiftingService = require(script.Parent.GiftingService)
local GiftingConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GiftingConfig"))
local RankingSeasonConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankingSeasonConfig"))

local SETTLEMENT_ID = RankingSeasonConfig.SettlementId
local TOP_COUNT = RankingSeasonConfig.TopCount or 60
local QUEUE_DELAY_SECONDS = tonumber(RankingSeasonConfig.SettlementQueueDelaySeconds) or 1
local LOCK_SECONDS = 900
local LOCK_ID = if game.JobId and game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local PreviousRankingStore = DataStoreService:GetOrderedDataStore(RankingSeasonConfig.PreviousStoreName or "LevelRanking_v1")
local SettlementStateStore = DataStoreService:GetDataStore(RankingSeasonConfig.SettlementStateStoreName or "LeaderboardSettlementState_v1")

local function normalizeState(rawState)
    local state = type(rawState) == "table" and rawState or {}
    state.SettlementId = SETTLEMENT_ID
    state.PreviousStoreName = RankingSeasonConfig.PreviousStoreName
    state.CurrentStoreName = RankingSeasonConfig.CurrentStoreName
    return state
end

local function acquireSettlementLock()
    local acquired = false
    local completed = false

    local success, err = pcall(function()
        SettlementStateStore:UpdateAsync(SETTLEMENT_ID, function(rawState)
            local state = normalizeState(rawState)
            if state.Status == "Completed" then
                completed = true
                return state
            end

            local now = os.time()
            local lockExpiresAt = tonumber(state.LockExpiresAt) or 0
            if state.Status == "InProgress" and lockExpiresAt > now then
                return state
            end

            state.Status = "InProgress"
            state.LockId = LOCK_ID
            state.LockExpiresAt = now + LOCK_SECONDS
            state.StartedAt = tonumber(state.StartedAt) or now
            state.LastAttemptAt = now
            state.Attempts = math.max(0, math.floor(tonumber(state.Attempts) or 0)) + 1
            acquired = true
            return state
        end)
    end)

    if not success then
        return false, false, err
    end

    return acquired, completed, nil
end

local function markSettlementFinished(entries, failedRewards)
    local status = (#failedRewards <= 0) and "Completed" or "Failed"
    local success, err = pcall(function()
        SettlementStateStore:UpdateAsync(SETTLEMENT_ID, function(rawState)
            local state = normalizeState(rawState)
            if state.Status == "Completed" then
                return state
            end

            if state.LockId ~= LOCK_ID and state.Status == "InProgress" then
                return state
            end

            state.Status = status
            state.LockExpiresAt = 0
            state.CompletedAt = status == "Completed" and os.time() or state.CompletedAt
            state.LastFailedAt = status == "Failed" and os.time() or state.LastFailedAt
            state.EntryCount = #entries
            state.FailedRewards = failedRewards
            state.Snapshot = entries
            return state
        end)
    end)

    if not success then
        warn("[LeaderboardSettlement] Failed to mark settlement state: " .. tostring(err))
        return false, err
    end

    return status == "Completed", status
end

local function readLeaderboardEntries()
    local success, pagesOrErr = pcall(function()
        return PreviousRankingStore:GetSortedAsync(false, TOP_COUNT)
    end)

    if not success or not pagesOrErr then
        return nil, pagesOrErr
    end

    local entries = {}
    for rank, entry in ipairs(pagesOrErr:GetCurrentPage()) do
        local userId = tonumber(entry.key)
        if userId and userId > 0 then
            table.insert(entries, {
                Rank = rank,
                UserId = userId,
                Score = tonumber(entry.value) or 0,
            })
        end
    end

    return entries
end

local function saveSettlementSnapshot(entries)
    local success, err = pcall(function()
        SettlementStateStore:UpdateAsync(SETTLEMENT_ID, function(rawState)
            local state = normalizeState(rawState)
            if state.LockId ~= LOCK_ID and state.Status == "InProgress" then
                return state
            end

            state.EntryCount = #entries
            state.Snapshot = entries
            state.SnapshotAt = os.time()
            return state
        end)
    end)

    if not success then
        warn("[LeaderboardSettlement] Failed to save settlement snapshot: " .. tostring(err))
        return false, err
    end

    return true, nil
end

local function normalizeAmount(amount)
    return math.max(1, math.floor(tonumber(amount) or 1))
end

local function getRewardType(reward)
    return reward.RewardType or reward.Type
end

local function getRewardItemId(reward)
    return reward.ItemId or reward.SeedId or reward.PlantId or reward.ChestId or reward.TitleId
end

local function getConfiguredRewards(rewardTier)
    if type(rewardTier.Rewards) == "table" and #rewardTier.Rewards > 0 then
        return rewardTier.Rewards
    end

    local rewards = {}
    if rewardTier.PlantId then
        table.insert(rewards, {
            RewardType = GiftingConfig.RewardTypes.Plant,
            ItemId = rewardTier.PlantId,
            Amount = rewardTier.PlantAmount,
            Mutation = 1,
        })
    end
    if rewardTier.TitleId then
        table.insert(rewards, {
            RewardType = GiftingConfig.RewardTypes.Title,
            ItemId = rewardTier.TitleId,
            Amount = 1,
        })
    end

    return rewards
end

local function buildRewardText(entry, reward, amount, itemId)
    local rewardRankText = "Rank #" .. tostring(entry.Rank)
    local displayName = reward.DisplayName or reward.Name or itemId or getRewardType(reward) or "Reward"

    if getRewardType(reward) == GiftingConfig.RewardTypes.Title then
        return rewardRankText .. ": " .. tostring(displayName)
    end

    return rewardRankText .. ": " .. tostring(amount) .. "x " .. tostring(displayName)
end

local function buildGift(entry, reward, index, createdAt)
    local rewardType = getRewardType(reward)
    local itemId = getRewardItemId(reward)
    local amount = normalizeAmount(reward.Amount)

    return {
        Id = SETTLEMENT_ID .. "_" .. tostring(entry.UserId) .. "_" .. tostring(index) .. "_" .. tostring(rewardType) .. "_" .. tostring(itemId or "Reward"),
        Title = "Leaderboard Season Reward",
        RewardType = rewardType,
        ItemId = itemId,
        Amount = amount,
        Mutation = reward.Mutation or reward.MutationLevel,
        RewardText = reward.RewardText or buildRewardText(entry, reward, amount, itemId),
        CreatedAt = createdAt,
    }
end

local function buildAdminPreviewGift(entry, reward, index, createdAt, previewVersion)
    local rewardType = getRewardType(reward)
    local itemId = getRewardItemId(reward)
    local amount = normalizeAmount(reward.Amount)

    return {
        Id = table.concat({
            "AdminSettlementPreview",
            previewVersion,
            SETTLEMENT_ID,
            tostring(entry.UserId),
            "Rank" .. tostring(entry.Rank),
            tostring(index),
            tostring(rewardType),
            tostring(itemId or "Reward"),
        }, "_"),
        Title = "Leaderboard Season Reward",
        RewardType = rewardType,
        ItemId = itemId,
        Amount = amount,
        Mutation = reward.Mutation or reward.MutationLevel,
        RewardText = reward.RewardText or buildRewardText(entry, reward, amount, itemId),
        CreatedAt = createdAt,
    }
end

local function queueAdminSettlementPreviews()
    if RankingSeasonConfig.AdminSettlementPreviewEnabled ~= true then
        return
    end

    if RunService:IsStudio() and RankingSeasonConfig.AdminSettlementPreviewInStudio ~= true then
        return
    end

    if type(SETTLEMENT_ID) ~= "string" or SETTLEMENT_ID == "" then
        warn("[LeaderboardSettlement] Admin preview skipped: SettlementId is missing.")
        return
    end

    local previewVersion = RankingSeasonConfig.AdminSettlementPreviewVersion
    if type(previewVersion) ~= "string" or previewVersion == "" then
        warn("[LeaderboardSettlement] Admin preview skipped: preview version is missing.")
        return
    end

    local previewRanks = RankingSeasonConfig.AdminSettlementPreviewRanks
    if type(previewRanks) ~= "table" then
        warn("[LeaderboardSettlement] Admin preview skipped: preview ranks config is invalid.")
        return
    end

    for configuredUserId, configuredRank in pairs(previewRanks) do
        local userId = tonumber(configuredUserId)
        local rank = tonumber(configuredRank)
        if not userId or userId <= 0 or userId % 1 ~= 0 or not rank or rank <= 0 or rank % 1 ~= 0 then
            warn("[LeaderboardSettlement] Admin preview skipped invalid user/rank config: "
                .. tostring(configuredUserId) .. "/" .. tostring(configuredRank))
            continue
        end

        local rewardTier = RankingSeasonConfig.GetRewardForRank(rank)
        if not rewardTier then
            warn("[LeaderboardSettlement] Admin preview skipped: no reward tier for rank " .. tostring(rank) .. ".")
            continue
        end

        local entry = {
            UserId = userId,
            Rank = rank,
        }
        local gifts = {}
        local createdAt = os.time()
        for index, reward in ipairs(getConfiguredRewards(rewardTier)) do
            table.insert(gifts, buildAdminPreviewGift(entry, reward, index, createdAt, previewVersion))
        end

        if #gifts <= 0 then
            warn("[LeaderboardSettlement] Admin preview skipped: reward tier is empty for rank " .. tostring(rank) .. ".")
            continue
        end

        local callOk, giftsOk, giftsMessage = pcall(GiftingService.QueueGiftsForUserId, userId, gifts)
        if not callOk then
            warn("[LeaderboardSettlement] Admin preview queue failed for user " .. tostring(userId)
                .. ": " .. tostring(giftsOk))
        elseif not giftsOk then
            warn("[LeaderboardSettlement] Admin preview queue failed for user " .. tostring(userId)
                .. ": " .. tostring(giftsMessage))
        end
    end
end

local function queueRankReward(entry)
    local reward = RankingSeasonConfig.GetRewardForRank(entry.Rank)
    if not reward then
        return true
    end

    if RankingSeasonConfig.SettlementAutoGiftEnabled ~= true then
        return true
    end

    local gifts = {}
    local createdAt = os.time()
    for index, rewardItem in ipairs(getConfiguredRewards(reward)) do
        table.insert(gifts, buildGift(entry, rewardItem, index, createdAt))
    end

    if #gifts <= 0 then
        return true
    end

    local giftsOk, giftsMessage = GiftingService.QueueGiftsForUserId(entry.UserId, gifts)
    if not giftsOk then
        return false, {
            {
                UserId = entry.UserId,
                Rank = entry.Rank,
                Gift = "RankRewards",
                Error = tostring(giftsMessage),
            },
        }
    end

    return true
end

local function appendFailure(failedRewards, failure)
    if type(failure) == "table" and failure.UserId then
        table.insert(failedRewards, failure)
        return
    end

    if type(failure) == "table" then
        for _, item in ipairs(failure) do
            if type(item) == "table" then
                table.insert(failedRewards, item)
            end
        end
    end
end

local function runSettlement()
    if type(SETTLEMENT_ID) ~= "string" or SETTLEMENT_ID == "" then
        warn("[LeaderboardSettlement] SettlementId is missing.")
        return
    end

    if RunService:IsStudio() and RankingSeasonConfig.RunSettlementInStudio ~= true then
        return
    end

    local acquired, completed, lockErr = acquireSettlementLock()
    if completed then
        print("[LeaderboardSettlement] Settlement already completed: " .. SETTLEMENT_ID)
        return
    end
    if not acquired then
        if lockErr then
            warn("[LeaderboardSettlement] Failed to acquire settlement lock: " .. tostring(lockErr))
        else
            print("[LeaderboardSettlement] Another server is processing settlement: " .. SETTLEMENT_ID)
        end
        return
    end

    local entries, readErr = readLeaderboardEntries()
    if not entries then
        markSettlementFinished({}, {
            {
                Gift = "ReadLeaderboard",
                Error = tostring(readErr),
            },
        })
        return
    end

    local snapshotOk, snapshotErr = saveSettlementSnapshot(entries)
    if not snapshotOk then
        markSettlementFinished(entries, {
            {
                Gift = "SaveSnapshot",
                Error = tostring(snapshotErr),
            },
        })
        return
    end

    local failedRewards = {}
    for _, entry in ipairs(entries) do
        local ok, failures = queueRankReward(entry)
        if not ok then
            appendFailure(failedRewards, failures)
        end

        task.wait(QUEUE_DELAY_SECONDS)
    end

    local completedOk, status = markSettlementFinished(entries, failedRewards)
    if completedOk then
        print("[LeaderboardSettlement] Completed " .. SETTLEMENT_ID .. " for " .. tostring(#entries) .. " entries.")
    else
        warn("[LeaderboardSettlement] Settlement ended with status " .. tostring(status)
            .. "; failed rewards: " .. tostring(#failedRewards))
    end
end

function LeaderboardSettlementService.Init()
    task.spawn(function()
        task.wait(5)
        local success, err = pcall(queueAdminSettlementPreviews)
        if not success then
            warn("[LeaderboardSettlement] Admin preview failed: " .. tostring(err))
        end
    end)

    task.spawn(function()
        task.wait(5)
        runSettlement()
    end)

    print("Server: LeaderboardSettlementService active.")
end

return LeaderboardSettlementService

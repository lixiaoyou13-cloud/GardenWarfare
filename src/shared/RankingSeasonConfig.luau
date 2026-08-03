local RankingSeasonConfig = {}

RankingSeasonConfig.SettlementId = "LevelRanking_v2_20260731"
RankingSeasonConfig.SeasonId = "LevelRanking_v3_20260731_Cap1000"
RankingSeasonConfig.PreviousSeasonId = "LevelRanking_v2_20260707_Reset1"
RankingSeasonConfig.PreviousStoreName = "LevelRanking_v2"
RankingSeasonConfig.CurrentStoreName = "LevelRanking_v3_lazy_v1"
RankingSeasonConfig.SettlementStateStoreName = "LeaderboardSettlementState_v1"
RankingSeasonConfig.TopCount = 60
RankingSeasonConfig.RankValuePrefix = "Lv."
RankingSeasonConfig.RunSettlementInStudio = false
RankingSeasonConfig.SettlementAutoGiftEnabled = true
RankingSeasonConfig.SettlementQueueDelaySeconds = 1
RankingSeasonConfig.DefaultSeasonNextLevel = 1

RankingSeasonConfig.AdminSettlementPreviewEnabled = true
RankingSeasonConfig.AdminSettlementPreviewInStudio = false
RankingSeasonConfig.AdminSettlementPreviewVersion = "rank50_v1"
RankingSeasonConfig.AdminSettlementPreviewRanks = {
    [10972923838] = 50,
}

RankingSeasonConfig.SeasonCarryOverFromSeasonId = RankingSeasonConfig.PreviousSeasonId
RankingSeasonConfig.SeasonCarryOverMaxClearedLevel = 1000
RankingSeasonConfig.SeasonCarryOverFallbackToUnlockedLevel = true

RankingSeasonConfig.CurrentStoreMigrationEnabled = false
RankingSeasonConfig.CurrentStoreMigrationId = "LevelRanking_v2_to_v3_cap1000_20260731"
RankingSeasonConfig.CurrentStoreMigrationSourceName = "LevelRanking_v2"
RankingSeasonConfig.CurrentStoreMigrationStateStoreName = "RankingStoreMigrationState_v1"
RankingSeasonConfig.CurrentStoreMigrationInStudio = false
RankingSeasonConfig.CurrentStoreMigrationPageSize = 100
RankingSeasonConfig.CurrentStoreMigrationMaxPages = 1000
RankingSeasonConfig.CurrentStoreMigrationWriteDelaySeconds = 0.05
RankingSeasonConfig.CurrentStoreMigrationCapClearedLevel = 1000

RankingSeasonConfig.LazyRankingMigrationEnabled = true
RankingSeasonConfig.LazyRankingMigrationSourceStoreName = "LevelRanking_v2"
RankingSeasonConfig.LazyRankingMigrationInStudio = false
RankingSeasonConfig.LazyRankingMigrationCapClearedLevel = 1000
RankingSeasonConfig.LazyRankingMigrationInitialRetryDelaySeconds = 30
RankingSeasonConfig.LazyRankingMigrationRetryIntervalSeconds = 5

RankingSeasonConfig.CurrentStoreResetEnabled = false
RankingSeasonConfig.CurrentStoreResetId = "LevelRanking_v3_unused_reset_20260731"
RankingSeasonConfig.CurrentStoreResetStateStoreName = "RankingStoreResetState_v1"
RankingSeasonConfig.CurrentStoreResetInStudio = false
RankingSeasonConfig.CurrentStoreResetPageSize = 100
RankingSeasonConfig.CurrentStoreResetMaxPages = 50

RankingSeasonConfig.RewardTiers = {
    {
        MinRank = 1,
        MaxRank = 1,
        Rewards = {
            { RewardType = "Plant", ItemId = "GloomShroom", Amount = 12, Mutation = 1, DisplayName = "Gloom-shroom" },
            { RewardType = "Item", ItemId = "DivinePotion", Amount = 20, DisplayName = "Divine Potion" },
            { RewardType = "Item", ItemId = "ThunderPotion", Amount = 10, DisplayName = "Thunder Potion" },
        },
    },
    {
        MinRank = 2,
        MaxRank = 5,
        Rewards = {
            { RewardType = "Plant", ItemId = "GloomShroom", Amount = 8, Mutation = 1, DisplayName = "Gloom-shroom" },
            { RewardType = "Item", ItemId = "DivinePotion", Amount = 10, DisplayName = "Divine Potion" },
            { RewardType = "Item", ItemId = "ThunderPotion", Amount = 5, DisplayName = "Thunder Potion" },
        },
    },
    {
        MinRank = 6,
        MaxRank = 10,
        Rewards = {
            { RewardType = "Plant", ItemId = "GloomShroom", Amount = 6, Mutation = 1, DisplayName = "Gloom-shroom" },
            { RewardType = "Item", ItemId = "DivinePotion", Amount = 6, DisplayName = "Divine Potion" },
            { RewardType = "Item", ItemId = "ThunderPotion", Amount = 3, DisplayName = "Thunder Potion" },
        },
    },
    {
        MinRank = 11,
        MaxRank = 20,
        Rewards = {
            { RewardType = "Plant", ItemId = "GloomShroom", Amount = 4, Mutation = 1, DisplayName = "Gloom-shroom" },
            { RewardType = "Item", ItemId = "DivinePotion", Amount = 3, DisplayName = "Divine Potion" },
        },
    },
    {
        MinRank = 21,
        MaxRank = 60,
        Rewards = {
            { RewardType = "Plant", ItemId = "GloomShroom", Amount = 2, Mutation = 1, DisplayName = "Gloom-shroom" },
            { RewardType = "Item", ItemId = "DivinePotion", Amount = 2, DisplayName = "Divine Potion" },
        },
    },
}

local function normalizePositiveInteger(value, fallback)
    local numberValue = math.floor(tonumber(value) or fallback or 1)
    if numberValue < 1 then
        numberValue = 1
    end

    return numberValue
end

function RankingSeasonConfig.GetRewardForRank(rank)
    rank = math.floor(tonumber(rank) or 0)
    for _, tier in ipairs(RankingSeasonConfig.RewardTiers) do
        if rank >= tier.MinRank and rank <= tier.MaxRank then
            return tier
        end
    end

    return nil
end

function RankingSeasonConfig.GetSeasonId()
    return tostring(RankingSeasonConfig.SeasonId or RankingSeasonConfig.CurrentStoreName or "LevelRanking_v3")
end

function RankingSeasonConfig.GetCarryOverClearedLevel(data)
    if type(data) ~= "table" then
        return 0
    end

    local maxClearedLevel = math.floor(tonumber(RankingSeasonConfig.SeasonCarryOverMaxClearedLevel) or 0)
    if maxClearedLevel <= 0 then
        return 0
    end

    local clearedLevel = 0
    local levels = data.RankingSeasonUnlockedLevels
    local sourceSeasonId = tostring(RankingSeasonConfig.SeasonCarryOverFromSeasonId or RankingSeasonConfig.PreviousSeasonId or "")
    local sourceNextLevel = nil

    if type(levels) == "table" and sourceSeasonId ~= "" then
        sourceNextLevel = levels[sourceSeasonId]
    end

    if sourceNextLevel ~= nil then
        clearedLevel = normalizePositiveInteger(sourceNextLevel, 1) - 1
    elseif RankingSeasonConfig.SeasonCarryOverFallbackToUnlockedLevel == true then
        clearedLevel = normalizePositiveInteger(data.UnlockedLevel, 1) - 1
    end

    return math.min(maxClearedLevel, math.max(0, clearedLevel))
end

function RankingSeasonConfig.NormalizeSeasonUnlockedLevels(data, seasonId)
    if type(data) ~= "table" then
        return nil, false
    end

    local changed = false
    seasonId = tostring(seasonId or RankingSeasonConfig.GetSeasonId())
    if type(data.RankingSeasonUnlockedLevels) ~= "table" then
        data.RankingSeasonUnlockedLevels = {}
        changed = true
    end

    local rawNextLevel = data.RankingSeasonUnlockedLevels[seasonId]
    local nextLevel
    if rawNextLevel == nil and seasonId == RankingSeasonConfig.GetSeasonId() then
        nextLevel = RankingSeasonConfig.GetCarryOverClearedLevel(data) + 1
    else
        nextLevel = normalizePositiveInteger(rawNextLevel, RankingSeasonConfig.DefaultSeasonNextLevel or 1)
    end

    if rawNextLevel ~= nextLevel then
        data.RankingSeasonUnlockedLevels[seasonId] = nextLevel
        changed = true
    end

    return data.RankingSeasonUnlockedLevels, changed
end

function RankingSeasonConfig.GetSeasonNextLevel(data, seasonId)
    seasonId = tostring(seasonId or RankingSeasonConfig.GetSeasonId())
    local levels = RankingSeasonConfig.NormalizeSeasonUnlockedLevels(data, seasonId)
    if type(levels) ~= "table" then
        return normalizePositiveInteger(RankingSeasonConfig.DefaultSeasonNextLevel, 1)
    end

    return normalizePositiveInteger(levels[seasonId], RankingSeasonConfig.DefaultSeasonNextLevel or 1)
end

function RankingSeasonConfig.GetSeasonClearedLevel(data, seasonId)
    return math.max(0, RankingSeasonConfig.GetSeasonNextLevel(data, seasonId) - 1)
end

function RankingSeasonConfig.AdvanceSeasonLevel(data, completedLevelId, seasonId)
    if type(data) ~= "table" then
        return false, 0
    end

    seasonId = tostring(seasonId or RankingSeasonConfig.GetSeasonId())
    local currentNextLevel = RankingSeasonConfig.GetSeasonNextLevel(data, seasonId)
    completedLevelId = math.max(0, math.floor(tonumber(completedLevelId) or 0))

    if completedLevelId >= currentNextLevel then
        data.RankingSeasonUnlockedLevels[seasonId] = completedLevelId + 1
        return true, RankingSeasonConfig.GetSeasonClearedLevel(data, seasonId)
    end

    return false, RankingSeasonConfig.GetSeasonClearedLevel(data, seasonId)
end

return RankingSeasonConfig

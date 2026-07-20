local RankingSeasonConfig = {}

RankingSeasonConfig.SettlementId = "LevelRanking_v1_20260707"
RankingSeasonConfig.SeasonId = "LevelRanking_v2_20260707_Reset1"
RankingSeasonConfig.PreviousStoreName = "LevelRanking_v1"
RankingSeasonConfig.CurrentStoreName = "LevelRanking_v2"
RankingSeasonConfig.SettlementStateStoreName = "LeaderboardSettlementState_v1"
RankingSeasonConfig.TopCount = 60
RankingSeasonConfig.RankValuePrefix = "Lv."
RankingSeasonConfig.RunSettlementInStudio = false
RankingSeasonConfig.SettlementAutoGiftEnabled = true
RankingSeasonConfig.SettlementQueueDelaySeconds = 1
RankingSeasonConfig.DefaultSeasonNextLevel = 1
RankingSeasonConfig.CurrentStoreResetEnabled = false
RankingSeasonConfig.CurrentStoreResetId = "LevelRanking_v2_publish_reset_20260707"
RankingSeasonConfig.CurrentStoreResetStateStoreName = "RankingStoreResetState_v1"
RankingSeasonConfig.CurrentStoreResetInStudio = false
RankingSeasonConfig.CurrentStoreResetPageSize = 100
RankingSeasonConfig.CurrentStoreResetMaxPages = 50

RankingSeasonConfig.RewardTiers = {
    {
        MinRank = 1,
        MaxRank = 1,
        PlantId = "EnergyMangosteen",
        PlantAmount = 12,
        TitleId = "CreatorPlayerNo1",
    },
    {
        MinRank = 2,
        MaxRank = 5,
        PlantId = "EnergyMangosteen",
        PlantAmount = 8,
        TitleId = "CreatorPlayer",
    },
    {
        MinRank = 6,
        MaxRank = 10,
        PlantId = "EnergyMangosteen",
        PlantAmount = 6,
        TitleId = "CreatorPlayer",
    },
    {
        MinRank = 11,
        MaxRank = 20,
        PlantId = "EnergyMangosteen",
        PlantAmount = 4,
        TitleId = "CreatorPlayer",
    },
    {
        MinRank = 21,
        MaxRank = 60,
        PlantId = "EnergyMangosteen",
        PlantAmount = 2,
        TitleId = "CreatorPlayer",
    },
}

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
    return tostring(RankingSeasonConfig.SeasonId or RankingSeasonConfig.CurrentStoreName or "LevelRanking_v2")
end

function RankingSeasonConfig.NormalizeSeasonUnlockedLevels(data, seasonId)
    if type(data) ~= "table" then
        return nil
    end

    seasonId = tostring(seasonId or RankingSeasonConfig.GetSeasonId())
    if type(data.RankingSeasonUnlockedLevels) ~= "table" then
        data.RankingSeasonUnlockedLevels = {}
    end

    local nextLevel = math.floor(tonumber(data.RankingSeasonUnlockedLevels[seasonId]) or RankingSeasonConfig.DefaultSeasonNextLevel or 1)
    if nextLevel < 1 then
        nextLevel = 1
    end

    data.RankingSeasonUnlockedLevels[seasonId] = nextLevel
    return data.RankingSeasonUnlockedLevels
end

function RankingSeasonConfig.GetSeasonNextLevel(data, seasonId)
    seasonId = tostring(seasonId or RankingSeasonConfig.GetSeasonId())
    local levels = RankingSeasonConfig.NormalizeSeasonUnlockedLevels(data, seasonId)
    if type(levels) ~= "table" then
        return math.max(1, math.floor(tonumber(RankingSeasonConfig.DefaultSeasonNextLevel) or 1))
    end

    return math.max(1, math.floor(tonumber(levels[seasonId]) or RankingSeasonConfig.DefaultSeasonNextLevel or 1))
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

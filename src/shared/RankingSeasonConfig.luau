local RankingSeasonConfig = {}

RankingSeasonConfig.SettlementId = "LevelRanking_v1_20260707"
RankingSeasonConfig.SeasonId = "LevelRanking_v2"
RankingSeasonConfig.PreviousStoreName = "LevelRanking_v1"
RankingSeasonConfig.CurrentStoreName = "LevelRanking_v2"
RankingSeasonConfig.SettlementStateStoreName = "LeaderboardSettlementState_v1"
RankingSeasonConfig.TopCount = 60
RankingSeasonConfig.RankValuePrefix = "Lv.+"
RankingSeasonConfig.RunSettlementInStudio = false
RankingSeasonConfig.SettlementQueueDelaySeconds = 1

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

return RankingSeasonConfig

local LeaderboardRewardConfig = {}

--[[ 展示页触发模型路径，从 Workspace 下开始。 ]]
LeaderboardRewardConfig.TouchModelPaths = {
    "Leaderboard.Gifts_1",
    "Leaderboard.Gifts_2",
}

--[[ 兼容旧入口名。 ]]
LeaderboardRewardConfig.TouchModelName = "LeaderboardRewardModel"

--[[ 防止玩家站在触发区时反复打开页面。 ]]
LeaderboardRewardConfig.TouchDebounceSeconds = 2

--[[ StarterGui.BasicGui 下的排行榜奖励展示页配置。 ]]
LeaderboardRewardConfig.UiName = "RankingRewards"
LeaderboardRewardConfig.ContentFrameName = "Store"

--[[ 只负责调起展示页，不承载领奖或排行榜数据。 ]]
LeaderboardRewardConfig.RemoteNames = {
    Open = "OpenLeaderboardRewardRE",
}

return LeaderboardRewardConfig

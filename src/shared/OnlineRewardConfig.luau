local OnlineRewardConfig = {}

OnlineRewardConfig.StateRemoteName = "GetOnlineRewardStateRF"
OnlineRewardConfig.ClaimRemoteName = "ClaimOnlineRewardRF"

OnlineRewardConfig.ReadyGradient = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 255, 14)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(132, 255, 16)),
})

OnlineRewardConfig.ClaimedGradient = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(76, 76, 76)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 168, 168)),
})

OnlineRewardConfig.Rewards = {
    [1] = {
        RequiredSeconds = 0,
        RewardType = "Coins",
        Amount = 2000,
        DisplayName = "2K Sun",
    },
    [2] = {
        RequiredSeconds = 60,
        RewardType = "RandomSeed",
        DisplayName = "Random Seed Box",
    },
    [3] = {
        RequiredSeconds = 5 * 60,
        RewardType = "RandomPlant",
        DisplayName = "Random Plant Box",
    },
    [4] = {
        RequiredSeconds = 10 * 60,
        RewardType = "Coins",
        Amount = 20000,
        DisplayName = "20K Sun",
    },
    [5] = {
        RequiredSeconds = 15 * 60,
        RewardType = "ExclusiveRollTicket",
        Amount = 1,
        DisplayName = "Exclusive Roll x1",
    },
    [6] = {
        RequiredSeconds = 30 * 60,
        RewardType = "Plant",
        PlantId = "Melonpult",
        Amount = 1,
        Mutation = 1,
        DisplayName = "Melon-pult",
    },
    [7] = {
        RequiredSeconds = 60 * 60,
        RewardType = "ExclusiveRollTicket",
        Amount = 2,
        DisplayName = "Exclusive Roll x2",
    },
}

function OnlineRewardConfig.GetReward(index)
    return OnlineRewardConfig.Rewards[tonumber(index)]
end

return OnlineRewardConfig

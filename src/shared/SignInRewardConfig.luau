-- src/shared/SignInRewardConfig.luau
local SignInRewardConfig = {}

SignInRewardConfig.MaxTier = 3
SignInRewardConfig.DaysPerTier = 7
SignInRewardConfig.LoopStartTier = 2

SignInRewardConfig.Tiers = {
    [1] = {
        [1] = { RewardType = "Coins", Amount = 2000, Tip = "Sign-in successful! Obtained 2000 Sunshine" },
        [2] = { RewardType = "Seed", ItemId = "SnowPea", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Snow Pea Seed" },
        [3] = { RewardType = "Coins", Amount = 20000, Tip = "Sign-in successful! Obtained 20000 Sunshine" },
        [4] = { RewardType = "Seed", ItemId = "Sunflower", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Sunflower Seed" },
        [5] = { RewardType = "Coins", Amount = 100000, Tip = "Sign-in successful! Obtained 100000 Sunshine" },
        [6] = { RewardType = "Seed", ItemId = "Melonpult", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Melon-pult Seed" },
        [7] = { RewardType = "Seed", ItemId = "CobCannon", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Cob Cannon Seed" },
    },

    [2] = {
        [1] = { RewardType = "Coins", Amount = 500000, Tip = "Sign-in successful! Obtained 500000 Sunshine" },
        [2] = { RewardType = "Seed", ItemId = "Magnetshroom", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Magnet-shroom Seed" },
        [3] = { RewardType = "Coins", Amount = 1500000, Tip = "Sign-in successful! Obtained 1500000 Sunshine" },
        [4] = { RewardType = "Seed", ItemId = "Jalapeno", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Jalapeno Seed" },
        [5] = { RewardType = "Coins", Amount = 3000000, Tip = "Sign-in successful! Obtained 3000000 Sunshine" },
        [6] = { RewardType = "Seed", ItemId = "Threepeater", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Threepeater Seed" },
        [7] = { RewardType = "Seed", ItemId = "CobCannon", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Cob Cannon Seed" },
    },

    [3] = {
        [1] = { RewardType = "Coins", Amount = 2000000, Tip = "Sign-in successful! Obtained 2000000 Sunshine" },
        [2] = { RewardType = "Seed", ItemId = "Cactus", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Cactus Seed" },
        [3] = { RewardType = "Coins", Amount = 5000000, Tip = "Sign-in successful! Obtained 5000000 Sunshine" },
        [4] = { RewardType = "Seed", ItemId = "TwinSunflower", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Twin Sunflower Seed" },
        [5] = { RewardType = "Coins", Amount = 10000000, Tip = "Sign-in successful! Obtained 10000000 Sunshine" },
        [6] = { RewardType = "Seed", ItemId = "IceMelonpult", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Ice Melon-pult Seed" },
        [7] = { RewardType = "Seed", ItemId = "MusicIcePeashooter", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Music Ice Peashooter Seed" },
    },
}

function SignInRewardConfig.NormalizeTier(tier)
    tier = math.floor(tonumber(tier) or 1)
    if tier < 1 then
        return 1
    end
    if tier > SignInRewardConfig.MaxTier then
        return SignInRewardConfig.MaxTier
    end
    return tier
end

function SignInRewardConfig.GetReward(tier, day)
    tier = SignInRewardConfig.NormalizeTier(tier)
    day = math.floor(tonumber(day) or 1)
    local rewards = SignInRewardConfig.Tiers[tier]
    return rewards and rewards[day] or nil
end

function SignInRewardConfig.GetTierRewards(tier)
    return SignInRewardConfig.Tiers[SignInRewardConfig.NormalizeTier(tier)]
end

function SignInRewardConfig.GetNextTier(tier)
    tier = SignInRewardConfig.NormalizeTier(tier)
    if tier < SignInRewardConfig.MaxTier then
        return tier + 1
    end
    return SignInRewardConfig.NormalizeTier(SignInRewardConfig.LoopStartTier or 2)
end

for day, reward in pairs(SignInRewardConfig.Tiers[1]) do
    SignInRewardConfig[day] = reward
end

return SignInRewardConfig

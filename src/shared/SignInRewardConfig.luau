-- src/shared/SignInRewardConfig.luau
local SignInRewardConfig = {
    [1] = { RewardType = "Coins", Amount = 2000,    Tip = "Sign-in successful! Obtained 2000 Sunshine" },
    [2] = { RewardType = "Seed",  ItemId = "SnowPea", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Ice Shooter Seed" },
    [3] = { RewardType = "Coins",   Amount = 20000,  Tip = "Sign-in successful! Obtained 20000 Sunshine" },
    [4] = { RewardType = "Seed",  ItemId = "Sunflower", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Ice Sunflower Seed" },
    [5] = { RewardType = "Coins",   Amount = 100000,  Tip = "Sign-in successful! Obtained 100000 Sunshine" },
    [6] = { RewardType = "Seed",  ItemId = "Melonpult", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Ice Melonpult Seed" },
    [7] = { RewardType = "Seed",  ItemId = "IceMelonpult", Amount = 1, IsSpecial = true, Tip = "Sign-in successful! Obtained 1 Ice IceMelonpult Seed" },
}

return SignInRewardConfig
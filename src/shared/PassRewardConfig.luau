local PassRewardConfig = {}

PassRewardConfig.ClientVisible = false
PassRewardConfig.DisabledMessage = "Pass event has ended."

PassRewardConfig.RemoteName = "ClaimPassRewardRF"
PassRewardConfig.RegularMaxLevel = 10
PassRewardConfig.RepeatTier = 11
PassRewardConfig.MaxLevel = 11
PassRewardConfig.PremiumGamePassId = 1890839237
PassRewardConfig.ExpProductId = 3606687341
PassRewardConfig.ExpProductAmount = 200

PassRewardConfig.TrackKeys = {
    Free = "Free",
    Premium = "Premium",
}

PassRewardConfig.RewardTypes = {
    None = "None",
    PassShopToken = "PassShopToken",
    ExclusiveRollTicket = "ExclusiveRollTicket",
    Seed = "Seed",
    Plant = "Plant",
}

local function createEmptyReward(tier)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.None,
        Amount = 0,
        DisplayName = "No Token",
        Claimable = false,
    }
end

local function createRepeatTokenReward(trackKey)
    local amount = trackKey == PassRewardConfig.TrackKeys.Premium and 9 or 3
    return {
        Tier = PassRewardConfig.RepeatTier,
        Type = PassRewardConfig.RewardTypes.PassShopToken,
        Amount = amount,
        DisplayName = "Token",
        Repeatable = true,
    }
end

local function createRollReward(tier, amount, displayName)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.ExclusiveRollTicket,
        Amount = amount,
        DisplayName = displayName or "ROLLS",
    }
end

local function createSeedReward(tier, seedId, amount, displayName)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.Seed,
        SeedId = seedId,
        Amount = amount,
        DisplayName = displayName or seedId,
    }
end

local function createPlantReward(tier, plantId, amount, displayName)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.Plant,
        PlantId = plantId,
        Amount = amount,
        DisplayName = displayName or plantId,
        Mutation = 1,
    }
end

PassRewardConfig.Tracks = {
    Free = {},
    Premium = {},
}

for tier = 1, PassRewardConfig.RegularMaxLevel do
    PassRewardConfig.Tracks.Free[tier] = createEmptyReward(tier)
    PassRewardConfig.Tracks.Premium[tier] = createEmptyReward(tier)
end

PassRewardConfig.Tracks.Free[1] = createSeedReward(1, "TallWall", 1, "Tall Wall-nut Seed")
PassRewardConfig.Tracks.Free[2] = createRollReward(2, 1, "ROLLS")
PassRewardConfig.Tracks.Free[3] = createSeedReward(3, "TallWall", 2, "Tall Wall-nut Seed")
PassRewardConfig.Tracks.Free[4] = createPlantReward(4, "Chomper", 1, "Chomper")
PassRewardConfig.Tracks.Free[5] = createPlantReward(5, "Melonpult", 1, "Melon-pult")
PassRewardConfig.Tracks.Free[6] = createSeedReward(6, "TallWall", 3, "Tall Wall-nut Seed")
PassRewardConfig.Tracks.Free[7] = createSeedReward(7, "Chomper", 1, "Chomper Seed")
PassRewardConfig.Tracks.Free[8] = createPlantReward(8, "IceMelonpult", 1, "Ice Melon-pult")
PassRewardConfig.Tracks.Free[9] = createPlantReward(9, "IceMelonpult", 2, "Ice Melon-pult")
PassRewardConfig.Tracks.Free[10] = createSeedReward(10, "Chomper", 2, "Chomper Seed")

PassRewardConfig.Tracks.Premium[1] = createPlantReward(1, "Chomper", 1, "Chomper")
PassRewardConfig.Tracks.Premium[2] = createRollReward(2, 1, "ROLLS")
PassRewardConfig.Tracks.Premium[3] = createPlantReward(3, "Chomper", 1, "Chomper")
PassRewardConfig.Tracks.Premium[4] = createRollReward(4, 1, "ROLLS")
PassRewardConfig.Tracks.Premium[5] = createPlantReward(5, "CobCannon", 1, "Cob Cannon")
PassRewardConfig.Tracks.Premium[6] = createPlantReward(6, "MutantChomper", 1, "Mutant Chomper")
PassRewardConfig.Tracks.Premium[7] = createRollReward(7, 1, "ROLLS")
PassRewardConfig.Tracks.Premium[8] = createPlantReward(8, "MutantChomper", 2, "Mutant Chomper")
PassRewardConfig.Tracks.Premium[9] = createRollReward(9, 1, "ROLLS")
PassRewardConfig.Tracks.Premium[10] = createPlantReward(10, "MutantChomper", 3, "Mutant Chomper")

PassRewardConfig.Tracks.Free[PassRewardConfig.RepeatTier] = createRepeatTokenReward(PassRewardConfig.TrackKeys.Free)
PassRewardConfig.Tracks.Premium[PassRewardConfig.RepeatTier] = createRepeatTokenReward(PassRewardConfig.TrackKeys.Premium)

function PassRewardConfig.NormalizeTrackKey(trackKey)
    trackKey = tostring(trackKey or "")
    if trackKey == PassRewardConfig.TrackKeys.Free then
        return PassRewardConfig.TrackKeys.Free
    end
    if trackKey == PassRewardConfig.TrackKeys.Premium then
        return PassRewardConfig.TrackKeys.Premium
    end
    return nil
end

function PassRewardConfig.GetReward(trackKey, tier)
    trackKey = PassRewardConfig.NormalizeTrackKey(trackKey)
    tier = math.floor(tonumber(tier) or 0)
    if not trackKey or tier < 1 or tier > PassRewardConfig.MaxLevel then
        return nil
    end

    local track = PassRewardConfig.Tracks[trackKey]
    return track and track[tier] or nil
end

return PassRewardConfig

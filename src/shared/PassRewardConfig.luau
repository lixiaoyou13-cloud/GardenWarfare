local PassRewardConfig = {}

PassRewardConfig.ClientVisible = true
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
    Item = "Item",
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

local function createPlantReward(tier, plantId, amount, displayName, mutation)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.Plant,
        PlantId = plantId,
        Amount = amount,
        DisplayName = displayName or plantId,
        Mutation = mutation or 1,
    }
end

-- 发放背包道具奖励，例如变异药水。
local function createItemReward(tier, itemId, amount, displayName)
    return {
        Tier = tier,
        Type = PassRewardConfig.RewardTypes.Item,
        ItemId = itemId,
        Amount = amount,
        DisplayName = displayName or itemId,
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

-- 新一期战令：免费线奖励。
PassRewardConfig.Tracks.Free[1] = createSeedReward(1, "SunShroom", 1, "Sun-shroom Seed")
PassRewardConfig.Tracks.Free[2] = createItemReward(2, "ShinyPotion", 1, "Shiny Potion")
PassRewardConfig.Tracks.Free[3] = createSeedReward(3, "SunShroom", 2, "Sun-shroom Seed")
PassRewardConfig.Tracks.Free[4] = createSeedReward(4, "PumpkinShield", 1, "Pumpkin Shield Seed")
PassRewardConfig.Tracks.Free[5] = createRollReward(5, 1, "ROLLS")
PassRewardConfig.Tracks.Free[6] = createSeedReward(6, "SunShroom", 3, "Sun-shroom Seed")
PassRewardConfig.Tracks.Free[7] = createSeedReward(7, "PumpkinShield", 1, "Pumpkin Shield Seed")
PassRewardConfig.Tracks.Free[8] = createItemReward(8, "ShinyPotion", 1, "Shiny Potion")
PassRewardConfig.Tracks.Free[9] = createItemReward(9, "ShinyPotion", 1, "Shiny Potion")
PassRewardConfig.Tracks.Free[10] = createSeedReward(10, "PumpkinShield", 2, "Pumpkin Shield Seed")

-- 新一期战令：付费线奖励。
PassRewardConfig.Tracks.Premium[1] = createPlantReward(1, "PumpkinShield", 1, "Pumpkin Shield")
PassRewardConfig.Tracks.Premium[2] = createItemReward(2, "ThunderPotion", 1, "Thunder Potion")
PassRewardConfig.Tracks.Premium[3] = createPlantReward(3, "PumpkinShield", 1, "Pumpkin Shield")
PassRewardConfig.Tracks.Premium[4] = createItemReward(4, "ThunderPotion", 1, "Thunder Potion")
PassRewardConfig.Tracks.Premium[5] = createPlantReward(5, "CobCannon", 1, "Cob Cannon")
PassRewardConfig.Tracks.Premium[6] = createPlantReward(6, "MutantPumpkinShield", 1, "Mutant Pumpkin Shield")
PassRewardConfig.Tracks.Premium[7] = createItemReward(7, "ThunderPotion", 2, "Thunder Potion")
PassRewardConfig.Tracks.Premium[8] = createPlantReward(8, "MutantPumpkinShield", 2, "Mutant Pumpkin Shield")
PassRewardConfig.Tracks.Premium[9] = createItemReward(9, "DivinePotion", 2, "Divine Potion")
PassRewardConfig.Tracks.Premium[10] = createPlantReward(10, "MutantPumpkinShield", 3, "Mutant Pumpkin Shield")

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

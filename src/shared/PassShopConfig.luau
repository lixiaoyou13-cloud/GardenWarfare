local PassShopConfig = {}

PassShopConfig.RemoteName = "PurchasePassShopItemRF"
PassShopConfig.TokenDataKey = "PassShopTokens"

PassShopConfig.RewardTypes = {
    Plant = "Plant",
    Seed = "Seed",
    Chest = "Chest",
    PassShopToken = "PassShopToken",
    ExclusiveRollTicket = "ExclusiveRollTicket",
}

PassShopConfig.Items = {
    Gamepass1 = {
        Id = "VipSpecialItem",
        SlotName = "Gamepass1",
        DisplayName = "Mutant Chomper",
        Price = 12,
        PremiumOnly = true,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "MutantChomper",
            Amount = 1,
            Mutation = 1,
        },
    },
    Gamepass2 = {
        Id = "NormalItemA",
        SlotName = "Gamepass2",
        DisplayName = "Chomper",
        Price = 12,
        PremiumOnly = false,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "Chomper",
            Amount = 1,
            Mutation = 1,
        },
    },
    Gamepass3 = {
        Id = "NormalItemB",
        SlotName = "Gamepass3",
        DisplayName = "Tall Wall-nut",
        Price = 6,
        PremiumOnly = false,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "TallWall",
            Amount = 1,
            Mutation = 1,
        },
    },
}

PassShopConfig.Order = { "Gamepass1", "Gamepass2", "Gamepass3" }

function PassShopConfig.GetItem(slotName)
    slotName = tostring(slotName or "")
    return PassShopConfig.Items[slotName]
end

return PassShopConfig

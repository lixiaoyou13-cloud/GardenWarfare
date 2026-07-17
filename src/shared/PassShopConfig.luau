local PassShopConfig = {}

-- 战令商店购买 RemoteFunction 名称。
PassShopConfig.RemoteName = "PurchasePassShopItemRF"

-- 玩家数据中用于保存战令商店代币的字段。
PassShopConfig.TokenDataKey = "PassShopTokens"

-- 战令商店可发放的奖励类型。
PassShopConfig.RewardTypes = {
    Plant = "Plant",
    Seed = "Seed",
    Chest = "Chest",
    PassShopToken = "PassShopToken",
    ExclusiveRollTicket = "ExclusiveRollTicket",
}

-- 战令商店商品配置：配置 key 负责服务端购买，HolderName/SlotName 负责绑定 Studio UI。
PassShopConfig.Items = {
    V1Gamepass1 = {
        Id = "V1RareChomper",
        HolderName = "Holder_v1",
        SlotName = "Gamepass1",
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
    V1Gamepass2 = {
        Id = "V1CommonTallWall",
        HolderName = "Holder_v1",
        SlotName = "Gamepass2",
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
    V2Gamepass1 = {
        Id = "V2VipMutantPumpkinShield",
        HolderName = "Holder_v2",
        SlotName = "Gamepass1",
        DisplayName = "Mutant Pumpkin Shield",
        Price = 12,
        PremiumOnly = true,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "MutantPumpkinShield",
            Amount = 1,
            Mutation = 1,
        },
    },
    V2Gamepass2 = {
        Id = "V2RarePumpkinShield",
        HolderName = "Holder_v2",
        SlotName = "Gamepass2",
        DisplayName = "Pumpkin Shield",
        Price = 12,
        PremiumOnly = false,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "PumpkinShield",
            Amount = 1,
            Mutation = 1,
        },
    },
    V2Gamepass3 = {
        Id = "V2CommonSunShroom",
        HolderName = "Holder_v2",
        SlotName = "Gamepass3",
        DisplayName = "Sun-shroom",
        Price = 6,
        PremiumOnly = false,
        Reward = {
            Type = PassShopConfig.RewardTypes.Plant,
            PlantId = "SunShroom",
            Amount = 1,
            Mutation = 1,
        },
    },
}

-- 商品绑定顺序，按 Holder 从一期到二期排列。
PassShopConfig.Order = {
    "V1Gamepass1",
    "V1Gamepass2",
    "V2Gamepass1",
    "V2Gamepass2",
    "V2Gamepass3",
}

-- 根据商品配置 key 获取商店商品。
function PassShopConfig.GetItem(itemKey)
    itemKey = tostring(itemKey or "")
    return PassShopConfig.Items[itemKey]
end

return PassShopConfig

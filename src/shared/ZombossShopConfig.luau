local ZombossShopConfig = {}

ZombossShopConfig.RefreshIntervalSeconds = 12 * 60 * 60
ZombossShopConfig.BossSpawnIntervalSeconds = 30 * 60
ZombossShopConfig.BossEventEnabled = false -- 僵王 Boss 定时事件总开关；临时关闭时不再自动拉起入场和 Boss 战。

ZombossShopConfig.RemoteNames = {
    GetState = "GetZombossShopStateRF",
    BuyItem = "BuyZombossShopItemRF",
}

ZombossShopConfig.OfferOrder = {
    "Template1",
    "Template2",
    "Template3",
    "SpecialShop",
}

ZombossShopConfig.Offers = {
    Template1 = {
        Id = "Template1",
        TemplateName = "Template1",
        Cost = 9,
        Limit = 5,
        RobuxProductId = 3609144320,
        RewardItemId = "ShinyPotion",
        RewardAmount = 1,
    },
    Template2 = {
        Id = "Template2",
        TemplateName = "Template2",
        Cost = 29,
        Limit = 3,
        RobuxProductId = 3609144645,
        RewardItemId = "ThunderPotion",
        RewardAmount = 1,
    },
    Template3 = {
        Id = "Template3",
        TemplateName = "Template3",
        Cost = 59,
        Limit = 1,
        RobuxProductId = 3609144834,
        RewardItemId = "DivinePotion",
        RewardAmount = 1,
    },
    SpecialShop = {
        Id = "SpecialShop",
        TemplateName = "SpecialShop",
        Cost = 100,
        Limit = 6,
        RobuxProductId = 3609144946,
        RewardType = "Plant",
        RewardItemId = "LightningReed",
        RewardAmount = 1,
        RewardMutation = 1,
    },
}

function ZombossShopConfig.GetCurrentWindowId(now)
    return math.floor((tonumber(now) or os.time()) / ZombossShopConfig.RefreshIntervalSeconds)
end

function ZombossShopConfig.GetRefreshAt(now)
    return (ZombossShopConfig.GetCurrentWindowId(now) + 1) * ZombossShopConfig.RefreshIntervalSeconds
end

function ZombossShopConfig.IsBossEventEnabled()
    return ZombossShopConfig.BossEventEnabled == true
end

function ZombossShopConfig.GetBossSpawnWindowId(now)
    if not ZombossShopConfig.IsBossEventEnabled() then
        return nil
    end

    return math.floor((tonumber(now) or os.time()) / ZombossShopConfig.BossSpawnIntervalSeconds)
end

function ZombossShopConfig.GetNextBossSpawnAt(now)
    local windowId = ZombossShopConfig.GetBossSpawnWindowId(now)
    if not windowId then
        return nil
    end

    return (windowId + 1) * ZombossShopConfig.BossSpawnIntervalSeconds
end

function ZombossShopConfig.GetOffer(offerId)
    return ZombossShopConfig.Offers[offerId]
end

return ZombossShopConfig

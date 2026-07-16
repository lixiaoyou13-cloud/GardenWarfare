local GiftingConfig = {}

GiftingConfig.StateRemoteName = "GetGiftingRewardsRF"
GiftingConfig.ClaimRemoteName = "ClaimGiftingRewardRF"
GiftingConfig.UpdateRemoteName = "GiftingRewardsUpdatedRE"

GiftingConfig.DataKey = "PendingGifts"
GiftingConfig.ClaimedDataKey = "ClaimedGiftIds"
GiftingConfig.InboxStoreName = "GiftingInbox_v1"

GiftingConfig.RewardTypes = {
    Coins = "Coins",
    Seed = "Seed",
    Plant = "Plant",
    Item = "Item",
    Chest = "Chest",
    Title = "Title",
    ExclusiveRollTicket = "ExclusiveRollTicket",
    PassShopToken = "PassShopToken",
    Tacos = "Tacos",
}

GiftingConfig.AdminCommand = "!gift"
GiftingConfig.AdminDeductSunCommand = "!deductsun"

-- 全服官方礼物：固定 Id 用来防止玩家重复领取。
GiftingConfig.GlobalGifts = {
    {
        Id = "official-divine-potion-2026-07-16",
        Title = "Official Gift",
        RewardType = GiftingConfig.RewardTypes.Item,
        ItemId = "DivinePotion",
        Amount = 3,
        RewardText = "3x Divine Potion",
    },
}

return GiftingConfig

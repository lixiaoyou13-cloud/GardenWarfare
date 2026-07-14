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
    Chest = "Chest",
    Title = "Title",
    ExclusiveRollTicket = "ExclusiveRollTicket",
    PassShopToken = "PassShopToken",
    Tacos = "Tacos",
}

GiftingConfig.AdminCommand = "!gift"
GiftingConfig.AdminDeductSunCommand = "!deductsun"

return GiftingConfig

local ShopConfig = {}

ShopConfig.Restock = {
    Price = 1_000_000_000,
    RequestCooldownSeconds = 1,
    PaidStockDurationSeconds = 300,
    RemoteName = "RefreshShopStockRF",
    ButtonText = "Restock",
    PriceText = "1B Sun",
    PendingText = "Refreshing...",
    Messages = {
        Success = "Shop stock refreshed!",
        NotEnoughSun = "Not enough Sun.",
        SaveUnavailable = "Save unavailable. Please try again.",
        DataLoading = "Data is still loading.",
        ShopUnavailable = "Shop is unavailable. Please try again.",
        Processing = "Restock is already processing.",
        Cooldown = "Please wait before refreshing again.",
        Failed = "Restock failed. Please try again.",
        PlayerUnavailable = "Player is unavailable.",
    },
}

return ShopConfig

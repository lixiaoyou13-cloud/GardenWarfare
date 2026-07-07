local NoticeConfig = {}

NoticeConfig.StateRemoteName = "GetNoticeReadStateRF"
NoticeConfig.MarkSeenRemoteName = "MarkNoticeSeenRF"

-- Each notice creates one tag button in Notice.TypeButtons.
-- PublishedAt uses YYYY-MM-DD; the newest valid date is selected by default.
NoticeConfig.Notices = {
    {
        Id = "notice-2026-07-03",
        TagText = "2026/7/3",
        PublishedAt = "2026-07-03",
        Title = "July 3 Update Notice",
        Sections = {
            {
                Title = "Sun Reset and Leaderboard Settlement Delayed",
                Content = "The Sun reset and leaderboard settlement have been delayed to July 6. Players on the leaderboard will still receive special leaderboard rewards. Reward details will be available on Discord.",
            },
            {
                Title = "Plant Balance Adjustments",
                Content = "Melon-pult, Ice Melon-pult, and Cob Cannon now deal splash damage to nearby zombies. Ice Melon-pult splash damage also slows nearby zombies. Fume-shroom, Cactus, and Music Ice Peashooter now have piercing attacks. Piercing follow-up hits deal 60% damage.",
            },
        },
    },
    {
        Id = "notice-2026-07-02-important",
        TagText = "Important",
        PublishedAt = "2026-07-02",
        Title = "Important Notice",
        Content = "Because Jalapeno can cause Sun overflow, we have to make this decision for future game balance: Sun will be reset, with up to 1M Sun retained. At the same time, we will reduce the prices of all plants. This update will arrive on Friday.",
    },
    {
        Id = "notice-2026-07-02",
        TagText = "2026/7/2",
        PublishedAt = "2026-07-02",
        Title = "Update Notice",
        Sections = {
            {
                Title = "Disturb Option Added",
                Content = "A new Disturb option has been added to Settings. When enabled, other players cannot knock you back unless you are stealing a plant or carrying an airdrop.",
            },
        },
    },
    {
        Id = "notice-2026-07-01",
        TagText = "2026/7/1",
        PublishedAt = "2026-07-01",
        Title = "Please Like the Game",
        Content = "Thank you for playing GardenWarfare. If you enjoy the game, please leave a like. Your support is the greatest encouragement to me. Enter code TB1234 in Codes to receive a gift pack of 100 Cherry Bombs.",
    },
   
}

return NoticeConfig

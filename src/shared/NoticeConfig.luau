local NoticeConfig = {}

NoticeConfig.StateRemoteName = "GetNoticeReadStateRF"
NoticeConfig.MarkSeenRemoteName = "MarkNoticeSeenRF"

-- Each notice creates one tag button in Notice.TypeButtons.
-- PublishedAt uses YYYY-MM-DD; the newest valid date is selected by default.
NoticeConfig.Notices = {
    {
        Id = "notice-2026-08-07",
        TagText = "2026/8/7",
        PublishedAt = "2026-08-07",
        Title = "August 7 Update Notice",
        Sections = {
            {
                Title = "New Features",
                Content = "Players can now spend 1B Sun to refresh the stock in Dave's Shop. The Sell All option in Dave's Shop now displays a confirmation prompt before selling all eligible items in your hotbar.",
            },
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue where growth-stage models were missing for some plants.",
            },
            {
                Title = "Season Pass",
                Content = "The Season Pass is temporarily unavailable. Stay tuned for its return in a future update!",
            },
        },
    },
    {
        Id = "notice-2026-08-05",
        TagText = "2026/8/5",
        PublishedAt = "2026-08-05",
        Title = "August 5 Event Notice",
        Sections = {
            {
                Title = "Dr. Zomboss Returns!",
                Content = "Zomboss is back! Join the battle, earn Tacos, and exchange them for special rewards in the Zomboss Shop!",
            },
        },
    },
    {
        Id = "notice-2026-08-04",
        TagText = "2026/8/4",
        PublishedAt = "2026-08-04",
        Title = "August 4 Update Notice",
        Sections = {
            {
                Title = "Bug Fix",
                Content = "Fixed an issue where Pumpkin Shields could cause the plant inside to receive an unintended mutation.",
            },
            {
                Title = "Incorrect Ban Compensation",
                Content = "Compensation for players affected by incorrect bans will arrive on August 7.",
            },
            {
                Title = "Coming August 7",
                Content = "A new feature will allow players to spend Sun to refresh Dave's Shop stock.",
            },
        },
    },
    {
        Id = "notice-2026-08-03",
        TagText = "2026/8/3",
        PublishedAt = "2026-08-03",
        Title = "August 3 Bug Fixes",
        Sections = {
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue where the new season leaderboard did not refresh correctly.\nFixed missing animations for some plants.",
            },
            {
                Title = "Season Pass Extension",
                Content = "The current Season Pass has been extended until August 7.",
            },
        },
    },
    {
        Id = "notice-2026-07-31",
        TagText = "2026/7/31",
        PublishedAt = "2026-07-31",
        Title = "July 31 Update",
        Sections = {
            {
                Title = "Three New Plants",
                Content = "Clover increases all plant damage dealt to zombies on the same plot. Up to five Clovers can stack.\nGatling Pea fires a rapid four-pea burst, dealing one powerful hit with each attack.\nGloom-shroom unleashes a piercing attack that damages every zombie within the surrounding 3x3 lawn area.\nClover Seeds and Gatling Pea Seeds can now appear as rare special stock in Dave's Shop.",
            },
            {
                Title = "Difficulty Progression",
                Content = "Zombies now gradually gain increased knockback resistance as you progress through later levels.",
            },
            {
                Title = "New Leaderboard Season",
                Content = "Rewards from the previous leaderboard season have been delivered to eligible players. Check the Gift page to claim them.\nA new leaderboard season is now live. Climb the rankings for a chance to earn special rewards!",
            },
            {
                Title = "Zomboss Event",
                Content = "The Zomboss event has been temporarily disabled while we prepare future improvements. It will return in a later update.",
            },
            {
                Title = "Fair Play Improvements",
                Content = "Server-side anti-cheat and invalid-item detection have been strengthened to provide a safer and fairer experience for everyone.",
            },
        },
    },
    -- 2026/7/23 更新公告：修复南瓜罩偶尔不保护内部植物的问题。
    {
        Id = "notice-2026-07-23",
        TagText = "2026/7/23",
        PublishedAt = "2026-07-23",
        Title = "July 23 Bug Fixes",
        Sections = {
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue where Pumpkin Shield could occasionally fail to protect the plant underneath it.",
            },
        },
    },
    {
        Id = "notice-2026-07-21",
        TagText = "2026/7/21",
        PublishedAt = "2026-07-21",
        Title = "July 21 Balance Update",
        Sections = {
            {
                Title = "Balance Update",
                Content = "Carrot Cannon's attack has been increased to 60,000, and its attack interval has been reduced to 1.5 seconds.",
            },
        },
    },
    {
        Id = "notice-2026-07-20",
        TagText = "2026/7/20",
        PublishedAt = "2026-07-20",
        Title = "July 20 Update",
        Sections = {
            {
                Title = "New Plants",
                Content = "Sun-shroom has joined the garden as a support plant that heals plants in front of it over time.\nPumpkin Shield can protect your plants by taking damage first.\nCarrot Cannon is a heavy artillery plant built for powerful long-range attacks.",
            },
            {
                Title = "Dave's Shop",
                Content = "Carrot Cannon Seeds can now appear in Dave's Shop as a rare special stock.",
            },
            {
                Title = "Season Pass",
                Content = "A new Season Pass is now live, featuring new rewards including Sun-shroom and Pumpkin Shield.\nThe Season Pass Shop can now offer rewards from both the current season and previous seasons.",
            },
            {
                Title = "Leaderboard Rewards",
                Content = "A new leaderboard reward preview page has been added. Visit the gift displays next to the leaderboard to check upcoming rewards.\nSeason leaderboard rewards will be updated on July 31.",
            },
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue in the Zomboss event where plants defeated by the boss could fail to redeploy after the event ended.",
            },
        },
    },
    -- 2026/7/16 更新公告：修复偷菜复制与手机端交易 UI 问题，并发放神圣药水补偿。
    {
        Id = "notice-2026-07-16",
        TagText = "2026/7/16",
        PublishedAt = "2026-07-16",
        Title = "July 16 Update",
        Sections = {
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue where stealing plants from another player's garden could sometimes duplicate plants.\nFixed layout issues with text and buttons on the mobile trading screen.",
            },
            {
                Title = "Compensation Gift",
                Content = "Open the Gift page to claim 3 Divine Potions. Thank you for playing and sharing your feedback!",
            },
        },
    },
    -- 2026/7/15 更新公告：交易系统上线，并修复图鉴与礼物界面问题。
    {
        Id = "notice-2026-07-15",
        TagText = "2026/7/15",
        PublishedAt = "2026-07-15",
        Title = "July 15 Trade Update",
        Sections = {
            {
                Title = "Player Trading Added",
                Content = "You can now send trade requests to nearby players and trade plants directly. Both players must confirm before a trade is completed.",
            },
            {
                Title = "Bug Fixes",
                Content = "Fixed an issue where Rotobaga could appear incorrectly in mutation tag displays.\nOpening the Gift page now uses the same UI rules as other pages, so other panels are properly disabled while it is open.",
            },
        },
    },
    {
        Id = "notice-2026-07-13",
        TagText = "2026/7/13",
        PublishedAt = "2026-07-13",
        Title = "July 13 Update Notice",
        Sections = {
            {
                Title = "Dr. Zomboss Schedule",
                Content = "Zomboss now appears every 30 minutes. Check the Event button or Zomboss Shop for the countdown.",
            },
            {
                Title = "Lucky Code Reward",
                Content = "Enter code Lucky in Codes to claim 3 Thunder Potions.",
            },
            {
                Title = "Pass Event Ended",
                Content = "The Pass event has ended for now. The Pass entry is temporarily hidden.",
            },
            {
                Title = "Boss Battle Improvements",
                Content = "Fixed several Zomboss battle UI issues, including blur lock problems and missing Boss HP/DPS display when joining an ongoing fight.",
            },
            {
                Title = "Shop and Balance Updates",
                Content = "Improved shop item list rendering and adjusted Boss battle balance for a smoother combat experience.",
            },
        },
    },
    {
        Id = "notice-2026-07-11",
        TagText = "2026/7/11",
        PublishedAt = "2026-07-11",
        Title = "July 11 Dr. Zomboss Update",
        Sections = {
            {
                Title = "Dr. Zomboss Event",
                Content = "Zomboss now appears every 2 hours. You can check the countdown on the Event button or in the Zomboss Shop.",
            },
            {
                Title = "Boss Battle Rewards",
                Content = "Deal damage to Dr. Zomboss to earn Taco drops. You receive 1 Taco for every 1% of the boss HP you deal, and 120 bonus Tacos are shared by all players who damaged the boss when he is defeated.",
            },
            {
                Title = "Zomboss Shop",
                Content = "The Zomboss Shop has been updated. Spend Tacos or Robux to get special items, mutation potions, and limited plants such as Lightning Reed.",
            },
            {
                Title = "New Mutation Potion Rules",
                Content = "Mutation potions can now be used near eligible plants. Hold a potion, stand near a plant, and press F for a chance to trigger its mutation effect.",
            },
            {
                Title = "Improvements",
                Content = "Purchase and claim actions now respond faster. Tutorial guidance, sign-in timing, Boss UI, DPS display, and several combat effects have also been improved.",
            },
        },
    },
    {
        Id = "notice-2026-07-09",
        TagText = "2026/7/9",
        PublishedAt = "2026-07-09",
        Title = "July 9 Update Notice",
        Sections = {
            {
                Title = "New Zombies",
                Content = "Dancing Zombie and Gargantuar Zombie have appeared in battle scenes. Prepare for tougher enemies and new combat challenges.",
            },
            {
                Title = "Skip Blind Box Option",
                Content = "A new Skip Blind Box option has been added to Settings. When enabled, Blind Box rewards are granted directly without dropping the box or playing the opening animation.",
            },
            {
                Title = "Bug Fixes",
                Content = "Fixed several bugs and improved the overall game experience.",
            },
        },
    },
    {
        Id = "notice-2026-07-08",
        TagText = "2026/7/8",
        PublishedAt = "2026-07-08",
        Title = "July 8 Update Notice",
        Sections = {
            {
                Title = "Leaderboard Reset",
                Content = "The leaderboard has been reset. Leaderboard season rewards have already been sent to eligible players. Please check your gifts or inventory in game.",
            },
            {
                Title = "Inventory Improvements",
                Content = "The inventory has been optimized. Item quantities and inventory display are now clearer and easier to use.",
            },
            {
                Title = "Sun Reset",
                Content = "Sun has been reset in this update to keep the game balance healthy. Thank you for your understanding and support.",
            },
        },
    },
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

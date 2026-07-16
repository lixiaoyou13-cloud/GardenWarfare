-- src/shared/ItemConfig.luau
local ItemConfig = {
	IdToSeedKey = {
        "Peashooter",
        "Wall",
        "CherryBomb",
        "KernelPult",
        "CarrotShooter",
        "CoconutTree",
        "SnowPea",
        "RadishShooter",
        "PotatoMine",
        "FumeShroom",
        "Magnetshroom",
        "Jalapeno",
        "Cactus",
        "Sunflower",
        "TwinSunflower",
        "Melonpult",
        "Threepeater",
        "IceMelonpult",
        "CobCannon",
        "MusicIcePeashooter",
        "AppleMortar",
        "LanternFlower",

    },

	BaseLimitedSaleKey = {
		-- 4 个商城中出现的植物(按解锁等级排序)
		"Peashooter", -- 商城: 0级解锁
		"Wall", -- 商城: 3级解锁
		"KernelPult", -- 商城: 8级解锁
		"Melonpult", -- 商城: 50级解锁 (大杀器代表)

		-- 6 个商城中未出现的植物(不可出售 / 抽奖 / 活动专属)
		"SnowPea", -- 寒冰射手 (3星)
		"CherryBomb", -- 樱桃炸弹 (3星)
		"Magnetshroom", -- 磁力菇 (4星)
		"TwinSunflower", -- 双子向日葵 (5星)
		"IceMelonpult", -- 冰西瓜投手 (5星)
	},


	Seeds = {
		-- 1星种子 (15秒 | 200金币)

		-- IsSellable = false
		["Peashooter"] = {
			Id = 1,
			Name = "Peashooter Seed",
			Quality = 1,
			GrowthTime = 5,
			YieldPlant = "Peashooter",
			BuyPrice = 200,
			UnlockLevel = 0, -- 0级解锁
			IAPProductId = 3599509881, -- Roblox Developer Product ID
			IAPPrice = 2,
		},
		["Wall"] = {
			Id = 2,
			Name = "Wall-nut Seed",
			Quality = 1,
			GrowthTime = 15,
			YieldPlant = "Wall",
			BuyPrice = 400,
			UnlockLevel = 2, -- 3级解锁
			IAPProductId = 3599513941, -- Roblox Developer Product ID
			IAPPrice = 4,
		},

		-- 2星种子 (180秒 | 3,000金币)
		["KernelPult"] = {
			Id = 3,
			Name = "Kernel-pult Seed",
			Quality = 2,
			GrowthTime = 30,
			YieldPlant = "KernelPult",
			BuyPrice = 1000,
			UnlockLevel = 7, -- 8级解锁
			IAPProductId = 3599525245, -- Roblox Developer Product ID
			IAPPrice = 12,
		},
		["CarrotShooter"] = {
			Id = 4,
			Name = "Carrot Shooter Seed",
			Quality = 2,
			GrowthTime = 100,
			YieldPlant = "CarrotShooter",
			BuyPrice = 3000,
			UnlockLevel = 10, -- 0级解锁
			IAPProductId = 3599525415, -- Roblox Developer Product ID
			IAPPrice = 18,
		},
		["CoconutTree"] = {
			Id = 5,
			Name = "Coconut Tree Seed",
			Quality = 2,
			GrowthTime = 120,
			YieldPlant = "CoconutTree",
			BuyPrice = 9000,
			UnlockLevel = 14, -- 12级解锁
			IAPProductId = 3599525663, -- Roblox Developer Product ID
			IAPPrice = 28,
		},

		-- 3星种子 (900秒 | 35,000金币)
		["SnowPea"] = {
			Id = 6,
			Name = "SnowPea Seed",
			Quality = 3,
			GrowthTime = 200,
			YieldPlant = "SnowPea",
			UnlockLevel = 17, -- 0级解锁
			BuyPrice = 50000,
			IAPProductId = 3599525941, -- Roblox Developer Product ID
			IAPPrice = 45,
		},
		["CherryBomb"] = {
			Id = 7,
			Name = "Cherry Bomb Seed",
			Quality = 3,
			GrowthTime = 210,
			YieldPlant = "CherryBomb",
			UnlockLevel = 4, -- 0级解锁
			BuyPrice = 500,
			IAPProductId = 3599516921, -- Roblox Developer Product ID
			IAPPrice = 2,
		},
		["RadishShooter"] = {
			Id = 8,
			Name = "Radish Shooter Seed",
			Quality = 3,
			GrowthTime = 300,
			YieldPlant = "RadishShooter",
			UnlockLevel = 23, -- 0级解锁
			BuyPrice = 100000,
			IAPProductId =3599526232, -- Roblox Developer Product ID
			IAPPrice = 65,
		},

		-- 4星种子 (1800秒 | 150,000金币)
		["PotatoMine"] = {
			Id = 9,
			Name = "Potato Mine Seed",
			Quality = 4,
			GrowthTime = 400,
			YieldPlant = "PotatoMine",
			BuyPrice = 320000,
			UnlockLevel = 29, -- 18级解锁
			IAPProductId = 3599526403, -- Roblox Developer Product ID
			IAPPrice = 90,
		},
		["FumeShroom"] = {
			Id = 10,
			Name = "Fume-shroom Seed",
			Quality = 4,
			GrowthTime = 400,
			YieldPlant = "FumeShroom",
			BuyPrice = 500000,
			UnlockLevel = 36, -- 23级解锁
			IAPProductId = 3599526628, -- Roblox Developer Product ID
			IAPPrice = 120,
		},
		["Magnetshroom"] = {
			Id = 11,
			Name = "Magnet-shroom Seed",
			Quality = 4,
			GrowthTime = 400,
			YieldPlant = "Magnetshroom",
			BuyPrice = 850000,
			UnlockLevel = 44, -- 0级解锁
			IAPProductId = 3599526993, -- Roblox Developer Product ID
			IAPPrice = 155,
		},
		["Jalapeno"] = {
			Id = 12,
			Name = "Jalapeno Seed",
			Quality = 4,
			GrowthTime = 400,
			YieldPlant = "Jalapeno",
			BuyPrice = 1500000,
			UnlockLevel = 53, -- 27级解锁
			IAPProductId = 3599527190, -- Roblox Developer Product ID
			IAPPrice = 190,
		},
		["Cactus"] = {
			Id = 13,
			Name = "Cactus Seed",
			Quality = 4,
			GrowthTime = 420,
			YieldPlant = "Cactus",
			BuyPrice = 2700000,
			UnlockLevel = 63, -- 32级解锁
			IAPProductId = 3599527499, -- Roblox Developer Product ID
			IAPPrice = 230,
		},
		["Sunflower"] = {
			Id = 14,
			Name = "Sunflower Seed",
			Quality = 4,
			GrowthTime = 500,
			YieldPlant = "Sunflower",
			BuyPrice = 5000000,
			UnlockLevel = 72, -- 40级解锁
			IAPProductId = 3599527640, -- Roblox Developer Product ID
			IAPPrice = 270,
		},

		-- 5星种子 (3600秒 | 500,000金币)
		["TwinSunflower"] = {
			Id = 15,
			Name = "Twin Sunflower Seed",
			Quality = 5,
			GrowthTime = 3600,
			YieldPlant = "TwinSunflower",
			UnlockLevel = 80, -- 0级解锁
			BuyPrice = 8000000,
			IAPProductId = 3599527917, -- Roblox Developer Product ID
			IAPPrice = 320,
		},
		["Melonpult"] = {
			Id = 16,
			Name = "Melon-pult Seed",
			Quality = 5,
			GrowthTime = 1800,
			YieldPlant = "Melonpult",
			BuyPrice = 10000000,
			UnlockLevel = 86, -- 50级解锁
			IAPProductId = 3599528132, -- Roblox Developer Product ID
			IAPPrice = 370,
		},
		["Threepeater"] = {
			Id = 17,
			Name = "Threepeater Seed",
			Quality = 5,
			GrowthTime = 1800,
			YieldPlant = "Threepeater",
			UnlockLevel = 91, -- 0级解锁
			BuyPrice = 24000000,
			IAPProductId = 3599528340, -- Roblox Developer Product ID
			IAPPrice = 420,
		},
		["IceMelonpult"] = {
			Id = 18,
			Name = "Ice Melon-pult Seed",
			Quality = 5,
			GrowthTime = 1800,
			YieldPlant = "IceMelonpult",
			UnlockLevel = 96, -- 0级解锁
			BuyPrice = 55000000,
			IAPProductId = 3599528561, -- Roblox Developer Product ID
			IAPPrice = 460,
		},
		["CobCannon"] = {
			Id = 19,
			Name = "Cob Cannon Seed",
			Quality = 5,
			GrowthTime = 1800,
			YieldPlant = "CobCannon",
			BuyPrice = 100000000,
			UnlockLevel = 100, -- 0级解锁
			IAPProductId = 3599528978, -- Roblox Developer Product ID
			IAPPrice = 499,
		},
		["MusicIcePeashooter"] = {
			Id = 20,
			Name = "Music Ice Peashooter Seed",
			Quality = 5,
			GrowthTime = 1800,
			YieldPlant = "MusicIcePeashooter",
			UnlockLevel = 120, -- 0级解锁
			BuyPrice = 100000000,
			IAPProductId = 3603543683, -- Roblox Developer Product ID
			IAPPrice = 499,
		},
		["AppleMortar"] = {
			Id = 21,
			Name = "Apple Mortar Seed",
			Quality = 5,
			GrowthTime = 2400,
			YieldPlant = "AppleMortar",
			UnlockLevel = 125,
			BuyPrice = 150000000,
			IAPProductId = 3606320465,
			IAPPrice = 599,
		},
		["TallWall"] = {
			Id = 22,
			Name = "Tall Wall-nut Seed",
			Quality = 5,
			GrowthTime = 10,
			YieldPlant = "TallWall",

			BuyPrice = 200000000,
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["Chomper"] = {
			Id = 23,
			Name = "Chomper Seed",
			Quality = 5,
			GrowthTime = 600,
			YieldPlant = "Chomper",
			BuyPrice = 250000000,
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["LanternFlower"] = {
			Id = 24,
			Name = "Lantern Flower Seed",
			Quality = 5,
			GrowthTime = 600,
			YieldPlant = "LanternFlower",
			BuyPrice = 2000000000,
			UnlockLevel = 240,
			ExcludeFromRandomSeedRewards = true,
			IAPProductId = 3609146952,
			IAPPrice = 620,
		},
		["LightningReed"] = {
			Id = 25,
			Name = "Lightning Reed Seed",
			Quality = 5,
			GrowthTime = 2400,
			YieldPlant = "LightningReed",
			BuyPrice = 0,
			IsSellable = false,
			ExcludeFromRandomSeedRewards = true,
			IAPProductId = 0,
			IAPPrice = 0,
		},
	},

	Plants = {
		-- 1星植物 (基础级)
		["Peashooter"] = {
			Id = "Peashooter",
			Name = "Peashooter",
			IconId = "rbxassetid://71143798063782",
			HP = 300,
			Quality = 1,
			IdleAnimId = "rbxassetid://78336317659894",
			CanAttack = true,
			Attack = 20,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 127),
			ProjectileName = "Pea",
			Description = "Description: Shoots peas to deal basic damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Wall"] = {
			Id = "Wall",
			Name = "Wall-nut",
			IconId = "rbxassetid://121783051376976",
			HP = 10000,
			Quality = 1,
			IdleAnimId = "rbxassetid://130556607788926",
			CanAttack = false,
			Description = "Description: High HP. Blocks zombies.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},

		-- 2星植物 (进阶级)
		["KernelPult"] = {
			Id = "KernelPult",
			Name = "Kernel-pult",
			IconId = "rbxassetid://71266450837088",
			HP = 500,
			Quality = 2,
			IdleAnimId = "rbxassetid://135320524253878",
			AttackAnimation = "rbxassetid://125434851620830",
			ArcHeight = 40, -- 投手专属
			CanAttack = true,
			Attack = 100,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Kernel",
			Description = "Description: Lobs kernels to deal basic damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["CarrotShooter"] = {
			Id = "CarrotShooter",
			Name = "CarrotShooter",
			IconId = "rbxassetid://76231084529607",
			HP = 500,
			Quality = 2,
			IdleAnimId = "rbxassetid://125291231495047",
			AttackAnimation = "rbxassetid://135622253127156",
			-- 射手：已移除 ArcHeight
			CanAttack = true,
			Attack = 150,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Carrot",
			Description = "Description: Shoots carrots to deal basic damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["CoconutTree"] = {
			Id = "CoconutTree",
			Name = "Coconut Tree",
			IconId = "rbxassetid://70525233151466",
			HP = 500,
			Quality = 2,
			CanAttack = true,
			ArcHeight = 20, -- 投手专属：已补上
			Attack = 250,
			IdleAnimId = "rbxassetid://82072725732014",
			AttackAnimation = "rbxassetid://140311761151184",
			AttackInterval = 3,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 170, 0),
			ProjectileName = "Coconut",
			Description = "Description: Lobs a heavy coconut, dealing single-target damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},

		-- 3星植物 (主力级)
		["SnowPea"] = {
			Id = "SnowPea",
			Name = "Snow Pea",
			IconId = "rbxassetid://112031217635780",
			HP = 800,
			Quality = 3,
			CanAttack = true,
			Attack = 500,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://78336317659894",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "IcePea",
			SlowOnHit = { MoveMultiplier = 0.5, Duration = 2, Color = Color3.fromRGB(80, 180, 255) },
			Description = "Details: Fires frost peas, inflicts damage and applies slow!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["CherryBomb"] = {
			Id = "CherryBomb",
			Name = "Cherry Bomb",
			IconId = "rbxassetid://86234409558738",
			HP = 800,
			Quality = 3,
			CanAttack = false,
			IsThrowable = true, -- 投掷爆炸类
			ExplosionRadius = 10,
			ExplosionDamage = 3000,
			ExplosionEffect = "CherryBombHit",
			Description = "Details: Explodes instantly in a large area!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["RadishShooter"] = {
			Id = "RadishShooter",
			Name = "RadishShooter",
			IconId = "rbxassetid://106121221312181",
			HP = 800,
			Quality = 3,
			IdleAnimId = "rbxassetid://86333907257335",
			AttackAnimation = "rbxassetid://85325901506430",
			-- 射手：无 ArcHeight
			CanAttack = true,
			Attack = 600,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "WhiteRadish",
			Description = "Description: Shoots heavy radishes to deal high damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},

		-- 4星植物 (精英级)
		["PotatoMine"] = {
			Id = "PotatoMine",
			Name = "Potato Mine",
			IconId = "rbxassetid://132301099035468",
			HP = 1500,
			Attack = 20000,
			Quality = 4,
			IdleAnimId = "rbxassetid://90962037485623",
			CanAttack = false,
			ExplosionType = "Single", -- 接触爆炸
			ExplosionDamage = 20000,
			Description = "Description: Explodes on contact, dealing massive single-target damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["FumeShroom"] = {
			Id = "FumeShroom",
			Name = "Fume-shroom",
			IconId = "rbxassetid://111582428953831",
			HP = 1500,
			Quality = 4,
			CanAttack = true,
			Attack = 800,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://137165648071153",
			AttackAnimation = "rbxassetid://106856862873566",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(170, 85, 255),
			ProjectileName = "Spore",
			Piercing = true,
			Description = "Description: Sprays high-damage spores to suppress zombies ahead.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Magnetshroom"] = {
			Id = "Magnetshroom",
			Name = "Magnetshroom",
			IconId = "rbxassetid://108524168044389",
			HP = 1500,
			Quality = 4,
			IdleAnimId = "rbxassetid://102236070169653",
			AttackAnimation = "rbxassetid://108055644403303",
			-- 射手：已移除 ArcHeight
			CanAttack = true,
			Attack = 800,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Lightning",
			Description = "Description: Fires lightning to deal heavy electric damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Jalapeno"] = {
			Id = "Jalapeno",
			Name = "Jalapeno",
			IconId = "rbxassetid://72546773609598",
			HP = 3000,
			Attack = 20000,
			Quality = 4,
			CanAttack = false,
			ExplosionType = "Row", -- 接触爆炸（清晰行）
			ExplosionDamage = 20000,
			Description = "Description: Explodes instantly, destroying all zombies in a lane.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Cactus"] = {
			Id = "Cactus",
			Name = "Cactus",
			IconId = "rbxassetid://74908812230797",
			HP = 1500,
			Quality = 4,
			CanAttack = true,
			Attack = 1000,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://132507907086232",
			AttackAnimation ="rbxassetid://87531231080785",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 0),
			ProjectileName = "Spike",
			Piercing = true,
			Description = "Description: Fires sharp spikes with strong piercing power.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Sunflower"] = {
			Id = "Sunflower",
			Name = "Sunflower",
			IconId = "rbxassetid://86938552465859",
			HP = 1500,
			Quality = 4,
			CanAttack = true,
			Attack = 1000,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://123013968700468",
			AttackAnimation = "rbxassetid://100300439397971",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 0),
			ProjectileName = "Sunflower",
			Description = "Description: Generates value and assists in combat.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["LanternFlower"] = {
			Id = "LanternFlower",
			Name = "Lantern Flower",
			IconId = "rbxassetid://138661011543911",
			HP = 500,
			Quality = 5,
			IdleAnimId = "rbxassetid://93774771904448",
			CanAttack = false,
			AttackBuffAura = {
				GridRadius = 1,
				BaseDamageBonus = 0.2,
			},
			ExcludeFromRandomPlantRewards = true,
			Description = "Description: Buffs plants in the surrounding 3x3 area, increasing their attack damage.",
			IAPProductId = 3609146952,
			IAPPrice = 620,
		},

		-- 5星植物 (传说级)
		["TwinSunflower"] = {
			Id = "TwinSunflower",
			Name = "Twin Sunflower",
			IconId = "rbxassetid://122574600110470",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			Attack = 2000,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://93822718710198",
			AttackAnimation = "rbxassetid://109061928244787",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(217, 255, 0),
			ProjectileName = "Sunbeam",
			Description = "Details: Fires laser to deal massive damage!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Melonpult"] = {
			Id = "Melonpult",
			Name = "Melon-pult",
			IconId = "rbxassetid://84463799904562",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			ArcHeight = 20, -- 投手专属
			Attack = 3000,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://117331055474996",
			AttackAnimation = "rbxassetid://125434851620830",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "Melon",
			SplashDamageScale = 0.7,
			SplashRadius = 14,
			Description = "Details: Lobs watermelons to deal massive damage!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["Threepeater"] = {
			Id = "Threepeater",
			Name = "Threepeater",
			IconId = "rbxassetid://96853882236956",
			HP = 3000,
			Quality = 5,
			IdleAnimId = "rbxassetid://133167269306731",
			AttackAnimation = "rbxassetid://79712453381011",
			CanAttack = true,
			Attack = 2500,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Pea",
			Description = "Description: Fires multiple peas to deal insane damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["IceMelonpult"] = {
			Id = "IceMelonpult",
			Name = "Ice Melon-pult",
			IconId = "rbxassetid://138388431733147",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			ArcHeight = 20, -- 投手专属：已补上
			Attack = 4000,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://117331055474996",
			AttackAnimation = "rbxassetid://125434851620830",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "IceMelon",
			SplashDamageScale = 0.7,
			SplashRadius = 14,
			SplashAppliesSlow = true,
			SlowOnHit = { MoveMultiplier = 0.5, Duration = 2, Color = Color3.fromRGB(80, 180, 255) },
			Description = "Details: Hurls ice melon to deal extreme damage and slow targets!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["CobCannon"] = {
			Id = "CobCannon",
			Name = "CobCannon",
			IconId = "rbxassetid://108711542034516",
			HP = 3000,
			Quality = 5,
			IdleAnimId = "rbxassetid://140048491047365",
			AttackAnimation = "rbxassetid://121193564169167",
			ArcHeight = 20, -- 投手专属
			CanAttack = true,
			Attack = 6000,
			AttackInterval = 2,
			HitEffectTexture = "CornMP",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Corn",
			SplashDamageScale = 0.7,
			SplashRadius = 14,
			Description = "Description: The ultimate weapon. Lobs giant cobs for devastating damage.",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["MusicIcePeashooter"] = {
			Id = "MusicIcePeashooter",
			Name = "Music Ice Peashooter",
			IconId = "rbxassetid://126682185215888",
			HP = 1500,
			Quality = 5,
			CanAttack = true,
			Attack = 6000,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://77070181691364",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "MusicIcePea",
			Piercing = true,
			SlowOnHit = { MoveMultiplier = 0.5, Duration = 2, Color = Color3.fromRGB(80, 180, 255) },
			Description = "Details: Fires frost peas, inflicts damage and applies slow!",
			IAPProductId = 0, -- Roblox Developer Product ID
			IAPPrice = 0,
		},
		["AppleMortar"] = {
			Id = "AppleMortar",
			Name = "Apple Mortar",
			IconId = "rbxassetid://102109364051173",
			HP = 3500,
			Quality = 5,
			CanAttack = true,
			Attack = 7000,
			AttackInterval = 2,
			IdleAnimId = "rbxassetid://111661411477584",
			AttackAnimation = "rbxassetid://133161846876069",
			ArcHeight = 24,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 80, 80),
			ProjectileName = "Apple",
			GroundEffect = {
				EffectName = "AppleMP",
				Duration = 2,
				DamagePerSecondScale = 0.1,
				TickInterval = 1,
				MaxOnePerGrid = true,
			},
			Description = "Description: Lobs heavy apples in a high arc, dealing huge burst damage.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["LightningReed"] = {
			Id = "LightningReed",
			Name = "Lightning Reed",
			IconId = "rbxassetid://75037609060928",
			HP = 1000,
			Quality = 5,
			CanAttack = true,
			Attack = 12000,
			AttackInterval = 1,
			IdleAnimId = "rbxassetid://86947836521261",
			AttackAnimation = "rbxassetid://91389394351978",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(120, 220, 255),
			ProjectileName = "Reed",
			ChainProjectile = {
				ExtraTargets = 3,
				Range = 100,
				DamageScale = 1,
				SpeedMultiplier = 3,
			},
			ExcludeFromRandomPlantRewards = true,
			Description = "Description: Fires lightning reeds that chain to nearby zombies.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["Rotobaga"] = {
			Id = "Rotobaga",
			Name = "Rotobaga",
			IconId = "rbxassetid://127561636844108",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			Attack = 12000,
			AttackInterval = 6,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Rotobaga",
			IsIAPOnly = true,
			NoMutation = true,
			Piercing = true,
			IdleAnimId = "rbxassetid://90459622226121",
			AttackAnimation = "rbxassetid://137485157321511",
			KnockbackOnHit = {
				GridDistance = 0.5,
				OnlyWhenTargetOnLawn = true,
			},
			Description = "Description: A premium shooter whose piercing shots knock zombies back by one lawn tile.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["TallWall"] = {
			Id = "TallWall",
			Name = "Tall Wall-nut",
			IconId = "rbxassetid://120854555693910",
			HP = 30000,
			Quality = 5,
			IdleAnimId = "rbxassetid://105592611320984",
			CanAttack = false,
			Description = "Description: Massive HP defensive plant. Blocks zombies without attacking.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["Chomper"] = {
			Id = "Chomper",
			Name = "Chomper",
			IconId = "rbxassetid://112334447628556",
			HP = 15000,
			Quality = 5,
			IdleAnimId = "rbxassetid://110255266467419",
			AttackAnimation = "rbxassetid://108938637840415",
			CanAttack = true,
			Attack = 1500,
			AttackInterval = 1,
			AttackMode = "FrontArea",
			FrontArea = {
				GridRange = 1,
				Height = 8,
			},
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(170, 255, 85),
			Description = "Description: Bites the front lawn tile, dealing area damage without a projectile.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["MutantChomper"] = {
			Id = "MutantChomper",
			Name = "Mutant Chomper",
			IconId = "rbxassetid://107497950746490",
			HP = 45000,
			Quality = 6,
			IdleAnimId = "rbxassetid://110255266467419",
			AttackAnimation = "rbxassetid://108938637840415",
			CanAttack = true,
			Attack = 3000,
			AttackInterval = 1,
			AttackMode = "FrontArea",
			FrontArea = {
				GridRange = 1,
				Height = 8,
			},
			NoSeed = true,
			HideFromStandardCodex = true,
			CodexCategory = 5,
			CodexLabel = "Mutant",
			ExcludeFromRandomPlantRewards = true,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 85, 255),
			Source = "Special",
			Description = "Description: A mutated Chomper that bites the front lawn tile, dealing heavy area damage without a projectile.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
		["EnergyMangosteen"] = {
			Id = "EnergyMangosteen",
			Name = "Energy Mangosteen",
			IconId = "rbxassetid://85135746264532",
			HP = 20000,
			Quality = 6,
			IdleAnimId = "rbxassetid://116519154276440",
			AttackAnimation = "rbxassetid://136391260231730",
			CanAttack = false,
			Attack = 2000,
			AttackInterval = 2,
			NoSeed = true,
			HideFromStandardCodex = true,
			CodexCategory = 5,
			CodexLabel = "Mutant",
			ExcludeFromRandomPlantRewards = true,
			Source = "Special",
			ReactiveOnDamaged = {
				Damage = 2000,
				Radius = 14,
				Cooldown = 2,
				EffectFolder = "Hit",
				EffectName = "Lightning",
				EffectLifetime = 1.25,
			},
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			Description = "Description: Releases stored energy when attacked, damaging nearby zombies with lightning.",
			IAPProductId = 0,
			IAPPrice = 0,
		},
	},

	MutationProb = { [1] = 90, [2] = 7, [3] = 3, [4] = 1 },
	MutationName = {
		[1] = "Normal",
		[2] = "Shiny",
		[3] = "Lightning",
		[4] = "Divine"
	},

	MutationIconIds = {
		[1] = "rbxassetid://79698788250686",
		[2] = "rbxassetid://85231855825621",
		[3] = "rbxassetid://99500984192285",
		[4] = "rbxassetid://102788508707196",
		Normal = "rbxassetid://79698788250686",
		Mutant = "rbxassetid://79698788250686",
		Shiny = "rbxassetid://85231855825621",
		Lightning = "rbxassetid://99500984192285",
		Thunder = "rbxassetid://99500984192285",
		Divine = "rbxassetid://102788508707196",
	},

	QualityColor = {
		[1] = Color3.fromRGB(255, 255, 255),
		[2] = Color3.fromRGB(85, 255, 127),
		[3] = Color3.fromRGB(85, 170, 255),
		[4] = Color3.fromRGB(170, 85, 255),
		[5] = Color3.fromRGB(255, 170, 0),
		[6] = Color3.fromRGB(255, 85, 85),
		[7] = Color3.fromRGB(255, 85, 255),
		[8] = Color3.fromRGB(0, 255, 255),
	},
}
ItemConfig.Items = {
    ["ShinyPotion"] = {
        Id = "ShinyPotion",
        Name = "Shiny Potion",
        IconId = "rbxassetid://82045159921006",
        Quality = 4,
        ModelName = "ShinyPotion",
        ItemType = "MutationPotion",
        MutationLevel = 2,
        DurationSeconds = 900,
        WeightBonusPercent = 100,
        AmountText = "100%",
    },
    ["ThunderPotion"] = {
        Id = "ThunderPotion",
        Name = "Thunder Potion",
        IconId = "rbxassetid://128785586508022",
        Quality = 5,
        ModelName = "ThunderPotion",
        ItemType = "MutationPotion",
        MutationLevel = 3,
        DurationSeconds = 900,
        WeightBonusPercent = 100,
        AmountText = "100%",
    },
    ["DivinePotion"] = {
        Id = "DivinePotion",
        Name = "Divine Potion",
        IconId = "rbxassetid://73520502074318",
        Quality = 6,
        ModelName = "DivinePotion",
        ItemType = "MutationPotion",
        MutationLevel = 4,
        DurationSeconds = 900,
        WeightBonusPercent = 100,
        AmountText = "100%",
    },
}
ItemConfig.Chests = {
    ["Chest1"] = {
        Id = "Chest1",
        Name = "Chest I",
        Quality = 2,
        Description = "A reward chest from cleared levels 1-30.",
        IconId = "",
    },
    ["Chest2"] = {
        Id = "Chest2",
        Name = "Chest II",
        Quality = 3,
        Description = "A reward chest from cleared levels 31-70.",
        IconId = "",
    },
    ["Chest3"] = {
        Id = "Chest3",
        Name = "Chest III",
        Quality = 4,
        Description = "A reward chest from cleared levels 71-120.",
        IconId = "",
    },
    ["Chest4"] = {
        Id = "Chest4",
        Name = "Chest IV",
        Quality = 5,
        Description = "A reward chest from cleared levels 121+.",
        IconId = "",
    },
}
ItemConfig.MutationStats = {
    [1] = { DamageMul = 1.0, HealthMul = 1.0, AuraBuffMul = 1.0 }, -- 普通
    [2] = { DamageMul = 1.5, HealthMul = 1.5, AuraBuffMul = 1.5 }, -- 闪光 (+50% 攻击, +50% 血量)
    [3] = { DamageMul = 2, HealthMul = 3, AuraBuffMul = 2.0 }, -- 雷电 (+100% 攻击, +200% 血量)
    [4] = { DamageMul = 2.5, HealthMul = 4, AuraBuffMul = 2.5 }, -- 神圣 (+150% 攻击, +300% 血量)
}
return ItemConfig

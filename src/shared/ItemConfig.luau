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
        "CobCannon"
    },
	
	BaseLimitedSaleKey = {
		-- ==========================================
		-- 🛒 【4 个商城中出现的植物】(按解锁等级排序)
		-- ==========================================
		"Peashooter",   -- 商城: 0级解锁
		"Wall",         -- 商城: 3级解锁
		"KernelPult",   -- 商城: 8级解锁
		"Melonpult",    -- 商城: 50级解锁 (大杀器代表)

		-- ==========================================
		-- 🎁 【6 个商城中未出现的植物】(不可出售 / 抽奖 / 活动专属)
		-- ==========================================
		"SnowPea",      -- 寒冰射手 (3星)
		"CherryBomb",   -- 樱桃炸弹 (3星)
		"Magnetshroom", -- 磁力菇 (4星)
		"TwinSunflower",-- 双子向日葵 (5星)
		"IceMelonpult", -- 冰西瓜投手 (5星)
	},
	

	Seeds = {
		-- ==========================================
		-- ⭐ 1星种子 (15秒 | 200金币)
		-- ==========================================
		["Peashooter"] = {
			Id = 1,
			Name = "Peashooter Seed",
			Quality = 1,
			GrowthTime = 5,
			YieldPlant = "Peashooter",
			BuyPrice = 200,       
			UnlockLevel = 0, -- ✅ 0级解锁
		},
		["Wall"] = {
			Id = 2,
			Name = "Wall-nut Seed",
			Quality = 1,
			GrowthTime = 15,
			YieldPlant = "Wall",
			BuyPrice = 400,       
			UnlockLevel = 2, -- ✅ 3级解锁
		},

		-- ==========================================
		-- ⭐⭐ 2星种子 (180秒 | 3,000金币)
		-- ==========================================
		["KernelPult"] = {
			Id = 3,
			Name = "Kernel-pult Seed",
			Quality = 2,
			GrowthTime = 180,
			YieldPlant = "KernelPult",
			BuyPrice = 1000,      
			UnlockLevel = 7, -- ✅ 8级解锁
		},
		["CarrotShooter"] = {
			Id = 4,
			Name = "Carrot Shooter Seed",
			Quality = 2,
			GrowthTime = 180,
			YieldPlant = "CarrotShooter",
			BuyPrice = 3000,       
			UnlockLevel = 10, -- ✅ 0级解锁
		},
		["CoconutTree"] = {
			Id = 5,
			Name = "Coconut Tree Seed",
			Quality = 2,
			GrowthTime = 180,
			YieldPlant = "CoconutTree",
			BuyPrice = 9000,     
			UnlockLevel = 14, -- ✅ 12级解锁
		},

		-- ==========================================
		-- ⭐⭐⭐ 3星种子 (900秒 | 35,000金币)
		-- ==========================================
		["SnowPea"] = {
			Id = 6,
			Name = "SnowPea Seed",
			Quality = 3,           
			GrowthTime = 900,      
			YieldPlant = "SnowPea",
			UnlockLevel = 17, -- ✅ 0级解锁
			BuyPrice = 50000,
		},
		["CherryBomb"] = {
			Id = 7,
			Name = "Cherry Bomb Seed",
			Quality = 3,           
			GrowthTime = 900,     
			YieldPlant = "CherryBomb",
			UnlockLevel = 4, -- ✅ 0级解锁
			BuyPrice = 500,
		},
		["RadishShooter"] = {
			Id = 8,
			Name = "Radish Shooter Seed",
			Quality = 3,           
			GrowthTime = 900,     
			YieldPlant = "RadishShooter",
			UnlockLevel = 23, -- ✅ 0级解锁
			BuyPrice = 100000,
		},

		-- ==========================================
		-- ⭐⭐⭐⭐ 4星种子 (1800秒 | 150,000金币)
		-- ==========================================
		["PotatoMine"] = {
			Id = 9,
			Name = "Potato Mine Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "PotatoMine",
			BuyPrice = 320000,    
			UnlockLevel = 29, -- ✅ 18级解锁
		},
		["FumeShroom"] = {
			Id = 10,
			Name = "Fume-shroom Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "FumeShroom",
			BuyPrice = 150000,    
			UnlockLevel = 36, -- ✅ 23级解锁
		},
		["Magnetshroom"] = {
			Id = 11,
			Name = "Magnet-shroom Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Magnetshroom",
			BuyPrice = 850000,       
			UnlockLevel = 44, -- ✅ 0级解锁
		},
		["Jalapeno"] = {
			Id = 12,
			Name = "Jalapeno Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Jalapeno",
			BuyPrice = 1500000,     
			UnlockLevel = 53, -- ✅ 27级解锁
		},
		["Cactus"] = {
			Id = 13,
			Name = "Cactus Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Cactus",
			BuyPrice = 2700000,    
			UnlockLevel = 63, -- ✅ 32级解锁
		},
		["Sunflower"] = {
			Id = 14,
			Name = "Sunflower Seed",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Sunflower",
			BuyPrice = 5000000,    
			UnlockLevel = 72, -- ✅ 40级解锁
		},

		-- ==========================================
		-- ⭐⭐⭐⭐⭐ 5星种子 (3600秒 | 500,000金币)
		-- ==========================================
		["TwinSunflower"] = {
			Id = 15,
			Name = "Twin Sunflower Seed",
			Quality = 5,           
			GrowthTime = 3600,     
			YieldPlant = "TwinSunflower",
			UnlockLevel = 80, -- ✅ 0级解锁
			BuyPrice = 8000000,
		},
		["Melonpult"] = {
			Id = 16,
			Name = "Melon-pult Seed",
			Quality = 5,           
			GrowthTime = 3600,     
			YieldPlant = "Melonpult",
			BuyPrice = 10000000,    
			UnlockLevel = 86, -- ✅ 50级解锁
		},
		["Threepeater"] = {
			Id = 17,
			Name = "Threepeater Seed",
			Quality = 5,           
			GrowthTime = 3600,     
			YieldPlant = "Threepeater",
			UnlockLevel = 91, -- ✅ 0级解锁
			BuyPrice = 24000000,
		},
		["IceMelonpult"] = {
			Id = 18,
			Name = "Ice Melon-pult Seed",
			Quality = 5,           
			GrowthTime = 3600,     
			YieldPlant = "IceMelonpult",
			UnlockLevel = 96, -- ✅ 0级解锁
			BuyPrice = 55000000,
		},
		["CobCannon"] = {
			Id = 19,
			Name = "Cob Cannon Seed",
			Quality = 5,
			GrowthTime = 3600,
			YieldPlant = "CobCannon",
			BuyPrice = 100000000,       
			UnlockLevel = 100, -- ✅ 0级解锁
		},
	},
	
	Plants = {
		-- ==========================================
		-- ⭐ 1星植物 (基础级)
		-- ==========================================
		["Peashooter"] = {
			Id = "Peashooter",
			Name = "Peashooter",
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
		},
		["Wall"] = {
			Id = "Wall",
			Name = "Wall-nut",
			HP = 10000,
			Quality = 1,
			IdleAnimId = "rbxassetid://130556607788926",
			CanAttack = false,
			Description = "Description: High HP. Blocks zombies.",
		},

		-- ==========================================
		-- ⭐⭐ 2星植物 (进阶级)
		-- ==========================================
		["KernelPult"] = {
			Id = "KernelPult",
			Name = "Kernel-pult",
			HP = 500,
			Quality = 2,
			IdleAnimId = "rbxassetid://135320524253878",
			AttackAnimation = "rbxassetid://125434851620830",
			ArcHeight = 40, -- 🏀 投手专属
			CanAttack = true,
			Attack = 100,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Kernel", 
			Description = "Description: Lobs kernels to deal basic damage.",
		},
		["CarrotShooter"] = {
			Id = "CarrotShooter",
			Name = "CarrotShooter",
			HP = 500,
			Quality = 2,
			IdleAnimId = "rbxassetid://125291231495047",
			AttackAnimation = "rbxassetid://135622253127156",
			-- 🔫 射手：已移除 ArcHeight
			CanAttack = true,
			Attack = 150,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Carrot", 
			Description = "Description: Shoots carrots to deal basic damage.",
		},
		["CoconutTree"] = {
			Id = "CoconutTree",
			Name = "Coconut Tree",
			HP = 500,
			Quality = 2,
			CanAttack = true,
			ArcHeight = 20, -- 🏀 投手专属：已修复补上
			Attack = 250, 
			IdleAnimId = "rbxassetid://82072725732014",
			AttackAnimation = "rbxassetid://140311761151184s",
			AttackInterval = 3, 
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 170, 0),
			ProjectileName = "Coconut", 
			Description = "Description: Lobs a heavy coconut, dealing single-target damage.",
		},

		-- ==========================================
		-- ⭐⭐⭐ 3星植物 (主力级)
		-- ==========================================
		["SnowPea"] = {
			Id = "SnowPea",
			Name = "Snow Pea",
			HP = 800,
			Quality = 3,
			CanAttack = true,
			Attack = 500,
			AttackInterval = 2, 
			IdleAnimId = "rbxassetid://78336317659894",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "IcePea", 
			Description = "Details: Fires frost peas, inflicts damage and applies slow!",
		},
		["CherryBomb"] = {
			Id = "CherryBomb",
			Name = "Cherry Bomb",
			HP = 800,
			Quality = 3,
			CanAttack = false, 
			IsThrowable = true, -- 💣 投掷爆炸类
			ExplosionRadius = 10, 
			ExplosionDamage = 3000, 
			ExplosionEffect = "CherryBombHit", 
			Description = "Details: Explodes instantly in a large area!",
		},
		["RadishShooter"] = {
			Id = "RadishShooter",
			Name = "RadishShooter",
			HP = 800,
			Quality = 3,
			IdleAnimId = "rbxassetid://86333907257335",
			AttackAnimation = "rbxassetid://85325901506430",
			-- 🔫 射手：无 ArcHeight
			CanAttack = true,
			Attack = 600,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "WhiteRadish", 
			Description = "Description: Shoots heavy radishes to deal high damage.",
		},

		-- ==========================================
		-- ⭐⭐⭐⭐ 4星植物 (精英级)
		-- ==========================================
		["PotatoMine"] = {
			Id = "PotatoMine",
			Name = "Potato Mine",
			HP = 1500,
			Attack = 999999,
			Quality = 4,
			IdleAnimId = "rbxassetid://90962037485623",
			CanAttack = false,
			ExplosionType = "Single", -- 💥 接触爆炸
			ExplosionDamage = 999999,
			Description = "Description: Explodes on contact, dealing massive single-target damage.",
		},
		["FumeShroom"] = {
			Id = "FumeShroom",
			Name = "Fume-shroom",
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
			Description = "Description: Sprays high-damage spores to suppress zombies ahead.",
		},
		["Magnetshroom"] = {
			Id = "Magnetshroom",
			Name = "Magnetshroom",
			HP = 1500,
			Quality = 4,
			IdleAnimId = "rbxassetid://102236070169653",
			AttackAnimation = "rbxassetid://108055644403303",
			-- 🔫 射手：已移除 ArcHeight
			CanAttack = true,
			Attack = 800,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Lightning", 
			Description = "Description: Fires lightning to deal heavy electric damage.",
		},
		["Jalapeno"] = {
			Id = "Jalapeno",
			Name = "Jalapeno",
			HP = 3000,
			Attack = 999999,
			Quality = 4,
			CanAttack = false,
			ExplosionType = "Row", -- 💥 接触爆炸（清行）
			ExplosionDamage =999999,
			Description = "Description: Explodes instantly, destroying all zombies in a lane.",
		},
		["Cactus"] = {
			Id = "Cactus",
			Name = "Cactus",
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
			Description = "Description: Fires sharp spikes with strong piercing power.",
		},
		["Sunflower"] = {
			Id = "Sunflower",
			Name = "Sunflower",
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
		},

		-- ==========================================
		-- ⭐⭐⭐⭐⭐ 5星植物 (传说级)
		-- ==========================================
		["TwinSunflower"] = {
			Id = "TwinSunflower",
			Name = "Twin Sunflower",
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
		},
		["Melonpult"] = {
			Id = "Melonpult",
			Name = "Melon-pult",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			ArcHeight = 20, -- 🏀 投手专属
			Attack = 3000,
			AttackInterval = 2, 
			IdleAnimId = "rbxassetid://117331055474996",
			AttackAnimation = "rbxassetid://125434851620830",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "Melon", 
			Description = "Details: Lobs watermelons to deal massive damage!",
		},
		["Threepeater"] = {
			Id = "Threepeater",
			Name = "Threepeater",
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
		},
		["IceMelonpult"] = {
			Id = "IceMelonpult",
			Name = "Ice Melon-pult",
			HP = 3000,
			Quality = 5,
			CanAttack = true,
			ArcHeight = 20, -- 🏀 投手专属：已修复补上
			Attack = 4000,
			AttackInterval = 2, 
			IdleAnimId = "rbxassetid://117331055474996",
			AttackAnimation = "rbxassetid://125434851620830",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "IceMelon", 
			Description = "Details: Hurls ice melon to deal extreme damage and slow targets!",
		},
		["CobCannon"] = {
			Id = "CobCannon",
			Name = "CobCannon",
			HP = 3000,
			Quality = 5,
			IdleAnimId = "rbxassetid://140048491047365",
			AttackAnimation = "rbxassetid://121193564169167",
			ArcHeight = 20, -- 🏀 投手专属
			CanAttack = true,
			Attack = 6000, 
			AttackInterval = 2,
			HitEffectTexture = "CornMP",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Corn", 
			Description = "Description: The ultimate weapon. Lobs giant cobs for devastating damage.",
		},
	},
	
	MutationProb = { [1] = 90, [2] = 7, [3] = 3, [4] = 1 },
	MutationName = { 
		[1] = "普通", 
		[2] = "闪光", 
		[3] = "雷电", 
		[4] = "神圣" 
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
ItemConfig.MutationStats = {
    [1] = { DamageMul = 1.0, HealthMul = 1.0 },   -- 普通
    [2] = { DamageMul = 1.5, HealthMul = 1.5 },   -- 闪光 (+50% 攻击, +50% 血量)
    [3] = { DamageMul = 2, HealthMul = 3 },       -- 雷电 (+100% 攻击, +200% 血量)
    [4] = { DamageMul = 2.5, HealthMul = 4 },     -- 神圣 (+150% 攻击, +300% 血量)
}
return ItemConfig
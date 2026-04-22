-- src/shared/ItemConfig.luau
local ItemConfig = {
	IdToSeedKey = {
		"Peashooter",
		"Wall",
		"PotatoMine",
		"Jalapeno",
	},
	
	Seeds = {
		-- ==========================================
		-- [第 1 阶段：新手体验期] (价格跨度：100 ~ 1,500)
		-- ==========================================
		["Peashooter"] = {
			Id = 1,
			Name = "豌豆射手种子",
			Quality = 1,
			GrowthTime = 5,
			YieldPlant = "Peashooter",
			BuyPrice = 100,       
			RobuxPrice = 19,      
			UnlockLevel = 0, 
		},
		["Wall"] = {
			Id = 2,
			Name = "坚果墙种子",
			Quality = 1,
			GrowthTime = 10,
			YieldPlant = "Wall",
			BuyPrice = 500,       -- (x5倍) 打完前两关就能买
			RobuxPrice = 39,      
			UnlockLevel = 0, 
		},
		["PotatoMine"] = {
			Id = 3,
			Name = "土豆地雷种子",
			Quality = 2,
			GrowthTime = 60,
			YieldPlant = "PotatoMine",
			BuyPrice = 1500,      -- (x3倍) 稍微需要攒一攒
			RobuxPrice = 79,      
			UnlockLevel = 0, 
		},

		-- ==========================================
		-- [第 2 阶段：中期发育期] (价格跨度：4,500 ~ 35,000)
		-- ==========================================
		["KernelPult"] = {
			Id = 4,
			Name = "玉米投手种子",
			Quality = 2,
			GrowthTime = 300,
			YieldPlant = "KernelPult",
			BuyPrice = 4500,      -- (x3倍) 此时玩家应该有了稳定的刷钱阵型
			RobuxPrice = 149,      
			UnlockLevel = 10, 
		},
		["Jalapeno"] = {
			Id = 5,
			Name = "火爆辣椒种子",
			Quality = 3,
			GrowthTime = 600,
			YieldPlant = "Jalapeno",
			BuyPrice = 12000,     -- (x2.6倍) 强力清屏道具，卖贵一点
			RobuxPrice = 249,     
			UnlockLevel = 16, 
		},
		["CoconutTree"] = {
			Id = 6,
			Name = "椰子树种子",
			Quality = 3,
			GrowthTime = 600,
			YieldPlant = "CoconutTree",
			BuyPrice = 35000,     -- (x2.9倍) 开始感受到金币压力
			RobuxPrice = 399,
			UnlockLevel = 24, 
		},

		-- ==========================================
		-- [第 3 阶段：后期肝帝期] (价格跨度：10万 ~ 200万)
		-- ==========================================
		["FumeShroom"] = {
			Id = 7,
			Name = "大喷菇种子",
			Quality = 3,
			GrowthTime = 600,
			YieldPlant = "FumeShroom",
			BuyPrice = 100000,    -- (x2.8倍) 突破十万大关！
			RobuxPrice = 599,
			UnlockLevel = 32, 
		},
		["Cactus"] = {
			Id = 8,
			Name = "仙人掌种子",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Cactus",
			BuyPrice = 250000,    -- (x2.5倍)
			RobuxPrice = 899,
			UnlockLevel = 40, 
		},
		["Sunflower"] = {
			Id = 9,
			Name = "向日葵种子",
			Quality = 4,
			GrowthTime = 1800,
			YieldPlant = "Sunflower",
			BuyPrice = 750000,    -- (x3倍) 经济类植物，前期极难获取
			RobuxPrice = 1299,
			UnlockLevel = 48, 
		},
		["MegaPeashooter"] = {
			Id = 10,
			Name = "超级豌豆射手",
			Quality = 5,           -- 传说品质
			GrowthTime = 3600,     
			YieldPlant = "MegaPeashooter",
			BuyPrice = 2000000,    -- (x2.6倍) 两百万！毕业级追求！
			RobuxPrice = 1999,     -- 标准终极道具定价 (约25美元)
			UnlockLevel = 50, 
		},

	},
	
	Plants = {
		["Peashooter"] = {
			Id = "Peashooter",
			Name = "豌豆射手",
			HP = 300,
			Quality = 1,
			IdleAnimId = "rbxassetid://78336317659894",
			CanAttack = true,
			Attack = 20,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 127),
			ProjectileName = "Pea", 
			Description = "详情：发射豌豆造成基础伤害。",
			Source = "商城购买",
		},
		["Wall"] = {
			Id = "Wall",
			Name = "坚果墙",
			HP = 4000,
			Quality = 1,
			IdleAnimId = "rbxassetid://130556607788926",
			CanAttack = false,
			Description = "详情：拥有极高的生命值，阻挡僵尸前进。",
			Source = "商城购买",
		},
		["PotatoMine"] = {
			Id = "PotatoMine",
			Name = "土豆地雷",
			HP = 1000,
			Attack = 1000,
			Quality = 2,
			IdleAnimId = "rbxassetid://90962037485623",
			CanAttack = false,
			ExplosionType = "Single",
			ExplosionDamage = 1000,
			Description = "详情：被吃掉时引发爆炸，造成巨额单体伤害。",
			Source = "商城购买",
		},
		["KernelPult"] = {
			Id = "KernelPult",
			Name = "玉米投手",
			HP = 300,
			Quality = 2,
			IdleAnimId = "rbxassetid://135320524253878",
			AttackAnimation = "rbxassetid://125434851620830",
			ArcHeight = 20,
			CanAttack = true,
			Attack = 20,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 255, 127),
			ProjectileName = "Kernel", 
			Description = "详情：投掷玉米粒，造成基础伤害。",
			Source = "商城购买",
		},
		["Jalapeno"] = {
			Id = "Jalapeno",
			Name = "火爆辣椒",
			HP = 5,
			Attack = 600,
			Quality = 2,
			CanAttack = false,
			ExplosionType = "Row",
			ExplosionDamage = 600,
			Description = "详情：极速引爆，对整条路线上的僵尸造成毁灭打击。",
			Source = "商城购买",
		},
        -- ==========================================
		-- [🌟 新增植物配置]
		-- ==========================================
        ["CoconutTree"] = {
			Id = "CoconutTree",
			Name = "椰子树",
			HP = 500,
			Quality = 3,
			CanAttack = true,
			Attack = 90,
			IdleAnimId = "rbxassetid://82072725732014",
			AttackAnimation = "rbxassetid://140311761151184s",
			AttackInterval = 3, -- 攻击慢，但伤害高
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(255, 170, 0),
			ProjectileName = "Coconut", -- 如果有椰子炮弹模型，可以改为 "Coconut"
			Description = "详情：发射重型椰子炮弹，对僵尸造成高额单次伤害。",
			Source = "商城购买",
		},
        ["FumeShroom"] = {
			Id = "FumeShroom",
			Name = "大喷菇",
			HP = 300,
			Quality = 3,
			CanAttack = true,
			Attack = 35,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://137165648071153",
			AttackAnimation = "rbxassetid://106856862873566",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(170, 85, 255), -- 紫色特效
			ProjectileName = "Spore", -- 如果有孢子模型，可以改为 "Spore"
			Description = "详情：喷射高伤害孢子，火力压制前方僵尸。",
			Source = "商城购买",
		},
        ["Cactus"] = {
			Id = "Cactus",
			Name = "仙人掌",
			HP = 400,
			Quality = 4,
			CanAttack = true,
			Attack = 40,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://132507907086232",
			AttackAnimation ="rbxassetid://87531231080785", 
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 0),
			ProjectileName = "Spike", -- 如果有尖刺模型，可以改为 "Spike"
			Description = "详情：发射锐利的尖刺，拥有极强的穿透打击感。",
			Source = "商城购买",
		},
        ["Sunflower"] = {
			Id = "Sunflower",
			Name = "向日葵",
			HP = 400,
			Quality = 4,
			CanAttack = true,
			Attack = 40,
			AttackInterval = 1.5,
			IdleAnimId = "rbxassetid://123013968700468",
			AttackAnimation = "rbxassetid://100300439397971",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 0),
			ProjectileName = "Sunflower",  
			Description = "详情：发射锐利的尖刺，拥有极强的穿透打击感。",
			Source = "商城购买",
		},
        ["MegaPeashooter"] = {
			Id = "MegaPeashooter",
			Name = "超级豌豆射手",
			HP = 600,
			Quality = 5,
			CanAttack = true,
			Attack = 30,
			AttackInterval = 0.5, -- 极快攻速，机枪豌豆体验
			IdleAnimId = "rbxassetid://78336317659894",
			AttackAnimation = "rbxassetid://84912090941129",
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(0, 255, 255),
			ProjectileName = "Pea", 
			Description = "详情：以极其恐怖的射速倾泻火力，传说级的战场收割机！",
			Source = "商城购买",
		},

	},
	
	MutationProb = { [1] = 70, [2] = 20, [3] = 7, [4] = 3 }, -- 调整为 4 个等级
	MutationName = { 
		[1] = "普通", 
		[2] = "闪耀", 
		[3] = "雷电", 
		[4] = "圣光" 
	},
	QualityName = { [1] = "常见", [2] = "不常见", [3] = "稀有", [4] = "史诗", [5] = "传奇" , [6] = "神话", [7] = "秘密" , [8] = "神圣" },
	-- [🌟 新增：全局品质颜色映射]
	QualityColor = {
		[1] = Color3.fromRGB(255, 255, 255), -- 常见：白色
		[2] = Color3.fromRGB(85, 255, 127),  -- 不常见：绿色
		[3] = Color3.fromRGB(85, 170, 255),  -- 稀有：蓝色
		[4] = Color3.fromRGB(170, 85, 255),  -- 史诗：紫色
		[5] = Color3.fromRGB(255, 170, 0),   -- 传奇：橙色
		[6] = Color3.fromRGB(255, 85, 85),   -- 神话：红色
		[7] = Color3.fromRGB(255, 85, 255),  -- 秘密：粉色
		[8] = Color3.fromRGB(0, 255, 255),   -- 神圣：青色
	},
}

return ItemConfig
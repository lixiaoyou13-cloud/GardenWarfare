local ItemConfig = {
	-- [🌟 新增：种子 ID 映射表，方便图鉴排序和随机抽取]
		IdToSeedKey = {
			"Peashooter",   -- ID 1
			"Wall",         -- ID 2
			"PotatoMine",   -- ID 3
			"Jalapeno",     -- ID 4
		},
	
	-- ==================================
	-- [种子类配置]
	-- ==================================
	Seeds = {
		
		-- [🌟 新增：神秘随机种子 (盲盒)]
		["RandomSeed"] = {
			Id = 999,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "神秘盲盒",
			Type = "RandomSeed",
			BuyPrice = 300,     -- 盲盒稍微贵一点
			GrowthTime = 30,    -- 盲盒长得快一点，保持期待感
			Icon = "rbxassetid://0",
		},
		-- 这里的 "SunflowerSeed" 就是这个物品的唯一 ID（字典的 Key）
		-- 以后不管是代码查找还是数据库存储,最好都用这个英文 ID,不要存中文名
		["Peashooter"] = {
			Id = 1,           -- 物品ID

			ModelId = "Seed" ,

			SeedId = "PlantSeed",
		
			Name = "豌豆射手种子",              -- UI显示的中文名

			Type = "Seed",                  -- 物品大类：种子
			
			-- 种植相关属性
			GrowthTime = 30,            -- 生长需要的时间（秒）,比如 60 秒
			YieldPlant = "Peashooter",       -- 成熟后产出的植物 ID (需要你在未来写植物配置)
			
			-- 经济属性
			BuyPrice = 100,                 -- 商店购买价格（金币）
			SellPrice = 120,                -- 卖出价格（金币）
			Output = 10,             		-- 产出价格
			
			-- 背包与显示属性
			MaxStack = 99,                  -- 背包中单个格子的最大叠加数量
			--  收获数量
			YieldCount = 3,

			Icon = "rbxassetid://0",        -- 种子的图片ID（填入 Roblox 的贴图 ID,0 是占位符）
		},
		["Wall"] = {
			Id = 2,           -- 物品ID
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
		
			Name = "坚果墙种子",              -- UI显示的中文名
			Type = "Wall",                  -- 物品大类：墙

			-- 种植相关属性
			GrowthTime = 30,                -- 生长需要的时间（秒）,比如 60 秒
			YieldPlant = "Wall",       -- 成熟后产出的植物 ID (需要你在未来写植物配置)

			-- 经济属性
			BuyPrice = 100,                 -- 商店购买价格（金币）
			SellPrice = 120,                -- 卖出价格（金币）
			Output = 10,             		-- 产出价格

			YieldCount = 3,
			
			-- 背包与显示属性
			MaxStack = 99,                  -- 背包中单个格子的最大叠加数量
			Icon = "rbxassetid://0",        -- 种子的图片ID（填入 Roblox 的贴图 ID,0 是占位符）

		},
		["PotatoMine"] = {
			Id = 3,           -- 物品ID
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			
			Name = "土豆地雷种子",              -- UI显示的中文名
			Type = "PotatoMine",                  -- 物品大类：土豆地雷

			
			-- 种植相关属性
			GrowthTime = 60,                -- 生长需要的时间（秒）,比如 60 秒
			YieldPlant = "PotatoMine",       -- 成熟后产出的植物 ID (需要你在未来写植物配置)

			-- 经济属性
			BuyPrice = 100,                 -- 商店购买价格（金币）
			SellPrice = 120,                -- 卖出价格（金币）
			Output = 10,             		-- 产出价格
			YieldCount = 3,
			
			-- 背包与显示属性
			MaxStack = 99,                  -- 背包中单个格子的最大叠加数量
			Icon = "rbxassetid://0",        -- 种子的图片ID（填入 Roblox 的贴图 ID,0 是占位符）

		},
		["Jalapeno"] = {
			Id = 4,           -- 物品ID
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
		
			Name = "火爆辣椒种子",              -- UI显示的中文名
			Type = "Jalapeno",                  -- 物品大类：辣椒	
			--  收获数量
			YieldCount = 3,
			
			-- 种植相关属性
			GrowthTime = 600,                -- 生长需要的时间（秒）,比如 60 秒
			YieldPlant = "Jalapeno",       -- 成熟后产出的植物 ID (需要你在未来写植物配置)

			-- 经济属性
			BuyPrice = 100,                 -- 商店购买价格（金币）
			SellPrice = 120,                -- 卖出价格（金币）
			Output = 10,             		-- 产出价格
			
			-- 背包与显示属性
			MaxStack = 999,                  -- 背包中单个格子的最大叠加数量
			Icon = "rbxassetid://0",        -- 种子的图片ID（填入 Roblox 的贴图 ID,0 是占位符）

		},
		



		
	},
	
	-- ==================================
	-- [植物类配置] (未来预留)
	-- ==================================
	Plants = {
		["Peashooter"] = {
			Id = "Peashooter",
			Name = "豌豆射手",
			HP = 300,
			IdleAnimId = "rbxassetid://78336317659894",
            
			-- [🌟 武装系属性]
			CanAttack = true,           -- 允许开火
			Attack = 20,                -- 伤害值
			AttackInterval = 2,       -- 攻击间隔（秒）
			-- [🌟 新增：专属命中爆炸特效配置！]
            HitEffectTexture = "rbxassetid://243098098",      -- 烟雾/火花贴图
            HitEffectColor = Color3.fromRGB(85, 255, 127),    -- 绿色的飞溅特效
            
            -- [🌟 核心：直接指向你在 Ammo 文件夹里做好的模型]
			ProjectileName = "Pea", 
		},
		["Wall"] = {
			Id = "Wall",
			Name = "坚果墙",
			HP = 4000,                  -- [🌟 防御系属性] 超高血量！
			IdleAnimId = "rbxassetid://130556607788926",
            
			CanAttack = false,          -- [🌟 坚果墙绝对不开火]
		},
		["PotatoMine"] = {
			Id = "PotatoMine",
			Name = "土豆地雷",
			HP = 1000,                     -- [🌟 陷阱属性] 只有1滴血，僵尸一碰就触发！
			IdleAnimId = "rbxassetid://90962037485623",
            
			CanAttack = false,
            
			-- [🌟 新增：自爆核心参数]
			ExplosionType = "Single",   -- 爆炸类型：单格爆炸
			ExplosionDamage = 1000,     -- 巨额真实伤害（秒杀大部分普通僵尸）
		},
		["Jalapeno"] = {
			Id = "Jalapeno",
			Name = "火爆辣椒",
			HP = 300,                   -- [🌟 炸药桶属性] 能抗住几口，死后拉垫背！
            
			CanAttack = false,
            
			-- [🌟 新增：自爆核心参数]
			ExplosionType = "Row",      -- 爆炸类型：整行清屏
			ExplosionDamage = 600,     -- 巨额真实伤害
		},
	},
	-- ==================================
	-- [变异概率]
	-- ==================================
	MutationProb = {
		[1] = 70,
		[2] = 20,
		[3] = 4,
		[4] = 3,
		[5] = 1,
	},
	-- ==================================
	-- [变异名称]
	-- ==================================
	MutationName = {
		[1] = "普通",
		[2] = "稀有",
		[3] = "变异",
		[4] = "彩虹",
		[5] = "宇宙",
	},
}

return ItemConfig
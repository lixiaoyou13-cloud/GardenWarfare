-- src/shared/ItemConfig.luau
local ItemConfig = {
	IdToSeedKey = {
		"Peashooter",
		"Wall",
		"PotatoMine",
		"Jalapeno",
	},
	
	Seeds = {
		["RandomSeed"] = {
			Id = 999,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "随机种子",
			Type = "RandomSeed",
			BuyPrice = 300,
			GrowthTime = 300,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["Peashooter"] = {
			Id = 1,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "豌豆射手种子",
			Type = "Seed",
			GrowthTime = 5,
			YieldPlant = "Peashooter",
			BuyPrice = 100,
			SellPrice = 120,
			Output = 10,
			MaxStack = 99,
			YieldCount = 3,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["Wall"] = {
			Id = 2,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "坚果墙种子",
			Type = "Wall",
			GrowthTime = 10,
			YieldPlant = "Wall",
			BuyPrice = 100,
			SellPrice = 120,
			Output = 10,
			YieldCount = 3,
			MaxStack = 99,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["PotatoMine"] = {
			Id = 3,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "土豆地雷种子",
			Type = "PotatoMine",
			GrowthTime = 60,
			YieldPlant = "PotatoMine",
			BuyPrice = 100,
			SellPrice = 120,
			Output = 10,
			YieldCount = 3,
			MaxStack = 99,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["Jalapeno"] = {
			Id = 4,
			ModelId = "Seed" ,
			SeedId = "PlantSeed",
			Name = "火爆辣椒种子",
			Type = "Jalapeno",
			YieldCount = 3,
			GrowthTime = 600,
			YieldPlant = "Jalapeno",
			BuyPrice = 100,
			SellPrice = 120,
			Output = 10,
			MaxStack = 999,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
	},
	
	Plants = {
		["Peashooter"] = {
			Id = "Peashooter",
			Name = "豌豆射手",
			HP = 300,
			IdleAnimId = "rbxassetid://78336317659894",
			CanAttack = true,
			Attack = 20,
			AttackInterval = 2,
			HitEffectTexture = "rbxassetid://243098098",
			HitEffectColor = Color3.fromRGB(85, 255, 127),
			ProjectileName = "Pea", 
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["Wall"] = {
			Id = "Wall",
			Name = "坚果墙",
			HP = 4000,
			IdleAnimId = "rbxassetid://130556607788926",
			CanAttack = false,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["PotatoMine"] = {
			Id = "PotatoMine",
			Name = "土豆地雷",
			HP = 1000,
			IdleAnimId = "rbxassetid://90962037485623",
			CanAttack = false,
			ExplosionType = "Single",
			ExplosionDamage = 1000,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
		["Jalapeno"] = {
			Id = "Jalapeno",
			Name = "火爆辣椒",
			HP = 300,
			CanAttack = false,
			ExplosionType = "Row",
			ExplosionDamage = 600,
			IconId = "rbxassetid://126862599177625", -- [🌟 统一图片字段]
		},
	},
	
	MutationProb = { [1] = 70, [2] = 20, [3] = 4, [4] = 3, [5] = 1, },
	MutationName = { [1] = "普通", [2] = "稀有", [3] = "变异", [4] = "彩虹", },
}

return ItemConfig
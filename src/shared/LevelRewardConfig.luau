-- src/shared/LevelRewardConfig.luau
local LevelRewardConfig = {
    
    -- [关卡数] = { Sun = 阳光数量, Seed = "种子ID", SeedCount = 种子数量 }
    -- 如果某关不给种子，直接不写 Seed 字段即可
    
    [1] = { Sun = 1000, Seed = "Peashooter", SeedCount = 3 },
    [5] = { Sun = 2000, Seed = "PotatoMine", SeedCount = 1 },
    [10]= { Sun = 5000, Seed = "PotatoMine", SeedCount = 3},
    [15]= { Sun = 10000,Seed = "PotatoMine", SeedCount = 7},
    [20]= { Sun = 30000 ,Seed = "KernelPult", SeedCount = 1},
    [25]= { Sun = 50000 ,Seed = "KernelPult", SeedCount = 3},
    [30]= { Sun = 100000 ,Seed = "KernelPult", SeedCount = 7},
    [35]= { Sun = 200000 ,Seed = "Jalapeno", SeedCount = 1},
    [40]= { Sun = 500000 ,Seed = "Jalapeno", SeedCount = 3},
    [45]= { Sun = 1000000 ,Seed = "Jalapeno", SeedCount = 7},
    [50]= { Sun = 1200000,Seed = "CoconutTree", SeedCount = 1},
    [55]= { Sun = 1500000,Seed = "CoconutTree", SeedCount = 3 },
    [60]= { Sun = 2000000 ,Seed = "CoconutTree", SeedCount = 7},
    [65]= { Sun = 5000000,Seed = "FumeShroom", SeedCount = 1 },
    [70]= { Sun = 6000000,Seed = "FumeShroom", SeedCount = 3 },
    [75]= { Sun = 7000000,Seed = "FumeShroom", SeedCount = 7},
    [80]= { Sun = 8000000 ,Seed = "Cactus", SeedCount = 1},
    [85]= { Sun = 15000000,Seed = "Cactus", SeedCount = 3 },
    [90]= { Sun = 20000000 ,Seed = "Cactus", SeedCount = 7},
    [95]= { Sun = 25000000,Seed = "Sunflower", SeedCount = 1 },
    [100]={ Sun = 30000000,Seed = "Sunflower", SeedCount = 3},
    [105]={ Sun = 50000000 ,Seed = "Sunflower", SeedCount = 7},
    [110]={ Sun = 60000000,Seed = "Melonpult", SeedCount = 1 },
    [115]={ Sun = 100000000 ,Seed = "Melonpult", SeedCount = 3},
}

return LevelRewardConfig
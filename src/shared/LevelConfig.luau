-- src/shared/LevelConfig.luau
local LevelConfig = {
    -- ==========================================
    -- 【新手热身期】增加基础数量，让你开局就能杀得爽
    -- ==========================================
    [1] = {
        LevelName = "第 1 关：僵尸小分队",
        Reward = 200, 
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 10 } } }
        }
    },
    [2] = {
        LevelName = "第 2 关：压力初现",
        Reward = 400,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 12 }, { Type = "ConeheadZombie", Count = 3 } } }
        }
    },
    [3] = {
        LevelName = "第 3 关：路障潮",
        Reward = 600,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 15 }, { Type = "ConeheadZombie", Count = 8 } } }
        }
    },

    -- ==========================================
    -- 【进阶抗压期】铁桶僵尸不再是稀客，数量翻倍
    -- ==========================================
    [4] = {
        LevelName = "第 4 关：铁桶大军",
        Reward = 800,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 15 }, { Type = "ConeheadZombie", Count = 10 }, { Type = "BucketheadZombie", Count = 4 } } }
        }
    },
    [5] = {
        LevelName = "第 5 关：第一波小高潮",
        Reward = 1000,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 20 }, { Type = "ConeheadZombie", Count = 12 }, { Type = "BucketheadZombie", Count = 6 } } }
        }
    },
    [6] = {
        LevelName = "第 6 关：持续推进",
        Reward = 1200,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 25 }, { Type = "ConeheadZombie", Count = 15 }, { Type = "BucketheadZombie", Count = 8 } } }
        }
    },

    -- ==========================================
    -- 【高难割草期】铁门僵尸作为主力，真正的尸潮来袭
    -- ==========================================
    [7] = {
        LevelName = "第 7 关：铁甲洪流",
        Reward = 1400,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 30 }, { Type = "ConeheadZombie", Count = 20 }, { Type = "BucketheadZombie", Count = 10 }, { Type = "ScreenDoorZombie", Count = 5 } } }
        }
    },
    [8] = {
        LevelName = "第 8 关：极限防守",
        Reward = 1600,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 35 }, { Type = "ConeheadZombie", Count = 25 }, { Type = "BucketheadZombie", Count = 15 }, { Type = "ScreenDoorZombie", Count = 8 } } }
        }
    },
    [9] = {
        LevelName = "第 9 关：疯狂前奏",
        Reward = 1800,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 40 }, { Type = "ConeheadZombie", Count = 30 }, { Type = "BucketheadZombie", Count = 20 }, { Type = "ScreenDoorZombie", Count = 12 } } }
        }
    },
    
    -- ==========================================
    -- 【终极决战】铺满全场的怪物，检验终极植物的时刻！
    -- ==========================================
    [10] = {
        LevelName = "第 10 关：僵尸王国的远征",
        Reward = 2000,
        Waves = {
            [1] = { NextWaveTime = 0,  Zombies = { { Type = "Zombie", Count = 60 }, { Type = "ConeheadZombie", Count = 40 }, { Type = "BucketheadZombie", Count = 30 }, { Type = "ScreenDoorZombie", Count = 20 } } }
        }
    }
}

-- ==========================================
-- [🌟 纯数据：无尽模式僵尸池 (解锁等级与权重)]
-- ==========================================
LevelConfig.InfiniteZombiePool = {
    { Type = "Zombie",          UnlockLevel = 1,  Weight = 100 }, 
    { Type = "ConeheadZombie",  UnlockLevel = 3,  Weight = 50 },  
    { Type = "BucketheadZombie",UnlockLevel = 6,  Weight = 20 },  
    { Type = "ScreenDoorZombie",UnlockLevel = 11, Weight = 10 },
}

return LevelConfig
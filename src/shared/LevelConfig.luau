-- src/shared/LevelConfig.luau
local LevelConfig = {
    -- ==========================================
    -- 【新手阶段】适应操作，认识防具
    -- ==========================================
    [1] = {
        LevelName = "第 1 关：初来乍到",
        Reward = 200, 
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 5 } } },
            [2] = { NextWaveTime = 0,  Zombies = { { Type = "Zombie", Count = 3 }, { Type = "ConeheadZombie", Count = 1 } } }
        }
    },
    [2] = {
        LevelName = "第 2 关：渐入佳境",
        Reward = 400,
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 6 } } },
            [2] = { NextWaveTime = 0,  Zombies = { { Type = "Zombie", Count = 5 }, { Type = "ConeheadZombie", Count = 3 } } }
        }
    },
    [3] = {
        LevelName = "第 3 关：小试牛刀",
        Reward = 600,
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 8 } } },
            [2] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 5 }, { Type = "ConeheadZombie", Count = 4 } } },
            [3] = { NextWaveTime = 0,  Zombies = { { Type = "ConeheadZombie", Count = 5 } } }
        }
    },

    -- ==========================================
    -- 【进阶阶段】铁桶登场，考验土豆雷与火力
    -- ==========================================
    [4] = {
        LevelName = "第 4 关：铁桶危机",
        Reward = 800,
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 10 } } },
            [2] = { NextWaveTime = 15, Zombies = { { Type = "ConeheadZombie", Count = 5 } } },
            -- [🌟 重点] 第一次出现铁桶僵尸，需要玩家提前埋好土豆雷
            [3] = { NextWaveTime = 0,  Zombies = { { Type = "BucketheadZombie", Count = 1 }, { Type = "Zombie", Count = 5 } } }
        }
    },
    [5] = {
        LevelName = "第 5 关：第一波尸潮！",
        Reward = 1000,
        Waves = {
            [1] = { NextWaveTime = 20, Zombies = { { Type = "Zombie", Count = 12 } } },
            [2] = { NextWaveTime = 0,  Zombies = { { Type = "Zombie", Count = 15 }, { Type = "ConeheadZombie", Count = 10 }, { Type = "BucketheadZombie", Count = 2 } } }
        }
    },
    [6] = {
        LevelName = "第 6 关：稳扎稳打",
        Reward = 1200,
        Waves = {
            [1] = { NextWaveTime = 12, Zombies = { { Type = "Zombie", Count = 8 } } },
            [2] = { NextWaveTime = 12, Zombies = { { Type = "ConeheadZombie", Count = 6 } } },
            [3] = { NextWaveTime = 12, Zombies = { { Type = "Zombie", Count = 5 }, { Type = "BucketheadZombie", Count = 2 } } },
            [4] = { NextWaveTime = 0,  Zombies = { { Type = "ConeheadZombie", Count = 8 } } }
        }
    },

    -- ==========================================
    -- 【高难阶段】重装压境，防线必须完美成型
    -- ==========================================
    [7] = {
        LevelName = "第 7 关：重装上阵",
        Reward = 1400,
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "ConeheadZombie", Count = 10 } } },
            [2] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 10 }, { Type = "BucketheadZombie", Count = 3 } } },
            [3] = { NextWaveTime = 0,  Zombies = { { Type = "ConeheadZombie", Count = 12 }, { Type = "BucketheadZombie", Count = 4 } } }
        }
    },
    [8] = {
        LevelName = "第 8 关：闪电突袭",
        Reward = 1600,
        Waves = {
            -- 缩短出怪间隔 (8秒)，僵尸会走得很密集，非常适合火爆辣椒发挥！
            [1] = { NextWaveTime = 8, Zombies = { { Type = "Zombie", Count = 8 } } },
            [2] = { NextWaveTime = 8, Zombies = { { Type = "ConeheadZombie", Count = 5 } } },
            [3] = { NextWaveTime = 8, Zombies = { { Type = "BucketheadZombie", Count = 2 } } },
            [4] = { NextWaveTime = 8, Zombies = { { Type = "ConeheadZombie", Count = 8 } } },
            [5] = { NextWaveTime = 0, Zombies = { { Type = "Zombie", Count = 15 }, { Type = "BucketheadZombie", Count = 3 } } }
        }
    },
    [9] = {
        LevelName = "第 9 关：破釜沉舟",
        Reward = 1800,
        Waves = {
            [1] = { NextWaveTime = 20, Zombies = { { Type = "ConeheadZombie", Count = 15 } } },
            [2] = { NextWaveTime = 20, Zombies = { { Type = "BucketheadZombie", Count = 6 }, { Type = "Zombie", Count = 10 } } },
            [3] = { NextWaveTime = 0,  Zombies = { { Type = "ConeheadZombie", Count = 15 }, { Type = "BucketheadZombie", Count = 8 } } }
        }
    },
    
    -- ==========================================
    -- 【最终关卡】极致压力，史诗级尸潮！
    -- ==========================================
    [10] = {
        LevelName = "第 10 关：终极决战",
        Reward = 2000,
        Waves = {
            [1] = { NextWaveTime = 15, Zombies = { { Type = "Zombie", Count = 15 }, { Type = "ConeheadZombie", Count = 5 } } },
            [2] = { NextWaveTime = 15, Zombies = { { Type = "ConeheadZombie", Count = 15 }, { Type = "BucketheadZombie", Count = 3 } } },
            [3] = { NextWaveTime = 15, Zombies = { { Type = "BucketheadZombie", Count = 10 } } },
            -- 终极混编军团
            [4] = { NextWaveTime = 0,  Zombies = { { Type = "Zombie", Count = 20 }, { Type = "ConeheadZombie", Count = 20 }, { Type = "BucketheadZombie", Count = 15 } } }
        }
    }
}
-- ==========================================
-- [🌟 纯数据：无尽模式僵尸池 (解锁等级与权重)]
-- ==========================================
LevelConfig.InfiniteZombiePool = {
    { Type = "NormalZombie",    UnlockLevel = 1,  Weight = 100 }, 
    { Type = "ConeheadZombie",  UnlockLevel = 3,  Weight = 50 },  
    { Type = "BucketheadZombie",UnlockLevel = 6,  Weight = 20 },  
    { Type = "ScreenDoorZombie",UnlockLevel = 11, Weight = 10 },
    -- 后续可以直接在这里加： { Type = "FootballZombie", UnlockLevel = 11, Weight = 10 },
}

return LevelConfig
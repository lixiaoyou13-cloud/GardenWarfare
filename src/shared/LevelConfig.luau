-- src/shared/LevelConfig.luau
local LevelConfig = {}

-- 自动生成 20平滑进度
for i = 1, 20 do
    local zombies = {}
    
    if i <= 5 then
        -- [1-5关]：纯普通僵尸，数量：5, 8, 11, 14, 18
        table.insert(zombies, { Type = "Zombie", Count = 2 + i * 3 + (i == 5 and 1 or 0) })
    elseif i <= 10 then
        -- [6-10关]：引入路障僵尸
        table.insert(zombies, { Type = "Zombie", Count = 15 + (i-5) * 2 })
        table.insert(zombies, { Type = "ConeheadZombie", Count = (i-5) * 2 })
    elseif i <= 15 then
        -- [11-15关]：引入铁桶僵尸
        table.insert(zombies, { Type = "Zombie", Count = 20 })
        table.insert(zombies, { Type = "ConeheadZombie", Count = 10 + (i-10) * 2 })
        table.insert(zombies, { Type = "BucketheadZombie", Count = (i-10) * 2 })
    else
        -- [16-20关]：引入铁门僵尸
        table.insert(zombies, { Type = "Zombie", Count = 25 })
        table.insert(zombies, { Type = "ConeheadZombie", Count = 15 })
        table.insert(zombies, { Type = "BucketheadZombie", Count = 5 + (i-15) * 2 })
        table.insert(zombies, { Type = "ScreenDoorZombie", Count = (i-15) * 2 })
    end

    LevelConfig[i] = {
        LevelName = "Level" .. i ,
        Reward = i * 100 + 100,
        Waves = {
            [1] = { NextWaveTime = 0, Zombies = zombies }
        }
    }
end

-- ==========================================
-- [🌟 无尽模式配置]：配合 20调整解锁等级
-- ==========================================
LevelConfig.InfiniteZombiePool = {
    { Type = "Zombie",          UnlockLevel = 1,  Weight = 100 }, 
    { Type = "ConeheadZombie",  UnlockLevel = 6,  Weight = 50 },  
    { Type = "BucketheadZombie",UnlockLevel = 11, Weight = 20 },  
    { Type = "ScreenDoorZombie",UnlockLevel = 16, Weight = 10 },
}

return LevelConfig
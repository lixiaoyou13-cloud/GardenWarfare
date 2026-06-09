-- src/shared/RollConfig.luau
local RollConfig = {}

-- 🌟 精简版 12 植物抽奖池 (总权重 = 1000)
RollConfig.Pools = {
    [1] = { 
        -- 【页签 1：普通池】 (共 11 种植物 | 只有 2 个五星 | 无玉米加农炮)
        
        -- ⭐ 1星 
        { Id = "Peashooter",   Weight = 300, DisplayRate = "30%" },   -- 商城
        
        -- ⭐⭐ 2星 
        { Id = "KernelPult",   Weight = 150, DisplayRate = "15%" },   -- 商城
        { Id = "CarrotShooter",Weight = 150, DisplayRate = "15%" },   -- 🎁 非商城
        
        -- ⭐⭐⭐ 3星 
        { Id = "SnowPea",      Weight = 100, DisplayRate = "10%" },   -- 🎁 非商城
        { Id = "CherryBomb",   Weight = 100, DisplayRate = "10%" },   -- 🎁 非商城
        { Id = "RadishShooter",Weight = 80,  DisplayRate = "8%" },    -- 🎁 非商城
        
        -- ⭐⭐⭐⭐ 4星 
        { Id = "FumeShroom",   Weight = 40,  DisplayRate = "4%" },    -- 商城
        { Id = "Magnetshroom", Weight = 40,  DisplayRate = "4%" },    -- 🎁 非商城
        { Id = "Cactus",       Weight = 30,  DisplayRate = "3%" },    -- 商城
        
        -- ⭐⭐⭐⭐⭐ 5星 (仅 2 个，掉率极低，无加农炮)
        { Id = "TwinSunflower",Weight = 5,   DisplayRate = "0.5%" },  -- 🎁 非商城
        { Id = "IceMelonpult", Weight = 5,   DisplayRate = "0.5%" },  -- 🎁 非商城
    },
    
    [2] = { 
        -- 【页签 2：高级池】 (共 12 种植物 | 包含 3 个五星 | 加农炮为极低概率 2%)
        
     

        { Id = "CarrotShooter",Weight = 130, DisplayRate = "13%" },   -- 🎁 非商城
        
        -- ⭐⭐⭐ 3星 
        { Id = "SnowPea",      Weight = 100, DisplayRate = "10%" },   -- 🎁 非商城
        { Id = "CherryBomb",   Weight = 100, DisplayRate = "10%" },   -- 🎁 非商城
        { Id = "RadishShooter",Weight = 100, DisplayRate = "10%" },   -- 🎁 非商城
        
        -- ⭐⭐⭐⭐ 4星 
        { Id = "FumeShroom",   Weight = 100,  DisplayRate = "11%" },    -- 商城
        { Id = "Magnetshroom", Weight = 100,  DisplayRate = "10%" },    -- 🎁 非商城
        { Id = "Cactus",       Weight = 130,  DisplayRate = "13%" },    -- 商城
        
        -- ⭐⭐⭐⭐⭐ 5星 (共 3 个，加农炮压轴)
        { Id = "MusicIcePeashooter",Weight = 80,  DisplayRate = "7%" },    -- 🎁 非商城
        { Id = "IceMelonpult", Weight = 90,  DisplayRate = "9%" },    -- 🎁 非商城
        { Id = "CobCannon",    Weight = 70,  DisplayRate = "7%" },    -- 🎁 非商城 (💣终极大奖，全场最低 2%)
    }
}

-- [抽奖算法]：根据传入的页签 ID 随机抽取对应的植物
function RollConfig.GetRandomPrize(tabIndex)
    local pool = RollConfig.Pools[tabIndex] or RollConfig.Pools[1]
    local totalWeight = 0
    
    for _, item in ipairs(pool) do
        totalWeight += item.Weight
    end

    local randomNum = math.random(1, totalWeight)
    local currentWeight = 0

    for _, item in ipairs(pool) do
        currentWeight += item.Weight
        if randomNum <= currentWeight then
            return item.Id
        end
    end
    
    return pool[1].Id 
end

-- [显示工具函数]：获取某个池子中植物的显示概率
function RollConfig.GetDisplayRate(tabIndex, itemId)
    local pool = RollConfig.Pools[tabIndex] or RollConfig.Pools[1]
    for _, item in ipairs(pool) do
        if item.Id == itemId then
            return item.DisplayRate
        end
    end
    return "0%"
end

return RollConfig
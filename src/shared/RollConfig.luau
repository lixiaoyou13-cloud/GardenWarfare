-- src/shared/RollConfig.luau
local RollConfig = {}

-- 🌟 升级为多池配置表，分别对应 Tab_1 和 Tab_2
RollConfig.Pools = {
    [1] = { -- 【页签 1：普通植物池】
        { Id = "Peashooter",   Weight = 300, DisplayRate = "30%" },
        { Id = "Sunflower",    Weight = 200, DisplayRate = "20%" },
        { Id = "Wall",         Weight = 150, DisplayRate = "15%" },
        { Id = "PotatoMine",   Weight = 150, DisplayRate = "15%" },
        { Id = "KernelPult",   Weight = 100, DisplayRate = "10%" },
        { Id = "FumeShroom",   Weight = 50,  DisplayRate = "5%" },
        { Id = "Jalapeno",     Weight = 20,  DisplayRate = "2%" },
        { Id = "Cactus",       Weight = 15,  DisplayRate = "1.5%" },
        { Id = "CoconutTree",  Weight = 10,  DisplayRate = "1%" },
        { Id = "Melonpult",    Weight = 5,   DisplayRate = "0.5%" },
    },
    
    [2] = { -- 【页签 2：全新高级/稀有池（自定义配置）】
        -- 这里为你配置了一套全新概率，大奖概率更高或包含不同植物
        { Id = "Jalapeno",     Weight = 300, DisplayRate = "30%" },
        { Id = "Cactus",       Weight = 250, DisplayRate = "25%" },
        { Id = "CoconutTree",  Weight = 200, DisplayRate = "20%" },
        { Id = "Melonpult",    Weight = 150, DisplayRate = "15%" },
        { Id = "Peashooter",   Weight = 100, DisplayRate = "10%" }, -- 举例：高级池里普通植物反而变稀有了
    }
}

-- [升级算法]：根据传入的页签 ID 随机抽取对应的植物
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

-- [升级工具函数]：获取某个池子中植物的显示概率
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
-- src/server/Services/ZombieBoxService.luau
local ZombieBoxService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- ✅ 修复了双端死等的 Bug：使用 FindFirstChild，如果没有再创建
local zombieBoxRE = ReplicatedStorage:FindFirstChild("ZombieBoxRE")
if not zombieBoxRE then
    zombieBoxRE = Instance.new("RemoteEvent")
    zombieBoxRE.Name = "ZombieBoxRE"
    zombieBoxRE.Parent = ReplicatedStorage
end

local pendingBoxes = {}

-- ==========================================
-- 🌟 1. 盲盒大类概率配置 (权重制)
-- ==========================================
local TYPE_WEIGHTS = {
    Seed = 65,      -- 种子权重 65
    Plant = 20,     -- 植物权重 20
    -- 以后想加新类型，只需解开注释并加上权重
    -- Prop = 10,   
    -- Currency = 5 
}

-- 品质权重配置 (1星~5星)
local QUALITY_WEIGHTS = { [1] = 70, [2] = 20, [3] = 8, [4] = 1.5, [5] = 0.5 }

-- 监听客户端动画播完后发来的“给我发奖”请求
zombieBoxRE.OnServerEvent:Connect(function(player, action, finalItem)
    if action == "GiveReward" then
        if pendingBoxes[player.UserId] and pendingBoxes[player.UserId] > 0 then
            pendingBoxes[player.UserId] -= 1

            -- ==========================================
            -- 🌟 2. 真实发奖逻辑扩展
            -- ==========================================
            if finalItem.type == "Plant" then
                PlayerDataManager.GivePlant(player, finalItem.id, 1, 1)
                
            elseif finalItem.type == "Seed" then
                PlayerDataManager.GiveSeed(player, finalItem.id, 1)
                
            elseif finalItem.type == "Prop" then
                -- 预留的道具发放接口
                -- PlayerDataManager.GiveItem(player, finalItem.id, 1)
                
            elseif finalItem.type == "Currency" then
                if finalItem.id == "CoinBox" then
                    PlayerDataManager.GiveCoins(player, finalItem.amount or 500)
                end
            end
        end
    end
end)

-- ✅ 这个就是你报错丢失的函数，必须确保它完整存在！
function ZombieBoxService.SpawnBox(player, dropPos)
    local categorizedPool = {}

    local function buildPool(configDict, typeName)
        if not configDict then return end
        categorizedPool[typeName] = {}
        for id, data in pairs(configDict) do
            local q = data.Quality or 1
            if not categorizedPool[typeName][q] then
                categorizedPool[typeName][q] = {}
            end
            table.insert(categorizedPool[typeName][q], {type = typeName, id = id})
        end
    end

    -- 初始化池子
    buildPool(ItemConfig.Plants, "Plant")
    buildPool(ItemConfig.Seeds, "Seed")

    -- 货币这种不需要星级的特殊物品，手动插入池子
    categorizedPool["Currency"] = {
        [1] = { {type = "Currency", id = "CoinBox", amount = 500} }
    }

    local function rollItem()
        -- 1. 先抽大类
        local totalTypeWeight = 0
        for _, weight in pairs(TYPE_WEIGHTS) do totalTypeWeight += weight end
        
        local typeRoll = math.random(1, totalTypeWeight)
        local targetType = "Seed" 
        local currentTypeWeight = 0
        
        for t, weight in pairs(TYPE_WEIGHTS) do
            currentTypeWeight += weight
            if typeRoll <= currentTypeWeight then
                targetType = t
                break
            end
        end

        -- 2. 再抽品质 
        local totalQualityWeight = 0
        for _, weight in pairs(QUALITY_WEIGHTS) do totalQualityWeight += weight end
        
        local qRoll = math.random(1, totalQualityWeight)
        local targetQuality = 1
        local currentQWeight = 0

        for q = 1, 5 do
            currentQWeight += (QUALITY_WEIGHTS[q] or 0)
            if qRoll <= currentQWeight then
                targetQuality = q
                break
            end
        end

        -- 3. 从对应大类和品质中随机选一个具体物品
        local typePool = categorizedPool[targetType]
        if typePool then
            local qualityPool = typePool[targetQuality]
            if qualityPool and #qualityPool > 0 then 
                return qualityPool[math.random(1, #qualityPool)] 
            end
            
            -- 降级拿1星保底
            local fallbackPool = typePool[1]
            if fallbackPool and #fallbackPool > 0 then 
                return fallbackPool[math.random(1, #fallbackPool)] 
            end
        end
        
        -- 极致兜底
        return {type = "Seed", id = "Peashooter"}
    end

    local finalItem = rollItem()

    if not pendingBoxes[player.UserId] then pendingBoxes[player.UserId] = 0 end
    pendingBoxes[player.UserId] += 1

    -- 通知客户端生成盲盒
    zombieBoxRE:FireClient(player, "SpawnBox", dropPos, finalItem)
end

-- ✅ return 必须在最底部
return ZombieBoxService
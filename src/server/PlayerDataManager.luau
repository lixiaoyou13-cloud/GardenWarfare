-- src/server/PlayerDataManager.luau
local PlayerDataManager = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataStore = DataStoreService:GetDataStore("MyGameData_V8")
local sessionData = {}

local function GetDefaultData()
   return {
        Coins = 500, Level = 1, UnlockedLevel = 1,
        Hotbar = {"Tool_Shovel"}, 
        Inventory = { Seeds = { { ID = "Peashooter", Quantity = 1 } }, Plants = {} },
        PlantedPlants = {}, CombatPlants = {},
        -- [🌟 新增：图鉴白名单]
        UnlockedSeeds = { ["Peashooter"] = true }, 
    }
end

local function saveWithRetry(userId, dataToSave)
    local dataForSave = table.clone(dataToSave)
    dataForSave.Hotbar = {} 
    
    for attempt = 1, 3 do
        local success = pcall(function() PlayerDataStore:SetAsync(userId, dataForSave) end)
        if success then return true else task.wait(2) end
    end
    return false
end

local function onPlayerAdded(player)
    local success, savedData = pcall(function() return PlayerDataStore:GetAsync(player.UserId) end)
    if success and savedData then
        -- [🌟 修改这里：老玩家上线，同样重置第一格为铲子]
        savedData.Hotbar = {"Tool_Shovel"} 
        if not savedData.PlantedPlants then savedData.PlantedPlants = {} end 
        if not savedData.CombatPlants then savedData.CombatPlants = {} end 
        -- [🌟 新增：老玩家强制补发图鉴数据]
        if type(savedData.UnlockedSeeds) ~= "table" then savedData.UnlockedSeeds = { ["Peashooter"] = true } end
        
        sessionData[player.UserId] = savedData
    else
        sessionData[player.UserId] = GetDefaultData()
    end
end

local function onPlayerRemoving(player)
    local dataToSave = sessionData[player.UserId]
    if dataToSave then
        sessionData[player.UserId] = nil 
        saveWithRetry(player.UserId, dataToSave)
    end
end

function PlayerDataManager.Init()
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do
            local dataToSave = sessionData[player.UserId]
            if dataToSave then task.spawn(function() saveWithRetry(player.UserId, dataToSave) end) end
        end
        task.wait(2)
    end)

    local getPlayerDataRF = Instance.new("RemoteFunction")
    getPlayerDataRF.Name = "GetPlayerDataRF"
    getPlayerDataRF.Parent = ReplicatedStorage
    getPlayerDataRF.OnServerInvoke = function(player)
        while not sessionData[player.UserId] do task.wait(0.1) end
        return sessionData[player.UserId]
    end
    
    if not ReplicatedStorage:FindFirstChild("UpdateInventoryRE") then
        local updateInventoryRE = Instance.new("RemoteEvent")
        updateInventoryRE.Name = "UpdateInventoryRE"
        updateInventoryRE.Parent = ReplicatedStorage
    end
end

function PlayerDataManager.GetPlayerData(player) return sessionData[player.UserId] end

function PlayerDataManager.UpdatePlantedPlant(player, soilName, seedId, plantedTime)
    local data = sessionData[player.UserId]
    if not data then return end
    -- 每次重新种地，覆盖记录，自带清除旧植物烙印的效果
    data.PlantedPlants[soilName] = { SeedId = seedId, PlantedTime = plantedTime }
end

-- ==========================================
-- [🌟 新增：防刷钱漏洞修复] 给已经爆过阳光的植物打上烙印！
-- ==========================================
function PlayerDataManager.MarkPlantAsDropped(player, soilName)
    local data = sessionData[player.UserId]
    if not data or not data.PlantedPlants[soilName] then return end
    data.PlantedPlants[soilName].HasDropped = true
end

function PlayerDataManager.RemovePlantedPlant(player, soilName)
    local data = sessionData[player.UserId]
    if not data then return end
    data.PlantedPlants[soilName] = nil
end

function PlayerDataManager.GiveSeed(player, seedId, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    local found = false
    for _, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then seedData.Quantity += amount;
        found = true; break end
    end
    if not found then table.insert(data.Inventory.Seeds, { ID = seedId, Quantity = amount }) end
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

function PlayerDataManager.ConsumeSeed(player, seedId, amount)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Seeds then return false end
    for i, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then
            if seedData.Quantity >= amount then
                seedData.Quantity -= amount
                if seedData.Quantity <= 0 then table.remove(data.Inventory.Seeds, i) end
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                return true
            end
            break
        end
    end
    return false
end

function PlayerDataManager.GivePlant(player, plantId, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId then plantData.Quantity += amount;
        found = true; break end
    end
    if not found then table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount }) end
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

function PlayerDataManager.ConsumeCoins(player, amount)
    local data = sessionData[player.UserId];
    if not data then return false end
    if data.Coins >= amount then
        data.Coins -= amount
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        return true 
    end
    return false 
end

function PlayerDataManager.GiveCoins(player, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    data.Coins += amount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end


-- ==========================================
-- [🌟 新增：战斗系统接口] 消耗成熟植物
-- ==========================================
function PlayerDataManager.ConsumePlant(player, plantId, amount)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Plants then return false end
    
    for i, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId then
            if plantData.Quantity >= amount then
                plantData.Quantity -= amount
                -- 如果植物用光了，从背包里彻底删掉它
                if plantData.Quantity <= 0 then table.remove(data.Inventory.Plants, i) end
                
                -- 通知客户端更新 UI
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                return true
            end
            break
        end
    end
    return false
end

-- ==========================================
-- [🌟 新增：关卡进度接口] 玩家通关后调用，解锁下一关
-- ==========================================
function PlayerDataManager.UnlockNextLevel(player, completedLevelId)
    local data = sessionData[player.UserId]
    if not data then return end
    
    -- 如果他刚打完的关卡，大于等于他当前的最高进度，就给他解锁下一关！
    if completedLevelId >= (data.UnlockedLevel or 1) then
        data.UnlockedLevel = completedLevelId + 1
        
        -- 通知客户端更新 UI 和数据
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        
        print("【存档系统】玩家 " .. player.Name .. " 成功解锁了第 " .. data.UnlockedLevel .. " 关！")
    end
end


-- ==========================================
-- [🌟 战斗植物数据接口]
-- ==========================================
function PlayerDataManager.AddCombatPlant(player, gridName, plantId, hp)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        -- [🌟 修改：不再存储 HP，只保存种下的植物 ID]
        data.CombatPlants[gridName] = { PlantId = plantId }
    end
end

function PlayerDataManager.UpdateCombatPlantHP(player, gridName, hp)
    -- [🌟 修改：废弃此功能。将函数置空以防止其他系统调用时报错]
    -- 现在植物每次加载/上线时，都会直接重新获得最大生命值
end

function PlayerDataManager.RemoveCombatPlant(player, gridName)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        data.CombatPlants[gridName] = nil
    end
end

function PlayerDataManager.UnlockSeed(player, seedId)
    local data = sessionData[player.UserId]
    if not data then return end
    
    if not data.UnlockedSeeds then data.UnlockedSeeds = {} end
    data.UnlockedSeeds[seedId] = true
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

function PlayerDataManager.ApplyBattleRewards(player, coins, seeds)
    local data = sessionData[player.UserId]
    
    if not data then return end
    
    PlayerDataManager.GiveCoins(player, coins)
    if seeds > 0 then
        PlayerDataManager.GiveSeed(player, "RandomSeed", seeds)
    end
    print("【存档系统】已为玩家 "..player.Name.." 核销战斗奖励：金币"..coins)
end

return PlayerDataManager
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
        UnlockedSeeds = { ["Peashooter"] = true }, 
        -- [🌟 新增：变异图鉴白名单] 默认拥有1级(普通)豌豆射手
        UnlockedMutations = { ["Peashooter"] = { [1] = true } } 
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
        savedData.Hotbar = {"Tool_Shovel"} 
        if not savedData.PlantedPlants then savedData.PlantedPlants = {} end 
        if not savedData.CombatPlants then savedData.CombatPlants = {} end 
        if type(savedData.UnlockedSeeds) ~= "table" then savedData.UnlockedSeeds = { ["Peashooter"] = true } end
        
        -- [🌟 老玩家补发图鉴数据结构]
        if type(savedData.UnlockedMutations) ~= "table" then savedData.UnlockedMutations = { ["Peashooter"] = { [1] = true } } end
        
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
    data.PlantedPlants[soilName] = { SeedId = seedId, PlantedTime = plantedTime }
end

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
    local data = sessionData[player.UserId]; if not data then return end
    local found = false
    for _, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then seedData.Quantity += amount; found = true; break end
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

-- ==========================================
-- [🌟 核心升级：给予植物时支持变异等级，并支持同变异独立堆叠]
-- ==========================================
function PlayerDataManager.GivePlant(player, plantId, amount, mutationLevel)
    local data = sessionData[player.UserId]; if not data then return end
    mutationLevel = mutationLevel or 1 -- 默认是 1(普通)
    
    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        -- 必须 ID 一样 且 变异等级 一样，才能堆叠在一起
        if plantData.ID == plantId and (plantData.Mutation or 1) == mutationLevel then 
            plantData.Quantity += amount; 
            found = true; 
            break 
        end
    end
    
    if not found then 
        table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount, Mutation = mutationLevel }) 
    end
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

-- ==========================================
-- [🌟 新增接口：解锁图鉴]
-- ==========================================
function PlayerDataManager.UnlockMutation(player, plantId, mutationLevel)
    local data = sessionData[player.UserId]
    if not data then return end
    
    if not data.UnlockedMutations then data.UnlockedMutations = {} end
    if not data.UnlockedMutations[plantId] then data.UnlockedMutations[plantId] = {} end
    
    data.UnlockedMutations[plantId][mutationLevel] = true
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

function PlayerDataManager.ConsumeCoins(player, amount)
    local data = sessionData[player.UserId]; if not data then return false end
    if data.Coins >= amount then
        data.Coins -= amount
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        return true 
    end
    return false 
end

function PlayerDataManager.GiveCoins(player, amount)
    local data = sessionData[player.UserId]; if not data then return end
    data.Coins += amount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

-- ==========================================
-- [🌟 战斗消耗：按变异等级精准扣除]
-- ==========================================
function PlayerDataManager.ConsumePlant(player, plantId, amount, mutationLevel)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Plants then return false end
    mutationLevel = mutationLevel or 1
    
    for i, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and (plantData.Mutation or 1) == mutationLevel then
            if plantData.Quantity >= amount then
                plantData.Quantity -= amount
                if plantData.Quantity <= 0 then table.remove(data.Inventory.Plants, i) end
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                return true
            end
            break
        end
    end
    return false
end

function PlayerDataManager.UnlockNextLevel(player, completedLevelId)
    local data = sessionData[player.UserId]
    if not data then return end
    if completedLevelId >= (data.UnlockedLevel or 1) then
        data.UnlockedLevel = completedLevelId + 1
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    end
end

function PlayerDataManager.AddCombatPlant(player, gridName, plantId, hp)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        data.CombatPlants[gridName] = { PlantId = plantId }
    end
end

function PlayerDataManager.UpdateCombatPlantHP(player, gridName, hp) end

function PlayerDataManager.RemoveCombatPlant(player, gridName)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then data.CombatPlants[gridName] = nil end
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
    if seeds > 0 then PlayerDataManager.GiveSeed(player, "RandomSeed", seeds) end
end

return PlayerDataManager
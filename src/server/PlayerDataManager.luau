-- src/server/PlayerDataManager.luau
local PlayerDataManager = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataStore = DataStoreService:GetDataStore("MyGameData_V12")
local sessionData = {}

local function GetDefaultData()
   return {
        Coins = 1000, Level = 1, UnlockedLevel = 1,
        TotalSun = 0, -- [🌟 新增：累计收集的阳光总量]
        UnlockedPlots = 4,
        Hotbar = {"Tool_Shovel"}, 
        Inventory = { Seeds = { { ID = "Peashooter", Quantity = 1 } }, Plants = {} },
        PlantedPlants = {}, CombatPlants = {},
        UnlockedSeeds = { ["Peashooter"] = true }, 
  
        UnlockedMutations = {} 
        
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
    local isLoaded = false
    task.spawn(function()
        local success, savedData = pcall(function() return PlayerDataStore:GetAsync(player.UserId) end)
        if not isLoaded then
            isLoaded = true
            if success and savedData then
                savedData.Hotbar = {"Tool_Shovel"} 
                if not savedData.PlantedPlants then savedData.PlantedPlants = {} end 
                if not savedData.CombatPlants then savedData.CombatPlants = {} end 
                if type(savedData.UnlockedSeeds) ~= "table" then savedData.UnlockedSeeds = { ["Peashooter"] = true } end
                if type(savedData.UnlockedMutations) ~= "table" then savedData.UnlockedMutations = {} end
                savedData.Coins = 9999999
                savedData.TotalSun =9999999
                savedData.UnlockedLevel = 99
                sessionData[player.UserId] = savedData
                print("✅ [数据系统] 玩家 " .. player.Name .. " 数据拉取成功！")
            else
                sessionData[player.UserId] = GetDefaultData()
                print("🆕 [数据系统] 玩家 " .. player.Name .. " 无存档，发放初始数据。")
            end
        end
    end)
    task.delay(5, function()
        if not isLoaded then
            isLoaded = true
            warn("⚠️ [数据系统] Roblox数据服务请求超时卡死！已强制跳过并下发初始数据，保护游戏进程不崩溃！")
            sessionData[player.UserId] = GetDefaultData()
        end
    end)
end

local function onPlayerRemoving(player)
    local dataToSave = sessionData[player.UserId]
    if dataToSave then
        sessionData[player.UserId] = nil 
        task.spawn(function() saveWithRetry(player.UserId, dataToSave) end)
    end
end

function PlayerDataManager.Init()
    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function() onPlayerAdded(player) end)
    end
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

    if not ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE") then
        local animRE = Instance.new("RemoteEvent")
        animRE.Name = "PlayUnlockAnimRE"
        animRE.Parent = ReplicatedStorage
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
                if seedData.Quantity <= 0 then 
                    table.remove(data.Inventory.Seeds, i) 
                    
                    -- [🌟 核心修复：种子耗尽时，强行从快捷栏数据中挖掉它的占位！]
                    if data.Hotbar then
                        for j = #data.Hotbar, 1, -1 do
                            local parts = string.split(data.Hotbar[j], "_")
                            if parts[1] == "Seed" and parts[2] == seedId then
                                table.remove(data.Hotbar, j)
                            end
                        end
                    end
                    
                end
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                return true
            end
            break
        end
    end
    return false
end

function PlayerDataManager.GivePlant(player, plantId, amount, mutationLevel)
    local data = sessionData[player.UserId];
    if not data then return end
    mutationLevel = mutationLevel or 1 
    
    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and (plantData.Mutation or 1) == mutationLevel then 
            plantData.Quantity += amount;
            found = true; break 
        end
    end
    
    if not found then 
        table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount, Mutation = mutationLevel }) 
    end
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

function PlayerDataManager.UnlockMutation(player, plantId, mutationLevel)
    local data = sessionData[player.UserId]
    if not data then return end
    
    if not data.UnlockedMutations then data.UnlockedMutations = {} end
    if not data.UnlockedMutations[plantId] then data.UnlockedMutations[plantId] = {} end
    
    local isFirstTimeUnlock = not data.UnlockedMutations[plantId][mutationLevel]
    
    data.UnlockedMutations[plantId][mutationLevel] = true
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    if isFirstTimeUnlock then
        print("【服务端】首次解锁检测成功，正在给客户端发送动画信号：", plantId, "等级", mutationLevel)
        local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
        if playUnlockAnimRE then 
            playUnlockAnimRE:FireClient(player, plantId, mutationLevel) 
        end
    end
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

function PlayerDataManager.ConsumePlant(player, plantId, amount, mutationLevel)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Plants then return false end
    mutationLevel = mutationLevel or 1
    
    for i, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and (plantData.Mutation or 1) == mutationLevel then
            if plantData.Quantity >= amount then
                plantData.Quantity -= amount
                if plantData.Quantity <= 0 then 
                    table.remove(data.Inventory.Plants, i) 
                    
                    -- [🌟 核心修复：植物耗尽时，强行从快捷栏数据中挖掉它的占位！]
                    if data.Hotbar then
                        for j = #data.Hotbar, 1, -1 do
                            local parts = string.split(data.Hotbar[j], "_")
                            local mLevel = tonumber(parts[3]) or 1
                            if parts[1] == "Plant" and parts[2] == plantId and mLevel == mutationLevel then
                                table.remove(data.Hotbar, j)
                            end
                        end
                    end
                    
                end
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

function PlayerDataManager.AddCombatPlant(player, gridName, plantId, hp, mutationLevel)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        data.CombatPlants[gridName] = { PlantId = plantId, Mutation = mutationLevel or 1 }
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


-- [新增：更新阳光的函数]
function PlayerDataManager.AddTotalSun(player, amount)
    local data = sessionData[player.UserId]
    if data then
        data.TotalSun = (data.TotalSun or 0) + amount
        -- 同步给客户端，以便更新 UI 和向日葵大小
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    end
end


function PlayerDataManager.CollectAllSun(player)
    local data = sessionData[player.UserId]
    if data and data.TotalSun and data.TotalSun > 0 then
        local amount = data.TotalSun
        data.Coins += amount -- 全部转为金币
        data.TotalSun = 0    -- 阳光重置为 0，这会自动让向日葵体型回到 1
        
        -- 同步数据给客户端更新 UI 和向日葵大小
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        
        return amount
    end
    return 0
end

-- [🌟 新增：获取和增加玩家土地数量]
function PlayerDataManager.GetUnlockedPlots(player)
    local data = sessionData[player.UserId]
    return data and data.UnlockedPlots or 4
end

function PlayerDataManager.IncrementUnlockedPlots(player)
    local data = sessionData[player.UserId]
    if data then
        data.UnlockedPlots = (data.UnlockedPlots or 4) + 1
        -- 同步最新数据给客户端
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    end
end
return PlayerDataManager
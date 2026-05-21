-- src/server/PlayerDataManager.luau
local PlayerDataManager = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local PlayerDataStore = DataStoreService:GetDataStore("MyGameData_V18")
local sessionData = {}

local analyticsRE = ReplicatedStorage:FindFirstChild("AnalyticsRE") or Instance.new("RemoteEvent")
analyticsRE.Name = "AnalyticsRE"
analyticsRE.Parent = ReplicatedStorage

analyticsRE.OnServerEvent:Connect(function(player, eventType, eventName, extraData)
    print(string.format("[Analytics] Player: %s | Type: %s | Event: %s", player.Name, tostring(eventType), tostring(eventName)))
    if eventType == "Custom" then
        local logValue = 1
        if type(extraData) == "number" then logValue = extraData end
        AnalyticsService:LogCustomEvent(player, eventName, logValue)
    elseif eventType == "Funnel" then
        if type(extraData) == "table" then
            local sessionId = extraData.SessionId
            local stepIndex = extraData.StepIndex or 1
            AnalyticsService:LogFunnelStepEvent(player, eventName, sessionId, stepIndex, extraData.StepName)
        end
    end
end)

local function GetDefaultData()
   return {
        Coins = 1000, Level = 1, UnlockedLevel = 1,
        TotalSun = 0,
        UnlockedPlots = 4,
        SignInDays = 0,       
        LastSignInTime = 0,   
        Hotbar = {"Tool_Shovel","System_Backpack", "Tool_WeaponBlock"},  
        Inventory = { Seeds = { { ID = "Peashooter", Quantity = 1 } }, Plants = {} },
        PlantedPlants = {}, CombatPlants = {},
        UnlockedSeeds = { ["Peashooter"] = true }, 
        TutorialStep = 0,
        UnlockedMutations = {},
        ClaimedAchieve = {},
        RollTickets = {0, 0},
        
        -- 🌟【新增】：新手限时礼包字段
        NewbieGiftStartTime = 0,     -- 记录触发礼包的 Unix 时间戳
        NewbieGiftPurchased = false  -- 记录是否已经购买
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
            if success and savedData  then
                savedData.Hotbar = {"Tool_Shovel", "System_Backpack", "Tool_WeaponBlock"}
                if not savedData.PlantedPlants then savedData.PlantedPlants = {} end 
                if not savedData.CombatPlants then savedData.CombatPlants = {} end 
                if type(savedData.UnlockedSeeds) ~= "table" then savedData.UnlockedSeeds = { ["Peashooter"] = true } end
                if type(savedData.UnlockedMutations) ~= "table" then savedData.UnlockedMutations = {} end
                if type(savedData.ClaimedAchieve) ~= "table" then savedData.ClaimedAchieve = {} end
                if type(savedData.NewbieGiftStartTime) ~= "number" then savedData.NewbieGiftStartTime = 0 end
                if type(savedData.NewbieGiftPurchased) ~= "boolean" then savedData.NewbieGiftPurchased = false end
                if type(savedData.RollTickets) ~= "table" then savedData.RollTickets = {0, 0} end -- 🌟 【兼容老玩家数据】
                
                sessionData[player.UserId] = savedData
                print("✅ [数据系统] 玩家 " .. player.Name .. " 数据拉取成功！")
                
                if (savedData.TutorialStep or 0) == 0 then
                    AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 1, "Step_1_Enter_Game")
                end
            else
                sessionData[player.UserId] = GetDefaultData()
                print("🆕 [数据系统] 玩家 " .. player.Name .. " 无存档，发放初始数据。")
                AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 1, "Step_1_Enter_Game")
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
        if (dataToSave.TutorialStep or 0) < 9 then
            return
        end
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
            if dataToSave then 
                if (dataToSave.TutorialStep or 0) >= 9 then
                    task.spawn(function() saveWithRetry(player.UserId, dataToSave) end) 
                end
            end
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
  
    if not ReplicatedStorage:FindFirstChild("UpdateTutorialRE") then
        local tutorialRE = Instance.new("RemoteEvent")
        tutorialRE.Name = "UpdateTutorialRE"
        tutorialRE.Parent = ReplicatedStorage
        tutorialRE.OnServerEvent:Connect(function(plr, step)
            local data = sessionData[plr.UserId]
            if data then
                if step > (data.TutorialStep or 0) then
                    data.TutorialStep = step
                end
            end
        end)
    end

    if not ReplicatedStorage:FindFirstChild("PlayObtainEffectRE") then
        local effectRE = Instance.new("RemoteEvent")
        effectRE.Name = "PlayObtainEffectRE"
        effectRE.Parent = ReplicatedStorage
    end
    
    -- ==========================================
    -- [🌟 新增：处理服务端抽奖扣除与发奖逻辑]
    -- ==========================================
    local performRollRF = ReplicatedStorage:FindFirstChild("PerformRollRF")
    if not performRollRF then
        performRollRF = Instance.new("RemoteFunction")
        performRollRF.Name = "PerformRollRF"
        performRollRF.Parent = ReplicatedStorage
    end
    
    performRollRF.OnServerInvoke = function(player, tabIndex)
        local data = sessionData[player.UserId]
        if not data then return false, "数据仍在加载中..." end
        if not data.RollTickets then data.RollTickets = {0, 0} end
        
        local tickets = data.RollTickets[tabIndex] or 0
        if tickets <= 0 then return false, "抽奖次数不足！" end
        
        -- 1. 扣除对应池子的次数
        data.RollTickets[tabIndex] = tickets - 1
        
        -- 2. 获取真正的随机奖励
        local RollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RollConfig"))
        local finalPrize = RollConfig.GetRandomPrize(tabIndex)
        
        -- 3. 发放种子奖励 (传入 suppressEffect = true，抑制立即弹出提示，让客户端在动画播完后再自己弹)
        PlayerDataManager.GiveSeed(player, finalPrize, 1, true)
        
        -- 4. 同步最新数据（更新 UI 上的次数和红点）
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        
        -- 5. 将结果返回给客户端用于播放转盘动画
        return true, finalPrize
    end
    local startNewbieGiftRF = ReplicatedStorage:FindFirstChild("StartNewbieGiftRF")
    if not startNewbieGiftRF then
        startNewbieGiftRF = Instance.new("RemoteFunction")
        startNewbieGiftRF.Name = "StartNewbieGiftRF"
        startNewbieGiftRF.Parent = ReplicatedStorage
    end
    startNewbieGiftRF.OnServerInvoke = function(player)
        local data = sessionData[player.UserId]
        -- 如果玩家存在，且计时未开始，则记录当前真实服务器时间
        if data and data.NewbieGiftStartTime == 0 then
            data.NewbieGiftStartTime = os.time()
            
            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
            
            return true, data.NewbieGiftStartTime
        end
        return false, data and data.NewbieGiftStartTime or 0
    end
end

function PlayerDataManager.GetPlayerData(player) return sessionData[player.UserId] end

function PlayerDataManager.ClearTransientPlotData(player)
    local data = sessionData[player.UserId]
    if not data then return end
    data.PlantedPlants = {}
    data.CombatPlants = {}
end

function PlayerDataManager.UpdatePlantedPlant(player, soilName, seedId, plantedTime)
    local data = sessionData[player.UserId]
    if not data then return end
    
    local existingPlant = data.PlantedPlants[soilName]
    local mutationLevel = existingPlant and existingPlant.Mutation
    
    if not mutationLevel then
        mutationLevel = 1
        if ItemConfig.MutationProb then
            local totalWeight = 0
            for _, weight in pairs(ItemConfig.MutationProb) do totalWeight += weight end
            local roll = math.random() * totalWeight
            local currentWeight = 0
            for level, weight in pairs(ItemConfig.MutationProb) do
                currentWeight += weight
                if roll <= currentWeight then
                    mutationLevel = level
                    break
                end
            end
        end
    end

    data.PlantedPlants[soilName] = { 
        SeedId = seedId, 
        PlantedTime = plantedTime, 
        Mutation = mutationLevel 
    }
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

-- 👇 增加了一个可选参数 suppressEffect 
function PlayerDataManager.GiveSeed(player, seedId, amount, suppressEffect)
    local data = sessionData[player.UserId]
    if not data then return end
 
    local found = false
    for _, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then 
            seedData.Quantity += amount
            found = true
            break 
        end
    end
    
    if not found then 
        table.insert(data.Inventory.Seeds, { ID = seedId, Quantity = amount }) 
    end

    if data.Hotbar then
        local itemKey = "Seed_" .. seedId
        local alreadyEquipped = false
        for _, v in ipairs(data.Hotbar) do
            if v == itemKey then
                alreadyEquipped = true
                break
            end
        end
        if not alreadyEquipped and #data.Hotbar < 9 then
            table.insert(data.Hotbar, itemKey)
        end
    end

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    
    -- 👇 如果被抑制了，就不在这里触发特效（比如抽奖需要等转盘转完再触发）
    if not suppressEffect then
        local effectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
        if effectRE then
            local itemDetail = ItemConfig.Seeds[seedId]
            local itemName = itemDetail and itemDetail.Name or seedId
            effectRE:FireClient(player, "Congratulations, you obtained " .. amount .. "x " .. itemName)
        end
    end
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
   local data = sessionData[player.UserId]
    if not data then return end
    mutationLevel = mutationLevel or 1 
    
    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and (plantData.Mutation or 1) == mutationLevel then 
            plantData.Quantity += amount
            found = true
            break 
        end
    end
    
    if not found then 
        table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount, Mutation = mutationLevel }) 
    end
    
    if data.Hotbar then
        local itemKey = "Plant_" .. plantId .. "_" .. mutationLevel
        local alreadyEquipped = false
        for _, v in ipairs(data.Hotbar) do
            if v == itemKey then
                alreadyEquipped = true
                break
            end
        end
        if not alreadyEquipped and #data.Hotbar < 9 then
            table.insert(data.Hotbar, itemKey)
        end
    end

    PlayerDataManager.UnlockMutation(player, plantId, mutationLevel)
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

function PlayerDataManager.AddTotalSun(player, amount)
    local data = sessionData[player.UserId]
    if data then
        data.TotalSun = (data.TotalSun or 0) + amount
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    end
end

function PlayerDataManager.CollectAllSun(player)
    local data = sessionData[player.UserId]
    if data and data.TotalSun and data.TotalSun > 0 then
        local amount = data.TotalSun
        data.Coins += amount 
        data.TotalSun = 0    
        
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        
        AnalyticsService:LogEconomyEvent(
            player, 
            Enum.AnalyticsEconomyFlowType.Source, 
            "Coins", 
            amount, 
            data.Coins,
            Enum.AnalyticsEconomyTransactionType.Gameplay.Name, 
            "Sunflower_Collect" 
        )
        return amount
    end
    return 0
end

function PlayerDataManager.GetUnlockedPlots(player)
    local data = sessionData[player.UserId]
    return data and data.UnlockedPlots or 4
end

function PlayerDataManager.IncrementUnlockedPlots(player)
    local data = sessionData[player.UserId]
    if data then
        data.UnlockedPlots = (data.UnlockedPlots or 4) + 1
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    end
end

function PlayerDataManager.GrantSignInReward(player, day)
    if day == 1 then PlayerDataManager.GiveCoins(player, 200)
    elseif day == 2 then PlayerDataManager.GiveCoins(player, 2000)
    elseif day == 3 then PlayerDataManager.GiveSeed(player, "SnowPea", 1)
    elseif day == 4 then PlayerDataManager.AddTotalSun(player, 10000)
    elseif day == 5 then PlayerDataManager.GiveSeed(player, "SnowPea", 2)
    elseif day == 6 then PlayerDataManager.AddTotalSun(player, 100000)
    elseif day == 7 then PlayerDataManager.GiveSeed(player, "SnowPea", 3)
    end
end

local claimAllBattleRF = Instance.new("RemoteFunction")
claimAllBattleRF.Name = "ClaimAllBattleRF"
claimAllBattleRF.Parent = ReplicatedStorage

claimAllBattleRF.OnServerInvoke = function(player)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then return false, "数据加载中..." end
    
    local currentDays = data.SignInDays or 0
    if currentDays >= 7 then return false, "已经全部领取过了" end
    
    for day = currentDays + 1, 7 do
        PlayerDataManager.GrantSignInReward(player, day)
    end
    
    data.SignInDays = 7
    data.LastSignInTime = os.time()
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    
    return true, "一键领取成功！"
end

local claimSignInRF = ReplicatedStorage:FindFirstChild("ClaimSignInRF")
if not claimSignInRF then
    claimSignInRF = Instance.new("RemoteFunction")
    claimSignInRF.Name = "ClaimSignInRF"
    claimSignInRF.Parent = ReplicatedStorage
end

claimSignInRF.OnServerInvoke = function(player)
    local data = sessionData[player.UserId]
    if not data then return false end

    local signInDays = data.SignInDays or 0
    if signInDays >= 7 then return false end 

    local lastTime = data.LastSignInTime or 0
    local isClaimedToday = false
    
    if lastTime > 0 then
        local lastDate = os.date("*t", lastTime)
        local currDate = os.date("*t", os.time())
        isClaimedToday = (lastDate.year == currDate.year and lastDate.month == currDate.month and lastDate.day == currDate.day)
    end

    if isClaimedToday then return false end 

    data.SignInDays = signInDays + 1
    data.LastSignInTime = os.time()
    
    PlayerDataManager.GrantSignInReward(player, data.SignInDays)

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    return true
end

local claimLevelRewardRF = ReplicatedStorage:FindFirstChild("ClaimLevelRewardRF")
if not claimLevelRewardRF then
    claimLevelRewardRF = Instance.new("RemoteFunction")
    claimLevelRewardRF.Name = "ClaimLevelRewardRF"
    claimLevelRewardRF.Parent = ReplicatedStorage
end

claimLevelRewardRF.OnServerInvoke = function(player, targetLevel)
    local data = sessionData[player.UserId]
    if not data then return false, "数据仍在加载中..." end

    if not data.ClaimedAchieve then data.ClaimedAchieve = {} end

    local currentUnlocked = data.UnlockedLevel or 1
    if currentUnlocked <= targetLevel then
        return false, "关卡进度不足，无法领取！"
    end

    if data.ClaimedAchieve[tostring(targetLevel)] then
        return false, "您已经领取过该奖励了！"
    end

    local LevelRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardConfig"))
    local rewardData = LevelRewardConfig[targetLevel]
    if not rewardData then return false, "配置不存在" end

    local msg = "Reward Claimed: "
    if rewardData.Seed then
        PlayerDataManager.GiveSeed(player, rewardData.Seed, rewardData.SeedCount or 1)
        msg = msg .. (rewardData.SeedCount or 1) .. "x " .. rewardData.Seed .. " "
    end
    if rewardData.Sun then
        PlayerDataManager.AddTotalSun(player, rewardData.Sun)
        msg = msg .. rewardData.Sun .. " Sun"
    end

    data.ClaimedAchieve[tostring(targetLevel)] = true

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    return true, msg
end

-- [💡 测试用函数]：给玩家添加抽奖次数，方便你测试
function PlayerDataManager.AddRollTicket(player, tabIndex, amount)
    local data = sessionData[player.UserId]
    if not data then return end
    if not data.RollTickets then data.RollTickets = {0, 0} end
    data.RollTickets[tabIndex] = (data.RollTickets[tabIndex] or 0) + amount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
end

return PlayerDataManager
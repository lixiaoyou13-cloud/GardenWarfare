-- src/server/PlayerDataManager.luau
local PlayerDataManager = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
-- 👇 新增：引入签到奖励配置
local SignInRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SignInRewardConfig"))

local PlayerDataStore = DataStoreService:GetDataStore("MyGameData_V18")
local sessionData = {}
local X2_SUN_GAME_PASS_ID = 1856661235
local x2SunOwnershipCache = {}
local x2SunOwnershipCacheTime = {}
local X2_SUN_CACHE_TTL = 60
local ROLL_TAB1_CASH_COST = 200000
local onlineRollTimerStarted = false

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
        
        -- 👇 新增：签到重置标记（新玩家默认已经重置）
        SignInReset_V1 = true,
        
        Hotbar = {"Tool_Shovel","System_Backpack", "Tool_WeaponBlock"},  
        Inventory = { Seeds = { { ID = "Peashooter", Quantity = 1 } }, Plants = {} },
        PlantedPlants = {}, CombatPlants = {},
        UnlockedSeeds = { ["Peashooter"] = true }, 
        TutorialStep = 0,
        UnlockedMutations = {},
        ClaimedAchieve = {},
        RollTickets = {0, 0},
        
        NewbieGiftStartTime = 0,     
        NewbieGiftPurchased = false, 
        OnlineRollTimer = 300 
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

local function startGlobalOnlineRollTimer()
    if onlineRollTimerStarted then return end
    onlineRollTimerStarted = true

    task.spawn(function()
        while true do
            task.wait(1)

            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            for _, plr in ipairs(Players:GetPlayers()) do
                local pData = sessionData[plr.UserId]
                if pData then
                    pData.OnlineRollTimer = (pData.OnlineRollTimer or 300) - 1

                    if pData.OnlineRollTimer <= 0 then
                        pData.OnlineRollTimer = 300
                        pData.RollTickets = pData.RollTickets or {0, 0}
                        pData.RollTickets[1] = (pData.RollTickets[1] or 0) + 1

                        if updateInventoryRE then
                            updateInventoryRE:FireClient(plr, pData)
                        end
                    end
                end
            end
        end
    end)
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
                if type(savedData.RollTickets) ~= "table" then savedData.RollTickets = {0, 0} end 
                
                -- 🌟 兼容老玩家数据
                if type(savedData.OnlineRollTimer) ~= "number" then savedData.OnlineRollTimer = 300 end
                -- ====================================================
                -- 👇 新增：强制重置所有老玩家的七日签到进度（只触发一次）
                -- ====================================================
                if not savedData.SignInReset_V1 then
                    savedData.SignInDays = 0       -- 签到天数归零
                    savedData.LastSignInTime = 0   -- 签到时间归零
                    savedData.SignInReset_V1 = true -- 打上标记，防止下次登录再次被重置
                    print("🔄 [数据系统] 玩家 " .. player.Name .. " 的七日签到已强制重置！")
                end
                -- ====================================================

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
            warn("⚠️ [数据系统] Roblox数据请求超时！已下发初始数据，保护游戏进程不崩溃！")
            sessionData[player.UserId] = GetDefaultData()
        end
    end)
end

local function onPlayerRemoving(player)
    local dataToSave = sessionData[player.UserId]
    if dataToSave then
        sessionData[player.UserId] = nil 
        x2SunOwnershipCache[player.UserId] = nil
        x2SunOwnershipCacheTime[player.UserId] = nil
        if (dataToSave.TutorialStep or 0) < 8 then -- 🟢 改成 8
            return
        end
        task.spawn(function() saveWithRetry(player.UserId, dataToSave) end)
    end
end

function PlayerDataManager.Init()
    startGlobalOnlineRollTimer()

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function() onPlayerAdded(player) end)
    end
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
        if passId == X2_SUN_GAME_PASS_ID then
            if wasPurchased then
                x2SunOwnershipCache[player.UserId] = true
                x2SunOwnershipCacheTime[player.UserId] = os.clock()
            else
                x2SunOwnershipCache[player.UserId] = nil
                x2SunOwnershipCacheTime[player.UserId] = nil
            end
        end
    end)

    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do
            local dataToSave = sessionData[player.UserId]
            if dataToSave then 
                if (dataToSave.TutorialStep or 0) >= 8 then -- 8
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
        tabIndex = tonumber(tabIndex) or 1
        if tabIndex ~= 1 and tabIndex ~= 2 then
            return false, "Invalid roll tab"
        end

        local data = sessionData[player.UserId]
        if not data then return false, "数据仍在加载中..." end
        if not data.RollTickets then data.RollTickets = {0, 0} end
        
        -- 兼容旧数据/异常数据里 RollTickets 使用字符串键的情况，避免误判为 0 后先扣阳光。
        local tickets = tonumber(data.RollTickets[tabIndex]) or tonumber(data.RollTickets[tostring(tabIndex)]) or 0
        data.RollTickets[tabIndex] = tickets
        data.RollTickets[tostring(tabIndex)] = nil

        if tickets > 0 then
            -- 1. 永远优先扣除对应池子的免费次数；只有没有免费次数时才会进入阳光扣费分支。
            data.RollTickets[tabIndex] = tickets - 1
        elseif tabIndex == 1 then
            -- 第 1 页没有免费次数时，允许消耗 200K 阳光继续抽奖
            if (data.Coins or 0) < ROLL_TAB1_CASH_COST then
                return false, "Not enough Sun!"
            end
            data.Coins -= ROLL_TAB1_CASH_COST
        else
            return false, "抽奖次数不足！"
        end
        
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

function PlayerDataManager.WaitForPlayerData(player, timeout)
    timeout = timeout or 10
    local startTime = os.clock()

    while player and player.Parent do
        local data = sessionData[player.UserId]
        if data then
            return data
        end

        if os.clock() - startTime >= timeout then
            break
        end

        task.wait(0.1)
    end

    return sessionData[player.UserId]
end

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
    local finalAmount = amount
    if PlayerDataManager.IsX2SunActive(player) then
        finalAmount = amount * 2
    end
    data.Coins += finalAmount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    return finalAmount
end

function PlayerDataManager.GiveCoinsRaw(player, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    data.Coins += amount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    return amount
end

function PlayerDataManager.IsX2SunActive(player)
    if not player then return false end
    local userId = player.UserId
    local cachedValue = x2SunOwnershipCache[userId]
    local cachedAt = x2SunOwnershipCacheTime[userId]
    if cachedValue ~= nil and (cachedValue == true or (cachedAt and os.clock() - cachedAt < X2_SUN_CACHE_TTL)) then
        return cachedValue
    end

    local ownsPass = false
    local success, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, X2_SUN_GAME_PASS_ID)
    end)
    if success then
        ownsPass = result == true
        x2SunOwnershipCache[userId] = ownsPass
        x2SunOwnershipCacheTime[userId] = os.clock()
    else
        warn("[PlayerDataManager] Failed to check X2Sun game pass ownership for " .. player.Name .. ": " .. tostring(result))
    end

    return ownsPass
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
    
    -- 只有当玩家打通了他们当前的最高关卡时，才需要升级和更新 UI
    if completedLevelId >= (data.UnlockedLevel or 1) then
        data.UnlockedLevel = completedLevelId + 1
        
        -- 🌟 【新增：实时更新玩家头顶的最高关卡 UI】
        local character = player.Character
        if character then
            local head = character:FindFirstChild("Head")
            if head then
                local titleGui = head:FindFirstChild("PlayerTitleGui")
                if titleGui then
                    local textLabel = titleGui:FindFirstChildWhichIsA("TextLabel")
                    if textLabel then
                        -- 直接显示当前解锁层数
                        local maxCleared = data.UnlockedLevel or 1
                        textLabel.Text = "MAX  " .. tostring(maxCleared)
                    end
                end
            end
        end

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
        local finalAmount = amount
        if PlayerDataManager.IsX2SunActive(player) then
            finalAmount = amount * 2
        end
        data.Coins += finalAmount 
        data.TotalSun = 0    
        
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        
        AnalyticsService:LogEconomyEvent(
            player, 
            Enum.AnalyticsEconomyFlowType.Source, 
            "Coins", 
            finalAmount, 
            data.Coins,
            Enum.AnalyticsEconomyTransactionType.Gameplay.Name, 
            "Sunflower_Collect" 
        )
        return finalAmount
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
    local rewardData = SignInRewardConfig[day]
    if not rewardData then return end
    
    -- 根据配置的 RewardType 发放对应的奖励
    if rewardData.RewardType == "Coins" then
        PlayerDataManager.GiveCoins(player, rewardData.Amount)
    elseif rewardData.RewardType == "Seed" then
        PlayerDataManager.GiveSeed(player, rewardData.ItemId, rewardData.Amount)
    elseif rewardData.RewardType == "Sun" then
        PlayerDataManager.AddTotalSun(player, rewardData.Amount)
    end
end

local claimAllBattleRF = Instance.new("RemoteFunction")
claimAllBattleRF.Name = "ClaimAllBattleRF"
claimAllBattleRF.Parent = ReplicatedStorage

claimAllBattleRF.OnServerInvoke = function(player)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then return false, "Loading data..." end
    
    local currentDays = data.SignInDays or 0
    if currentDays >= 7 then return false, "Already claimed all" end
    
    for day = currentDays + 1, 7 do
        PlayerDataManager.GrantSignInReward(player, day)
    end
    
    data.SignInDays = 7
    data.LastSignInTime = os.time()
    
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    
    return true, "Claim successful with one click!"
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
    if not data then return false, "Data still loading..." end

    if not data.ClaimedAchieve then data.ClaimedAchieve = {} end

    local currentUnlocked = data.UnlockedLevel or 1
    if currentUnlocked <= targetLevel then
        return false, "Progress not enough to claim!"
    end

    if data.ClaimedAchieve[tostring(targetLevel)] then
        return false, "You have already claimed this reward！"
    end

    local LevelRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardConfig"))
    local rewardData = LevelRewardConfig[targetLevel]
    if not rewardData then return false, "Configuration does not exist" end

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


return PlayerDataManager

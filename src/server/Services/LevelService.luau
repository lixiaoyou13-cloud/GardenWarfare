-- src/server/Services/LevelService.luau
local LevelService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotService = require(script.Parent.PlotService)
local ZombieService = require(script.Parent.ZombieService)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local function fireTip(player, message)
    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE then
        showTipRE:FireClient(player, message)
    end
end

local function isZombossBossFightActive()
    local ok, service = pcall(function()
        return require(script.Parent.ZombossBossFightService)
    end)

    if not ok or not service or type(service.IsActive) ~= "function" then
        return false
    end

    return service.IsActive()
end

local function getMaxSelectableLevel(player)
    return math.max(1, PlayerDataManager.GetRankingSeasonNextLevel(player))
end

local function normalizeLevelId(levelId)
    return math.max(1, math.floor(tonumber(levelId) or 1))
end

local function getLevelSelectCost(levelId)
    levelId = normalizeLevelId(levelId)
    return math.max(1, math.floor((100 + levelId * 20) / 20))
end

local function cancelCurrentBattle(player, plot)
    plot:SetAttribute("BattleToken", (plot:GetAttribute("BattleToken") or 0) + 1)
    plot:SetAttribute("IsGameOver", true)
    plot:SetAttribute("IsLevelActive", false)
    plot:SetAttribute("ActiveZombies", 0)
    plot:SetAttribute("TotalZombies", 0)
    plot:SetAttribute("ZombiesDefeated", 0)

    ZombieService.CleanupPlayerBattle(player)
end



local function startLevel(player, plot, levelId, shouldCancelCurrentBattle)
    if shouldCancelCurrentBattle then
        cancelCurrentBattle(player, plot)
        task.wait(0.1)
    end

    -- Clear any retreat/game-over state left by the previous battle before starting.
    plot:SetAttribute("IsGameOver", false)

    local CombatService = require(script.Parent.CombatService)
    ZombieService.RestorePlotPlants(plot, player)
    CombatService.ReloadSavedPlants(player)

    print("[LevelService] Player " .. player.Name .. " battle refreshed: Level " .. levelId .. "")
    ZombieService.StartLevel(plot, levelId, player)
end

local function startDefaultLevel(player)
    if isZombossBossFightActive() then
        return false, "Defeat Dr. Zomboss first."
    end

    local plot = PlotService.GetPlayerPlot(player)
    if not plot then
        return false, "Battle plot is not ready."
    end

    if plot:GetAttribute("IsLevelActive") then
        return false
    end

    local levelId = getMaxSelectableLevel(player)
    startLevel(player, plot, levelId, false)
    return true, nil, levelId, 0
end

local function startSelectedLevel(player, targetLevel)
    if isZombossBossFightActive() then
        return false, "Defeat Dr. Zomboss first."
    end

    local requestedLevel = tonumber(targetLevel)
    if not requestedLevel then
        return false, "Please select a level."
    end

    local plot = PlotService.GetPlayerPlot(player)
    if not plot then
        return false, "Battle plot is not ready."
    end

    requestedLevel = normalizeLevelId(requestedLevel)
    local maxLevel = getMaxSelectableLevel(player)
    local levelId = math.min(requestedLevel, maxLevel)
    local cost = getLevelSelectCost(levelId)

    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Player data is still loading.", levelId, cost
    end

    if (tonumber(data.Coins) or 0) < cost then
        return false, "Not enough Sunshine.", levelId, cost
    end

    if not PlayerDataManager.ConsumeCoins(player, cost) then
        return false, "Not enough Sunshine.", levelId, cost
    end

    if requestedLevel > maxLevel then
        fireTip(player, "Your current season max level is Level " .. tostring(maxLevel) .. ". Starting Level " .. tostring(maxLevel) .. ".")
    end

    task.spawn(function()
        local ok, err = pcall(function()
            startLevel(player, plot, levelId, true)
        end)

        if not ok then
            PlayerDataManager.GiveCoinsRaw(player, cost)
            warn("[LevelService] Failed to start selected level for " .. player.Name .. ": " .. tostring(err))
            fireTip(player, "Unable to start level. Please try again.")
        end
    end)

    return true, nil, levelId, cost
end

function LevelService.Init()
    local startBattleRE = ReplicatedStorage:FindFirstChild("StartBattleRE") or Instance.new("RemoteEvent")
    startBattleRE.Name = "StartBattleRE"
    startBattleRE.Parent = ReplicatedStorage

    local endBattleRE = ReplicatedStorage:FindFirstChild("EndBattleRE") or Instance.new("RemoteEvent")
    endBattleRE.Name = "EndBattleRE"
    endBattleRE.Parent = ReplicatedStorage

    local startSelectedLevelRF = ReplicatedStorage:FindFirstChild("StartSelectedLevelRF") or Instance.new("RemoteFunction")
    startSelectedLevelRF.Name = "StartSelectedLevelRF"
    startSelectedLevelRF.Parent = ReplicatedStorage

    local syncBattleUI_RE = ReplicatedStorage:FindFirstChild("SyncBattleUI_RE") or Instance.new("RemoteEvent")
    syncBattleUI_RE.Name = "SyncBattleUI_RE"
    syncBattleUI_RE.Parent = ReplicatedStorage

    startSelectedLevelRF.OnServerInvoke = function(player, targetLevel)
        return startSelectedLevel(player, targetLevel)
    end

    startBattleRE.OnServerEvent:Connect(function(player, targetLevel)
        local success, message
        if targetLevel == nil then
            success, message = startDefaultLevel(player)
        else
            success, message = startSelectedLevel(player, targetLevel)
        end

        if not success and message then
            fireTip(player, message)
        end
    end)

    endBattleRE.OnServerEvent:Connect(function(player)
        if isZombossBossFightActive() then
            fireTip(player, "Defeat Dr. Zomboss first.")
            return
        end

        local plot = PlotService.GetPlayerPlot(player)

        -- 如果没在战斗中，直接无视
        if not plot or not plot:GetAttribute("IsLevelActive") then return end

        print("[LevelService] Player " .. player.Name .. " chose manual retreat")

        -- 1. 标签记游戏
        plot:SetAttribute("IsGameOver", true)

        -- 2. 强力清理专属场地的僵尸，加上 OwnerId 判断
        for _, obj in pairs(Workspace:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("IsZombie") and obj:GetAttribute("OwnerId") == player.UserId then
                obj:Destroy()
            end
        end

        -- 第二步精确落位
        -- 引入 CombatService (动态引入防止循环依赖)
        local CombatService = require(script.Parent.CombatService)

        -- 调用我们刚才写好的“超级恢复函数”
        -- 这一行代码会把隐身的、残血的、被炸掉的植物彻底满血复原
        CombatService.ReloadSavedPlants(player)

        -- 3. 强制触发结算
        ZombieService.FinalSettlement(player, plot, false)
    end)

    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            local plot = nil
            while player.Parent do
                plot = PlotService.GetPlayerPlot(player)
                if plot then break end
                task.wait(1)
            end

            if plot then
                plot:GetAttributeChangedSignal("IsLevelActive"):Connect(function()
                    if not plot:GetAttribute("IsLevelActive") then
                        syncBattleUI_RE:FireClient(player, false, 1, 0, 0)
                    end
                end)
            end
        end)
    end)
end

return LevelService

-- src/server/Services/LevelService.luau
local LevelService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")

local PlotService = require(script.Parent.PlotService)
local ZombieService = require(script.Parent.ZombieService)



function LevelService.Init()
    local startBattleRE = ReplicatedStorage:FindFirstChild("StartBattleRE") or Instance.new("RemoteEvent")
    startBattleRE.Name = "StartBattleRE"
    startBattleRE.Parent = ReplicatedStorage

    local endBattleRE = ReplicatedStorage:FindFirstChild("EndBattleRE") or Instance.new("RemoteEvent")
    endBattleRE.Name = "EndBattleRE"
    endBattleRE.Parent = ReplicatedStorage

    local syncBattleUI_RE = ReplicatedStorage:FindFirstChild("SyncBattleUI_RE") or Instance.new("RemoteEvent")
    syncBattleUI_RE.Name = "SyncBattleUI_RE"
    syncBattleUI_RE.Parent = ReplicatedStorage

   -- 修改：增加对 targetLevel 的支持，并在开始前刷新植物
    -- 修改：增加对 targetLevel 的支持，并在开始前刷新植物
    startBattleRE.OnServerEvent:Connect(function(player, targetLevel)
        local plot = PlotService.GetPlayerPlot(player)
        if not plot or plot:GetAttribute("IsLevelActive") then return end

        -- 👇 【新增这一行核心修复代码】：强行清除上一局残留的撤退/结束标记
        plot:SetAttribute("IsGameOver", false)

        -- [🌟 优化方案]：不再先销毁后重连，而是执行原地复活逻辑
        local CombatService = require(script.Parent.CombatService)
        
        -- 1. 瞬间重置地块上已存在的植物（满血、变回可见）
        ZombieService.RestorePlotPlants(plot, player)
        
        -- 2. 同步存档中的新植物（如果有的话）
        CombatService.ReloadSavedPlants(player)

        local levelId = targetLevel or 1 
        print("[LevelService] Player " .. player.Name .. " battle refreshed: Level " .. levelId .. "")

        ZombieService.StartLevel(plot, levelId, player)
    end)

    endBattleRE.OnServerEvent:Connect(function(player)
        local plot = PlotService.GetPlayerPlot(player)
    
        -- 如果没在战斗中，直接无视
        if not plot or not plot:GetAttribute("IsLevelActive") then return end

        local currentLevel = plot:GetAttribute("CurrentLevel") or 1
        AnalyticsService:LogCustomEvent(player, "Manual_Retreat_Level_" .. tostring(currentLevel), 1)

        print("[LevelService] Player " .. player.Name .. " chose manual retreat")

        -- 1. 标记游戏结束
        plot:SetAttribute("IsGameOver", true)
        
        -- 2. 强力清理专属场地的僵尸，加上 OwnerId 判断
        for _, obj in pairs(Workspace:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("IsZombie") and obj:GetAttribute("OwnerId") == player.UserId then
                obj:Destroy()
            end
        end

        -- ==========================================
        -- 👇 [🌟 核心修复：第二步精确落位] 👇
        -- ==========================================
        -- 引入 CombatService (动态引入防止循环依赖)
        local CombatService = require(script.Parent.CombatService)
        
        -- 调用我们刚才写好的“超级恢复函数”
        -- 这一行代码会把隐身的、残血的、被炸掉的植物彻底满血复原！
        CombatService.ReloadSavedPlants(player)
        -- ==========================================
        
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
    local analyticsRE = ReplicatedStorage:FindFirstChild("AnalyticsRE") or Instance.new("RemoteEvent")
    analyticsRE.Name = "AnalyticsRE"
    analyticsRE.Parent = ReplicatedStorage

    
end

return LevelService
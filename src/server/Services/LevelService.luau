-- src/server/Services/LevelService.luau
local LevelService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

    -- 修改：增加对 targetLevel 的支持，方便从 UI 重启第一关
    startBattleRE.OnServerEvent:Connect(function(player, targetLevel)
        local plot = PlotService.GetPlayerPlot(player)
        if not plot or plot:GetAttribute("IsLevelActive") then return end

        local levelId = targetLevel or 1 

        print("【关卡系统】玩家 " .. player.Name .. " 开始战斗：第 " .. levelId .. " 关")

        syncBattleUI_RE:FireClient(player, true, levelId)
        ZombieService.StartLevel(plot, levelId, player)
    end)

    endBattleRE.OnServerEvent:Connect(function(player)
        local plot = PlotService.GetPlayerPlot(player)
        -- 如果没在战斗中，直接无视
        if not plot or not plot:GetAttribute("IsLevelActive") then return end

        print("【关卡系统】玩家 " .. player.Name .. " 选择了手动撤退")

        -- 1. 标记游戏结束（这会终止 ZombieService 中的循环）
        plot:SetAttribute("IsGameOver", true)
        
        -- 2. 强力清理全场僵尸
        for _, obj in pairs(Workspace:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("IsZombie") then
                obj:Destroy()
            end
        end

        -- 3. 恢复植物到非战斗状态
        ZombieService.RestorePlotPlants(plot, player)
        
        -- 4. [核心修复]：强制触发结算，重置 IsLevelActive 状态并弹出 UI
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
                        syncBattleUI_RE:FireClient(player, false, 1)
                    end
                end)
            end
        end)
    end)
end

return LevelService
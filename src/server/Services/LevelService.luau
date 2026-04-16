-- src/server/Services/LevelService.luau
local LevelService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotService = require(script.Parent.PlotService)
local ZombieService = require(script.Parent.ZombieService)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

function LevelService.Init()
    -- 1. 创建通讯电报机
    local startBattleRE = ReplicatedStorage:FindFirstChild("StartBattleRE") or Instance.new("RemoteEvent")
    startBattleRE.Name = "StartBattleRE"
    startBattleRE.Parent = ReplicatedStorage

    local endBattleRE = ReplicatedStorage:FindFirstChild("EndBattleRE") or Instance.new("RemoteEvent")
    endBattleRE.Name = "EndBattleRE"
    endBattleRE.Parent = ReplicatedStorage

    local syncBattleUI_RE = ReplicatedStorage:FindFirstChild("SyncBattleUI_RE") or Instance.new("RemoteEvent")
    syncBattleUI_RE.Name = "SyncBattleUI_RE"
    syncBattleUI_RE.Parent = ReplicatedStorage

    -- ==========================================
    -- [🌟 修改：监听开始战斗按钮 - 固定从第 1 关开始]
    -- ==========================================
    startBattleRE.OnServerEvent:Connect(function(player)
        local plot = PlotService.GetPlayerPlot(player)
        if not plot or plot:GetAttribute("IsLevelActive") then return end

        -- [🌟 核心改动：不再使用 data.UnlockedLevel，强制设为 1]
        local levelId = 1 

        print("【关卡系统】玩家 " .. player.Name .. " 点击开始战斗，强制从第 1 关开始挑战")

        -- 同步 UI 状态
        syncBattleUI_RE:FireClient(player, true, levelId)
        
        -- 调用僵尸服务开始刷怪
        ZombieService.StartLevel(plot, levelId, player)
    end)
    -- ==========================================
    -- [🌟 监听手动结束/撤退按钮]
    -- ==========================================
    endBattleRE.OnServerEvent:Connect(function(player)
        local plot = PlotService.GetPlayerPlot(player)
        if not plot or not plot:GetAttribute("IsLevelActive") then return end

        print("【关卡系统】玩家 " .. player.Name .. " 选择了手动撤退")

        plot:SetAttribute("IsGameOver", true)
        
        -- [🌟 核心修复：触发结算单！]
        -- 调用 ZombieService 的最终结算函数（传入 false 表示撤退/防守失败）
        ZombieService.FinalSettlement(player, plot, false)

        -- 恢复植物并清理僵尸
        ZombieService.RestorePlotPlants(plot, player)
        for _, obj in pairs(Workspace:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChild("HumanoidRootPart") then
                if obj.HumanoidRootPart.CollisionGroup == "Zombies" then
                    obj:Destroy()
                end
            end
        end
    end)

    -- 自动状态同步逻辑（监听战斗自然结束）
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
    local claimRewardsRE = Instance.new("RemoteEvent")
    claimRewardsRE.Name = "ClaimBattleRewardsRE"
    claimRewardsRE.Parent = ReplicatedStorage

    claimRewardsRE.OnServerEvent:Connect(function(player)
        -- [🌟 核心修复：直接呼叫 ZombieService 去处理私有的 activeSessions！]
        ZombieService.ClaimBattleRewards(player)
    end)
end

return LevelService
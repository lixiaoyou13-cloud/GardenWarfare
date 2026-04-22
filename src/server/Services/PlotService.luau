-- src/server/Services/PlotService.luau
local PlotService = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerPlots = {} 

function PlotService.Init()
    local plotsFolder = Workspace:WaitForChild("Plots")

    -- ==========================================
    -- [🌟 新增：二倍速通讯频道]
    -- ==========================================
    local toggleSpeedRE = Instance.new("RemoteEvent")
    toggleSpeedRE.Name = "ToggleSpeedRE"
    toggleSpeedRE.Parent = ReplicatedStorage

    toggleSpeedRE.OnServerEvent:Connect(function(player)
        local plot = playerPlots[player.UserId]
        if plot then
            -- 1x 和 2x 来回切换
            local currentSpeed = plot:GetAttribute("GameSpeed") or 1
            local newSpeed = (currentSpeed == 1) and 2 or 1
            plot:SetAttribute("GameSpeed", newSpeed)
            
            -- 把最新倍速发回给客户端，更新 UI
            toggleSpeedRE:FireClient(player, newSpeed)
        end
    end)

    Players.PlayerAdded:Connect(function(player)
        local assignedPlot = nil
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local isOccupied = false
            for _, occupiedPlot in pairs(playerPlots) do
                if plot == occupiedPlot then isOccupied = true; break end
            end
            if not isOccupied then assignedPlot = plot; break end
        end

        if assignedPlot then
            playerPlots[player.UserId] = assignedPlot
            
            -- [🌟 给领地打上默认的 1 倍速标签]
            assignedPlot:SetAttribute("GameSpeed", 1)
            
            print("【地块系统】为玩家 " .. player.Name .. " 分配了专属领地: " .. assignedPlot.Name)

            player.CharacterAdded:Connect(function(character)
                local spawnPoint = assignedPlot:FindFirstChild("SpawnLocation")
                if spawnPoint then
                    task.wait(0.1)
                   -- character:PivotTo(spawnPoint.CFrame * CFrame.new(0, 3, 0))
                end
            end)
        else
            warn("【严重警告】服务器爆满了！没有空闲的地块分配给 " .. player.Name)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        local plot = playerPlots[player.UserId]
        if plot then
            playerPlots[player.UserId] = nil
            local plantsFolder = plot:FindFirstChild("Plants")
            if plantsFolder then plantsFolder:ClearAllChildren() end

            local lawnFolder = plot:FindFirstChild("Lawn")
            if lawnFolder then
                for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
                    if lawnPart:IsA("BasePart") then
                        lawnPart:SetAttribute("OccupiedBy", nil)
                        for _, child in pairs(lawnPart:GetChildren()) do
                            if child:IsA("Model") and child:GetAttribute("IsCombatPlant") then
                                child:Destroy()
                            end
                        end
                        local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                        if prompt then prompt.Enabled = true end
                     end
                end
            end
        end
    end)

    print("服务端：PlotService 加载完毕！独立领地二倍速支持已开启！")
end

function PlotService.GetPlayerPlot(player)
    return playerPlots[player.UserId]
end

-- ==========================================
    -- [🌟 新增：独立倍速设定通讯频道]
    -- ==========================================
    local setSpeedRE = Instance.new("RemoteEvent")
    setSpeedRE.Name = "SetSpeedRE"
    setSpeedRE.Parent = ReplicatedStorage

    setSpeedRE.OnServerEvent:Connect(function(player, targetSpeed)
        local plot = playerPlots[player.UserId]
        if plot then
            -- [防作弊校验] 确保客户端传来的倍数只能是这三个合法值
            if targetSpeed ~= 1 and targetSpeed ~= 1.5 and targetSpeed ~= 4 then
                targetSpeed = 1
            end
            
            -- 设置领地倍速属性（ZombieService 和 CombatService 都在监听这个属性）
            plot:SetAttribute("GameSpeed", targetSpeed)
            
            -- 把最新倍速发回给客户端，用于更新按钮的高亮状态
            setSpeedRE:FireClient(player, targetSpeed)
        end
    end)

return PlotService
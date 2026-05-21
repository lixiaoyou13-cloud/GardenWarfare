-- src/client/Services/ZombieBoxController.luau
local ZombieBoxController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local itemModels = ReplicatedStorage:WaitForChild("ItemModels")
local zombieBoxRE = ReplicatedStorage:WaitForChild("ZombieBoxRE")

-- 用于假抽奖滚动动画的模型库
local fakeItemPool = {}

function ZombieBoxController.Init()
    -- 初始化假抽奖池
    for _, template in pairs(itemModels:GetChildren()) do
        if template:IsA("Model") and template.Name ~= "Box" then
            table.insert(fakeItemPool, template.Name)
        end
    end

    -- 监听服务端要求生成盲盒的指令
    zombieBoxRE.OnClientEvent:Connect(function(action, dropPos, finalItem)
        if action == "SpawnBox" then
            ZombieBoxController.SpawnLocalBox(dropPos, finalItem)
        end
    end)
end

function ZombieBoxController.SpawnLocalBox(dropPos, finalItem)
    local luckyTemplate = itemModels:FindFirstChild("Box")
    if not luckyTemplate then return end

    local box = luckyTemplate:Clone()
    
    -- 1. 找地面放置
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    if localPlayer.Character then
        raycastParams.FilterDescendantsInstances = {localPlayer.Character}
    end
    local rayResult = Workspace:Raycast(dropPos, Vector3.new(0, -30, 0), raycastParams)
    
    local cf, size = box:GetBoundingBox()
    local groundPos = rayResult and rayResult.Position or dropPos
    box:PivotTo(CFrame.new(groundPos + Vector3.new(0, size.Y/2, 0)))
    
    for _, part in pairs(box:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false 
        end
    end
    
    -- 🌟 关键：在客户端放入 Workspace，因此只有自己能看到这个盲盒
    box.Parent = Workspace

    -- 2. 距离检测与开箱动画
    task.spawn(function()
        local triggered = false
        while box.Parent and not triggered do
            local char = localPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            -- 玩家靠近（距离 <= 8）触发开箱
            if hrp and (hrp.Position - box:GetPivot().Position).Magnitude <= 8 then
                triggered = true
                
                -- 特效：宝箱变白发光
                for _, p in pairs(box:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Color = Color3.fromRGB(255, 255, 255)
                        p.Material = Enum.Material.Neon
                    elseif p:IsA("ParticleEmitter") or p:IsA("Light") then
                        p.Enabled = true
                    end
                end
                
                task.wait(0.3) 
                
                local boxPos = box:GetPivot().Position
                box:Destroy() 

                -- 动画：上方滚动物品演示
                local displayModel
                local iterations = 15 
                for i = 1, iterations do
                    if displayModel then displayModel:Destroy() end
                    
                    -- 从客户端库中随机抽一个模型作为过场动画
                    local randomName = fakeItemPool[math.random(1, #fakeItemPool)] or "Seed"
                    local template = itemModels:FindFirstChild(randomName) or itemModels:FindFirstChild("Seed")
                    
                    if template then
                        displayModel = template:Clone()
                        for _, p in pairs(displayModel:GetDescendants()) do
                            if p:IsA("BasePart") then
                                p.Color = Color3.new(0, 0, 0)
                                p.Material = Enum.Material.SmoothPlastic
                                p.Anchored = true
                                p.CanCollide = false
                            end
                        end
                        displayModel:PivotTo(CFrame.new(boxPos + Vector3.new(0, 3, 0)))
                        displayModel.Parent = Workspace
                    end
                    task.wait(0.12)
                end
                if displayModel then displayModel:Destroy() end

                -- 生成真正的奖励实体
                local templateName = finalItem.type == "Plant" and (finalItem.id .. "_Plant") or finalItem.id
                local finalTemplate = itemModels:FindFirstChild(templateName) or itemModels:FindFirstChild("Seed")

                if finalTemplate then
                    local finalModel = finalTemplate:Clone()
                    for _, p in pairs(finalModel:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Anchored = true
                            p.CanCollide = false
                        end
                    end
                    finalModel:PivotTo(CFrame.new(boxPos + Vector3.new(0, 3, 0)))
                    finalModel.Parent = Workspace
                    
                    local glow = Instance.new("Highlight")
                    glow.FillColor = Color3.fromRGB(255, 215, 0)
                    glow.Parent = finalModel

                    task.wait(0.5) 

                    -- 动画：抛物线飞入玩家身体
                    local flightTime = 0.6 
                    local startTime = os.clock()
                    local startPos = finalModel:GetPivot().Position
                    
                    local connection
                    connection = RunService.Heartbeat:Connect(function()
                        local elapsedTime = os.clock() - startTime
                        local t = math.clamp(elapsedTime / flightTime, 0, 1)
                        
                        if t >= 1 then
                            connection:Disconnect()
                            finalModel:Destroy()
                            
                            -- 🌟 动画全部播完后，告诉服务端真正发奖！
                            zombieBoxRE:FireServer("GiveReward", finalItem)
                        else
                            -- 追踪玩家位置
                            local targetChar = localPlayer.Character
                            local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                            local endPos = targetHRP and targetHRP.Position or startPos
                            
                            local p0 = startPos
                            local p2 = endPos
                            local p1 = p0:Lerp(p2, 0.5) + Vector3.new(0, 15, 0) 
                            
                            local currentPos = ((1 - t)^2 * p0) + (2 * (1 - t) * t * p1) + (t^2 * p2)
                            finalModel:PivotTo(CFrame.new(currentPos))
                        end
                    end)
                end
            end
            task.wait(0.2)
        end
    end)
end

return ZombieBoxController
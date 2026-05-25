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
    
    -- 👇 ================= [核心修复：穿透型找地面逻辑] ================= 👇
    local function GetRealGroundPos(startPos)
        local rayOrigin = startPos + Vector3.new(0, 30, 0) -- 从头顶 30 格往下扫
        local rayDirection = Vector3.new(0, -200, 0)      -- 扫 200 格深
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        
        -- 初始忽略列表
        local ignoreList = {}
        if localPlayer.Character then table.insert(ignoreList, localPlayer.Character) end
        if Workspace:FindFirstChild("Zombies") then table.insert(ignoreList, Workspace:FindFirstChild("Zombies")) end
        if Workspace:FindFirstChild("Enemies") then table.insert(ignoreList, Workspace:FindFirstChild("Enemies")) end
        
        -- 循环穿透：如果打到隐形或无碰撞的零件，就把这个零件加入黑名单，继续往下打
        while true do
            raycastParams.FilterDescendantsInstances = ignoreList
            local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
            
            if not result then 
                return startPos -- 如果什么都没打到，返回原位置兜底
            end
            
            local hitPart = result.Instance
            -- 如果打到的零件是全透明的，或者是无碰撞的（且名字不叫地面），就穿透它
            if (hitPart.Transparency >= 1 or not hitPart.CanCollide) and not string.find(string.lower(hitPart.Name), "ground") and not string.find(string.lower(hitPart.Name), "baseplate") then
                table.insert(ignoreList, hitPart)
            else
                -- 真正打到了实体模型（地面）
                -- print("📍 盲盒落地，打到了: ", hitPart.Name) -- 测试用：如果还浮空，可以把这句取消注释看看打到了什么
                return result.Position
            end
        end
    end

    local groundPos = GetRealGroundPos(dropPos)
    
    -- 🌟 修复模型隐形包围盒过大的问题：
    -- 不再使用 size.Y/2，而是固定向上偏移 1.2 格（如果你觉得 1.2 还是浮空，可以改成 0.5 或者 0；如果陷地里了，改成 2 等）
    local fixedYOffset = 1.2 
    box:PivotTo(CFrame.new(groundPos + Vector3.new(0, fixedYOffset, 0)))
    -- 👆 ============================================================= 👆
    
    for _, part in pairs(box:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false 
        end
    end
    
    box.Parent = Workspace

    -- 2. 距离检测与开箱动画
    task.spawn(function()
        local triggered = false
        while box.Parent and not triggered do
            local char = localPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if hrp and (hrp.Position - box:GetPivot().Position).Magnitude <= 8 then
                triggered = true
                
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

                local displayModel
                local iterations = 15 
                for i = 1, iterations do
                    if displayModel then displayModel:Destroy() end
                    
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
                            
                            zombieBoxRE:FireServer("GiveReward", finalItem)
                        else
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
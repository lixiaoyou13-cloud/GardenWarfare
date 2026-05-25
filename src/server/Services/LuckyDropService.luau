local LuckyDropService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PlotService = require(script.Parent.PlotService) 

local QUALITY_WEIGHTS = { [1] = 45, [2] = 30, [3] = 15, [4] = 8, [5] = 2 }

function LuckyDropService.OnAirdropDelivered(player, dropPosition, luckyBox)
    print("【空投】" .. player.Name .. " 成功将空投运回基地！")
    
    -- 👇 [🌟 恢复 100% 正常移速]
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid:GetAttribute("WalkSpeedBeforeAirdrop") then
        humanoid.WalkSpeed = humanoid:GetAttribute("WalkSpeedBeforeAirdrop")
        humanoid:SetAttribute("WalkSpeedBeforeAirdrop", nil)
    end

    if luckyBox then luckyBox:Destroy() end

    local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModels then return end

    -- 👇 [🌟 获取玩家头顶的实时位置的函数]
    local function getOverheadCFrame()
        local currentChar = player.Character
        local head = currentChar and currentChar:FindFirstChild("Head")
        if head then
            -- 在玩家头部正上方 3.5 格处（留出一点空间防穿模）
            return CFrame.new(head.Position + Vector3.new(0, 3.5, 0))
        end
        -- 如果玩家突然死亡或找不到头，退回保底的基地中心上方
        return CFrame.new(dropPosition + Vector3.new(0, 3, 0))
    end

    local plantsByQuality = {}
    local allPlantIds = {} 
    for plantId, data in pairs(ItemConfig.Plants) do
        local q = data.Quality or 1
        if not plantsByQuality[q] then plantsByQuality[q] = {} end
        table.insert(plantsByQuality[q], plantId)
        table.insert(allPlantIds, plantId)
    end

    local totalWeight = 0
    for q, weight in pairs(QUALITY_WEIGHTS) do
        if plantsByQuality[q] and #plantsByQuality[q] > 0 then totalWeight += weight end
    end

    local randomRoll = math.random() * totalWeight
    local currentWeight = 0
    local targetQuality = 1
    for q, weight in pairs(QUALITY_WEIGHTS) do
        if plantsByQuality[q] and #plantsByQuality[q] > 0 then
            currentWeight += weight
            if randomRoll <= currentWeight then
                targetQuality = q
                break
            end
        end
    end

    local possiblePlants = plantsByQuality[targetQuality]
    local finalPlantId = possiblePlants[math.random(1, #possiblePlants)]

    local displayModel
    -- 👇 [🌟 修改盲盒抽奖时长]
    local totalDuration = 3.5 
    local interval = 0.15 
    local iterations = math.floor(totalDuration / interval)

    -- [🌟 滚动抽奖动画阶段]
    for i = 1, iterations do
        if displayModel then displayModel:Destroy() end
        local randomId = allPlantIds[math.random(1, #allPlantIds)]
        local template = itemModels:FindFirstChild(randomId .. "_Plant")
        if template then
            displayModel = template:Clone()
            for _, part in pairs(displayModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Color = Color3.new(0, 0, 0)
                    part.Material = Enum.Material.SmoothPlastic
                    if part:IsA("MeshPart") then part.TextureID = "" end
                    part.Anchored = true
                    part.CanCollide = false
                end
            end
            local highlight = Instance.new("Highlight")
            highlight.FillColor = Color3.new(0, 0, 0)
            highlight.FillTransparency = 0
            highlight.OutlineColor = Color3.new(1, 1, 1)
            highlight.Parent = displayModel

            if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
            
            -- 👇 [🌟 改为在玩家头顶显示，每次循环获取最新位置]
            displayModel:PivotTo(getOverheadCFrame())
            displayModel.Parent = Workspace
        end
        task.wait(interval)
    end

    if displayModel then displayModel:Destroy() end
    local finalTemplate = itemModels:FindFirstChild(finalPlantId .. "_Plant")
    if not finalTemplate then return end

    -- [🌟 最终揭晓阶段]
    displayModel = finalTemplate:Clone()
    for _, part in pairs(displayModel:GetDescendants()) do
        if part:IsA("BasePart") then 
            part.Anchored = true 
            part.CanCollide = false
         end
    end
    -- 👇 [🌟 核心修复] 遍历并关闭最终模型上的 "Glow", "Lightning", "HolyLight" 变异特效
    for _, node in ipairs(displayModel:GetDescendants()) do
        if node.Name == "Glow" or node.Name == "Lightning" or node.Name == "HolyLight" then
            for _, child in ipairs(node:GetDescendants()) do
                if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                    child.Enabled = false
                end
            end
        end
    end

    if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
    
    -- 👇 [🌟 最终开出的植物也锁定在玩家头顶]
    displayModel:PivotTo(getOverheadCFrame())
    displayModel.Parent = Workspace

    local glow = Instance.new("Highlight")
    glow.FillColor = ItemConfig.QualityColor[targetQuality] or Color3.new(1, 1, 1)
    glow.OutlineColor = Color3.new(1, 1, 1)
    glow.Parent = displayModel

    task.wait(0.5) 

    displayModel:Destroy()
    
    local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
    local EquipmentService = require(script.Parent.EquipmentService)
    
    -- 👇 1. 发放植物并刷新背包
    PlayerDataManager.GivePlant(player, finalPlantId, 1, 1)
    
    -- 👇 2. 直接拿在手里！
    local compositeId = "Plant_" .. finalPlantId .. "_1"
    EquipmentService.UpdateHoldItem(player, compositeId)

    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE then
        local plantName = ItemConfig.Plants[finalPlantId] and ItemConfig.Plants[finalPlantId].Name or finalPlantId
        local broadcastMsg = player.Name .. " successfully claimed a " .. plantName .. " from the Airdrop!"
        showTipRE:FireAllClients(broadcastMsg)
    end
end

function LuckyDropService.SpawnDrop()
    local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
    local luckyTemplate = itemModels and itemModels:FindFirstChild("Lucky")
    if not luckyTemplate then return end

    local luckyBox = luckyTemplate:Clone()
    if not luckyBox.PrimaryPart then luckyBox.PrimaryPart = luckyBox:FindFirstChildWhichIsA("BasePart", true) end
    
    -- ==========================================
    -- [E 键拾取交互]
    -- ==========================================
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Pickup Airdrop"
    prompt.ObjectText = "Mystery Box"
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.HoldDuration = 0.5 
    prompt.RequiresLineOfSight = false
    prompt.MaxActivationDistance = 12
    prompt.Parent = luckyBox.PrimaryPart

    prompt.Triggered:Connect(function(player)
        -- 👇 [🌟 核心修复：防抢夺并发] 检查是否已经被别人抢先拿到了，如果有，立刻终止！
        if luckyBox:GetAttribute("Carrier") then 
            return 
        end
        prompt.Enabled = false
        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid") 
        if not head or not hrp or not humanoid then prompt.Enabled = true return end

        local myPlot = PlotService.GetPlayerPlot(player)
        if not myPlot then prompt.Enabled = true return end
        local plotCenter = myPlot.PrimaryPart or myPlot:FindFirstChildWhichIsA("BasePart", true)
        if not plotCenter then prompt.Enabled = true return end

        -- 👇 [🌟 设置携带者属性，供客户端过滤 UI（保留原本的 AirdropBox 标签）]
        luckyBox:SetAttribute("Carrier", player.UserId) 

        -- ==========================================
        -- [在解除固定前，先把箱子内部的所有零件互相焊死]
        -- ==========================================
        local primary = luckyBox.PrimaryPart
        for _, p in pairs(luckyBox:GetDescendants()) do
            if p:IsA("BasePart") and p ~= primary then 
                local innerWeld = Instance.new("WeldConstraint")
                innerWeld.Part0 = primary
                innerWeld.Part1 = p
                innerWeld.Parent = primary
            end
        end

        -- ==========================================
        -- [彻底关闭箱子的碰撞和重力，解除空中固定]
        -- ==========================================
        for _, p in pairs(luckyBox:GetDescendants()) do
            if p:IsA("BasePart") then 
                p.CanCollide = false 
                p.Massless = true    
                p.Anchored = false   
            end
        end
        
        -- 移到玩家头顶
        luckyBox:PivotTo(head.CFrame * CFrame.new(0, (primary.Size.Y/2) + (head.Size.Y/2) + 0.5, 0))
        
        -- 👇 [🌟 将主零件焊接到玩家头上，并且把 Weld 放在 Head 下面并命名]
        local weld = Instance.new("WeldConstraint")
        weld.Name = "AirdropWeld"
        weld.Part0 = head
        weld.Part1 = primary
        weld.Parent = head

        -- ==========================================
        -- 👇 [🌟 记录当前移速并减速 10%]
        -- ==========================================
        if not humanoid:GetAttribute("WalkSpeedBeforeAirdrop") then
            humanoid:SetAttribute("WalkSpeedBeforeAirdrop", humanoid.WalkSpeed)
        end
        humanoid.WalkSpeed = humanoid:GetAttribute("WalkSpeedBeforeAirdrop") * 0.9

        -- ==========================================
        -- [引导光束代码]
        -- ==========================================
        local att0 = Instance.new("Attachment", hrp)
        local att1 = Instance.new("Attachment", plotCenter)
        att1.Position = Vector3.new(0, 3, 0) 

        local beam = Instance.new("Beam")
        beam.Attachment0 = att0
        beam.Attachment1 = att1
        beam.Texture = "rbxassetid://6661208797" 
        beam.TextureMode = Enum.TextureMode.Wrap
        beam.TextureLength = 5 
        beam.TextureSpeed = 3  
        beam.Width0 = 3
        beam.Width1 = 3
        beam.FaceCamera = true
        beam.LightEmission = 1
        beam.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0)) 
        beam.Parent = char

        -- ==========================================
        -- [🌟 循环检测是否到达基地或被抢夺]
        -- ==========================================
        task.spawn(function()
            while luckyBox and luckyBox.Parent and char and char.Parent do
                task.wait(0.5)
                
                -- 👇防抢夺检测：如果头上的 AirdropWeld 消失了，说明被别人打爆/抢走了，立刻中断并清理光线特效！
                if not head:FindFirstChild("AirdropWeld") then
                    break 
                end

                local dist = (hrp.Position - plotCenter.Position).Magnitude
                if dist <= 22 then
                    if beam then beam:Destroy() end
                    if att0 then att0:Destroy() end
                    if att1 then att1:Destroy() end
                    
                    LuckyDropService.OnAirdropDelivered(player, plotCenter.Position, luckyBox)
                    break
                end
            end
            
            -- 清理内存：防止玩家中途死亡或被抢导致特效残留
            if beam then beam:Destroy() end
            if att0 then att0:Destroy() end
            if att1 then att1:Destroy() end
        end)
    end)

    -- 落地位置计算
    local baseplate = Workspace:FindFirstChild("Baseplate1")
    local spawnY, targetY, dropX, dropZ = 150, 3, 0, 0
    if baseplate then
        local randomX = (math.random() - 0.5) * (baseplate.Size.X * 0.85)
        local randomZ = (math.random() - 0.5) * (baseplate.Size.Z * 0.85)
        local targetCFramePos = baseplate.CFrame * CFrame.new(randomX, 0, randomZ)
        dropX, dropZ = targetCFramePos.X, targetCFramePos.Z
        targetY = targetCFramePos.Y + (baseplate.Size.Y / 2) + (luckyBox.PrimaryPart.Size.Y / 2)
    end

    local startCFrame = CFrame.new(dropX, spawnY, dropZ)
    local targetCFrame = CFrame.new(dropX, targetY, dropZ)
    
    for _, part in pairs(luckyBox:GetDescendants()) do
        if part:IsA("BasePart") then part.Anchored = true end
    end
    luckyBox:PivotTo(startCFrame)

    CollectionService:AddTag(luckyBox, "AirdropBox")
    luckyBox.Parent = Workspace

    local tweenValue = Instance.new("NumberValue")
    local dropTween = TweenService:Create(tweenValue, TweenInfo.new(12, Enum.EasingStyle.Linear), {Value = 1})
    
    tweenValue:GetPropertyChangedSignal("Value"):Connect(function()
        if luckyBox and luckyBox.Parent then luckyBox:PivotTo(startCFrame:Lerp(targetCFrame, tweenValue.Value)) end
    end)

    dropTween:Play()
    dropTween.Completed:Connect(function()
        if luckyBox and luckyBox.Parent then
            local balloons = luckyBox:FindFirstChild("Balloons")
            if balloons then balloons:Destroy() end

            local head = luckyBox:FindFirstChild("Head")
            local smoke = head and head:FindFirstChild("Smoke")
            if smoke then smoke.Enabled = true end
        end
        tweenValue:Destroy()
        Debris:AddItem(luckyBox, 300)
    end)
end

function LuckyDropService.Init()
    local showTipRE = ReplicatedStorage:WaitForChild("ShowTipRE", 10)
    task.spawn(function()
        while true do
            task.wait(120) 
            for timeLeft =10, 1, -1 do
                if showTipRE then showTipRE:FireAllClients("Mystery Random Plant Airdrop in " .. timeLeft .. "s") end
                task.wait(1)
            end
            LuckyDropService.SpawnDrop()
        end
    end)
end

return LuckyDropService
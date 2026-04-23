-- src/client/UI/PlantHoverController.luau
local PlantHoverController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function PlantHoverController.Init()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local playerGui = player:WaitForChild("PlayerGui")

    -- ==========================================
    -- [🎨 UI 核心容器 - 1.5倍整体放大]
    -- ==========================================
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlantHoverUI"
    billboard.Size = UDim2.new(0, 195, 0, 130)
    billboard.StudsOffset = Vector3.new(0, 6, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 50
    billboard.Enabled = false
    
    -- 🌟 1. 变异图标：移除描边防止“黑框”干扰，直接显示图片内容
    local mutIcon = Instance.new("ImageLabel")
    mutIcon.Name = "MutationIcon"
    mutIcon.Size = UDim2.new(0, 45, 0, 45) 
    mutIcon.Position = UDim2.new(0.5, -22, 0, 0) -- 位于容器最顶部
    mutIcon.BackgroundTransparency = 1 
    mutIcon.Visible = false 
    mutIcon.ScaleType = Enum.ScaleType.Fit 
    mutIcon.ZIndex = 10
    mutIcon.Parent = billboard

    -- 🌟 2. 名称/血条底板
    local bgFrame = Instance.new("Frame")
    bgFrame.Name = "MainPanel"
    bgFrame.Size = UDim2.new(1, 0, 0, 83)
    bgFrame.Position = UDim2.new(0, 0, 1, -83) -- 底部对齐
    bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bgFrame.BackgroundTransparency = 0.5
    Instance.new("UICorner", bgFrame).CornerRadius = UDim.new(0, 8)
    bgFrame.Parent = billboard

    -- ⚔️ DPS 显示标签
    local dpsLabel = Instance.new("TextLabel")
    dpsLabel.Name = "DPSLabel"
    dpsLabel.Size = UDim2.new(1, 0, 0.25, 0)
    dpsLabel.Position = UDim2.new(0, 0, 0.08, 0)
    dpsLabel.BackgroundTransparency = 1
    -- 🌟 修复 1：必须设为白色，渐变色 UIGradient 才能正确显示！
    dpsLabel.TextColor3 = Color3.new(1, 1, 1) 
    dpsLabel.TextScaled = true
    dpsLabel.Font = Enum.Font.SourceSansBold
    dpsLabel.Parent = bgFrame

    local dpsGradient = Instance.new("UIGradient")
    dpsGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(134, 255, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(37, 205, 9))
    })
    dpsGradient.Rotation = 90
    dpsGradient.Parent = dpsLabel

    local dpsStroke = Instance.new("UIStroke")
    dpsStroke.Thickness = 1.5
    dpsStroke.Color = Color3.fromRGB(0, 0, 0)
    dpsStroke.Parent = dpsLabel

    -- 📛 植物名称
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.35, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.Parent = bgFrame

    local nameStroke = Instance.new("UIStroke")
    nameStroke.Thickness = 1.5
    nameStroke.Color = Color3.fromRGB(0, 0, 0)
    nameStroke.Parent = nameLabel

    -- ❤️ 血条区域
    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(0.85, 0, 0.15, 0)
    barBg.Position = UDim2.new(0.075, 0, 0.75, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    barBg.BackgroundTransparency = 0.5
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)
    barBg.Parent = bgFrame

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(85, 255, 127) 
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 6)
    barFill.Parent = barBg

    billboard.Parent = playerGui

    -- ==========================================
    -- [🌟 图片素材配置]
    -- ==========================================
    local MUTATION_ICONS = {
        [2] = "rbxassetid://89526577666854", -- 闪耀
        [3] = "rbxassetid://101706251051471", -- 雷电
        [4] = "rbxassetid://14507112520",  -- 圣光
    }

    -- ==========================================
    -- [🌟 动态逻辑处理]
    -- ==========================================
    local currentTarget = nil
    local hpConnection = nil

    local function updateUI()
        if not currentTarget or not currentTarget.Parent then return end
        
        local currentHP = currentTarget:GetAttribute("Health") or 0
        local maxHP = currentTarget:GetAttribute("MaxHealth") or 1
        local mutationLevel = currentTarget:GetAttribute("MutationLevel") or 1
        local ratio = math.clamp(currentHP / maxHP, 0, 1)

        TweenService:Create(barFill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

        local plantId = currentTarget.Name
        local plantConfig = ItemConfig.Plants[plantId]
        nameLabel.Text = plantConfig and plantConfig.Name or plantId

        -- 🌟 更新图标：如果图片 ID 正确，现在会正常显示
        local iconId = MUTATION_ICONS[mutationLevel]
        if iconId then
            -- 获取品质颜色
            local mutColor =  Color3.fromRGB(255, 255, 255)
            mutIcon.Image = iconId
            -- 🌟 修复 2：如果图标本身带颜色，建议先将 ImageColor3 设为白色观察效果
            mutIcon.ImageColor3 = mutColor 
            mutIcon.Visible = true
        else
            mutIcon.Visible = false
        end

        -- 更新 DPS 显示
        if plantConfig and plantConfig.CanAttack and plantConfig.Attack and plantConfig.AttackInterval then
            local dpsValue = plantConfig.Attack / plantConfig.AttackInterval
            if mutationLevel > 1 then dpsValue = dpsValue * 1.5 end 
            dpsLabel.Text = string.format("DPS: %.1f", dpsValue)
            dpsLabel.Visible = true
        else
            dpsLabel.Visible = false
        end
    end

    -- [雷达扫描]
    RunService.RenderStepped:Connect(function()
        local targetPart = mouse.Target
        local foundPlant = nil
        if targetPart then
            local currentObj = targetPart
            while currentObj and currentObj ~= Workspace do
                if currentObj:IsA("Model") and currentObj:GetAttribute("IsCombatPlant") then
                    foundPlant = currentObj
                    break
                end
                currentObj = currentObj.Parent
            end
        end

        if foundPlant then
            if currentTarget ~= foundPlant then
                currentTarget = foundPlant
                billboard.Adornee = foundPlant.PrimaryPart or foundPlant:FindFirstChildWhichIsA("BasePart") or foundPlant
                billboard.Enabled = true
                if hpConnection then hpConnection:Disconnect() end
                hpConnection = currentTarget:GetAttributeChangedSignal("Health"):Connect(updateUI)
                updateUI()
            end
        else
            if currentTarget then
                currentTarget = nil
                billboard.Enabled = false
                billboard.Adornee = nil
                if hpConnection then hpConnection:Disconnect(); hpConnection = nil end
            end
        end
    end)
end

return PlantHoverController
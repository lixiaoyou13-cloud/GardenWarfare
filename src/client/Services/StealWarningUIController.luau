-- src/client/Services/StealWarningUIController.luau
local StealWarningUIController = {}

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

function StealWarningUIController.Init()
    local player = Players.LocalPlayer

    -- 1. 创建 UI 容器
    local pointerGui = Instance.new("ScreenGui")
    pointerGui.Name = "StealWarningPointerGui"
    pointerGui.ResetOnSpawn = false
    pointerGui.DisplayOrder = 105 -- 层级拉高
    pointerGui.Parent = player:WaitForChild("PlayerGui")

    local container = Instance.new("Frame")
    container.Name = "PointerContainer"
    container.Size = UDim2.new(0, 80, 0, 80)
    container.BackgroundTransparency = 1
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Visible = false
    container.Parent = pointerGui

    -- 2. 红色指向箭头
    local arrow = Instance.new("ImageLabel")
    arrow.Name = "Arrow"
    arrow.Size = UDim2.new(0, 50, 0, 50)
    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.BackgroundTransparency = 1
    arrow.Image = "rbxassetid://3145534143" -- 复用空投的箭头形状
    arrow.ImageColor3 = Color3.fromRGB(255, 0, 0) -- 纯红色
    arrow.Parent = container

    -- 3. 红色醒目叹号
    local label = Instance.new("TextLabel")
    label.Name = "Exclamation"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Position = UDim2.new(0.5, 0, 0.5, 0)
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.BackgroundTransparency = 1
    label.Text = "!"
    label.TextColor3 = Color3.fromRGB(255, 0, 0)
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.Parent = container

    -- 黑色描边增强可视度
    local textStroke = Instance.new("UIStroke")
    textStroke.Color = Color3.fromRGB(0, 0, 0)
    textStroke.Thickness = 4
    textStroke.Parent = label

    -- ==========================================
    -- [🌟 核心]：急促的闪烁警告动画
    -- ==========================================
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = container

    -- 相比空投的 0.6 秒，这里改成 0.25 秒，让它像警报一样快速闪烁缩放
    local scaleTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local scaleTween = TweenService:Create(uiScale, scaleTweenInfo, {Scale = 1.5})
    scaleTween:Play()

    -- ==========================================
    -- [🌟 雷达追踪算法]
    -- ==========================================
    RunService.RenderStepped:Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        -- 寻找场景中被打上 "被偷" 标签的植物
        local stolenPlants = CollectionService:GetTagged("BeingStolen")
        local targetPlant = nil

        -- 遍历确认这颗植物是不是属于 "我" 的
        for _, plant in ipairs(stolenPlants) do
            if plant:GetAttribute("OwnerId") == player.UserId then
                targetPlant = plant
                break
            end
        end

        -- 如果没有我的植物正在被偷，立刻隐藏 UI
        if not targetPlant or not targetPlant.PrimaryPart then
            container.Visible = false
            return
        end

        local targetPos = targetPlant.PrimaryPart.Position + Vector3.new(0, 5, 0)
        local vector, onScreen = camera:WorldToViewportPoint(targetPos)
        local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

        container.Visible = true

        if onScreen then
            -- 【情况 A：植物已经在屏幕视野内】
            container.Position = UDim2.new(0, vector.X, 0, vector.Y)
            arrow.Visible = false -- 在屏幕内不需要箭头指引，只留一个巨大的闪烁叹号在植物头上
            label.Position = UDim2.new(0.5, 0, 0.5, 0)
        else
            -- 【情况 B：植物在视野外，开启屏幕边缘贴边算法】
            arrow.Visible = true
            local offset = Vector2.new(vector.X - center.X, vector.Y - center.Y)
            if vector.Z < 0 then offset = -offset end 

            local angle = math.atan2(offset.Y, offset.X)
            
            local paddingX, paddingY = 80, 80
            local edgeX = center.X - paddingX
            local edgeY = center.Y - paddingY

            local cosAngle = math.cos(angle)
            local sinAngle = math.sin(angle)
            local screenX, screenY

            if math.abs(cosAngle) * edgeY > math.abs(sinAngle) * edgeX then
                screenX = math.sign(cosAngle) * edgeX
                screenY = math.tan(angle) * screenX
            else
                screenY = math.sign(sinAngle) * edgeY
                screenX = screenY / math.tan(angle)
            end

            container.Position = UDim2.new(0, center.X + screenX, 0, center.Y + screenY)
            arrow.Rotation = math.deg(angle)
            
            -- 将叹号稍微偏移一点，别挡住箭头本身
            label.Position = UDim2.new(0.5, 0, 0.5, -20)
        end
    end)
    
    print("客户端：StealWarningUIController 加载完毕！防偷菜雷达启动。")
end

return StealWarningUIController
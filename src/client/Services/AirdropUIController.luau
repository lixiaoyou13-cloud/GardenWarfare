local AirdropUIController = {}

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

function AirdropUIController.Init()
    local player = Players.LocalPlayer

    -- 1. 动态生成 ScreenGui
    local pointerGui = Instance.new("ScreenGui")
    pointerGui.Name = "AirdropPointerGui"
    pointerGui.ResetOnSpawn = false
    -- [🌟 修复]：层级调到 100，防止被游戏原本的黑底遮罩挡住
    pointerGui.DisplayOrder = 100 
    pointerGui.Parent = player:WaitForChild("PlayerGui")

    -- [🌟 新增]：容器框架，方便文字和箭头整体移动和缩放
    local container = Instance.new("Frame")
    container.Name = "PointerContainer"
    container.Size = UDim2.new(0, 80, 0, 80)
    container.BackgroundTransparency = 1
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Visible = false
    container.Parent = pointerGui

    -- 2. 箭头图标
    local arrow = Instance.new("ImageLabel")
    arrow.Name = "Arrow"
    arrow.Size = UDim2.new(0, 45, 0, 45)
    arrow.Position = UDim2.new(0.5, 0, 0.4, 0) -- 稍微往上提一点，给文字留空间
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.BackgroundTransparency = 1
    -- [🌟 保留]：使用你自己设定的图片 ID
    arrow.Image = "rbxassetid://3145534143" 
    arrow.ImageColor3 = Color3.fromRGB(255, 215, 0) -- 金色
    arrow.Parent = container

    -- [🌟 新增]：绿色英文提示文字 "CLAIM"
    local label = Instance.new("TextLabel")
    label.Name = "ClaimLabel"
    label.Size = UDim2.new(1, 20, 0, 20)
    label.Position = UDim2.new(0.5, 0, 1, 0)
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.BackgroundTransparency = 1
    label.Text = "CLAIM"
    label.TextColor3 = Color3.fromRGB(0, 255, 0) -- 绿色
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = container

    -- 👇 [🌟 本次新增]：给文字加上黑色描边
    local textStroke = Instance.new("UIStroke")
    textStroke.Color = Color3.fromRGB(0, 0, 0) -- 黑色
    textStroke.Thickness = 3 -- 描边粗细可以自己微调
    textStroke.Parent = label
    -- ==========================================
    -- [🌟 核心]：无限循环的呼吸动画效果 (作用于容器)
    -- ==========================================
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = container -- 放在 Container 下，箭头和字一起缩放

    local scaleTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local scaleTween = TweenService:Create(uiScale, scaleTweenInfo, {Scale = 1.3})
    scaleTween:Play()

    -- 3. 实时渲染循环
    RunService.RenderStepped:Connect(function()
        -- [🌟 修复]：必须在循环内部获取 Camera，防止玩家死亡/重置时旧 Camera 失效报错
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local airdrops = CollectionService:GetTagged("AirdropBox")
        local targetBox = nil

        -- 👇 [🌟 核心修改]：寻找一个当前不是由“我”携带的空投进行追踪
        for _, box in ipairs(airdrops) do
            local carrierId = box:GetAttribute("Carrier")
            if carrierId ~= player.UserId then
                targetBox = box
                break
            end
        end

        -- 如果没有找到符合条件的空投（说明唯一的空投在自己头上，或者没空投），隐藏 UI
        if not targetBox or not targetBox.PrimaryPart or not targetBox.Parent then
            container.Visible = false
            return
        end

        local targetPos = targetBox.PrimaryPart.Position
        local vector, onScreen = camera:WorldToViewportPoint(targetPos)
        local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

        container.Visible = true

        if onScreen then
            -- 【情况 A：空投在屏幕视野内】
            container.Position = UDim2.new(0, vector.X, 0, vector.Y - 70)
            arrow.Rotation = 270 
        else
            -- 【情况 B：空投在视野外】
            local offset = Vector2.new(vector.X - center.X, vector.Y - center.Y)
            if vector.Z < 0 then offset = -offset end 

            local angle = math.atan2(offset.Y, offset.X)
            
            -- 设置屏幕边缘的内边距 
            local paddingX, paddingY = 50, 50
            local edgeX = center.X - paddingX
            local edgeY = center.Y - paddingY

            local cosAngle = math.cos(angle)
            local sinAngle = math.sin(angle)
            local screenX, screenY

            -- 边缘碰撞检测算法
            if math.abs(cosAngle) * edgeY > math.abs(sinAngle) * edgeX then
                screenX = math.sign(cosAngle) * edgeX
                screenY = math.tan(angle) * screenX
            else
                screenY = math.sign(sinAngle) * edgeY
                screenX = screenY / math.tan(angle)
            end

            container.Position = UDim2.new(0, center.X + screenX, 0, center.Y + screenY)
            arrow.Rotation = math.deg(angle) 
        end
    end)
    
    print("客户端：AirdropUIController 加载完毕！带 'CLAIM' 提示的呼吸箭头已激活。")
end

return AirdropUIController
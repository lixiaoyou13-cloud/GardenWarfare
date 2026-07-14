-- src/client/Utils/TutorialEffect.luau
local TutorialEffect = {}
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UI_ARROW_SIZE = 60

-- 1. UI 闪烁特效 (保持不变)
function TutorialEffect.AddFlash(object, color, thickness)
    local existing = object:FindFirstChild("TutorialFlash")
    if existing then existing:Destroy() end

    local stroke = Instance.new("UIStroke")
    stroke.Name = "TutorialFlash"
    stroke.Color = color or Color3.fromRGB(255, 255, 255)
    stroke.Thickness = thickness or 8
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Transparency = 1
    stroke.Parent = object

    local info = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local tween = TweenService:Create(stroke, info, {Transparency = 0})
    tween:Play()

    return function()
        tween:Cancel()
        stroke:Destroy()
    end
end

-- 2. 3D 滚动引导线特效 (版)
function TutorialEffect.AddGuideBeam(character, targetPart, beamColor)
    if not character or not targetPart then return function() end end
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not rootPart then return function() end end

    beamColor = beamColor or Color3.fromRGB(85, 255, 127)

    -- 创建附着点击
    local attPlayer = Instance.new("Attachment")
    attPlayer.Name = "TutorialAttPlayer"
    attPlayer.Parent = rootPart

    local attTarget = Instance.new("Attachment")
    attTarget.Name = "TutorialAttTarget"
    attTarget.Parent = targetPart

    -- 创建引导光束 (Beam)
    local guideBeam = Instance.new("Beam")
    guideBeam.Name = "TutorialGuideBeam"
    guideBeam.Attachment0 = attPlayer
    guideBeam.Attachment1 = attTarget
    guideBeam.FaceCamera = true
    guideBeam.Width0 = 1.5
    guideBeam.Width1 = 1.5
    guideBeam.Color = ColorSequence.new(beamColor)

    -- 使用你提示供的滚动贴图片 ID
    guideBeam.Texture = "rbxassetid://6661208797"
    guideBeam.TextureMode = Enum.TextureMode.Wrap
    guideBeam.TextureSpeed = 2 -- 滚动速度

    -- 增强可见度
    guideBeam.LightEmission = 1
    guideBeam.LightInfluence = 0
    guideBeam.Transparency = NumberSequence.new(0)
    guideBeam.Enabled = true
    guideBeam.Parent = targetPart

    -- 目标高亮
    local highlight = Instance.new("Highlight")
    highlight.Name = "TutorialHighlight"
    highlight.FillColor = beamColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.Parent = targetPart

    return function()
        if attPlayer then attPlayer:Destroy() end
        if attTarget then attTarget:Destroy() end
        if guideBeam then guideBeam:Destroy() end
        if highlight then highlight:Destroy() end
    end
end

function TutorialEffect.AddUIArrow(targetUI)
    if not targetUI then return function() end end

    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- 创建一个独立的 ScreenGui，确保箭头永远在最上层，不会被遮挡
    local screenGui = playerGui:FindFirstChild("TutorialArrowGui")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "TutorialArrowGui"
        screenGui.DisplayOrder = 9999
        screenGui.Parent = playerGui
    end

    local arrow = Instance.new("ImageLabel")
    arrow.Name = "TutorialUIArrow"
    arrow.Size = UDim2.new(0, UI_ARROW_SIZE, 0, UI_ARROW_SIZE)
    arrow.AnchorPoint = Vector2.new(0.5, 1) -- 锚点设为底部居中
    arrow.BackgroundTransparency = 1
    arrow.Image = "rbxassetid://120753408134411" -- 这是一个通用向下箭头的素材ID，你可以自转行替换
    arrow.ImageColor3 = Color3.fromRGB(255, 215, 0) -- 显眼的金色

    arrow.Rotation = - 90
    arrow.Parent = screenGui

    local startTime = tick()
    local connection

    -- 实时跟随目标 UI 并加上下浮动的动画
    connection = RunService.RenderStepped:Connect(function()
        -- 确保目标 UI 仍然存在并且可见
        if targetUI and targetUI.Parent and targetUI.AbsoluteSize.X > 0 then
            arrow.Visible = true
            -- 计算浮动偏移量 (上下浮动 8 像素)
            local bounceOffset = math.sin((tick() - startTime) * 6) * 8

            -- 定位在目标 UI 的正上方
            arrow.Position = UDim2.new(
                0, targetUI.AbsolutePosition.X + (targetUI.AbsoluteSize.X / 2),
                0, targetUI.AbsolutePosition.Y - 5 + bounceOffset
            )
        else
            arrow.Visible = false
        end
    end)

    -- 返回清理函数
    return function()
        if connection then connection:Disconnect() end
        if arrow then arrow:Destroy() end
    end
end

return TutorialEffect

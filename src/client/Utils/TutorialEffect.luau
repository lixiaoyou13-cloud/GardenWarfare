-- src/client/Utils/TutorialEffect.luau
local TutorialEffect = {}
local TweenService = game:GetService("TweenService")

-- ==========================================
-- 1. UI 闪烁特效 (保持不变)
-- ==========================================
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

-- ==========================================
-- 2. 3D 滚动引导线特效 (优化版)
-- ==========================================
function TutorialEffect.AddGuideBeam(character, targetPart, beamColor)
    if not character or not targetPart then return function() end end
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not rootPart then return function() end end

    beamColor = beamColor or Color3.fromRGB(85, 255, 127)

    -- 创建附着点
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
    
    -- 【关键修改】：使用你提供的滚动贴图 ID
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

return TutorialEffect
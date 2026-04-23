-- src/client/Utils/UIEffectUtil.luau
local UIEffectUtil = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))

-- ==========================================
-- [🌟 核心算法：数字智能精简 (例如 1500 -> 1.5K, 1000 -> 1K)]
-- ==========================================
local function FormatNumber(num)
    if num >= 1000000 then
        -- 转换 M (百万)，并用 gsub 智能去掉末尾多余的 ".0" (1.0M 变成 1M)
        local str = string.format("%.1fM", num / 1000000)
        return string.gsub(str, "%.0M", "M")
    elseif num >= 1000 then
        -- 转换 K (千)，同样去掉多余的 ".0" (1.0K 变成 1K)
        local str = string.format("%.1fK", num / 1000)
        return string.gsub(str, "%.0K", "K")
    else
        return tostring(math.floor(num))
    end
end

-- [🌟 UI模块 1：数字平滑滚动]
function UIEffectUtil.RollNumber(textLabel, newValue, prefix)
    prefix = prefix or ""
    local intValue = textLabel:FindFirstChild("RollingValue")
    if not intValue then
        intValue = Instance.new("IntValue")
        intValue.Name = "RollingValue"
        
        -- 智能解析带有 K 或 M 的初始数字
        local rawText = textLabel.Text
        local baseNum = tonumber(string.match(rawText, "[%d%.]+")) or 0
        if string.match(rawText, "M") then baseNum = baseNum * 1000000
        elseif string.match(rawText, "K") then baseNum = baseNum * 1000 end
        
        intValue.Value = math.floor(baseNum)
        intValue.Parent = textLabel
        
        -- [🌟 应用智能精简算法]
        intValue.Changed:Connect(function(val) 
            textLabel.Text = prefix .. FormatNumber(val) 
        end)
    end
    TweenService:Create(intValue, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = newValue}):Play()
end

-- [🌟 UI模块 2：金币飞天特效 (已巨大化)]
function UIEffectUtil.Play2DCollectEffect(amount, onCompleteCallback)
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = playerGui:FindFirstChild("CoinCollectGui") or Instance.new("ScreenGui")
    screenGui.Name = "CoinCollectGui"; screenGui.DisplayOrder = 100; screenGui.Parent = playerGui

    local startX = math.random(30, 70) / 100; local startY = math.random(20, 50) / 100
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1; container.Position = UDim2.new(startX, 0, startY, 0)
    
    -- 【🌟 提升体积：整体容器放大近一倍！】
    container.Size = UDim2.new(0, 160, 0, 60); 
    container.AnchorPoint = Vector2.new(0.5, 0.5); container.Parent = screenGui

    local icon = Instance.new("ImageLabel")
    icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://102426033120992"
    
    -- 【🌟 图标巨大化】(原本 35x35，现在 60x60)
    icon.Size = UDim2.new(0, 60, 0, 60); 
    icon.Position = UDim2.new(0, 0, 0.5, 0); icon.AnchorPoint = Vector2.new(0, 0.5); icon.Parent = container

    local textLabel = Instance.new("TextLabel")
    textLabel.BackgroundTransparency = 1; 
    
    -- 【🌟 浮空数值也应用 K/M 进制缩写】
    textLabel.Text = "+" .. FormatNumber(amount); 
    
    textLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    textLabel.TextStrokeColor3 = Color3.fromRGB(150, 80, 0); textLabel.TextStrokeTransparency = 0; textLabel.Font = Enum.Font.GothamBlack; textLabel.TextScaled = true
    
    -- 【🌟 数值文本框也跟着放大】
    textLabel.Size = UDim2.new(0, 100, 0, 50); 
    textLabel.Position = UDim2.new(0, 65, 0.5, 0); 
    textLabel.AnchorPoint = Vector2.new(0, 0.5); textLabel.Parent = container

    local popScale = Instance.new("UIScale", container); popScale.Scale = 0
    TweenService:Create(popScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.2}):Play()
    TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(startX + math.random(-5, 5)/100, 0, startY - 0.05, 0)}):Play()

    task.delay(1, function()
        local targetPos = UDim2.new(0, 80, 1, -80) 
        local basicGui = playerGui:FindFirstChild("BasicGui")
        local realCoinLabel = basicGui and basicGui:FindFirstChild("PlayProperty") and basicGui.PlayProperty:FindFirstChild("CoinLabel")
        if realCoinLabel then targetPos = UDim2.new(0, realCoinLabel.AbsolutePosition.X + realCoinLabel.AbsoluteSize.X/2, 0, realCoinLabel.AbsolutePosition.Y + realCoinLabel.AbsoluteSize.Y/2) end

        local flyTween = TweenService:Create(container, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = targetPos})
        TweenService:Create(popScale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.3}):Play()
        flyTween:Play()
        flyTween.Completed:Connect(function()
            container:Destroy()
            if realCoinLabel then
                local uiScale = realCoinLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", realCoinLabel)
                TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Bounce), {Scale = 1.3}):Play()
                task.delay(0.1, function() TweenService:Create(uiScale, TweenInfo.new(0.1), {Scale = 1}):Play() end)
            end
            if onCompleteCallback then onCompleteCallback() end
        end)
    end)
end

-- [🌟 UI模块 3：UI渲染 3D 模型通用方案]
function UIEffectUtil.RenderToViewport(viewport, modelName, itemType, mutationLevel)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    for _, c in pairs(viewport:GetChildren()) do if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end end
    viewport.Ambient = Color3.fromRGB(200, 200, 200); viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
    if itemType == "Seed" then targetModel = itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    elseif itemType == "Tool" or itemType == "System" then targetModel = itemModelsFolder:FindFirstChild(modelName) end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end end
        if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
        
        if itemType == "Plant" then EffectUtil.ApplyMutationEffects(displayModel, mutationLevel) end

        if displayModel.PrimaryPart then displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0)) end
        displayModel.Parent = viewport
        local camera = Instance.new("Camera"); camera.FieldOfView = 40; viewport.CurrentCamera = camera; camera.Parent = viewport
        local cframe, size = displayModel:GetBoundingBox()
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end 
        camera.CFrame = CFrame.lookAt(Vector3.new(cframe.Position.X, cframe.Position.Y + size.Y/6, cframe.Position.Z + maxDim * 1.5 + 1), cframe.Position)
    end
end

return UIEffectUtil
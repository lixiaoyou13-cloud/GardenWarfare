-- src/client/Utils/UIEffectUtil.luau
local UIEffectUtil = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))
local NumberFormatUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormatUtil"))
local currentTipId = 0 -- 内部变量，用于追踪当前的提示任务

-- 算法：数字智能精简 (例如 1500 -> 1.5K, 1000 -> 1K)
local function FormatNumber(num)
    return NumberFormatUtil.FormatNumber(num)
end
UIEffectUtil.FormatNumber = FormatNumber

-- UI模块 1：数字平滑滚动
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

        -- 应用智能精简算法
        intValue.Changed:Connect(function(val)
            textLabel.Text = prefix .. FormatNumber(val)
        end)
    end
    TweenService:Create(intValue, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = newValue}):Play()
end

-- UI模块 2：金币飞天特效 (已巨大化)
function UIEffectUtil.Play2DCollectEffect(amount, onCompleteCallback, displayText)
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = playerGui:FindFirstChild("CoinCollectGui") or Instance.new("ScreenGui")
    screenGui.ResetOnSpawn = false
    screenGui.Name = "CoinCollectGui"; screenGui.DisplayOrder = 100; screenGui.Parent = playerGui

    local startX = math.random(30, 70) / 100; local startY = math.random(20, 50) / 100
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1; container.Position = UDim2.new(startX, 0, startY, 0)

    -- 提升体积：整体容器放大近一倍
    container.Size = UDim2.new(0, 160, 0, 60);
    container.AnchorPoint = Vector2.new(0.5, 0.5); container.Parent = screenGui

    local icon = Instance.new("ImageLabel")
    icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://102426033120992"

    -- 图片标签巨大化(原本 35x35，现在 60x60)
    icon.Size = UDim2.new(0, 60, 0, 60);
    icon.Position = UDim2.new(0, 0, 0.5, 0); icon.AnchorPoint = Vector2.new(0, 0.5); icon.Parent = container

    local textLabel = Instance.new("TextLabel")
    textLabel.BackgroundTransparency = 1;

    -- 浮空数值也应用 K/M 进制缩写
    textLabel.Text = displayText or ("+" .. FormatNumber(amount));

    textLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    textLabel.TextStrokeColor3 = Color3.fromRGB(150, 80, 0); textLabel.TextStrokeTransparency = 0; textLabel.Font = Enum.Font.GothamBlack; textLabel.TextScaled = true

    -- 数值文本框也跟着放大
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

-- UI模块 3：UI渲染 3D 模型通用方案
function UIEffectUtil.RenderToViewport(viewport, modelName, itemType, mutationLevel)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    for _, c in pairs(viewport:GetChildren()) do if c:IsA("Model") or c:IsA("BasePart") or c:IsA("Camera") then c:Destroy() end end
    viewport.Ambient = Color3.fromRGB(200, 200, 200); viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
   if itemType == "Seed" then
        -- 渲染时间同样查找特定的种子模型，兜底使用默认模型
        targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Seed") or itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    elseif itemType == "Chest" then
        local chestFolder = ReplicatedStorage:FindFirstChild("Chest")
        targetModel = chestFolder and chestFolder:FindFirstChild(modelName)
    elseif itemType == "Item" then
        targetModel = itemModelsFolder:FindFirstChild(modelName)
    elseif itemType == "Tool" or itemType == "System" then targetModel = itemModelsFolder:FindFirstChild(modelName) end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end end
        if displayModel:IsA("Model") then
            if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
            if itemType == "Plant" then EffectUtil.ApplyMutationEffects(displayModel, mutationLevel) end
            if displayModel.PrimaryPart then displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0)) end
        elseif displayModel:IsA("BasePart") then
            displayModel.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0)
        end
        displayModel.Parent = viewport
        local camera = Instance.new("Camera"); camera.FieldOfView = 40; viewport.CurrentCamera = camera; camera.Parent = viewport
        local cframe, size
        if displayModel:IsA("Model") then
            cframe, size = displayModel:GetBoundingBox()
        else
            cframe, size = displayModel.CFrame, displayModel.Size
        end
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end
        local cameraDistance = maxDim * 1.5 + 1
        if itemType == "Chest" then
            cameraDistance = maxDim * 2.6 + 2
        end
        camera.CFrame = CFrame.lookAt(Vector3.new(cframe.Position.X, cframe.Position.Y + size.Y/6, cframe.Position.Z + cameraDistance), cframe.Position)
    end
end
local Lighting = game:GetService("Lighting")
local blurEffect = Lighting:FindFirstChild("UIBlur") or Instance.new("BlurEffect")
blurEffect.Name = "UIBlur"
blurEffect.Size = 0
blurEffect.Parent = Lighting

UIEffectUtil.BlurRequests = 0 -- 智能记录当前打开了几个全屏UI，防止冲突

function UIEffectUtil.SetScreenBlur(enabled, overlayFrame)
    if enabled then
        UIEffectUtil.BlurRequests = UIEffectUtil.BlurRequests + 1
    else
        UIEffectUtil.BlurRequests = math.max(0, UIEffectUtil.BlurRequests - 1)
    end

    -- 只要还有一个全屏UI开着，就保持虚化
    local targetBlur = (UIEffectUtil.BlurRequests > 0) and 20 or 0
    local targetTrans = enabled and 0.5 or 1
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

    TweenService:Create(blurEffect, tweenInfo, {Size = targetBlur}):Play()

    if overlayFrame then
        if enabled then overlayFrame.Visible = true end
        local tw = TweenService:Create(overlayFrame, tweenInfo, {BackgroundTransparency = targetTrans})
        tw:Play()
        -- 渐变后如果完全透明，则隐藏，防止阻挡点击
        if not enabled then
            tw.Completed:Once(function()
                if targetTrans == 1 then overlayFrame.Visible = false end
            end)
        end
    end
end

local function forceHideOverlay(overlayFrame)
    if typeof(overlayFrame) ~= "Instance" or not overlayFrame:IsA("GuiObject") then
        return
    end

    overlayFrame.BackgroundTransparency = 1
    overlayFrame.Visible = false
    overlayFrame.Active = false
end

function UIEffectUtil.ForceClearScreenBlur(...)
    UIEffectUtil.BlurRequests = 0
    blurEffect.Size = 0
    TweenService:Create(blurEffect, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = 0}):Play()

    local overlays = {...}
    if #overlays == 1 and type(overlays[1]) == "table" and typeof(overlays[1]) ~= "Instance" then
        overlays = overlays[1]
    end

    for _, overlayFrame in ipairs(overlays) do
        forceHideOverlay(overlayFrame)
    end
end

-- 封装提示模块：层级已提升至最高级 9999
function UIEffectUtil.ShowTip(message: string)
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- 1. 改进：确保提示信息在独立的最高层级 Gui 中
    local topMsgGui = playerGui:FindFirstChild("TopMessageGui")
    if not topMsgGui then
        topMsgGui = Instance.new("ScreenGui")
        topMsgGui.Name = "TopMessageGui"
        topMsgGui.ResetOnSpawn = false
        topMsgGui.DisplayOrder = 9999 -- 设置为极高数值，确保盖过所有 UI 和礼花
        topMsgGui.Parent = playerGui
    end

    -- 2. 获取原始的 TipInfo 节点击并迁移（如果是第一次数调用）
    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local tipInfo = topMsgGui:FindFirstChild("TipInfo")

    if not tipInfo then
        -- 从原有位置克隆或移动过来
        local originalTip = playProperty:FindFirstChild("TipInfo")
        if originalTip then
            tipInfo = originalTip -- 直接移动节点击，保持原有的 UI 样式
            tipInfo.Parent = topMsgGui
        else
            -- 兜底：如果找不到原始节点击，警告并返回
            warn("UIEffectUtil: original TipInfo node not found")
            return
        end
    end

    local tipLabel = tipInfo:WaitForChild("TextLabel")

    -- 3. 逻辑处理
    currentTipId += 1
    local myTipId = currentTipId

    -- /样式
    -- 1. 文字居中显示
    tipLabel.TextXAlignment = Enum.TextXAlignment.Center
    tipLabel.TextYAlignment = Enum.TextYAlignment.Center
    tipInfo.AnchorPoint = Vector2.new(0.5, 0.5) -- 确保整个提示框的锚点在中心

    -- 2. 稍微向上一点击 (Y轴 0.35 表示在屏幕高度的 35% 处。数字越小越靠上，你也可以改成 0.3 试试)
    tipInfo.Position = UDim2.new(0.5, 0, 0.2, 0)

    -- 3. 文字颜色改为绿色 (使用亮绿色，防止跟黑色背景融为一体)
    tipLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
    -- /

    -- 初始化状态
    tipLabel.Text = message
    tipInfo.Visible = true
    tipLabel.TextTransparency = 0

    -- 停留并消失
    task.delay(1.5, function()
        if currentTipId == myTipId then
            local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)

            local fadeOutLabel = TweenService:Create(tipLabel, tweenInfo, {TextTransparency = 1})
            local fadeOutBg = TweenService:Create(tipInfo, tweenInfo, {BackgroundTransparency = 1})

            fadeOutLabel:Play()
            fadeOutBg:Play()

            fadeOutLabel.Completed:Connect(function()
                if currentTipId == myTipId then
                    tipInfo.Visible = false
                end
            end)
        end
    end)
end

function UIEffectUtil.PlayConfettiEffect()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- 创建一个专属的 UI 层放礼花
    local confettiGui = Instance.new("ScreenGui")
    confettiGui.Name = "ConfettiGui"
    confettiGui.ResetOnSpawn = false
    confettiGui.DisplayOrder = 1000 -- 确保在最上层
    confettiGui.Parent = playerGui

    -- 礼花的颜色库 (红点, 黄, 绿, 蓝, 紫, 粉, 橙)
    local colors = {
        Color3.fromRGB(255, 87, 34),
        Color3.fromRGB(255, 235, 59),
        Color3.fromRGB(76, 175, 80),
        Color3.fromRGB(33, 150, 243),
        Color3.fromRGB(156, 39, 176),
        Color3.fromRGB(233, 30, 99),
        Color3.fromRGB(255, 152, 0)
    }

    local particleCount = 80 -- 礼花数量，设置多一些感觉更新饱满

    for i = 1, particleCount do
        local isRibbon = math.random() > 0.5 -- 一半是方格，一半是飘带
        local particle = Instance.new("Frame")
        particle.BackgroundColor3 = colors[math.random(1, #colors)]
        particle.BorderSizePixel = 0
        particle.AnchorPoint = Vector2.new(0.5, 0.5)

        if isRibbon then
            particle.Size = UDim2.new(0, math.random(4, 8), 0, math.random(15, 30)) -- 长条飘带
        else
            particle.Size = UDim2.new(0, math.random(8, 14), 0, math.random(8, 14)) -- 方块
        end

        -- 初始位置：屏幕底部中央偏下的位置 (模拟从玩家手中或底部喷出)
        particle.Position = UDim2.new(math.random(40, 60) / 100, 0, 1.1, 0)
        particle.Rotation = math.random(0, 360)
        particle.Parent = confettiGui

        -- 计算喷射目标点击：向屏幕上方四周散开
        local explodeX = math.random(5, 95) / 100
        local explodeY = math.random(10, 60) / 100

        -- 阶段1：爆发喷射 (向上方快速飞出)
        local shootTween = TweenService:Create(particle, TweenInfo.new(
            math.random(40, 90) / 100,
            Enum.EasingStyle.Cubic,
            Enum.EasingDirection.Out
        ), {
            Position = UDim2.new(explodeX, 0, explodeY, 0),
            Rotation = particle.Rotation + math.random(-360, 360) -- 飞行时间翻滚动
        })

        -- 阶段2：受重力缓存慢飘落
        local fallTween = TweenService:Create(particle, TweenInfo.new(
            math.random(150, 300) / 100,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.In
        ), {
            Position = UDim2.new(explodeX + math.random(-15, 15) / 100, 0, 1.2, 0), -- 飘落时间带点击风吹的偏移
            Rotation = particle.Rotation + math.random(-720, 720),
            BackgroundTransparency = 1 -- 落地过程逐渐变透明
        })

        shootTween:Play()
        -- 喷射后自转动衔接飘落
        shootTween.Completed:Connect(function()
            fallTween:Play()
        end)
    end

    -- 4 秒后自转动清理整个礼花 UI，防止内存泄漏
    task.delay(4, function()
        confettiGui:Destroy()
    end)
end


-- 监听全局获得道具特效：平缓长震动 + 提示 + 礼花
function UIEffectUtil.PlayObtainEffect(message, playFullEffect)
    if playFullEffect == nil then
        playFullEffect = true
    end

    if playFullEffect then
        UIEffectUtil.PlayConfettiEffect()

        local player = Players.LocalPlayer
        local char = player.Character
        local hum = char and char:FindFirstChild("Humanoid")

        if hum then
            task.spawn(function()
                local originalOffset = hum.CameraOffset
                for _ = 1, 30 do
                    local rx = (math.random() - 0.5) * 0.3
                    local ry = (math.random() - 0.5) * 0.3
                    local rz = (math.random() - 0.5) * 0.3

                    hum.CameraOffset = originalOffset + Vector3.new(rx, ry, rz)
                    task.wait(0.02)
                end
                hum.CameraOffset = originalOffset
            end)
        end
    end

    UIEffectUtil.ShowTip(message)
end

task.spawn(function()
    local playObtainEffectRE = ReplicatedStorage:WaitForChild("PlayObtainEffectRE")

    playObtainEffectRE.OnClientEvent:Connect(function(message, playFullEffect)
        UIEffectUtil.PlayObtainEffect(message, playFullEffect)
    end)
end)
return UIEffectUtil

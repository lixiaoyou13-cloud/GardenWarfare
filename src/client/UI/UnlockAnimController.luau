-- src/client/UI/UnlockAnimController.luau
local UnlockAnimController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RunService = game:GetService("RunService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- 创建 3D ViewportFrame 并自转动适配模型大小与旋转
local function CreateViewportForModel(plantId, parentFrame)
    -- 1. 创建 ViewportFrame
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "ModelViewport"
    viewport.Size = UDim2.new(1, 0, 1, 0)
    viewport.Position = UDim2.new(0.5, 0, 0.5, 0)
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.BackgroundTransparency = 1
    viewport.Parent = parentFrame

    -- 2. 从 ReplicatedStorage 获取真实模型
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return viewport end

    -- 按植物配置里的 ModelName 查找模型，兼容独立植物临时复用其他模型。
    local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
    local configuredModelName = (plantDetail and plantDetail.ModelName) or plantId
    local modelTemplate = itemModelsFolder:FindFirstChild(configuredModelName .. "_Plant")
        or itemModelsFolder:FindFirstChild(configuredModelName)
        or itemModelsFolder:FindFirstChild(plantId .. "_Plant")
        or itemModelsFolder:FindFirstChild(plantId)

    if not modelTemplate then
        warn("ViewportFrame display model not found: " .. tostring(plantId))
        return viewport
    end

    -- 3. 克隆模型
    local displayModel = modelTemplate:Clone()

    -- 清理可能影响 UI 渲染的杂物（比如特效、声音、脚本）
    for _, child in ipairs(displayModel:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Sound") then
            child:Destroy()
        end
    end
    displayModel.Parent = viewport

    -- 4. 设置专属摄像机
    local camera = Instance.new("Camera")
    viewport.CurrentCamera = camera
    camera.Parent = viewport

    -- 5. 计算模型的碰撞箱，自转动镜头距离，防止模型太大出框或太小看不见
    local cframe, size = displayModel:GetBoundingBox()
    local maxDim = math.max(size.X, size.Y, size.Z)
    local cameraDistance = maxDim * 1.5 -- 1.5 倍的距离刚刚好

    -- 将相机摆放在模型正前方偏上一点击，看向模型中心
    local cameraPos = cframe.Position + Vector3.new(0, maxDim * 0.2, cameraDistance)
    camera.CFrame = CFrame.lookAt(cameraPos, cframe.Position)

    -- 6. 开启自转效果
    local connection
    connection = RunService.RenderStepped:Connect(function()
        -- 如果 UI 被关闭（ViewportFrame 被销毁），立刻停止旋转循环，防止内存泄漏
        if not viewport or not viewport.Parent then
            if connection then connection:Disconnect() end
            return
        end
        -- 每帧旋转一点击点击
        displayModel:PivotTo(displayModel:GetPivot() * CFrame.Angles(0, math.rad(1), 0))
    end)

    return viewport
end

function UnlockAnimController.PlayUnlockAnim(plantId, itemName, qualityColor, subText)
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TempUnlockUI"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 9999
    screenGui.Parent = playerGui

    -- 回归正的长方形与水平位移
    local horizontalBand = Instance.new("Frame")
    horizontalBand.Name = "HorizontalBand"
    horizontalBand.AnchorPoint = Vector2.new(0.5, 0.5)

    -- 初始位置：屏幕左侧外 (水平居中对齐 0.5 Y轴)
    horizontalBand.Position = UDim2.new(-1, 0, 0.5, 0)
    horizontalBand.Size = UDim2.new(1.5, 0, 0.5, 0) -- 恢复标签准厚度，宽度略长
    horizontalBand.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    horizontalBand.BackgroundTransparency = 0.3
    horizontalBand.Rotation = 0 -- 保持水平，不倾斜
    horizontalBand.BorderSizePixel = 0
    horizontalBand.Parent = screenGui

    local contentContainer = Instance.new("Frame")
    contentContainer.AnchorPoint = Vector2.new(0.5, 0.5)
    contentContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
    contentContainer.Size = UDim2.new(0, 500, 0, 250)
    contentContainer.BackgroundTransparency = 1
    contentContainer.Rotation = 0 -- 容器同样不旋转
    contentContainer.Parent = horizontalBand

    -- 物品图片标签
    local itemIcon = CreateViewportForModel(plantId, contentContainer)
    itemIcon.Position = UDim2.new(0.5, 0, 0.35, 0)
    itemIcon.Size = UDim2.new(0, 0, 0, 0) -- 初始大小为0，靠弹出的Tween动画

    -- 物品名称
    local nameLabel = Instance.new("TextLabel")
    nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    nameLabel.Position = UDim2.new(0.5, 0, 0.75, 0)
    nameLabel.Size = UDim2.new(1, 0, 0, 50)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.Text = itemName or "New Plant"
    nameLabel.TextColor3 = qualityColor or Color3.fromRGB(255, 255, 255)
    nameLabel.TextSize = 40
    nameLabel.TextTransparency = 1
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Parent = contentContainer

    -- 副标签题
    local subLabel = Instance.new("TextLabel")
    subLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    subLabel.Position = UDim2.new(0.5, 0, 0.9, 0)
    subLabel.Size = UDim2.new(1, 0, 0, 30)
    subLabel.BackgroundTransparency = 1
    subLabel.Font = Enum.Font.SourceSansBold
    subLabel.Text = subText or "Collection Updated"
    subLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    subLabel.TextSize = 26
    subLabel.TextTransparency = 1
    subLabel.Parent = contentContainer

    -- 动画定义
    -- 1. 从左向右切入屏幕中心
    local bandSlideIn = TweenService:Create(horizontalBand, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.5, 0)
    })

    -- 2. 继续向右滑出屏幕
    local bandSlideOut = TweenService:Create(horizontalBand, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Position = UDim2.new(2, 0, 0.5, 0)
    })

    local iconPop = TweenService:Create(itemIcon, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 180, 0, 180)
    })

    local function PlayShakeAnim()
        local shakeAngles = {10, -10, 7, -7, 4, -4, 0}
        for _, angle in ipairs(shakeAngles) do
            local shakeTween = TweenService:Create(itemIcon, TweenInfo.new(0.04, Enum.EasingStyle.Linear), { Rotation = angle })
            shakeTween:Play()
            shakeTween.Completed:Wait()
        end
    end

    local textFadeIn = TweenService:Create(nameLabel, TweenInfo.new(0.35), { TextTransparency = 0 })
    local subFadeIn = TweenService:Create(subLabel, TweenInfo.new(0.35), { TextTransparency = 0 })

    task.spawn(function()
        -- 第 1 幕：横条从左侧滑入
        bandSlideIn:Play()
        bandSlideIn.Completed:Wait()

        -- 第 2 幕：内容弹出并轻微抖动
        iconPop:Play()
        iconPop.Completed:Wait()
        PlayShakeAnim()

        -- 第 3 幕：文字显示
        textFadeIn:Play()
        subFadeIn:Play()

        -- 第 4 幕：定格
        task.wait(2.5)

        -- 第 5 幕：内容先消失，让路给滑出动画
        TweenService:Create(itemIcon, TweenInfo.new(0.2), { Size = UDim2.new(0, 0, 0, 0) }):Play()
        TweenService:Create(nameLabel, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
        TweenService:Create(subLabel, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
        task.wait(0.2)

        -- 第 6 幕：横条继续向右滑出销毁
        bandSlideOut:Play()
        bandSlideOut.Completed:Wait()

        screenGui:Destroy()
    end)
end

function UnlockAnimController.Init()
    local playUnlockAnimRE = ReplicatedStorage:WaitForChild("PlayUnlockAnimRE")
    playUnlockAnimRE.OnClientEvent:Connect(function(plantId, mutationLevel)
        local plantDetail = ItemConfig.Plants[plantId]
        if not plantDetail then return end

        local mutName = ItemConfig.MutationName[mutationLevel] or "Normal"
        local itemName = mutName .. " - " .. (plantDetail.Name or plantId)
        local iconId = plantDetail.IconId or ""

        local qualityColor = Color3.fromRGB(255, 255, 255)
        if mutationLevel == 2 then qualityColor = Color3.fromRGB(85, 170, 255)
        elseif mutationLevel == 3 then qualityColor = Color3.fromRGB(170, 85, 255)
        elseif mutationLevel == 4 then qualityColor = Color3.fromRGB(255, 170, 0) end

        local subText = mutationLevel > 1 and "Rare Mutation Discovered!" or "New Species Discovered!"
        UnlockAnimController.PlayUnlockAnim(plantId, itemName, qualityColor, subText)
    end)
end

return UnlockAnimController

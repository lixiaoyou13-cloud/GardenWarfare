-- src/client/Services/StealablePointerUIController.luau
local StealablePointerUIController = {}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local POINTER_UPDATE_INTERVAL = 0.2

function StealablePointerUIController.Init()
    local player = Players.LocalPlayer

    -- 1. 创建 UI 容器
    local pointerGui = Instance.new("ScreenGui")
    pointerGui.Name = "StealablePointerGui"
    pointerGui.ResetOnSpawn = false
    pointerGui.DisplayOrder = 104 -- 略低于防偷警报
    pointerGui.Parent = player:WaitForChild("PlayerGui")

    -- 用于存储当前屏幕上所有高品质植物的 UI 状态
    local activeUIs = {}

    -- 2. 雷达追踪算法
    task.spawn(function()
        while pointerGui.Parent do
        local camera = Workspace.CurrentCamera
            if not camera then
                task.wait(POINTER_UPDATE_INTERVAL)
                continue
            end

        -- 寻找场景中被打上 "可偷取" 标签的高级植物
        local stealablePlants = CollectionService:GetTagged("StealableHighQuality")

        -- 标签记本帧是否被处理
        for _, uiData in pairs(activeUIs) do
            uiData.updated = false
        end

        for _, plant in ipairs(stealablePlants) do
            -- 判断：必须是别人的植物，才能显示"可偷取"
            if plant:GetAttribute("OwnerId") ~= player.UserId and plant.PrimaryPart then

                -- 如果还没有为这颗植物生成 UI，则动态生成
                local uiData = activeUIs[plant]
                if not uiData then
                    local container = Instance.new("Frame")
                    container.Size = UDim2.new(0, 80, 0, 80)
                    container.BackgroundTransparency = 1
                    container.AnchorPoint = Vector2.new(0.5, 0.5)
                    container.Parent = pointerGui

                    -- 金色指示箭头
                    local arrow = Instance.new("ImageLabel")
                    arrow.Size = UDim2.new(0, 50, 0, 50)
                    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
                    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
                    arrow.BackgroundTransparency = 1
                    arrow.Image = "rbxassetid://3145534143"
                    arrow.ImageColor3 = Color3.fromRGB(255, 215, 0) -- 金色
                    arrow.Parent = container

                    -- "可偷取" 文本
                    local label = Instance.new("TextLabel")
                    label.Size = UDim2.new(1.5, 0, 0.5, 0)
                    label.Position = UDim2.new(0.5, 0, 0.5, 0)
                    label.AnchorPoint = Vector2.new(0.5, 0.5)
                    label.BackgroundTransparency = 1
                    label.Text = "Stealable"
                    label.TextColor3 = Color3.fromRGB(255, 215, 0) -- 金色
                    label.Font = Enum.Font.GothamBlack
                    label.TextScaled = true
                    label.Parent = container

                    local textStroke = Instance.new("UIStroke")
                    textStroke.Color = Color3.fromRGB(0, 0, 0)
                    textStroke.Thickness = 3
                    textStroke.Parent = label

                    -- 呼吸缩放动画
                    local uiScale = Instance.new("UIScale")
                    uiScale.Parent = container
                    local scaleTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
                    TweenService:Create(uiScale, scaleTweenInfo, {Scale = 1.15}):Play()

                    uiData = { container = container, arrow = arrow, label = label }
                    activeUIs[plant] = uiData
                end

                uiData.updated = true

                -- 贴边雷达运算
                local targetPos = plant.PrimaryPart.Position + Vector3.new(0, 5, 0)
                local vector, onScreen = camera:WorldToViewportPoint(targetPos)
                local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

                if onScreen then
                    -- 在屏幕内：直接显示在植物头上，不显示箭头
                    uiData.container.Position = UDim2.new(0, vector.X, 0, vector.Y)
                    uiData.arrow.Visible = false
                    uiData.label.Position = UDim2.new(0.5, 0, 0.5, 0)
                else
                    -- 在屏幕外：开启边缘贴边计算
                    uiData.arrow.Visible = true
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

                    uiData.container.Position = UDim2.new(0, center.X + screenX, 0, center.Y + screenY)
                    uiData.arrow.Rotation = math.deg(angle)
                    uiData.label.Position = UDim2.new(0.5, 0, 0.5, -20)
                end
            end
        end

        -- 3. 销毁已经失效的 UI (例如植物已经被偷走销毁、被收获)
        for plant, uiData in pairs(activeUIs) do
            if not uiData.updated or not plant.Parent then
                uiData.container:Destroy()
                activeUIs[plant] = nil
            end
        end
            task.wait(POINTER_UPDATE_INTERVAL)
        end
    end)

    print("Client: StealablePointerUIController loaded; treasure radar active.")
end

return StealablePointerUIController

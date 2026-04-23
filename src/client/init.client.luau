-- src/client/init.client.luau
print("客户端启动：沉浸式 UI 系统（层级适配修复版）激活...")

local InventoryController = require(script.UI.InventoryController)
local HotbarController = require(script.UI.HotbarController) 
local ShopController = require(script.UI.ShopController)
local CoinDropController = require(script.Services.CoinDropController)
local PlantUIController = require(script.Services.PlantUIController)
local HighlightController = require(script.Services.HighlightController)
local PlantHoverController = require(script.UI.PlantHoverController)
local ToolController = require(script.Services.ToolController)
local EncyclopediaController = require(script.UI.EncyclopediaController)
-- [🌟 已经删除了 BattleResultController]
local UnlockAnimController = require(script.UI.UnlockAnimController)

local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

task.spawn(function()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")

    basicGui:WaitForChild("InventoryGui")
    basicGui:WaitForChild("ShopGui")
    basicGui:WaitForChild("Codex")
    basicGui:WaitForChild("PlayProperty")
    
    local TWEEN_TIME = 0.4
    local POS_CENTER = UDim2.new(0.5, 0, 0.5, 0)
    local POS_BOTTOM = UDim2.new(0.5, 0, 1.5, 0)

    local function applyGlobalButtonEffect(button)
        if button:IsA("TextButton") or button:IsA("ImageButton") then
            if button:GetAttribute("HoverAnimBound") then return end
            button:SetAttribute("HoverAnimBound", true)
            button.AutoButtonColor = false

            if (button.AnchorPoint - Vector2.new(0.5, 0.5)).Magnitude > 0.01 then
                local oldAnchor = button.AnchorPoint
                local size = button.Size
                button.AnchorPoint = Vector2.new(0.5, 0.5)
                button.Position = UDim2.new(
                    button.Position.X.Scale + (size.X.Scale * (0.5 - oldAnchor.X)),
                    button.Position.X.Offset + (size.X.Offset * (0.5 - oldAnchor.X)),
                    button.Position.Y.Scale + (size.Y.Scale * (0.5 - oldAnchor.Y)),
                    button.Position.Y.Offset + (size.Y.Offset * (0.5 - oldAnchor.Y))
                )
            end

            local uiScale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", button)
            button.MouseEnter:Connect(function() TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Back), {Scale = 1.12}):Play() end)
            button.MouseLeave:Connect(function() TweenService:Create(uiScale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
            button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
            button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TweenInfo.new(0.1), {Scale = 1.12}):Play() end)
        end
    end

    for _, uiNode in pairs(playerGui:GetDescendants()) do applyGlobalButtonEffect(uiNode) end
    playerGui.DescendantAdded:Connect(applyGlobalButtonEffect)

    local blurEffect = Lighting:FindFirstChild("GlobalUIBlur") or Instance.new("BlurEffect", Lighting)
    blurEffect.Name = "GlobalUIBlur"
    blurEffect.Size = 0

    local camera = Workspace.CurrentCamera
    local defaultFOV = 70

    local overlayGui = Instance.new("ScreenGui")
    overlayGui.Name = "GlobalOverlayGui"
    overlayGui.DisplayOrder = 90
    overlayGui.IgnoreGuiInset = true 
    overlayGui.Parent = playerGui

    local bgOverlay = Instance.new("Frame")
    bgOverlay.Name = "BlackMask"
    bgOverlay.Size = UDim2.new(1, 0, 1, 0)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bgOverlay.BackgroundTransparency = 1
    bgOverlay.Active = true 
    bgOverlay.Visible = false
    bgOverlay.Parent = overlayGui

    local inventoryGui = basicGui:WaitForChild("InventoryGui")
    local shopGui = basicGui:WaitForChild("ShopGui")
    local codexGui = basicGui:WaitForChild("Codex")
    local playProperty = basicGui:WaitForChild("PlayProperty")

    local panels = {
        { gui = inventoryGui, frame = inventoryGui:WaitForChild("MainFrame", 5) },
        { gui = shopGui, frame = shopGui:FindFirstChild("ShopFrame") or shopGui:WaitForChild("MainFrame", 5) },
        { gui = codexGui, frame = codexGui:WaitForChild("MainFrame", 5) } 
    }

    local isAnyOpen = false

    local function setBackgroundEffects(enabled)
        if enabled then
            bgOverlay.Visible = true
            if playProperty:IsA("ScreenGui") then playProperty.DisplayOrder = 1 end
            TweenService:Create(bgOverlay, TweenInfo.new(TWEEN_TIME), {BackgroundTransparency = 0.8}):Play()
            TweenService:Create(blurEffect, TweenInfo.new(TWEEN_TIME), {Size = 24}):Play()
            TweenService:Create(camera, TweenInfo.new(TWEEN_TIME), {FieldOfView = 60}):Play()
        else
            if playProperty:IsA("ScreenGui") then playProperty.DisplayOrder = 50 end
            TweenService:Create(bgOverlay, TweenInfo.new(TWEEN_TIME), {BackgroundTransparency = 1}):Play()
            TweenService:Create(blurEffect, TweenInfo.new(TWEEN_TIME), {Size = 0}):Play()
            TweenService:Create(camera, TweenInfo.new(TWEEN_TIME), {FieldOfView = defaultFOV}):Play()
            task.delay(TWEEN_TIME, function() 
                if not isAnyOpen then bgOverlay.Visible = false end 
            end)
        end
    end

    local function initiateClose(p)
        if not p.gui.Enabled then return end
        if p.frame then
            local tween = TweenService:Create(p.frame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = POS_BOTTOM})
            tween:Play()
            tween.Completed:Wait()
        end
        p.gui.Enabled = false
        local stillOpen = false
        for _, item in ipairs(panels) do 
            if item.gui.Enabled then 
                stillOpen = true 
                break 
            end 
        end
        if not stillOpen then
            isAnyOpen = false
            setBackgroundEffects(false)
        end
    end

    for _, p in ipairs(panels) do
        p.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if p.gui.Enabled then
                for _, other in ipairs(panels) do
                    if other.gui ~= p.gui and other.gui.Enabled then other.gui.Enabled = false end
                end
                
                p.gui.DisplayOrder = 100
                isAnyOpen = true
                setBackgroundEffects(true)

                if p.frame then
                    p.frame.AnchorPoint = Vector2.new(0.5, 0.5)
                    p.frame.Position = POS_BOTTOM
                    TweenService:Create(p.frame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = POS_CENTER}):Play()
                end

                local closeBtn = p.frame and (
                    p.frame:FindFirstChild("CloseBtn", true) or 
                    p.frame:FindFirstChild("CloseButton", true) or 
                    p.frame:FindFirstChild("Close", true)
                )
                if closeBtn and not closeBtn:GetAttribute("CustomCloseBound") then
                    closeBtn:SetAttribute("CustomCloseBound", true)
                    closeBtn.Activated:Connect(function() initiateClose(p) end)
                end
            else
                local stillOpen = false
                for _, item in ipairs(panels) do 
                    if item.gui.Enabled then 
                        stillOpen = true 
                        break 
                    end 
                end
                if not stillOpen and isAnyOpen then
                    isAnyOpen = false
                    setBackgroundEffects(false)
                end
            end
        end)
    end

    -- ==========================================
    -- [🌟 系统三：战斗控制逻辑]
    -- ==========================================
    local startBattleBtn = playProperty:WaitForChild("StartBattle", 5)
    local inBattleFrame = playProperty:WaitForChild("InBattle", 5)
    local endBattleBtn = inBattleFrame and inBattleFrame:WaitForChild("EndBattle", 5)
    local levelText = inBattleFrame and inBattleFrame:WaitForChild("LevelText", 5)
    local btnSpeed1_5 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*1.5", 5)
    local btnSpeed4 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*4", 5)
    local btnAutoBattle = inBattleFrame and inBattleFrame:WaitForChild("AutoBattle", 5)

    if startBattleBtn and inBattleFrame then
        startBattleBtn.Visible = true
        inBattleFrame.Visible = false

        local autoRed = ColorSequence.new(Color3.fromRGB(249, 0, 0), Color3.fromRGB(180, 0, 0))
        local autoGreen = ColorSequence.new(Color3.fromRGB(90, 255, 90), Color3.fromRGB(0, 180, 0))

        local autoLabel = btnAutoBattle:FindFirstChild("TextLabel")
        local autoGrad = btnAutoBattle:FindFirstChild("UIGradient")
        
        player:SetAttribute("AutoBattle", false)
        if autoGrad then autoGrad.Color = autoRed end

        startBattleBtn.MouseButton1Click:Connect(function()
            ReplicatedStorage:WaitForChild("StartBattleRE"):FireServer()
        end)

        if endBattleBtn then
            endBattleBtn.MouseButton1Click:Connect(function()
                ReplicatedStorage:WaitForChild("EndBattleRE"):FireServer()
            end)
        end

        btnAutoBattle.MouseButton1Click:Connect(function()
            local isAuto = not player:GetAttribute("AutoBattle")
            player:SetAttribute("AutoBattle", isAuto)
            if autoLabel then autoLabel.Text = isAuto and "自动战斗(开启)" or "自动战斗(关闭)" end
            if autoGrad then autoGrad.Color = isAuto and autoGreen or autoRed end
            if isAuto and startBattleBtn.Visible then ReplicatedStorage.StartBattleRE:FireServer() end
        end)

        local setSpeedRE = ReplicatedStorage:WaitForChild("SetSpeedRE")
        local currentSpeed = 1
        local grad4RotationConn = nil

        local function updateSpeedUI(activeSpeed)
            currentSpeed = activeSpeed
            local grad4 = btnSpeed4:FindFirstChild("UIGradient")
            if grad4RotationConn then grad4RotationConn:Disconnect(); grad4RotationConn = nil end
            if grad4 then grad4.Rotation = 0 end
            if activeSpeed == 4 and grad4 then
                local currentAngle = 0
                grad4RotationConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
                    currentAngle = (currentAngle + dt * 120) % 360
                    grad4.Rotation = currentAngle
                end)
            end
        end

        btnSpeed1_5.MouseButton1Click:Connect(function() setSpeedRE:FireServer(currentSpeed == 1.5 and 1 or 1.5) end)
        btnSpeed4.MouseButton1Click:Connect(function() setSpeedRE:FireServer(currentSpeed == 4 and 1 or 4) end)
        setSpeedRE.OnClientEvent:Connect(updateSpeedUI)

        ReplicatedStorage:WaitForChild("SyncBattleUI_RE").OnClientEvent:Connect(function(isActive, currentLevelId)
            if isActive then
                startBattleBtn.Visible = false
                inBattleFrame.Visible = true
                levelText.Text = "第 " .. currentLevelId .. " 关"
            else
                if player:GetAttribute("AutoBattle") then
                    levelText.Text = "正在重新开始..."
                else
                    startBattleBtn.Visible = true
                    inBattleFrame.Visible = false
                end
            end
        end)
    end
end)

InventoryController.Init()
HotbarController.Init()
ShopController.Init()
CoinDropController.Init()
PlantUIController.Init()
HighlightController.Init()
PlantHoverController.Init()
ToolController.Init()
EncyclopediaController.Init()
-- [🌟 彻底删除了 BattleResultController.Init()]
UnlockAnimController.Init()
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
local UnlockAnimController = require(script.UI.UnlockAnimController)
local TutorialController = require(script.UI.TutorialController)
local EventUIManager = require(script.UI.EventUI.EventUIManager)

local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local AnalyticsRE = ReplicatedStorage:WaitForChild("AnalyticsRE")
local X2_SUN_GAME_PASS_ID = 1856661235
local localPlayer = game:GetService("Players").LocalPlayer
local initialCameraMaxZoomDistance = localPlayer.CameraMaxZoomDistance
localPlayer.CameraMaxZoomDistance = initialCameraMaxZoomDistance

local function restoreInitialCameraMaxZoomDistance()
    localPlayer.CameraMaxZoomDistance = initialCameraMaxZoomDistance
end

local function pullCameraUp()
    -- 必须稍微等待一下，确保 Roblox 的默认相机系统已经绑定到了玩家角色上
    task.wait(0.5) 
    
    -- 强行将相机拉远到 45 的距离
    localPlayer.CameraMinZoomDistance = 45
    localPlayer.CameraMaxZoomDistance = 45
    
    -- 给相机 0.1 秒的反应时间把镜头推出去，然后再解除最小距离限制；最大距离恢复到玩家进入游戏时的初始值
    task.wait(0.1)
    localPlayer.CameraMinZoomDistance = 0.5
    restoreInitialCameraMaxZoomDistance()
end

-- 监听玩家角色生成（每次进入游戏或死亡重生时都会触发）
localPlayer.CharacterAdded:Connect(function()
    pullCameraUp()
end)

-- 如果脚本运行的瞬间角色已经存在，直接执行一次
if localPlayer.Character then
    pullCameraUp()
end


task.spawn(function()
    local player = game:GetService("Players").LocalPlayer

    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    for _, gui in pairs(basicGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            gui.ResetOnSpawn = false
            print("已为 UI 锁定防重置保护: " .. gui.Name)
        end
    end

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
    overlayGui.ResetOnSpawn = false
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

    local x2SunBtn = playProperty:FindFirstChild("X2Sun")
    if x2SunBtn and not x2SunBtn:GetAttribute("IAPBound") then
        x2SunBtn:SetAttribute("IAPBound", true)
        local function refreshX2SunButton()
            local ownsPass = false
            pcall(function()
                ownsPass = MarketplaceService:UserOwnsGamePassAsync(player.UserId, X2_SUN_GAME_PASS_ID)
            end)
            x2SunBtn.Visible = not ownsPass
            x2SunBtn.Active = not ownsPass
        end

        refreshX2SunButton()
        x2SunBtn.Activated:Connect(function()
            MarketplaceService:PromptGamePassPurchase(player, X2_SUN_GAME_PASS_ID)
        end)

        MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, passId, wasPurchased)
            if purchasingPlayer == player and passId == X2_SUN_GAME_PASS_ID and wasPurchased then
                refreshX2SunButton()
            end
        end)
    end

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
                if p.gui == shopGui then
                    -- 生成一个简单的随机 SessionId 区分每一次打开商店的行为
                    local shopSessionId = "ShopSession_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                    player:SetAttribute("CurrentShopSessionId", shopSessionId)
                    -- 👇 【新增埋点】：商店漏斗第一步
                    AnalyticsRE:FireServer("Funnel", "Shop_Purchase_Flow", {StepIndex = 1, StepName = "Step_1_Open_Shop", SessionId = shopSessionId})
                end
                for _, other in ipairs(panels) do
                    if other.gui ~= p.gui and other.gui.Enabled then other.gui.Enabled = false end
                end
                
                p.gui.DisplayOrder = 100
                isAnyOpen = true
                setBackgroundEffects(true)

                if p.frame then
                    p.frame.AnchorPoint = Vector2.new(0.5, 0.5)
                    p.frame.Position = POS_BOTTOM
                    if p.gui.Name == "Codex" then
                        TweenService:Create(p.frame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0.4, 0)}):Play()
                    else
                        TweenService:Create(p.frame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = POS_CENTER}):Play()
                    end

                   
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
    local battleProgress = inBattleFrame and inBattleFrame:WaitForChild("Progress", 5)
    local currentTotalZombies = 0
    local currentZombiesDefeated = 0
    local battleProgressFill = nil

    local function setupBattleProgressBar()
        if not battleProgress then return end

        battleProgress.ClipsDescendants = true

        battleProgressFill = battleProgress:FindFirstChild("BattleProgressFill")
            or battleProgress:FindFirstChild("Fill", true)
            or battleProgress:FindFirstChild("BarFill", true)
            or battleProgress:FindFirstChild("ProgressFill", true)

        if not battleProgressFill then
            battleProgressFill = Instance.new("Frame")
            battleProgressFill.Name = "BattleProgressFill"
            battleProgressFill.AnchorPoint = Vector2.new(0, 0)
            battleProgressFill.Position = UDim2.new(0, 0, 0, 0)
            battleProgressFill.Size = UDim2.new(0, 0, 1, 0)
            battleProgressFill.BackgroundColor3 = Color3.fromRGB(90, 255, 90)
            battleProgressFill.BackgroundTransparency = 0.15
            battleProgressFill.BorderSizePixel = 0
            battleProgressFill.ZIndex = battleProgress.ZIndex + 1

            local fillGradient = Instance.new("UIGradient")
            fillGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 255, 120)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 190, 50)),
            })
            fillGradient.Parent = battleProgressFill

            battleProgressFill.Parent = battleProgress
        end
    end

    local function updateBattleProgress(defeated, totalZombies)
        if not battleProgress then return end
        setupBattleProgressBar()

        currentZombiesDefeated = defeated or currentZombiesDefeated or 0
        currentTotalZombies = totalZombies or currentTotalZombies or 0

        local displayTotal = math.max(currentTotalZombies, 0)
        local displayDefeated = math.clamp(currentZombiesDefeated, 0, displayTotal)
        local ratio = displayTotal > 0 and math.clamp(displayDefeated / displayTotal, 0, 1) or 0

        local fill = battleProgressFill
            or battleProgress:FindFirstChild("Fill", true)
            or battleProgress:FindFirstChild("BarFill", true)
            or battleProgress:FindFirstChild("ProgressFill", true)
        if fill and (fill:IsA("Frame") or fill:IsA("ImageLabel") or fill:IsA("ImageButton")) then
            fill.Size = UDim2.new(ratio, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
        end
    end

    if battleProgress then
        battleProgress.Visible = false
        updateBattleProgress(0, 0)
    end
    local btnSpeed1_5 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*1.5", 5)
    local btnSpeed4 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*4", 5)
    local btnAutoBattle = inBattleFrame and inBattleFrame:WaitForChild("AutoBattle", 5)
    local homeBtn = playProperty:WaitForChild("Home", 5)
    if homeBtn then
        homeBtn.MouseButton1Click:Connect(function()
            local character = player.Character
            if not character then return end
            
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not rootPart then return end

            local plotsFolder = Workspace:FindFirstChild("Plots")
            if plotsFolder then
                -- 遍历寻找属于本地玩家的基地
                for _, plot in ipairs(plotsFolder:GetChildren()) do
                    if plot:GetAttribute("OwnerId") == player.UserId then
                        -- 找到基地后，优先找出生点零件
                        local spawnPart = plot:FindFirstChild("SpawnPoint") or plot:FindFirstChild("SpawnLocation")
                        
                        -- 执行传送逻辑（与服务端的生成逻辑保持一致）
                        if spawnPart and spawnPart:IsA("BasePart") then
                            character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
                        else
                            character:PivotTo(plot:GetPivot() * CFrame.new(0, 5, 20))
                        end
                        
                        break
                    end
                end
            end
        end)
    end

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
                -- 【修复1】：玩家手动点击停止战斗时，强制OffAuto Battle状态
                if player:GetAttribute("AutoBattle") then
                    player:SetAttribute("AutoBattle", false)
                    
                    local autoLabel = btnAutoBattle:FindFirstChild("TextLabel")
                    local autoGrad = btnAutoBattle:FindFirstChild("UIGradient")
                    
                    if autoLabel then autoLabel.Text = "Auto Battle(Off)" end
                    if autoGrad then autoGrad.Color = ColorSequence.new(Color3.fromRGB(249, 0, 0), Color3.fromRGB(180, 0, 0)) end
                end

                ReplicatedStorage:WaitForChild("EndBattleRE"):FireServer()
            end)
        end

        btnAutoBattle.MouseButton1Click:Connect(function()
            local isAuto = not player:GetAttribute("AutoBattle")
            -- 👇 【新增埋点】
            if isAuto then
                AnalyticsRE:FireServer("Custom", "UI_Click_AutoBattle_On")
            end
            player:SetAttribute("AutoBattle", isAuto)
            if autoLabel then autoLabel.Text = isAuto and "Auto Battle(On)" or "Auto Battle(Off)" end
            if autoGrad then autoGrad.Color = isAuto and autoGreen or autoRed end
            if isAuto and startBattleBtn.Visible then ReplicatedStorage.StartBattleRE:FireServer() end
        end)

        local setSpeedRE = ReplicatedStorage:WaitForChild("SetSpeedRE")
        local currentSpeed = 1
        local grad4RotationConn = nil
        -- 获取文字组件
        local label1_5 = btnSpeed1_5:FindFirstChildWhichIsA("TextLabel")
        local label4 = btnSpeed4:FindFirstChildWhichIsA("TextLabel")

        local function updateSpeedUI(activeSpeed)
            currentSpeed = activeSpeed
            
            -- [🌟 仅修改 2 Speed文字]
            local is1_5 = (activeSpeed == 2)
            if label1_5 then 
                label1_5.Text = is1_5 and "Back 1 Speed" or "X2 Speed" 
            elseif btnSpeed1_5:IsA("TextLabel") or btnSpeed1_5:IsA("TextButton") then
                btnSpeed1_5.Text = is1_5 and "Back 1 Speed" or "X2 Speed" 
            end

            -- [🌟 仅修改 4 Speed文字]
            local is4 = (activeSpeed == 4)
            if label4 then 
                label4.Text = is4 and "Back 1 Speed" or "X4 Speed" 
            elseif btnSpeed4:IsA("TextLabel") or btnSpeed4:IsA("TextButton") then
                btnSpeed4.Text = is4 and "Back 1 Speed" or "X4 Speed" 
            end
            local grad4 = btnSpeed4:FindFirstChild("UIGradient")
            if grad4RotationConn then grad4RotationConn:Disconnect(); grad4RotationConn = nil end
            if grad4 then grad4.Rotation = 0 end
            if activeSpeed == 4 and grad4 then

                local currentAngle = 0
                grad4RotationConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
                    currentAngle = (currentAngle + dt * 120) % 360
                    grad4.Rotation = currentAngle
                end)
            else

            end
        end
        -- [🌟 新增：内购服务与你的通行证ID]
        local MarketplaceService = game:GetService("MarketplaceService")
        local SPEED_PASS_ID = 1811835638 -- ⚠️⚠️⚠️ 请把这串数字替换成你刚才复制的 Game Pass ID！

        btnSpeed1_5.MouseButton1Click:Connect(function() 
            AnalyticsRE:FireServer("Custom", "UI_Click_Speed_1_5")
            setSpeedRE:FireServer(currentSpeed == 2 and 1 or 2) 
        end)
        btnSpeed4.MouseButton1Click:Connect(function()
            AnalyticsRE:FireServer("Custom", "UI_Click_Speed_4")
            
            -- 检查玩家是否已经拥有该通行证
            local hasPass = false
            pcall(function()
                hasPass = MarketplaceService:UserOwnsGamePassAsync(player.UserId, SPEED_PASS_ID)
            end)

            if hasPass then
                -- 如果已经购买，正常切换倍速
                setSpeedRE:FireServer(currentSpeed == 4 and 1 or 4) 
            else
                -- 如果没有购买，在屏幕中央弹出 299 Robux 的购买确认框！
                MarketplaceService:PromptGamePassPurchase(player, SPEED_PASS_ID)
            end
        end)

        -- [🌟 新增：监听玩家付钱成功]
        MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, passId, wasPurchased)
            if purchasingPlayer == player and passId == SPEED_PASS_ID and wasPurchased then
                -- 购买成功后，直接帮玩家自动开启 4 倍速
                setSpeedRE:FireServer(4)
                
                -- 屏幕右下角弹一个原生的成功提示框
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "🎉 Success!",
                        Text = "4X Speed is now Unlocked!",
                        Duration = 4,
                    })
                end)
            end
        end)

        setSpeedRE.OnClientEvent:Connect(updateSpeedUI)
        ReplicatedStorage:WaitForChild("SyncBattleUI_RE").OnClientEvent:Connect(function(isActive, currentLevelId, totalZombies, zombiesDefeated)
            if isActive then
                startBattleBtn.Visible = false
                inBattleFrame.Visible = true
                if battleProgress then battleProgress.Visible = true end
                updateBattleProgress(zombiesDefeated or 0, totalZombies or currentTotalZombies)
                
                if levelText then levelText.Text = "Level " .. currentLevelId end 
                
            else
                if battleProgress then
                    battleProgress.Visible = false
                    updateBattleProgress(0, 0)
                end

                -- 战斗结束逻辑保持不变...
                if player:GetAttribute("AutoBattle") then
                    levelText.Text = "Restarting..."
                    
                    -- 【修复2】：延迟 1 秒后真正触发下一场战斗，防止卡死
                    task.delay(1, function()
                        -- 再次检查确认玩家没有在此期间取消Auto Battle
                        if player:GetAttribute("AutoBattle") then
                            ReplicatedStorage:WaitForChild("StartBattleRE"):FireServer()
                        end
                    end)
                else
                    -- 如果没有OnAuto Battle（或者已被手动停止Off），则正常返回非战斗 UI
                    startBattleBtn.Visible = true
                    inBattleFrame.Visible = false
                end
            end
        end)
    end
end)

local UIEffectUtil = require(script.Utils.UIEffectUtil) -- 请确保路径匹配你的实际结构

local showTipRE = ReplicatedStorage:WaitForChild("ShowTipRE")

-- 监听服务端的提示请求，并调用封装好的 ShowTip
showTipRE.OnClientEvent:Connect(function(message)
    UIEffectUtil.ShowTip(message)
end)


showTipRE.OnClientEvent:Connect(function(message)
    UIEffectUtil.ShowTip(message)
end)

-- ==========================================
-- 🌟 新增：监听补偿弹窗指令并显示 UI
-- ==========================================
local PopupUtil = require(script.Utils.PopupUtil)
local showCompensationPopupRE = ReplicatedStorage:WaitForChild("ShowCompensationPopupRE", 10)
if showCompensationPopupRE then
    showCompensationPopupRE.OnClientEvent:Connect(function(message)
        -- 使用现有的弹窗组件，点击确定后自动关闭
        PopupUtil.ShowConfirm(message, function()
            -- 留空即可，弹窗会自动消失
        end)
    end)
end

InventoryController.Init()
HotbarController.Init()
ShopController.Init()
CoinDropController.Init()
PlantUIController.Init()
HighlightController.Init()
PlantHoverController.Init()
ToolController.Init()
EncyclopediaController.Init()
EventUIManager.Init()
UnlockAnimController.Init()
TutorialController.Init()
local AirdropUIController = require(script.Services.AirdropUIController)
AirdropUIController.Init()
local StealWarningUIController = require(script.Services.StealWarningUIController)
StealWarningUIController.Init()
local GroupJoinPromptController = require(script.Services.GroupJoinPromptController)
GroupJoinPromptController.Init()
local ZombieBoxController = require(script.Services.ZombieBoxController)
ZombieBoxController.Init()
local RollController = require(script.UI.RollController)
RollController.Init()
local StealablePointerUIController = require(script.Services.StealablePointerUIController)
StealablePointerUIController.Init()
require(script.UI.EventUI.NewbieGiftController).Init()
local FreeRewardClientController = require(script.Services.FreeRewardClientController)
FreeRewardClientController.Init()

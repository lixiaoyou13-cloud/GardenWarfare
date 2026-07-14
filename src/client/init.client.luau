-- src/client/init.client.luau
print("Client started: immersive UI system (layer adaptation fix) active...")

local InventoryController = require(script.UI.InventoryController)
local HotbarController = require(script.UI.HotbarController)
local ShopController = require(script.UI.ShopController)
local CoinDropController = require(script.Services.CoinDropController)
local PlantAttackVisualController = require(script.Services.PlantAttackVisualController)
local SettingsController = require(script.Services.SettingsController)
local PlantUIController = require(script.Services.PlantUIController)
local HighlightController = require(script.Services.HighlightController)
local PlantHoverController = require(script.UI.PlantHoverController)
local ToolController = require(script.Services.ToolController)
local EncyclopediaController = require(script.UI.EncyclopediaController)
local UnlockAnimController = require(script.UI.UnlockAnimController)
local ChestController = require(script.UI.ChestController)
local TutorialController = require(script.UI.TutorialController)
local CodesController = require(script.UI.CodesController)
local IAPShopController = require(script.UI.IAPShopController)
local OnlineRewardController = require(script.UI.OnlineRewardController)
local PassController = require(script.UI.PassController)
local GiftingController = require(script.UI.GiftingController)
local TradeController = require(script.UI.TradeController)
local NoticeController = require(script.UI.NoticeController)
local FriendInviteController = require(script.UI.FriendInviteController)
local EventUIManager = require(script.UI.EventUI.EventUIManager)
local MutationPotionBuffController = require(script.Services.MutationPotionBuffController)
local ZombossIntroController = require(script.Services.ZombossIntroController)
local ZombossBossFightController = require(script.Services.ZombossBossFightController)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RankingSeasonConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankingSeasonConfig"))
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

PlantAttackVisualController.Init()
ZombossIntroController.Init()
ZombossBossFightController.Init()

local AnalyticsRE = ReplicatedStorage:WaitForChild("AnalyticsRE")
local localPlayer = game:GetService("Players").LocalPlayer
local initialCameraMaxZoomDistance = localPlayer.CameraMaxZoomDistance
localPlayer.CameraMaxZoomDistance = initialCameraMaxZoomDistance

local VISIBLE_TEXT_TRANSLATIONS = {
    ["蓝色"] = "Blue",
    ["假的"] = "Placeholder",
    ["豌豆射手种子"] = "Peashooter Seed",
    ["补货：03：55"] = "Restock: 03:55",
    ["种子1号"] = "Seed 1",
    ["变异效果"] = "Mutation",
    ["达到100关即可获得奖励"] = "Reach Level 100 to earn rewards",
    ["关卡1奖励"] = "Level 1 Reward",
}
local watchedTranslatedTextObjects = setmetatable({}, { __mode = "k" })

local function translateTextObject(instance)
    if not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
        return
    end

    local replacement = VISIBLE_TEXT_TRANSLATIONS[instance.Text]
    if replacement then
        instance.Text = replacement
    end

    if watchedTranslatedTextObjects[instance] then
        return
    end
    watchedTranslatedTextObjects[instance] = true
    instance:GetPropertyChangedSignal("Text"):Connect(function()
        local updatedReplacement = VISIBLE_TEXT_TRANSLATIONS[instance.Text]
        if updatedReplacement then
            instance.Text = updatedReplacement
        end
    end)
end

local function translateVisibleText(root)
    if not root then
        return
    end

    translateTextObject(root)
    for _, descendant in ipairs(root:GetDescendants()) do
        translateTextObject(descendant)
    end
end

local function watchVisibleText(root)
    if not root then
        return
    end

    translateVisibleText(root)
    root.DescendantAdded:Connect(function(descendant)
        task.defer(translateVisibleText, descendant)
    end)
end

task.spawn(function()
    watchVisibleText(localPlayer:WaitForChild("PlayerGui", 10))
    watchVisibleText(ReplicatedStorage:WaitForChild("UITemplates", 10))
end)

local function disableDefaultBackpack()
    local success, err = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)

    if not success then
        warn("[Client] Failed to disable default Roblox backpack: " .. tostring(err))
    end
end

task.spawn(function()
    for _ = 1, 10 do
        disableDefaultBackpack()
        task.wait(1)
    end
end)



local function pullCameraUp()
    -- 必须稍微等待一下，确保 Roblox 的默认相机系统已经绑定到了玩家角色上
    task.wait(0.5)

    -- 强行将相机拉远到 45 的距离
    localPlayer.CameraMinZoomDistance = 45
    localPlayer.CameraMaxZoomDistance = 45

    task.wait(0.1)
    localPlayer.CameraMinZoomDistance = 0.5
end

-- 监听玩家角色生成（每次进入游戏或死亡重生时间都会触发）
localPlayer.CharacterAdded:Connect(function()
    disableDefaultBackpack()
    pullCameraUp()
end)

-- 如果脚本运行的瞬间角色已经存在，直接执行一次数
if localPlayer.Character then
    disableDefaultBackpack()
    pullCameraUp()
end


task.spawn(function()
    local player = game:GetService("Players").LocalPlayer

    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        warn("[Client] PlayerGui was not found within 10 seconds; skipping global UI effect binding.")
        return
    end

    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        warn("[Client] BasicGui was not found within 10 seconds; skipping global UI effect binding.")
        return
    end
    for _, gui in pairs(basicGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            gui.ResetOnSpawn = false
            print("Locked UI reset protection for: " .. gui.Name)
        end
    end

    local inventoryGui = basicGui:WaitForChild("InventoryGui", 10)
    local shopGui = basicGui:WaitForChild("ShopGui", 10)
    local codexGui = basicGui:WaitForChild("Codex", 10)
    local playProperty = basicGui:WaitForChild("PlayProperty", 10)
    local levelSelectGui = basicGui:WaitForChild("LevelSelect", 10)
    if not (inventoryGui and shopGui and codexGui and playProperty) then
        warn("[Client] One or more BasicGui children were not found; skipping global UI effect binding.")
        return
    end
    if levelSelectGui and levelSelectGui:IsA("ScreenGui") then
        levelSelectGui.Enabled = false
    end

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
            button.Activated:Connect(function()
                task.delay(0.05, function()
                    if uiScale.Parent then
                        TweenService:Create(uiScale, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {Scale = 1}):Play()
                    end
                end)
            end)
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

    local x2SunBtn = playProperty:FindFirstChild("X2Sun")
    if x2SunBtn then
        -- External shortcut archived. The IAP shop x2 sun button is still handled by IAPShopController.
        x2SunBtn.Visible = false
        if x2SunBtn:IsA("GuiButton") then
            x2SunBtn.Active = false
            x2SunBtn.AutoButtonColor = false
        end
    end

    local panels = {}
    local function addGlobalPanel(gui, frame, bindClose)
        if not gui then
            return
        end

        table.insert(panels, {
            gui = gui,
            frame = frame,
            bindClose = bindClose ~= false,
        })
    end

    addGlobalPanel(inventoryGui, inventoryGui:WaitForChild("MainFrame", 5))
    addGlobalPanel(shopGui, shopGui:FindFirstChild("ShopFrame") or shopGui:WaitForChild("MainFrame", 5))
    addGlobalPanel(codexGui, codexGui:FindFirstChild("Index") or codexGui:WaitForChild("MainFrame", 5))

    -- Later pages keep their own open/close rules; this global layer only adds blur and input blocking.
    local passGui = basicGui:FindFirstChild("PassGui")
    local codesGui = basicGui:FindFirstChild("Codes")
    local iapShopGui = basicGui:FindFirstChild("IAPShopGui")
    local onlineGui = basicGui:FindFirstChild("OnlineGui")
    local settingsGui = basicGui:FindFirstChild("Settings")
    local rollPage = basicGui:FindFirstChild("RollPage")
    local giftingGui = basicGui:FindFirstChild("GiftingGui")

    addGlobalPanel(passGui, nil, false)
    addGlobalPanel(codesGui, nil, false)
    addGlobalPanel(iapShopGui, nil, false)
    addGlobalPanel(onlineGui, nil, false)
    addGlobalPanel(settingsGui, nil, false)
    addGlobalPanel(rollPage, nil, false)
    -- 礼物界面也走统一面板逻辑，打开时关闭其他界面并启用背景遮罩。
    addGlobalPanel(giftingGui, nil, false)

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
                    -- 生成一个简单的随机 SessionId 区分每一次数打开商店的行为
                    local shopSessionId = "ShopSession_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                    player:SetAttribute("CurrentShopSessionId", shopSessionId)
                    -- 埋点击：商店漏斗第一步
                    AnalyticsRE:FireServer("Funnel", "Shop_Purchase_Flow", {StepIndex = 1, StepName = "Step_1_Open_Shop", SessionId = shopSessionId})
                end
                for _, other in ipairs(panels) do
                    if other.gui ~= p.gui and other.gui.Enabled then other.gui.Enabled = false end
                end

                p.gui.DisplayOrder = math.max(p.gui.DisplayOrder, 100)
                isAnyOpen = true
                setBackgroundEffects(true)

                if p.frame then
                    p.frame.AnchorPoint = Vector2.new(0.5, 0.5)
                    p.frame.Position = POS_BOTTOM
                    TweenService:Create(p.frame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = POS_CENTER}):Play()


                end

                local closeRoot = p.bindClose and (p.frame or p.gui)
                local closeBtn = closeRoot and (
                    closeRoot:FindFirstChild("CloseBtn", true) or
                    closeRoot:FindFirstChild("CloseButton", true) or
                    closeRoot:FindFirstChild("Close", true)
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

    -- 战斗控制逻辑
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
            battleProgressFill.BackgroundTransparency = 0
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
    local btnLevelSelect = inBattleFrame and inBattleFrame:WaitForChild("AutoBattle", 5)
    local levelInputBox = inBattleFrame and inBattleFrame:FindFirstChild("InputBox", true)
    local levelTextBox = levelInputBox and (levelInputBox:IsA("TextBox") and levelInputBox or levelInputBox:FindFirstChildWhichIsA("TextBox", true))
    local homeBtn = playProperty:WaitForChild("Home", 5)
    local UIEffectUtilForHome = require(script.Utils.UIEffectUtil)

    local function isCarryingAirdrop()
        local character = player.Character
        if not character then return false end

        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant.Name == "AirdropWeld" and descendant:IsA("WeldConstraint") then
                local carriedPart = descendant.Part1
                local carriedBox = carriedPart and carriedPart:FindFirstAncestorOfClass("Model")
                if carriedPart and carriedPart.Parent and carriedBox and carriedBox:GetAttribute("Carrier") == player.UserId then
                    return true
                end
            end
        end

        return false
    end

    if homeBtn then
        homeBtn.Activated:Connect(function()
            if isCarryingAirdrop() then
                UIEffectUtilForHome.ShowTip("You cannot use Home while carrying an airdrop.")
                return
            end

            local character = player.Character
            if not character then return end

            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not rootPart then return end

            local plotsFolder = Workspace:FindFirstChild("Plots")
            if plotsFolder then
                -- 遍历寻找属于本地玩家的基地
                for _, plot in ipairs(plotsFolder:GetChildren()) do
                    if plot:GetAttribute("OwnerId") == player.UserId then
                        -- 找到基地后，优先找出生点击零件
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

        local autoLabel = btnLevelSelect and btnLevelSelect:FindFirstChild("TextLabel")
        local autoGrad = btnLevelSelect and btnLevelSelect:FindFirstChild("UIGradient")
        local UIEffectUtilForBattle = require(script.Utils.UIEffectUtil)
        local isLevelSelectConfirming = false
        local maxSelectableLevel = 1
        local hasMaxSelectableLevel = false
        local currentPlayerData = nil
        local levelInputFocusLostBound = false
        local confirmSelectedLevel

        local function setLevelSelectText(text)
            if autoLabel then autoLabel.Text = text end
            if btnLevelSelect and btnLevelSelect:IsA("TextButton") then btnLevelSelect.Text = text end
        end

        local function closeLevelSelect()
            if levelSelectGui and levelSelectGui:IsA("ScreenGui") then
                levelSelectGui.Enabled = false
            end
        end

        local function ensureLevelInputBox()
            if not levelInputBox then
                if not inBattleFrame then
                    return false
                end

                local inputFrame = Instance.new("Frame")
                inputFrame.Name = "InputBox"
                inputFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                inputFrame.Size = UDim2.new(0, 220, 0, 48)
                if btnLevelSelect and btnLevelSelect:IsA("GuiObject") then
                    inputFrame.Position = UDim2.new(
                        btnLevelSelect.Position.X.Scale,
                        btnLevelSelect.Position.X.Offset,
                        btnLevelSelect.Position.Y.Scale,
                        btnLevelSelect.Position.Y.Offset - 58
                    )
                    inputFrame.LayoutOrder = btnLevelSelect.LayoutOrder - 1
                else
                    inputFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
                end
                inputFrame.BackgroundColor3 = Color3.fromRGB(30, 42, 54)
                inputFrame.BackgroundTransparency = 0.05
                inputFrame.BorderSizePixel = 0
                inputFrame.Visible = false
                inputFrame.Parent = inBattleFrame

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = inputFrame

                local stroke = Instance.new("UIStroke")
                stroke.Color = Color3.fromRGB(127, 214, 255)
                stroke.Thickness = 2
                stroke.Transparency = 0.15
                stroke.Parent = inputFrame

                local input = Instance.new("TextBox")
                input.Name = "LevelTextBox"
                input.AnchorPoint = Vector2.new(0.5, 0.5)
                input.Position = UDim2.new(0.5, 0, 0.5, 0)
                input.Size = UDim2.new(1, -20, 1, -10)
                input.BackgroundTransparency = 1
                input.ClearTextOnFocus = false
                input.Font = Enum.Font.GothamBold
                input.PlaceholderColor3 = Color3.fromRGB(180, 202, 215)
                input.PlaceholderText = "Level number"
                input.Text = ""
                input.TextColor3 = Color3.fromRGB(255, 255, 255)
                input.TextScaled = true
                input.Parent = inputFrame

                levelInputBox = inputFrame
                levelTextBox = input
            elseif not levelTextBox then
                if levelInputBox:IsA("TextBox") then
                    levelTextBox = levelInputBox
                elseif levelInputBox:IsA("GuiObject") then
                    levelTextBox = levelInputBox:FindFirstChildWhichIsA("TextBox", true)
                    if not levelTextBox then
                        local input = Instance.new("TextBox")
                        input.Name = "LevelTextBox"
                        input.AnchorPoint = Vector2.new(0.5, 0.5)
                        input.Position = UDim2.new(0.5, 0, 0.5, 0)
                        input.Size = UDim2.new(1, -12, 1, -8)
                        input.BackgroundTransparency = 1
                        input.ClearTextOnFocus = false
                        input.Font = Enum.Font.GothamBold
                        input.PlaceholderText = "Level number"
                        input.Text = ""
                        input.TextColor3 = Color3.fromRGB(255, 255, 255)
                        input.TextScaled = true
                        input.Parent = levelInputBox
                        levelTextBox = input
                    end
                end
            end

            if levelTextBox then
                levelTextBox.ClearTextOnFocus = false
                if levelTextBox.PlaceholderText == "" then
                    levelTextBox.PlaceholderText = "Level number"
                end
                if not levelInputFocusLostBound then
                    levelInputFocusLostBound = true
                    levelTextBox.FocusLost:Connect(function(enterPressed)
                        if enterPressed and isLevelSelectConfirming and confirmSelectedLevel then
                            confirmSelectedLevel()
                        end
                    end)
                end
            end

            return levelTextBox ~= nil
        end

        local function setLevelSelectState(isConfirming)
            isLevelSelectConfirming = isConfirming
            setLevelSelectText(isConfirming and "Click Confirm" or "Level Select")
            if autoGrad then autoGrad.Color = isConfirming and autoGreen or autoRed end

            local hasInput = ensureLevelInputBox()
            if levelInputBox and levelInputBox:IsA("GuiObject") then
                levelInputBox.Visible = isConfirming
            end
            if hasInput and levelTextBox then
                if isConfirming then
                    levelTextBox.Text = ""
                    levelTextBox:CaptureFocus()
                else
                    levelTextBox:ReleaseFocus()
                end
            end
        end

        local function refreshPlayerData(data)
            if type(data) == "table" then
                currentPlayerData = data
                local ok, nextLevel = pcall(function()
                    return RankingSeasonConfig.GetSeasonNextLevel(data)
                end)
                if ok then
                    maxSelectableLevel = math.max(1, tonumber(nextLevel) or maxSelectableLevel)
                    hasMaxSelectableLevel = true
                end
            end
        end

        local function applyPlayerDataPatch(patch)
            if type(patch) ~= "table" then return end
            currentPlayerData = currentPlayerData or {}
            for key, value in pairs(patch) do
                currentPlayerData[key] = value
            end
            refreshPlayerData(currentPlayerData)
        end

        local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 5)
        local function fetchPlayerData()
            if not getPlayerDataRF then
                return currentPlayerData
            end

            local ok, data = pcall(function()
                return getPlayerDataRF:InvokeServer()
            end)
            if ok then
                refreshPlayerData(data)
            else
                warn("[LevelSelect] Failed to fetch player data: " .. tostring(data))
            end
            return currentPlayerData
        end

        local function getLevelInputText()
            if ensureLevelInputBox() and levelTextBox then
                return levelTextBox.Text or ""
            end
            if levelInputBox and (levelInputBox:IsA("TextLabel") or levelInputBox:IsA("TextButton")) then
                return levelInputBox.Text or ""
            end
            return ""
        end

        confirmSelectedLevel = function()
            local rawText = getLevelInputText()
            local selectedLevel = tonumber(rawText)
            if not selectedLevel then
                UIEffectUtilForBattle.ShowTip("Please enter a level number.")
                return
            end

            selectedLevel = math.max(1, math.floor(selectedLevel))
            if hasMaxSelectableLevel and selectedLevel > maxSelectableLevel then
                selectedLevel = maxSelectableLevel
                UIEffectUtilForBattle.ShowTip("Your current season max level is Level " .. tostring(maxSelectableLevel) .. ". Starting Level " .. tostring(maxSelectableLevel) .. ".")
            end

            AnalyticsRE:FireServer("Custom", "UI_Click_LevelSelect_Confirm")
            setLevelSelectState(false)
            ReplicatedStorage:WaitForChild("StartBattleRE"):FireServer(selectedLevel)
        end

        local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 5)
        if updateInventoryRE then
            updateInventoryRE.OnClientEvent:Connect(function(data)
                refreshPlayerData(data)
            end)
        end

        local playerDataPatchRE = ReplicatedStorage:WaitForChild("PlayerDataPatchRE", 5)
        if playerDataPatchRE then
            playerDataPatchRE.OnClientEvent:Connect(function(patch)
                applyPlayerDataPatch(patch)
            end)
        end

        fetchPlayerData()
        setLevelSelectState(false)

        startBattleBtn.Activated:Connect(function()
            setLevelSelectState(false)
            closeLevelSelect()
            ReplicatedStorage:WaitForChild("StartBattleRE"):FireServer()

        end)

        if endBattleBtn then
            endBattleBtn.Activated:Connect(function()
                setLevelSelectState(false)
                closeLevelSelect()

                ReplicatedStorage:WaitForChild("EndBattleRE"):FireServer()
            end)
        end

        if btnLevelSelect then
            btnLevelSelect.Activated:Connect(function()
                if not isLevelSelectConfirming then
                    fetchPlayerData()
                    AnalyticsRE:FireServer("Custom", "UI_Click_LevelSelect_Open")
                    if not ensureLevelInputBox() then
                        UIEffectUtilForBattle.ShowTip("Level input is not ready.")
                        return
                    end
                    closeLevelSelect()
                    setLevelSelectState(true)
                    return
                end

                confirmSelectedLevel()
            end)
        end
        local setSpeedRE = ReplicatedStorage:WaitForChild("SetSpeedRE")
        local currentSpeed = 1
        local grad4RotationConn = nil
        -- 获取文字组件
        local label1_5 = btnSpeed1_5:FindFirstChildWhichIsA("TextLabel")
        local label4 = btnSpeed4:FindFirstChildWhichIsA("TextLabel")

        local function updateSpeedUI(activeSpeed)
            currentSpeed = activeSpeed

            -- 仅 2 Speed文字
            local is1_5 = (activeSpeed == 2)
            if label1_5 then
                label1_5.Text = is1_5 and "Back 1 Speed" or "X2 Speed"
            elseif btnSpeed1_5:IsA("TextLabel") or btnSpeed1_5:IsA("TextButton") then
                btnSpeed1_5.Text = is1_5 and "Back 1 Speed" or "X2 Speed"
            end

            -- 仅 4 Speed文字
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
        -- 内购服务与你的通行证ID
        local MarketplaceService = game:GetService("MarketplaceService")
        local SPEED_PASS_ID = 1811835638 -- 请把这串数字替换成你刚才复制的 Game Pass ID

        btnSpeed1_5.Activated:Connect(function()
            setSpeedRE:FireServer(currentSpeed == 2 and 1 or 2)
        end)
        btnSpeed4.Activated:Connect(function()
            -- 检查玩家是否已经拥有该通行证
            local hasPass = false
            pcall(function()
                hasPass = MarketplaceService:UserOwnsGamePassAsync(player.UserId, SPEED_PASS_ID)
            end)

            if hasPass then
                -- 如果已经购买，正常切换倍速
                setSpeedRE:FireServer(currentSpeed == 4 and 1 or 4)
            else
                -- 如果没有购买，在屏幕中央弹出 299 Robux 的购买确认框
                MarketplaceService:PromptGamePassPurchase(player, SPEED_PASS_ID)
            end
        end)

        -- 监听玩家付钱成功
        MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, passId, wasPurchased)
            if purchasingPlayer == player and passId == SPEED_PASS_ID and wasPurchased then
                -- 购买成功后，直接帮玩家自转动开启 4 倍速
                setSpeedRE:FireServer(4)

                -- 屏幕右下角弹一个原生的成功提示框
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "Success!",
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

                setLevelSelectState(false)
                closeLevelSelect()
                startBattleBtn.Visible = true
                inBattleFrame.Visible = false
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

-- 监听补偿弹窗指令并显示 UI
local PopupUtil = require(script.Utils.PopupUtil)
local showCompensationPopupRE = ReplicatedStorage:WaitForChild("ShowCompensationPopupRE", 10)
if showCompensationPopupRE then
    showCompensationPopupRE.OnClientEvent:Connect(function(message)
        -- 使用现有的弹窗组件，点击确定后自转动关闭
        PopupUtil.ShowConfirm(message, function()
            -- 留空即可，弹窗会自转动消失
        end)
    end)
end

InventoryController.Init()
HotbarController.Init()
ShopController.Init()
CoinDropController.Init()
SettingsController.Init()
PlantUIController.Init()
HighlightController.Init()
PlantHoverController.Init()
ToolController.Init()
EncyclopediaController.Init()
EventUIManager.Init()
UnlockAnimController.Init()
ChestController.Init()
TutorialController.Init()
CodesController.Init()
IAPShopController.Init()
OnlineRewardController.Init()
PassController.Init()
NoticeController.Init()
FriendInviteController.Init()
MutationPotionBuffController.Init()
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
local FreeRewardClientController = require(script.Services.FreeRewardClientController)
FreeRewardClientController.Init()
GiftingController.Init()
TradeController.Init()

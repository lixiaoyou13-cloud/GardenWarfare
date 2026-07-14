local TradeController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(sharedFolder:WaitForChild("ItemConfig"))
local TradeConfig = require(sharedFolder:WaitForChild("TradeConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local remoteEvent = ReplicatedStorage:WaitForChild(TradeConfig.RemoteName or "TradeRE")
local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")

local screenGui = nil
local tradeRootFrame = nil
local tradeBlurOverlay = nil
local inviteFrame = nil
local inviteMessage = nil
local inviteAcceptButton = nil
local inviteDeclineButton = nil
local inviteCancelButton = nil

local mainFrame = nil
local titleLabel = nil
local statusLabelA = nil
local statusLabelB = nil
local myOfferContainer = nil
local otherOfferContainer = nil
local inventoryContainer = nil
local myEmojiLabel = nil
local myEmojiImage = nil
local myPortraitImage = nil
local otherEmojiLabel = nil
local otherEmojiImage = nil
local otherPortraitImage = nil
local confirmButton = nil
local offerSlotTemplate = nil
local inventoryRowTemplate = nil

local inviteAcceptCallback = nil
local inviteDeclineCallback = nil
local inviteCancelCallback = nil

local playerData = nil
local currentSessionState = nil
local currentInviteId = nil
local currentInventorySelectionControls = nil
local lastInventorySelectionToggleAt = 0
local lastInventorySelectionToggleControls = nil
local avatarImageCache = {}
local emojiPulseTweens = {}
local lastEmojiAnimationKeys = {}
local localEmojiClickSeq = 0
local localEmojiPendingKind = nil
local localEmojiPendingUntil = 0
local sendTradeEmoji = nil
local tradeVisualOpen = false
local tradeBaseCameraFov = nil
local tradeCameraTween = nil

local promptName = "TradePromptLocal_" .. tostring(localPlayer.UserId)
local tradePrompts = {}
local localEquipChangedConnection = nil
local BOSS_LOCK_ATTRIBUTES = {
    "ZombossIntroUILocked",
    "ZombossFightUILocked",
}
local TRADE_CAMERA_FOV_OFFSET = -8
local TRADE_CAMERA_MIN_FOV = 45
local TRADE_CAMERA_TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TRADE_BLUR_OVERLAY_NAME = "TradeBlurOverlay"
local TRADE_BLUR_OVERLAY_Z_INDEX = 1
local TRADE_PANEL_MIN_Z_INDEX = 2
local TRADE_EXPRESSION_MIN_Z_INDEX = 60
local TRADE_INVENTORY_ROW_SIZE = UDim2.new(1, -8, 0, 74)
local TRADE_INVENTORY_ICON_SIZE = UDim2.new(0, 48, 0, 48)

local function make(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties or {}) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function addCorner(parent, radius)
    return make("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
    }, parent)
end

local function addStroke(parent, color, thickness)
    return make("UIStroke", {
        Color = color or Color3.fromRGB(255, 255, 255),
        Thickness = thickness or 1,
        Transparency = 0.15,
    }, parent)
end

-- 把界面树整体抬到遮罩上方，避免背景遮罩挡住可点击按钮。
local function raiseGuiTree(root, minZIndex)
    if not root then
        return
    end

    if root:IsA("GuiObject") then
        root.ZIndex = math.max(root.ZIndex, minZIndex)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            descendant.ZIndex = math.max(descendant.ZIndex, minZIndex)
        end
    end
end

-- 创建独立的交易背景遮罩，公共模糊工具只控制这个节点，不再隐藏交易根节点。
local function ensureTradeBlurOverlay()
    local overlayParent = tradeRootFrame
    if not overlayParent then
        overlayParent = screenGui
    end
    if not (overlayParent and (overlayParent:IsA("ScreenGui") or overlayParent:IsA("GuiObject"))) then
        return nil
    end

    local overlay = overlayParent:FindFirstChild(TRADE_BLUR_OVERLAY_NAME)
    if not overlay then
        overlay = Instance.new("Frame")
        overlay.Name = TRADE_BLUR_OVERLAY_NAME
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
        overlay.AnchorPoint = Vector2.new(0, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.Visible = false
        overlay.Parent = overlayParent
    end

    if overlay:IsA("GuiObject") then
        overlay.Active = true
        overlay.ZIndex = TRADE_BLUR_OVERLAY_Z_INDEX
    end

    tradeBlurOverlay = overlay
    return tradeBlurOverlay
end

local function showTip(message)
    local success = pcall(function()
        UIEffectUtil.ShowTip(tostring(message or ""))
    end)
    if not success then
        warn("[TradeController] " .. tostring(message))
    end
end

-- 给 TextButton/ImageButton/带文字子节点的按钮统一设置显示文字。
local function setGuiText(instance, value)
    if not instance then
        return
    end

    local text = tostring(value or "")
    if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
        instance.Text = text
        return
    end

    local textObject = instance:FindFirstChildWhichIsA("TextLabel", true)
        or instance:FindFirstChildWhichIsA("TextButton", true)
        or instance:FindFirstChildWhichIsA("TextBox", true)
    if textObject then
        textObject.Text = text
    end
end

local function setGuiTextColor(instance, color)
    if not instance then
        return
    end

    if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
        instance.TextColor3 = color
        return
    end

    local textObject = instance:FindFirstChildWhichIsA("TextLabel", true)
        or instance:FindFirstChildWhichIsA("TextButton", true)
        or instance:FindFirstChildWhichIsA("TextBox", true)
    if textObject then
        textObject.TextColor3 = color
    end
end

-- 设置 GuiObject 的锚点、尺寸和位置，用于还原编辑器模板克隆后的运行时布局。
local function setGuiObjectLayout(instance, anchorPoint, position, size)
    if not (instance and instance:IsA("GuiObject")) then
        return
    end

    if anchorPoint then
        instance.AnchorPoint = anchorPoint
    end
    if position then
        instance.Position = position
    end
    if size then
        instance.Size = size
    end
end

-- 设置准备状态文案和颜色：准备为绿色，未准备为红色。
local function setReadyLabel(label, playerName, isReady)
    setGuiText(label, tostring(playerName or "Player") .. " ready: " .. (isReady and "YES" or "NO"))
    setGuiTextColor(label, isReady and Color3.fromRGB(63, 226, 94) or Color3.fromRGB(255, 76, 76))
end

-- 绑定 GuiButton 点击事件，兼容编辑器里的 ImageButton 和脚本兜底 TextButton。
local function bindGuiButton(button, callback)
    if not button or not button:IsA("GuiButton") then
        return
    end

    button.Activated:Connect(callback)
end

-- 给交易背包克隆按钮补 hover/按下反馈，避免模板克隆继承 HoverAnimBound 后丢失事件连接。
local function bindTradeHoverEffect(button)
    if not button or not button:IsA("GuiButton") or button:GetAttribute("TradeHoverAnimBound") then
        return
    end

    button:SetAttribute("TradeHoverAnimBound", true)
    button.AutoButtonColor = false

    local uiScale = button:FindFirstChildOfClass("UIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Parent = button
    end
    uiScale.Scale = 1

    button.MouseEnter:Connect(function()
        TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1.12 }):Play()
    end)
    button.MouseLeave:Connect(function()
        TweenService:Create(uiScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
    end)
    button.MouseButton1Down:Connect(function()
        TweenService:Create(uiScale, TweenInfo.new(0.1), { Scale = 0.9 }):Play()
    end)
    button.MouseButton1Up:Connect(function()
        TweenService:Create(uiScale, TweenInfo.new(0.1), { Scale = 1.12 }):Play()
    end)
    button.Activated:Connect(function()
        task.delay(0.05, function()
            if uiScale.Parent then
                TweenService:Create(uiScale, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
            end
        end)
    end)
end

-- 播放交易界面打开时的镜头缩放效果。
local function setTradeCameraZoom(enabled)
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    if tradeCameraTween then
        tradeCameraTween:Cancel()
        tradeCameraTween = nil
    end

    local targetFov = camera.FieldOfView
    if enabled then
        if not tradeBaseCameraFov then
            tradeBaseCameraFov = camera.FieldOfView
        end
        targetFov = math.max(TRADE_CAMERA_MIN_FOV, tradeBaseCameraFov + TRADE_CAMERA_FOV_OFFSET)
    else
        targetFov = tradeBaseCameraFov or camera.FieldOfView
        tradeBaseCameraFov = nil
    end

    tradeCameraTween = TweenService:Create(camera, TRADE_CAMERA_TWEEN_INFO, {
        FieldOfView = targetFov,
    })
    tradeCameraTween:Play()
end

-- 统一控制交易 UI 打开状态：显示遮罩、吃掉输入、模糊背景和缩放镜头。
local function setRootVisible(isVisible)
    if screenGui then
        screenGui.Enabled = true
        if screenGui:IsA("ScreenGui") then
            screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, 180)
        end
    end
    if tradeRootFrame then
        tradeRootFrame.Active = true
    end
    ensureTradeBlurOverlay()

    if isVisible == true then
        if tradeRootFrame then
            tradeRootFrame.Visible = true
        end
        if not tradeVisualOpen then
            tradeVisualOpen = true
            UIEffectUtil.SetScreenBlur(true, tradeBlurOverlay)
            setTradeCameraZoom(true)
        end
        return
    end

    if tradeVisualOpen then
        tradeVisualOpen = false
        UIEffectUtil.SetScreenBlur(false, tradeBlurOverlay)
        setTradeCameraZoom(false)
    end

    if tradeRootFrame then
        tradeRootFrame.Visible = false
    end
end

-- 判断交易 UI 是否已经打开，防止 Prompt 透过界面再次拉起弹窗。
local function isTradeUiOpen()
    return currentSessionState ~= nil
        or currentInviteId ~= nil
        or (inviteFrame and inviteFrame.Visible)
        or (mainFrame and mainFrame.Visible)
end

local function isBossUILocked()
    for _, attributeName in ipairs(BOSS_LOCK_ATTRIBUTES) do
        if localPlayer:GetAttribute(attributeName) == true then
            return true
        end
    end
    return false
end

-- 判断当前装备是否需要隐藏交易 Prompt，例如手持武器时避免误触交易。
local function isTradePromptBlockedByEquippedItem()
    local character = localPlayer.Character
    local equippedItem = character and character:GetAttribute("EquippedSeed")
    if type(equippedItem) ~= "string" or equippedItem == "" then
        return false
    end

    local blockedEquippedIds = TradeConfig.PromptBlockedEquippedIds or {}
    if type(blockedEquippedIds) ~= "table" then
        return false
    end
    if blockedEquippedIds[equippedItem] == true then
        return true
    end

    for _, blockedId in pairs(blockedEquippedIds) do
        if blockedId == equippedItem then
            return true
        end
    end
    return false
end

-- 根据本地装备状态统一刷新所有玩家身上的交易 Prompt 可见性。
local function refreshTradePromptEnabled()
    local shouldEnable = not isTradePromptBlockedByEquippedItem()
    for prompt in pairs(tradePrompts) do
        if prompt and prompt.Parent then
            prompt.Enabled = shouldEnable
        else
            tradePrompts[prompt] = nil
        end
    end
end

local function getGuiParent()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local basicGui = playerGui:FindFirstChild("BasicGui")
    return basicGui or playerGui
end

local function findChild(parent, childName)
    return parent and parent:FindFirstChild(childName) or nil
end

local function findDescendant(parent, childName)
    return parent and parent:FindFirstChild(childName, true) or nil
end

-- 按稳定命名绑定小佑在编辑器里制作的交易 UI。
local function bindEditorUi(existingGui)
    local root = findChild(existingGui, "TradeFrame") or existingGui
    local existingMainFrame = findChild(root, "MainFrame") or findDescendant(existingGui, "MainFrame")
    local existingInviteFrame = findChild(root, "InviteFrame") or findDescendant(existingGui, "InviteFrame")
    if not existingMainFrame or not existingInviteFrame then
        return false
    end

    local tradePanel = findChild(existingMainFrame, "TradePanel")
    local otherOfferPanel = tradePanel and findChild(tradePanel, "OtherOfferPanel")
    local myOfferPanel = tradePanel and findChild(tradePanel, "MyOfferPanel")
    local inventoryPanel = findChild(existingMainFrame, "InventoryPanel")
    local templates = findChild(existingGui, "Templates")

    if not (otherOfferPanel and myOfferPanel and inventoryPanel) then
        return false
    end

    screenGui = existingGui
    tradeRootFrame = root ~= existingGui and root or nil
    if tradeRootFrame and tradeRootFrame:IsA("GuiObject") then
        tradeRootFrame.Active = true
        tradeRootFrame.Size = UDim2.fromScale(1, 1)
        tradeRootFrame.Position = UDim2.fromScale(0, 0)
        tradeRootFrame.BorderSizePixel = 0
    end
    mainFrame = existingMainFrame
    inviteFrame = existingInviteFrame
    ensureTradeBlurOverlay()
    raiseGuiTree(mainFrame, TRADE_PANEL_MIN_Z_INDEX)
    raiseGuiTree(inviteFrame, TRADE_PANEL_MIN_Z_INDEX)
    titleLabel = findChild(mainFrame, "Title") or findDescendant(mainFrame, "Title")
    inviteMessage = findChild(inviteFrame, "Message")
        or findChild(inviteFrame, "Detail")
        or findDescendant(inviteFrame, "Message")
    inviteAcceptButton = findChild(inviteFrame, "AcceptButton")
    inviteDeclineButton = findChild(inviteFrame, "DeclineButton")
    inviteCancelButton = findChild(inviteFrame, "CancelButton")

    otherOfferContainer = findChild(otherOfferPanel, "OfferList")
    myOfferContainer = findChild(myOfferPanel, "OfferList")
    inventoryContainer = findChild(inventoryPanel, "InventoryList")
    otherEmojiImage = findChild(otherOfferPanel, "EmojiImage")
    otherEmojiLabel = findChild(otherOfferPanel, "EmojiText")
    otherPortraitImage = findChild(otherOfferPanel, "PortraitImage")
    myEmojiImage = findChild(myOfferPanel, "EmojiImage")
    myEmojiLabel = findChild(myOfferPanel, "EmojiText")
    myPortraitImage = findChild(myOfferPanel, "PortraitImage")
    statusLabelA = findChild(otherOfferPanel, "ReadyLabel")
    statusLabelB = findChild(myOfferPanel, "ReadyLabel")
    confirmButton = findChild(mainFrame, "ConfirmTradeButton")

    offerSlotTemplate = templates and findChild(templates, "OfferSlotTemplate")
    inventoryRowTemplate = templates and findChild(templates, "InventoryRowTemplate")
    if offerSlotTemplate then
        offerSlotTemplate.Visible = false
    end
    if inventoryRowTemplate then
        inventoryRowTemplate.Visible = false
    end

    bindGuiButton(inviteAcceptButton, function()
        if inviteAcceptCallback then
            inviteAcceptCallback()
        end
    end)
    bindGuiButton(inviteDeclineButton, function()
        if inviteDeclineCallback then
            inviteDeclineCallback()
        end
    end)
    bindGuiButton(inviteCancelButton, function()
        if inviteCancelCallback then
            inviteCancelCallback()
        end
    end)

    bindGuiButton(findChild(mainFrame, "CloseButton"), function()
        remoteEvent:FireServer("CancelSession")
    end)
    bindGuiButton(findChild(mainFrame, "CancelTradeButton"), function()
        remoteEvent:FireServer("CancelSession")
    end)
    bindGuiButton(findChild(mainFrame, "OkEmojiButton"), function()
        sendTradeEmoji("OK")
    end)
    bindGuiButton(findChild(mainFrame, "NoEmojiButton"), function()
        sendTradeEmoji("NO")
    end)
    bindGuiButton(confirmButton, function()
        if currentSessionState and currentSessionState.Ready and currentSessionState.Ready[tostring(localPlayer.UserId)] then
            remoteEvent:FireServer("SetReady", false)
        else
            remoteEvent:FireServer("SetReady", true)
        end
    end)

    if mainFrame then
        mainFrame.Visible = false
    end
    if inviteFrame then
        inviteFrame.Visible = false
    end
    setRootVisible(false)

    return inviteMessage
        and inviteAcceptButton
        and inviteCancelButton
        and myOfferContainer
        and otherOfferContainer
        and inventoryContainer
        and confirmButton
end

local function getQualityColor(quality)
    local colors = ItemConfig.QualityColor or {}
    return colors[tonumber(quality) or 1] or Color3.fromRGB(255, 255, 255)
end

local function getMutationName(mutationLevel)
    mutationLevel = tonumber(mutationLevel) or 1
    local names = ItemConfig.MutationName or {}
    return names[mutationLevel] or "Normal"
end

-- 把纯数字或 rbxassetid 表情资源转成资产缩略图，兼容 Decal 类型资源在 ImageLabel 里不显示的问题。
local function normalizeEmojiImageId(imageId)
    if type(imageId) == "number" then
        return "rbxthumb://type=Asset&id=" .. tostring(imageId) .. "&w=150&h=150"
    end

    if type(imageId) ~= "string" or imageId == "" then
        return nil
    end

    local assetId = string.match(imageId, "^rbxassetid://(%d+)$")
    if assetId then
        return "rbxthumb://type=Asset&id=" .. assetId .. "&w=150&h=150"
    end

    return imageId
end

local function getEmojiImageId(kind)
    local emojiImages = TradeConfig.EmojiImageIds or {}
    return normalizeEmojiImageId(emojiImages[kind])
end

local function clearGeneratedChildren(container)
    if not container then
        return
    end

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject")
            or child:GetAttribute("TradeGenerated") == true
            or child:GetAttribute("TradeGeneratedPreview") == true
        then
            child:Destroy()
        end
    end
end

local function fetchPlayerData()
    local success, result = pcall(function()
        return getPlayerDataRF:InvokeServer()
    end)
    if success and type(result) == "table" then
        playerData = result
    end
    return playerData
end

local function styleButton(button, color)
    button.BackgroundColor3 = color
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.AutoButtonColor = true
    addCorner(button, 6)
    addStroke(button, Color3.fromRGB(255, 255, 255), 1)
end

local function createLabel(parent, text, size, position)
    return make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Position = position,
        Size = size,
        Text = text,
        TextColor3 = Color3.fromRGB(236, 244, 255),
        TextScaled = true,
        TextWrapped = true,
    }, parent)
end

local function createPanel(parent, title, position, size)
    local panel = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(22, 29, 38),
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
    }, parent)
    addCorner(panel, 8)
    addStroke(panel, Color3.fromRGB(82, 104, 130), 1)

    createLabel(panel, title, UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 6))

    return panel
end

local function createScrollingGrid(parent, position, size, cellSize)
    local scroll = make("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Position = position,
        ScrollBarThickness = 6,
        Size = size,
    }, parent)

    local grid = make("UIGridLayout", {
        CellPadding = UDim2.new(0, 8, 0, 8),
        CellSize = cellSize,
        FillDirectionMaxCells = 5,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)

    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 10)
    end)

    return scroll
end

local function setGuiImage(instance, imageId)
    if instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
        instance.Image = imageId or ""
        instance.ImageTransparency = 0
        instance.ImageColor3 = Color3.fromRGB(255, 255, 255)
        instance.Visible = imageId ~= nil and imageId ~= ""
    end
end

-- 表情和头像属于沟通区表现层，强制抬高层级避免被列表或装饰图盖住。
local function raiseExpressionObject(instance)
    if instance and instance:IsA("GuiObject") then
        instance.ZIndex = math.max(instance.ZIndex, TRADE_EXPRESSION_MIN_Z_INDEX)
    end
end

-- 播放表情/文字的点击反馈，快速放大再回弹，让连续点击也有明显变化。
local function playExpressionPulse(instance)
    if not (instance and instance:IsA("GuiObject")) then
        return
    end

    local uiScale = instance:FindFirstChild("TradeExpressionPulseScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Name = "TradeExpressionPulseScale"
        uiScale.Parent = instance
    end

    local previousTweens = emojiPulseTweens[instance]
    if previousTweens then
        for _, tween in ipairs(previousTweens) do
            tween:Cancel()
        end
    end

    uiScale.Scale = 0.9
    local growTween = TweenService:Create(uiScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1.22,
    })
    local settleTween = TweenService:Create(uiScale, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        Scale = 1,
    })
    emojiPulseTweens[instance] = { growTween, settleTween }

    growTween.Completed:Connect(function(playbackState)
        if playbackState == Enum.PlaybackState.Completed
            and emojiPulseTweens[instance]
            and emojiPulseTweens[instance][1] == growTween
            and uiScale.Parent
        then
            settleTween:Play()
        end
    end)
    growTween:Play()
end

-- 给非按钮模板补一个透明点击层，用于点击移除我方已上传植物。
local function getSlotClickTarget(slot)
    if slot:IsA("GuiButton") then
        return slot
    end

    local existing = slot:FindFirstChild("TradeClickTarget")
    if existing and existing:IsA("GuiButton") then
        return existing
    end

    return make("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Name = "TradeClickTarget",
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = slot.ZIndex + 20,
    }, slot)
end

local function createTradeSlot(parent, entry, isMine)
    local plantId = entry.PlantId
    local mutationLevel = tonumber(entry.Mutation) or 1
    local quantity = math.max(1, math.floor(tonumber(entry.Quantity) or 1))
    local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
    local displayName = plantDetail and plantDetail.Name or plantId

    if offerSlotTemplate then
        local slot = offerSlotTemplate:Clone()
        slot.Name = "TradeSlot_" .. tostring(plantId)
        slot.LayoutOrder = #parent:GetChildren()
        slot.Visible = true
        slot.Parent = parent
        slot:SetAttribute("TradeGenerated", true)

        setGuiImage(findDescendant(slot, "Icon"), plantDetail and plantDetail.IconId or "")
        setGuiText(findDescendant(slot, "Quantity"), "x" .. tostring(quantity))
        setGuiText(findDescendant(slot, "NameLabel"), displayName)
        setGuiText(findDescendant(slot, "MutationLabel"), getMutationName(mutationLevel))

        if isMine then
            bindGuiButton(getSlotClickTarget(slot), function()
                remoteEvent:FireServer("RemoveOfferItem", {
                    PlantId = plantId,
                    Mutation = mutationLevel,
                })
            end)
        end
        return
    end

    local slot = make("TextButton", {
        AutoButtonColor = isMine,
        BackgroundColor3 = Color3.fromRGB(34, 43, 55),
        BorderSizePixel = 0,
        Text = "",
    }, parent)
    slot:SetAttribute("TradeGenerated", true)
    addCorner(slot, 6)
    addStroke(slot, getQualityColor(plantDetail and plantDetail.Quality), 2)

    local icon = make("ImageLabel", {
        BackgroundTransparency = 1,
        Image = plantDetail and plantDetail.IconId or "",
        Position = UDim2.new(0.12, 0, 0.05, 0),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.new(0.76, 0, 0.48, 0),
    }, slot)

    local qty = make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(0, 4, 0.48, 0),
        Size = UDim2.new(1, -8, 0.18, 0),
        Text = "x" .. tostring(quantity),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, slot)

    local nameLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamSemibold,
        Position = UDim2.new(0, 4, 0.66, 0),
        Size = UDim2.new(1, -8, 0.16, 0),
        Text = displayName,
        TextColor3 = Color3.fromRGB(236, 244, 255),
        TextScaled = true,
        TextWrapped = true,
    }, slot)

    local mutLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Position = UDim2.new(0, 4, 0.82, 0),
        Size = UDim2.new(1, -8, 0.15, 0),
        Text = getMutationName(mutationLevel),
        TextColor3 = Color3.fromRGB(179, 204, 255),
        TextScaled = true,
    }, slot)

    icon.ZIndex = slot.ZIndex + 1
    qty.ZIndex = slot.ZIndex + 1
    nameLabel.ZIndex = slot.ZIndex + 1
    mutLabel.ZIndex = slot.ZIndex + 1

    if isMine then
        slot.MouseButton1Click:Connect(function()
            remoteEvent:FireServer("RemoveOfferItem", {
                PlantId = plantId,
                Mutation = mutationLevel,
            })
        end)
    end
end

local function getStatePlayerInfo(userId)
    if not currentSessionState or type(currentSessionState.Players) ~= "table" then
        return nil
    end
    return currentSessionState.Players[tostring(userId)]
end

local function getPartnerUserId(state)
    if not state or type(state.PlayerOrder) ~= "table" then
        return nil
    end

    for _, userId in ipairs(state.PlayerOrder) do
        if tonumber(userId) ~= localPlayer.UserId then
            return tonumber(userId)
        end
    end
    return nil
end

local function getAvatarThumbUrl(userId)
    if (tonumber(userId) or 0) <= 0 then
        return TradeConfig.DefaultPortraitImageId
    end
    return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
end

-- 先写入 rbxthumb 头像链接，再用异步接口结果覆盖，避免 Studio 里头像长期空白。
local function setPortraitImage(imageLabel, userId)
    if not imageLabel then
        return
    end

    raiseExpressionObject(imageLabel)
    userId = tonumber(userId)
    if not userId then
        imageLabel:SetAttribute("TradePortraitUserId", nil)
        setGuiImage(imageLabel, TradeConfig.DefaultPortraitImageId)
        return
    end

    local previewImage = getAvatarThumbUrl(userId)

    imageLabel:SetAttribute("TradePortraitUserId", userId)
    local cachedImage = avatarImageCache[userId]
    if cachedImage then
        setGuiImage(imageLabel, cachedImage)
        return
    end

    setGuiImage(imageLabel, previewImage)
    if userId <= 0 then
        return
    end

    task.spawn(function()
        local success, image = pcall(function()
            return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        end)
        if success and type(image) == "string" then
            avatarImageCache[userId] = image
            if imageLabel.Parent and imageLabel:GetAttribute("TradePortraitUserId") == userId then
                setGuiImage(imageLabel, image)
            end
        end
    end)
end

local function renderPortraits(state)
    local partnerUserId = getPartnerUserId(state)
    setPortraitImage(myPortraitImage, localPlayer.UserId)
    setPortraitImage(otherPortraitImage, partnerUserId)
end

-- 获取表情点击的唯一动画 key，服务端 Seq 能保证同表情连续点击也会变化。
local function getEmojiAnimationKey(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local kind = tostring(entry.Kind or "")
    if kind == "" then
        return nil
    end

    return kind .. ":" .. tostring(entry.Seq or entry.LocalSeq or entry.SentAt or "")
end

-- 判断本次表情状态是否需要播放动画，避免普通交易状态刷新重复抖动。
local function shouldAnimateEmoji(userKey, entry)
    local animationKey = getEmojiAnimationKey(entry)
    if not animationKey then
        return false
    end

    if tonumber(userKey) == localPlayer.UserId
        and entry.Kind == localEmojiPendingKind
        and os.clock() < localEmojiPendingUntil
        and entry.Seq
    then
        lastEmojiAnimationKeys[userKey] = animationKey
        return false
    end

    if lastEmojiAnimationKeys[userKey] == animationKey then
        return false
    end

    lastEmojiAnimationKeys[userKey] = animationKey
    return true
end

local function renderEmoji(kind, label, image, shouldAnimate)
    if not label and not image then
        return
    end

    if type(kind) ~= "string" or kind == "" then
        if label then
            label.Visible = false
        end
        if image then
            image.Visible = false
        end
        return
    end

    local imageId = getEmojiImageId(kind)
    if imageId and image then
        raiseExpressionObject(image)
        setGuiImage(image, imageId)
        if shouldAnimate then
            playExpressionPulse(image)
        end
        if label then
            label.Visible = false
        end
    else
        if label then
            raiseExpressionObject(label)
            label.Text = kind
            label.TextColor3 = kind == "OK" and Color3.fromRGB(51, 220, 98) or Color3.fromRGB(255, 73, 73)
            label.Visible = true
            if shouldAnimate then
                playExpressionPulse(label)
            end
        end
        if image then
            image.Visible = false
        end
    end
end

function sendTradeEmoji(kind)
    kind = tostring(kind or "")
    if kind ~= "OK" and kind ~= "NO" then
        return
    end

    if currentSessionState then
        currentSessionState.LastEmoji = currentSessionState.LastEmoji or {}
        localEmojiClickSeq += 1
        localEmojiPendingKind = kind
        localEmojiPendingUntil = os.clock() + 0.35
        currentSessionState.LastEmoji[tostring(localPlayer.UserId)] = {
            Kind = kind,
            SentAt = os.clock(),
            LocalSeq = localEmojiClickSeq,
        }
        lastEmojiAnimationKeys[tostring(localPlayer.UserId)] = getEmojiAnimationKey(currentSessionState.LastEmoji[tostring(localPlayer.UserId)])
        renderEmoji(kind, myEmojiLabel, myEmojiImage, true)
    end

    remoteEvent:FireServer("Emoji", kind)
end

local function renderOfferContainers()
    if not currentSessionState then
        return
    end

    local localKey = tostring(localPlayer.UserId)
    local partnerUserId = getPartnerUserId(currentSessionState)
    local partnerKey = tostring(partnerUserId or "")

    clearGeneratedChildren(myOfferContainer)
    clearGeneratedChildren(otherOfferContainer)

    for _, entry in ipairs((currentSessionState.Offers and currentSessionState.Offers[localKey]) or {}) do
        createTradeSlot(myOfferContainer, entry, true)
    end
    for _, entry in ipairs((currentSessionState.Offers and currentSessionState.Offers[partnerKey]) or {}) do
        createTradeSlot(otherOfferContainer, entry, false)
    end

    local ready = currentSessionState.Ready or {}
    local localInfo = getStatePlayerInfo(localPlayer.UserId)
    local partnerInfo = partnerUserId and getStatePlayerInfo(partnerUserId)
    local localName = localInfo and localInfo.DisplayName or localPlayer.DisplayName
    local partnerName = partnerInfo and partnerInfo.DisplayName or "Other Player"

    setReadyLabel(statusLabelA, partnerName, ready[partnerKey] == true)
    setReadyLabel(statusLabelB, localName, ready[localKey] == true)
    setGuiText(confirmButton, ready[localKey] and "Waiting..." or "Confirm Trade")
    renderPortraits(currentSessionState)

    local emoji = currentSessionState.LastEmoji or {}
    local localEmojiEntry = emoji[localKey]
    local partnerEmojiEntry = emoji[partnerKey]
    local localEmoji = localEmojiEntry and localEmojiEntry.Kind
    local partnerEmoji = partnerEmojiEntry and partnerEmojiEntry.Kind
    renderEmoji(localEmoji, myEmojiLabel, myEmojiImage, shouldAnimateEmoji(localKey, localEmojiEntry))
    renderEmoji(partnerEmoji, otherEmojiLabel, otherEmojiImage, shouldAnimateEmoji(partnerKey, partnerEmojiEntry))
end

local function getExistingOfferQuantity(plantId, mutationLevel)
    if not currentSessionState or not currentSessionState.Offers then
        return 0
    end

    local localOffer = currentSessionState.Offers[tostring(localPlayer.UserId)] or {}
    mutationLevel = tonumber(mutationLevel) or 1
    for _, entry in ipairs(localOffer) do
        if entry.PlantId == plantId and (tonumber(entry.Mutation) or 1) == mutationLevel then
            return tonumber(entry.Quantity) or 0
        end
    end
    return 0
end

-- 判断一次点击是否落在指定控件区域内，用来避免整行点击抢走加减按钮和输入框。
local function isInputInsideGui(input, guiObject)
    if not (input and guiObject and guiObject:IsA("GuiObject") and guiObject.Visible) then
        return false
    end

    local inputPosition = input.Position
    local x = inputPosition.X
    local y = inputPosition.Y
    local absolutePosition = guiObject.AbsolutePosition
    local absoluteSize = guiObject.AbsoluteSize

    return x >= absolutePosition.X
        and x <= absolutePosition.X + absoluteSize.X
        and y >= absolutePosition.Y
        and y <= absolutePosition.Y + absoluteSize.Y
end

local function isInputOnInventoryControls(input, controls)
    for _, control in ipairs(controls or {}) do
        if isInputInsideGui(input, control) then
            return true
        end
    end
    return false
end

-- 切换背包条目的上传控件；图标和整行点击都会走这里。
local function toggleInventoryRowSelection(controls, amountBox)
    local now = os.clock()
    if lastInventorySelectionToggleControls == controls and now - lastInventorySelectionToggleAt < 0.25 then
        return
    end
    lastInventorySelectionToggleControls = controls
    lastInventorySelectionToggleAt = now

    if currentInventorySelectionControls and currentInventorySelectionControls ~= controls then
        for _, control in ipairs(currentInventorySelectionControls) do
            if control and control.Parent then
                control.Visible = false
            end
        end
    end

    local nextVisible = true
    if amountBox then
        nextVisible = not amountBox.Visible
    elseif controls and controls[1] then
        nextVisible = not controls[1].Visible
    end

    for _, control in ipairs(controls or {}) do
        if control then
            control.Visible = nextVisible == true
        end
    end
    currentInventorySelectionControls = nextVisible and controls or nil
end

-- 让背包条目支持点击整行选中，同时保留图标点击的兼容入口。
local function bindInventoryRowSelection(row, iconButton, controls, amountBox)
    bindGuiButton(iconButton, function()
        toggleInventoryRowSelection(controls, amountBox)
    end)

    if row and row:IsA("GuiObject") then
        row.Active = true
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch
            then
                return
            end
            if isInputOnInventoryControls(input, controls) then
                return
            end

            toggleInventoryRowSelection(controls, amountBox)
        end)
    end
end

-- 还原背包条目模板的标准尺寸，避免编辑器里误调模板后运行时条目过大。
local function applyInventoryRowTemplateLayout(row)
    if not (row and row:IsA("GuiObject")) then
        return
    end

    row.Size = TRADE_INVENTORY_ROW_SIZE

    setGuiObjectLayout(findDescendant(row, "IconButton"), Vector2.new(0.5, 0.5), UDim2.new(0, 32, 0.5, 0), TRADE_INVENTORY_ICON_SIZE)
    setGuiObjectLayout(findDescendant(row, "NameLabel"), Vector2.new(0, 0), UDim2.new(0, 64, 0, 7), UDim2.new(1, -208, 0, 24))
    setGuiObjectLayout(findDescendant(row, "MutationLabel"), Vector2.new(0, 0), UDim2.new(0, 64, 0, 31), UDim2.new(1, -208, 0, 18))
    setGuiObjectLayout(findDescendant(row, "QuantityLabel"), Vector2.new(0, 0), UDim2.new(0, 64, 0, 51), UDim2.new(1, -208, 0, 18))
    setGuiObjectLayout(findDescendant(row, "MinusButton"), Vector2.new(0.5, 0.5), UDim2.new(1, -122, 0.5, 0), UDim2.new(0, 28, 0, 32))
    setGuiObjectLayout(findDescendant(row, "AmountBox"), Vector2.new(0.5, 0.5), UDim2.new(1, -85, 0.5, 0), UDim2.new(0, 38, 0, 32))
    setGuiObjectLayout(findDescendant(row, "PlusButton"), Vector2.new(0.5, 0.5), UDim2.new(1, -48, 0.5, 0), UDim2.new(0, 28, 0, 32))
    setGuiObjectLayout(findDescendant(row, "UploadButton"), Vector2.new(0.5, 0.5), UDim2.new(1, -18, 0.5, 0), UDim2.new(0, 24, 0, 32))

    bindTradeHoverEffect(findDescendant(row, "IconButton"))
    bindTradeHoverEffect(findDescendant(row, "MinusButton"))
    bindTradeHoverEffect(findDescendant(row, "PlusButton"))
    bindTradeHoverEffect(findDescendant(row, "UploadButton"))
end

local function createInventoryRow(parent, plantData, layoutOrder)
    local plantId = plantData.ID
    local mutationLevel = tonumber(plantData.Mutation) or 1
    local quantity = math.max(0, math.floor(tonumber(plantData.Quantity) or 0))
    local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
    if not plantDetail or quantity <= 0 then
        return
    end

    if inventoryRowTemplate then
        local row = inventoryRowTemplate:Clone()
        row.Name = "InventoryRow_" .. tostring(plantId)
        row.LayoutOrder = layoutOrder
        row.Visible = true
        row.Parent = parent
        row:SetAttribute("TradeGenerated", true)
        applyInventoryRowTemplateLayout(row)

        local iconButton = findDescendant(row, "IconButton")
        local amountBox = findDescendant(row, "AmountBox")
        local minusButton = findDescendant(row, "MinusButton")
        local plusButton = findDescendant(row, "PlusButton")
        local uploadButton = findDescendant(row, "UploadButton")

        setGuiImage(iconButton, plantDetail.IconId or "")
        setGuiText(findDescendant(row, "NameLabel"), plantDetail.Name or plantId)
        setGuiText(findDescendant(row, "MutationLabel"), getMutationName(mutationLevel))
        setGuiText(findDescendant(row, "QuantityLabel"), "Owned x" .. tostring(quantity))

        local defaultAmount = math.clamp(
            getExistingOfferQuantity(plantId, mutationLevel) > 0 and getExistingOfferQuantity(plantId, mutationLevel) or 1,
            1,
            quantity
        )
        setGuiText(amountBox, tostring(defaultAmount))

        local controls = {}
        for _, control in ipairs({ minusButton, amountBox, plusButton, uploadButton }) do
            if control then
                control.Visible = false
                table.insert(controls, control)
            end
        end

        bindInventoryRowSelection(row, iconButton, controls, amountBox)

        local function getAmount()
            local amountText = amountBox and amountBox.Text or nil
            local amount = math.floor(tonumber(amountText) or 1)
            amount = math.clamp(amount, 1, quantity)
            setGuiText(amountBox, tostring(amount))
            return amount
        end

        bindGuiButton(minusButton, function()
            setGuiText(amountBox, tostring(math.max(1, getAmount() - 1)))
        end)

        bindGuiButton(plusButton, function()
            setGuiText(amountBox, tostring(math.min(quantity, getAmount() + 1)))
        end)

        if amountBox and amountBox:IsA("TextBox") then
            amountBox.FocusLost:Connect(function()
                getAmount()
            end)
        end

        bindGuiButton(uploadButton, function()
            remoteEvent:FireServer("SetOfferItem", {
                PlantId = plantId,
                Mutation = mutationLevel,
                Quantity = getAmount(),
            })
        end)
        return
    end

    local row = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(31, 39, 50),
        BorderSizePixel = 0,
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, -8, 0, 74),
    }, parent)
    row:SetAttribute("TradeGenerated", true)
    addCorner(row, 7)
    addStroke(row, getQualityColor(plantDetail.Quality), 1)

    local iconButton = make("ImageButton", {
        AutoButtonColor = true,
        BackgroundTransparency = 1,
        Image = plantDetail.IconId or "",
        Position = UDim2.new(0, 8, 0.12, 0),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.new(0, 48, 0, 48),
    }, row)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(0, 64, 0, 8),
        Size = UDim2.new(1, -208, 0, 24),
        Text = plantDetail.Name or plantId,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Position = UDim2.new(0, 64, 0, 36),
        Size = UDim2.new(1, -208, 0, 22),
        Text = getMutationName(mutationLevel) .. "  Owned x" .. tostring(quantity),
        TextColor3 = Color3.fromRGB(189, 207, 226),
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local minusButton = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(79, 92, 108),
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -136, 0.5, -16),
        Size = UDim2.new(0, 28, 0, 32),
        Text = "-",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, row)
    addCorner(minusButton, 5)

    local amountBox = make("TextBox", {
        BackgroundColor3 = Color3.fromRGB(15, 21, 30),
        ClearTextOnFocus = false,
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -104, 0.5, -16),
        Size = UDim2.new(0, 38, 0, 32),
        Text = tostring(math.clamp(getExistingOfferQuantity(plantId, mutationLevel) > 0 and getExistingOfferQuantity(plantId, mutationLevel) or 1, 1, quantity)),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, row)
    addCorner(amountBox, 5)
    addStroke(amountBox, Color3.fromRGB(99, 125, 155), 1)

    local plusButton = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(79, 92, 108),
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -62, 0.5, -16),
        Size = UDim2.new(0, 28, 0, 32),
        Text = "+",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, row)
    addCorner(plusButton, 5)

    local uploadButton = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(42, 164, 89),
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -30, 0.5, -16),
        Size = UDim2.new(0, 24, 0, 32),
        Text = ">",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, row)
    addCorner(uploadButton, 5)

    local controls = { minusButton, amountBox, plusButton, uploadButton }
    for _, control in ipairs(controls) do
        control.Visible = false
    end

    bindInventoryRowSelection(row, iconButton, controls, amountBox)

    local function getAmount()
        local amount = math.floor(tonumber(amountBox.Text) or 1)
        amount = math.clamp(amount, 1, quantity)
        amountBox.Text = tostring(amount)
        return amount
    end

    minusButton.Activated:Connect(function()
        amountBox.Text = tostring(math.max(1, getAmount() - 1))
    end)

    plusButton.Activated:Connect(function()
        amountBox.Text = tostring(math.min(quantity, getAmount() + 1))
    end)

    amountBox.FocusLost:Connect(function()
        getAmount()
    end)

    uploadButton.Activated:Connect(function()
        remoteEvent:FireServer("SetOfferItem", {
            PlantId = plantId,
            Mutation = mutationLevel,
            Quantity = getAmount(),
        })
    end)
end

local function renderInventory()
    currentInventorySelectionControls = nil
    lastInventorySelectionToggleControls = nil
    lastInventorySelectionToggleAt = 0
    clearGeneratedChildren(inventoryContainer)
    local data = playerData or fetchPlayerData()
    if not (data and data.Inventory and type(data.Inventory.Plants) == "table") then
        return
    end

    local entries = {}
    for _, plantData in ipairs(data.Inventory.Plants) do
        local plantId = plantData.ID
        local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
        if plantDetail and (tonumber(plantData.Quantity) or 0) > 0 then
            table.insert(entries, {
                Data = plantData,
                Quality = tonumber(plantDetail.Quality) or 1,
                Name = plantDetail.Name or plantId,
            })
        end
    end

    table.sort(entries, function(a, b)
        if a.Quality == b.Quality then
            return tostring(a.Name) < tostring(b.Name)
        end
        return a.Quality > b.Quality
    end)

    for index, entry in ipairs(entries) do
        createInventoryRow(inventoryContainer, entry.Data, index)
    end
end

local function renderSessionState(state)
    currentSessionState = state
    if not currentSessionState then
        return
    end

    local partnerUserId = getPartnerUserId(currentSessionState)
    local partnerInfo = partnerUserId and getStatePlayerInfo(partnerUserId)
    setGuiText(titleLabel, partnerInfo and ("Trade with " .. tostring(partnerInfo.DisplayName)) or "Trade")
    setRootVisible(true)
    mainFrame.Visible = true
    inviteFrame.Visible = false

    renderOfferContainers()
    renderInventory()
end

local function hideTrade()
    currentSessionState = nil
    currentInviteId = nil
    inviteAcceptCallback = nil
    inviteDeclineCallback = nil
    inviteCancelCallback = nil
    currentInventorySelectionControls = nil
    lastInventorySelectionToggleControls = nil
    lastInventorySelectionToggleAt = 0
    lastEmojiAnimationKeys = {}
    localEmojiPendingKind = nil
    localEmojiPendingUntil = 0
    if mainFrame then
        mainFrame.Visible = false
    end
    if inviteFrame then
        inviteFrame.Visible = false
    end
    setRootVisible(false)
end

local function cancelAnyTradeOnServer()
    remoteEvent:FireServer("CancelAny")
end

local function closeInviteOnly()
    if inviteFrame then
        inviteFrame.Visible = false
    end
    if not (mainFrame and mainFrame.Visible) then
        setRootVisible(false)
    end
end

local function showInvite(mode, message, acceptCallback, declineCallback, cancelCallback)
    inviteAcceptCallback = acceptCallback
    inviteDeclineCallback = declineCallback
    inviteCancelCallback = cancelCallback
    if mode == "received" and not inviteDeclineButton then
        inviteCancelCallback = declineCallback
    end

    setGuiText(inviteMessage, message)
    inviteAcceptButton.Visible = mode == "confirm" or mode == "received"
    if inviteDeclineButton then
        inviteDeclineButton.Visible = mode == "received"
    end
    inviteCancelButton.Visible = mode == "confirm" or mode == "pending" or (mode == "received" and not inviteDeclineButton)

    if mode == "confirm" then
        setGuiText(inviteAcceptButton, "Yes")
        setGuiText(inviteCancelButton, "No")
    elseif mode == "pending" then
        setGuiText(inviteCancelButton, "Cancel")
    elseif mode == "received" then
        setGuiText(inviteAcceptButton, "Accept")
        setGuiText(inviteDeclineButton or inviteCancelButton, "Decline")
    end

    setRootVisible(true)
    inviteFrame.Visible = true
end

local function showTradeConfirm(targetPlayer)
    if not (targetPlayer and targetPlayer.Parent == Players) then
        return
    end
    if isTradeUiOpen() then
        return
    end
    if isBossUILocked() then
        showTip("Defeat Dr. Zomboss first.")
        return
    end

    showInvite(
        "confirm",
        "Trade with " .. targetPlayer.DisplayName .. "?",
        function()
            remoteEvent:FireServer("RequestInvite", targetPlayer)
            showInvite(
                "pending",
                "Waiting for " .. targetPlayer.DisplayName .. "...",
                nil,
                nil,
                function()
                    if currentInviteId then
                        remoteEvent:FireServer("CancelInvite", currentInviteId)
                    end
                    closeInviteOnly()
                end
            )
        end,
        nil,
        function()
            closeInviteOnly()
        end
    )
end

local function buildInviteUi(parent)
    inviteFrame = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(20, 27, 36),
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 360, 0, 170),
        Visible = false,
    }, parent)
    addCorner(inviteFrame, 10)
    addStroke(inviteFrame, Color3.fromRGB(111, 145, 184), 2)

    inviteMessage = createLabel(inviteFrame, "", UDim2.new(1, -28, 0, 78), UDim2.new(0, 14, 0, 18))

    inviteAcceptButton = make("TextButton", {
        Position = UDim2.new(0, 26, 1, -56),
        Size = UDim2.new(0, 92, 0, 38),
        Text = "Accept",
    }, inviteFrame)
    styleButton(inviteAcceptButton, Color3.fromRGB(42, 164, 89))

    inviteDeclineButton = make("TextButton", {
        Position = UDim2.new(0.5, -46, 1, -56),
        Size = UDim2.new(0, 92, 0, 38),
        Text = "Decline",
    }, inviteFrame)
    styleButton(inviteDeclineButton, Color3.fromRGB(202, 58, 58))

    inviteCancelButton = make("TextButton", {
        Position = UDim2.new(1, -118, 1, -56),
        Size = UDim2.new(0, 92, 0, 38),
        Text = "Cancel",
    }, inviteFrame)
    styleButton(inviteCancelButton, Color3.fromRGB(95, 109, 126))

    inviteAcceptButton.Activated:Connect(function()
        if inviteAcceptCallback then
            inviteAcceptCallback()
        end
    end)
    inviteDeclineButton.Activated:Connect(function()
        if inviteDeclineCallback then
            inviteDeclineCallback()
        end
    end)
    inviteCancelButton.Activated:Connect(function()
        if inviteCancelCallback then
            inviteCancelCallback()
        end
    end)
end

local function buildMainUi(parent)
    mainFrame = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(13, 18, 25),
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 980, 0, 610),
        Visible = false,
    }, parent)
    addCorner(mainFrame, 10)
    addStroke(mainFrame, Color3.fromRGB(126, 151, 179), 2)

    titleLabel = createLabel(mainFrame, "Trade", UDim2.new(1, -120, 0, 40), UDim2.new(0, 24, 0, 12))

    local closeButton = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(178, 48, 48),
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -52, 0, 14),
        Size = UDim2.new(0, 34, 0, 34),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextScaled = true,
    }, mainFrame)
    addCorner(closeButton, 6)
    closeButton.Activated:Connect(function()
        remoteEvent:FireServer("CancelSession")
    end)

    local leftPanel = createPanel(mainFrame, "Trade Window", UDim2.new(0, 18, 0, 62), UDim2.new(0, 560, 0, 470))
    local inventoryPanel = createPanel(mainFrame, "My Backpack", UDim2.new(0, 596, 0, 62), UDim2.new(1, -614, 0, 470))

    createLabel(leftPanel, "Other Offer", UDim2.new(0.48, 0, 0, 24), UDim2.new(0, 12, 0, 38))
    createLabel(leftPanel, "My Offer", UDim2.new(0.48, 0, 0, 24), UDim2.new(0, 12, 0, 250))

    otherOfferContainer = createScrollingGrid(leftPanel, UDim2.new(0, 12, 0, 66), UDim2.new(1, -92, 0, 130), UDim2.new(0, 76, 0, 92))
    myOfferContainer = createScrollingGrid(leftPanel, UDim2.new(0, 12, 0, 278), UDim2.new(1, -92, 0, 130), UDim2.new(0, 76, 0, 92))

    otherEmojiImage = make("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -70, 0, 78),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.new(0, 52, 0, 52),
        Visible = false,
    }, leftPanel)
    otherEmojiLabel = createLabel(leftPanel, "", UDim2.new(0, 56, 0, 34), UDim2.new(1, -72, 0, 88))
    otherEmojiLabel.Visible = false

    myEmojiImage = make("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -70, 0, 290),
        ScaleType = Enum.ScaleType.Fit,
        Size = UDim2.new(0, 52, 0, 52),
        Visible = false,
    }, leftPanel)
    myEmojiLabel = createLabel(leftPanel, "", UDim2.new(0, 56, 0, 34), UDim2.new(1, -72, 0, 300))
    myEmojiLabel.Visible = false

    statusLabelA = createLabel(leftPanel, "Other ready: NO", UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 0, 208))
    statusLabelB = createLabel(leftPanel, "You ready: NO", UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 0, 420))
    statusLabelA.TextColor3 = Color3.fromRGB(128, 158, 255)
    statusLabelB.TextColor3 = Color3.fromRGB(128, 158, 255)

    local okButton = make("TextButton", {
        Position = UDim2.new(0, 18, 1, -58),
        Size = UDim2.new(0, 72, 0, 40),
        Text = "OK",
    }, mainFrame)
    styleButton(okButton, Color3.fromRGB(42, 164, 89))
    okButton.Activated:Connect(function()
        sendTradeEmoji("OK")
    end)

    local noButton = make("TextButton", {
        Position = UDim2.new(0, 98, 1, -58),
        Size = UDim2.new(0, 72, 0, 40),
        Text = "NO",
    }, mainFrame)
    styleButton(noButton, Color3.fromRGB(202, 58, 58))
    noButton.Activated:Connect(function()
        sendTradeEmoji("NO")
    end)

    local cancelButton = make("TextButton", {
        Position = UDim2.new(0.5, -124, 1, -58),
        Size = UDim2.new(0, 112, 0, 40),
        Text = "Cancel Trade",
    }, mainFrame)
    styleButton(cancelButton, Color3.fromRGB(202, 58, 58))
    cancelButton.Activated:Connect(function()
        remoteEvent:FireServer("CancelSession")
    end)

    confirmButton = make("TextButton", {
        Position = UDim2.new(0.5, 12, 1, -58),
        Size = UDim2.new(0, 128, 0, 40),
        Text = "Confirm Trade",
    }, mainFrame)
    styleButton(confirmButton, Color3.fromRGB(42, 164, 89))
    confirmButton.Activated:Connect(function()
        if currentSessionState and currentSessionState.Ready and currentSessionState.Ready[tostring(localPlayer.UserId)] then
            remoteEvent:FireServer("SetReady", false)
        else
            remoteEvent:FireServer("SetReady", true)
        end
    end)

    inventoryContainer = make("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0, 10, 0, 42),
        ScrollBarThickness = 6,
        Size = UDim2.new(1, -20, 1, -52),
    }, inventoryPanel)

    local inventoryList = make("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, inventoryContainer)
    inventoryList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        inventoryContainer.CanvasSize = UDim2.new(0, 0, 0, inventoryList.AbsoluteContentSize.Y + 10)
    end)
end

local function ensureUi()
    if screenGui then
        return
    end

    local guiParent = getGuiParent()
    local existingGui = guiParent:FindFirstChild("TradeGui")
    if existingGui and existingGui:IsA("ScreenGui") and bindEditorUi(existingGui) then
        return
    end

    screenGui = make("ScreenGui", {
        DisplayOrder = 180,
        IgnoreGuiInset = true,
        Name = "TradeGui",
        ResetOnSpawn = false,
    }, guiParent)
    tradeRootFrame = make("Frame", {
        Active = true,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Name = "TradeFrame",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        Visible = false,
    }, screenGui)

    buildInviteUi(tradeRootFrame)
    buildMainUi(tradeRootFrame)
    ensureTradeBlurOverlay()
    raiseGuiTree(mainFrame, TRADE_PANEL_MIN_Z_INDEX)
    raiseGuiTree(inviteFrame, TRADE_PANEL_MIN_Z_INDEX)
    hideTrade()
end

local function attachPromptToCharacter(player, character)
    if player == localPlayer or not character then
        return
    end

    task.spawn(function()
        local root = character:WaitForChild("HumanoidRootPart", 10)
        if not root or root:FindFirstChild(promptName) then
            return
        end

        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = promptName
        prompt.ActionText = "Trade"
        prompt.ObjectText = player.DisplayName
        prompt.HoldDuration = tonumber(TradeConfig.PromptHoldDuration) or 0
        prompt.MaxActivationDistance = tonumber(TradeConfig.PromptDistance) or 12
        prompt.RequiresLineOfSight = false
        prompt.Parent = root
        tradePrompts[prompt] = true
        prompt.AncestryChanged:Connect(function()
            if not prompt.Parent then
                tradePrompts[prompt] = nil
            end
        end)
        refreshTradePromptEnabled()

        prompt.Triggered:Connect(function()
            ensureUi()
            if isTradePromptBlockedByEquippedItem() then
                return
            end
            if isTradeUiOpen() then
                return
            end
            if isBossUILocked() then
                showTip("Defeat Dr. Zomboss first.")
                return
            end
            showTradeConfirm(player)
        end)
    end)
end

-- 监听本地玩家装备切换，手持武器时隐藏交易 Prompt，卸下后恢复。
local function bindLocalCharacterPromptState(character)
    if localEquipChangedConnection then
        localEquipChangedConnection:Disconnect()
        localEquipChangedConnection = nil
    end

    if not character then
        refreshTradePromptEnabled()
        return
    end

    localEquipChangedConnection = character:GetAttributeChangedSignal("EquippedSeed"):Connect(refreshTradePromptEnabled)
    refreshTradePromptEnabled()
end

local function watchPlayer(player)
    if player == localPlayer then
        return
    end

    if player.Character then
        attachPromptToCharacter(player, player.Character)
    end
    player.CharacterAdded:Connect(function(character)
        attachPromptToCharacter(player, character)
    end)
end

function TradeController.Init()
    ensureUi()
    fetchPlayerData()
    bindLocalCharacterPromptState(localPlayer.Character)
    localPlayer.CharacterAdded:Connect(bindLocalCharacterPromptState)

    for _, player in ipairs(Players:GetPlayers()) do
        watchPlayer(player)
    end
    Players.PlayerAdded:Connect(watchPlayer)

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 10)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function(newData)
            if type(newData) == "table" then
                playerData = newData
                if mainFrame and mainFrame.Visible then
                    renderInventory()
                end
            end
        end)
    end

    remoteEvent.OnClientEvent:Connect(function(action, payload)
        action = tostring(action or "")

        if isBossUILocked()
            and (
                action == "InvitePending"
                or action == "InviteReceived"
                or action == "SessionStarted"
                or action == "SessionState"
            )
        then
            cancelAnyTradeOnServer()
            hideTrade()
            return
        end

        if action == "InvitePending" then
            currentInviteId = payload and payload.InviteId
            local targetName = payload and payload.TargetName or "player"
            showInvite(
                "pending",
                "Waiting for " .. tostring(targetName) .. "...",
                nil,
                nil,
                function()
                    if currentInviteId then
                        remoteEvent:FireServer("CancelInvite", currentInviteId)
                    end
                    closeInviteOnly()
                end
            )
        elseif action == "InviteReceived" then
            currentInviteId = payload and payload.InviteId
            local fromName = payload and payload.FromName or "A player"
            showInvite(
                "received",
                tostring(fromName) .. " wants to trade.",
                function()
                    remoteEvent:FireServer("RespondInvite", currentInviteId, true)
                    closeInviteOnly()
                end,
                function()
                    remoteEvent:FireServer("RespondInvite", currentInviteId, false)
                    closeInviteOnly()
                end,
                nil
            )
        elseif action == "InviteClosed" then
            currentInviteId = nil
            closeInviteOnly()
            if payload and payload.Message then
                showTip(payload.Message)
            end
        elseif action == "SessionStarted" then
            lastEmojiAnimationKeys = {}
            localEmojiPendingKind = nil
            localEmojiPendingUntil = 0
            fetchPlayerData()
            renderSessionState(payload)
        elseif action == "SessionState" then
            renderSessionState(payload)
        elseif action == "SessionClosed" then
            hideTrade()
            fetchPlayerData()
            if payload and payload.Reason then
                showTip(payload.Reason)
            end
        elseif action == "TradeComplete" then
            hideTrade()
            fetchPlayerData()
            showTip((payload and payload.Message) or "Trade complete.")
        elseif action == "Error" then
            if inviteFrame and inviteFrame.Visible and not (mainFrame and mainFrame.Visible) then
                closeInviteOnly()
                currentInviteId = nil
            end
            if payload and payload.Message then
                showTip(payload.Message)
            end
        end
    end)
end

function TradeController.ForceCloseForBoss()
    local hadTradeUi = currentSessionState ~= nil
        or currentInviteId ~= nil
        or (inviteFrame and inviteFrame.Visible)
        or (mainFrame and mainFrame.Visible)

    if hadTradeUi then
        cancelAnyTradeOnServer()
    end

    hideTrade()
end

return TradeController

-- src/client/UI/IAPShopController.luau
local IAPShopController = {}

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
local ExclusiveRollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ExclusiveRollConfig"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local X2_SUN_GAME_PASS_ID = 1856661235

local function setGuiOpen(gui, isOpen)
    if not gui then
        return
    end

    if gui:IsA("ScreenGui") then
        gui.Enabled = isOpen
    elseif gui:IsA("GuiObject") then
        gui.Visible = isOpen
    else
        pcall(function()
            gui.Enabled = isOpen
        end)
    end
end

local function findButton(root)
    if not root then
        return nil
    end

    if root:IsA("GuiButton") then
        return root
    end

    return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function getExclamationTemplate()
    local templates = ReplicatedStorage:FindFirstChild("UITemplates")
    return templates and templates:FindFirstChild("Exclamation")
end

local function waitForPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        if not current then
            return nil
        end
        current = current:WaitForChild(name, 10)
    end
    return current
end

local function findPath(root, path)
    local current = root
    for _, name in ipairs(path or {}) do
        if not current then
            return nil
        end
        current = current:FindFirstChild(name)
    end
    return current
end

local function findServerLuckX2Button(buyButtons)
    if not buyButtons then
        return nil
    end

    local explicit = buyButtons:FindFirstChild("1按钮") or buyButtons:FindFirstChild("1")
    if explicit then
        return findButton(explicit)
    end

    return buyButtons:FindFirstChildWhichIsA("GuiButton", true)
end

local function findImageObject(root)
    if not root then
        return nil
    end

    if root:IsA("ImageLabel") or root:IsA("ImageButton") then
        return root
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
            return descendant
        end
    end

    return nil
end

local function findTextObject(root)
    if not root then
        return nil
    end

    if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
        return root
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
            return descendant
        end
    end

    return nil
end

local exclusiveOutcomeSlots = {}
local exclusiveOutcomeSlotsByGroup = {}
local currentOutcomeIndexByGroup = {}
local originalGradientColors = setmetatable({}, { __mode = "k" })
local exclusiveAnimationQueue = {}
local isPlayingExclusiveAnimation = false
local currentOutcomeIndex = 0
local exclusiveRewardShowFrame = nil
local exclusiveRewardIconTemplate = nil
local exclusiveRewardFlightLayer = nil
local exclusiveRewardShowQueue = {}
local exclusivePityTextObject = nil
local exclusivePityTextObjectsByGroup = {}
local exclusiveRollCloseLocked = false
local exclusiveRollCloseLockToken = 0
local exclusiveTicketButton = nil
local exclusiveTicketPriceTextObject = nil
local exclusiveTicketCount = 0
local exclusiveTicketRollInProgress = false
local exclusiveTicketRollRF = nil
local exclusiveFreeRollStates = {}
local exclusiveFreeRollStatusLoopStarted = false
local iapShopNotificationParent = nil
local warnedMissingExclamationTemplate = false

local EXCLUSIVE_ROLL_EXCLAMATION_NAME = "ExclusiveRollExclamation"

local function setExclamation(parent, enabled)
    if not (parent and parent.Parent) then
        return
    end

    local hostParent = parent.Parent
    local existing = hostParent:FindFirstChild(EXCLUSIVE_ROLL_EXCLAMATION_NAME)
    local function placeAtTarget(node)
        if node:IsA("GuiObject") and parent:IsA("GuiObject") then
            node.AnchorPoint = parent.AnchorPoint
            node.Position = parent.Position
            node.ZIndex = math.max(node.ZIndex, parent.ZIndex + 10)
            node.Active = false
        end
    end

    if enabled then
        if existing then
            if existing:IsA("GuiObject") then
                existing.Visible = true
            end
            placeAtTarget(existing)
            return
        end

        local template = getExclamationTemplate()
        if not template then
            if not warnedMissingExclamationTemplate then
                warnedMissingExclamationTemplate = true
                warn("[IAPShopController] ReplicatedStorage.UITemplates.Exclamation was not found.")
            end
            return
        end

        local clone = template:Clone()
        clone.Name = EXCLUSIVE_ROLL_EXCLAMATION_NAME
        if clone:IsA("GuiObject") then
            clone.Visible = true
        end
        placeAtTarget(clone)
        clone.Parent = hostParent
    elseif existing then
        existing:Destroy()
    end
end

local function setExclusiveRollCloseLocked(isLocked, timeoutSeconds)
    exclusiveRollCloseLockToken += 1
    local lockToken = exclusiveRollCloseLockToken
    exclusiveRollCloseLocked = isLocked == true

    if exclusiveRollCloseLocked and timeoutSeconds and timeoutSeconds > 0 then
        task.delay(timeoutSeconds, function()
            if exclusiveRollCloseLocked and exclusiveRollCloseLockToken == lockToken and not isPlayingExclusiveAnimation then
                exclusiveRollCloseLocked = false
            end
        end)
    end
end

local function getSelectedGradientColor()
    local animationConfig = ExclusiveRollConfig.Animation or {}
    return animationConfig.SelectedGradientColor or ColorSequence.new(Color3.fromRGB(255, 255, 255))
end

local function getRollAnimationDuration(productKey)
    local animationConfig = ExclusiveRollConfig.Animation or {}
    local durationByProductKey = animationConfig.DurationByProductKey or {}
    return math.max(0.05, tonumber(durationByProductKey[productKey]) or 0.5)
end

local function getResultHoldDuration()
    local animationConfig = ExclusiveRollConfig.Animation or {}
    return math.max(0, tonumber(animationConfig.ResultHoldDuration) or 0)
end

local function getPreAnimationDelay()
    local animationConfig = ExclusiveRollConfig.Animation or {}
    return math.max(0, tonumber(animationConfig.PreAnimationDelay) or 0)
end

local function getRollGroupKey(rollGroup)
    if type(rollGroup) == "string" and rollGroup ~= "" then
        return rollGroup
    end

    return "Exclusive"
end

local function getRollGroupConfig(rollGroup)
    if ExclusiveRollConfig.GetRollGroupConfig then
        return ExclusiveRollConfig.GetRollGroupConfig(getRollGroupKey(rollGroup))
    end

    return ExclusiveRollConfig, "Exclusive"
end

local function getPityConfig(rollGroup)
    local rollConfig = getRollGroupConfig(rollGroup)
    if type(rollConfig.Pity) == "table" then
        return rollConfig.Pity
    end

    return nil
end

local function getPityGuaranteeAt(rollGroup)
    local pityConfig = getPityConfig(rollGroup) or {}
    return math.max(1, math.floor(tonumber(pityConfig.GuaranteeAt) or 100))
end

local function getPityDataKey(rollGroup)
    local pityConfig = getPityConfig(rollGroup) or {}
    return pityConfig.DataKey or "ExclusiveRollPity_Rotobaga"
end

local function setExclusivePityText(currentPity, rollGroup)
    local groupKey = getRollGroupKey(rollGroup)
    local pityTextObject = exclusivePityTextObjectsByGroup[groupKey]
    if not pityTextObject then
        return
    end

    local guaranteeAt = getPityGuaranteeAt(groupKey)
    local normalizedPity = math.clamp(math.floor(tonumber(currentPity) or 0), 0, guaranteeAt)
    pityTextObject.Text = "Pity " .. tostring(normalizedPity) .. "/" .. tostring(guaranteeAt)
end

local function refreshExclusivePityFromData(data)
    if type(data) ~= "table" then
        return
    end

    if getPityConfig("Exclusive") then
        setExclusivePityText(data[getPityDataKey("Exclusive")], "Exclusive")
    end

    for groupKey in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        if getPityConfig(groupKey) then
            setExclusivePityText(data[getPityDataKey(groupKey)], groupKey)
        end
    end
end

local function getExclusiveTicketConfig()
    return ExclusiveRollConfig.TicketRoll or {}
end

local function getExclusiveTicketDataKey()
    local ticketConfig = getExclusiveTicketConfig()
    return ticketConfig.DataKey or "ExclusiveRollTickets"
end

local function getExclusiveTicketCountFromData(data)
    if type(data) ~= "table" then
        return 0
    end

    return math.max(0, math.floor(tonumber(data[getExclusiveTicketDataKey()]) or 0))
end

local function setExclusiveTicketCount(count)
    exclusiveTicketCount = math.max(0, math.floor(tonumber(count) or 0))

    if exclusiveTicketPriceTextObject then
        exclusiveTicketPriceTextObject.Text = tostring(exclusiveTicketCount)
    end

    setExclamation(iapShopNotificationParent, exclusiveTicketCount > 0)
end

local function refreshExclusiveTicketFromData(data)
    setExclusiveTicketCount(getExclusiveTicketCountFromData(data))
end

local function getExclusiveFreeRollDataKey(freeRollConfig)
    local dataKey = freeRollConfig and freeRollConfig.DataKey or nil
    if type(dataKey) == "string" and dataKey ~= "" then
        return dataKey
    end

    return nil
end

local function formatExclusiveFreeRollText(remainingSeconds, readyText)
    remainingSeconds = math.max(0, math.ceil(tonumber(remainingSeconds) or 0))
    if remainingSeconds <= 0 then
        return readyText or "Claim"
    end

    local minutes = math.floor(remainingSeconds / 60)
    local seconds = remainingSeconds % 60
    return string.format("(%02d:%02d)", minutes, seconds)
end

local function getExclusiveFreeRollRemaining(groupKey)
    local state = exclusiveFreeRollStates[groupKey]
    if not state then
        return 0
    end

    return math.max(0, math.ceil((tonumber(state.ReadyAtClock) or 0) - os.clock()))
end

local function updateExclusiveFreeRollText(groupKey)
    local state = exclusiveFreeRollStates[groupKey]
    if not state or not state.PriceTextObject then
        return
    end

    state.PriceTextObject.Text = formatExclusiveFreeRollText(getExclusiveFreeRollRemaining(groupKey), state.ReadyText)
end

local function setExclusiveFreeRollRemaining(groupKey, remainingSeconds, cooldownSeconds)
    local state = exclusiveFreeRollStates[groupKey]
    if not state then
        return
    end

    state.CooldownSeconds = math.max(1, math.floor(tonumber(cooldownSeconds) or state.CooldownSeconds or 300))
    state.ReadyAtClock = os.clock() + math.max(0, tonumber(remainingSeconds) or 0)
    updateExclusiveFreeRollText(groupKey)
end

local function refreshExclusiveFreeRollsFromData(data)
    if type(data) ~= "table" then
        return
    end

    for groupKey, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        local freeRollConfig = groupConfig.FreeRoll
        if type(freeRollConfig) == "table" and exclusiveFreeRollStates[groupKey] then
            local dataKey = getExclusiveFreeRollDataKey(freeRollConfig)
            if not dataKey then
                continue
            end

            local nextAt = math.max(0, math.floor(tonumber(data[dataKey]) or 0))
            setExclusiveFreeRollRemaining(
                groupKey,
                math.max(0, nextAt - os.time()),
                freeRollConfig.CooldownSeconds
            )
        end
    end
end

local function requestExclusiveFreeRollStatus(groupKey)
    local state = exclusiveFreeRollStates[groupKey]
    if not (state and state.Remote) then
        return
    end

    task.spawn(function()
        local ok, success, remainingOrMessage, cooldownSeconds = pcall(function()
            return state.Remote:InvokeServer("status")
        end)

        if not ok then
            warn("[IAPShopController] Exclusive free roll status failed: " .. tostring(success))
            return
        end
        if success then
            setExclusiveFreeRollRemaining(groupKey, remainingOrMessage, cooldownSeconds)
        end
    end)
end

local function requestExclusiveFreeRollStatuses()
    for groupKey in pairs(exclusiveFreeRollStates) do
        requestExclusiveFreeRollStatus(groupKey)
    end
end

local function startExclusiveFreeRollStatusLoop()
    if exclusiveFreeRollStatusLoopStarted then
        return
    end
    exclusiveFreeRollStatusLoopStarted = true

    task.spawn(function()
        while true do
            for groupKey in pairs(exclusiveFreeRollStates) do
                updateExclusiveFreeRollText(groupKey)
            end
            task.wait(1)
        end
    end)
end

local function requestExclusivePityRefresh()
    local getPlayerDataRF = ReplicatedStorage:FindFirstChild("GetPlayerDataRF")
    if not getPlayerDataRF then
        return
    end

    task.spawn(function()
        local ok, data = pcall(function()
            return getPlayerDataRF:InvokeServer()
        end)
        if ok then
            refreshExclusivePityFromData(data)
            refreshExclusiveTicketFromData(data)
            refreshExclusiveFreeRollsFromData(data)
        end
    end)
end

local function collectExclusiveOutcomeSlotsForGroup(iapShopGui, rollGroup, rollConfig)
    local groupKey = getRollGroupKey(rollGroup)
    local slots = {}
    exclusiveOutcomeSlotsByGroup[groupKey] = slots

    local outcomesRoot = waitForPath(iapShopGui, rollConfig.OutcomesPath or {})
    if not outcomesRoot then
        warn("[IAPShopController] Exclusive outcomes root was not found: " .. groupKey)
        return
    end

    for index, plantId in ipairs(rollConfig.OutcomeOrder or {}) do
        local outcome = outcomesRoot:WaitForChild(tostring(index), 10)
        local stroke = outcome and outcome:FindFirstChild("UIStroke")
        local gradient = stroke and stroke:FindFirstChild("UIGradient")
        local imageObject = findImageObject(outcome)

        if gradient and gradient:IsA("UIGradient") then
            originalGradientColors[gradient] = gradient.Color
            slots[index] = {
                PlantId = plantId,
                Gradient = gradient,
                ImageObject = imageObject,
            }
        else
            warn("[IAPShopController] Exclusive outcome gradient was not found: " .. groupKey .. "/" .. tostring(index))
        end
    end
end

local function collectExclusiveOutcomeSlots(iapShopGui)
    table.clear(exclusiveOutcomeSlots)
    table.clear(exclusiveOutcomeSlotsByGroup)
    collectExclusiveOutcomeSlotsForGroup(iapShopGui, "Exclusive", ExclusiveRollConfig)
    exclusiveOutcomeSlots = exclusiveOutcomeSlotsByGroup.Exclusive or {}

    for groupKey, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        collectExclusiveOutcomeSlotsForGroup(iapShopGui, groupKey, groupConfig)
    end
end

local function collectExclusivePityTextForGroup(iapShopGui, rollGroup, rollConfig)
    local groupKey = getRollGroupKey(rollGroup)
    local pityConfig = type(rollConfig.Pity) == "table" and rollConfig.Pity or nil
    if not pityConfig then
        return
    end

    local pityRoot = waitForPath(iapShopGui, pityConfig.TextPath or { "Store", "StoreFrame", "Container", "Exclusive", "Pity" })
    local pityTextObject = findTextObject(pityRoot)
    exclusivePityTextObjectsByGroup[groupKey] = pityTextObject
    if groupKey == "Exclusive" then
        exclusivePityTextObject = pityTextObject
    end

    if not pityTextObject then
        warn("[IAPShopController] Exclusive pity text was not found: " .. groupKey)
        return
    end

    setExclusivePityText(0, groupKey)
end

local function collectExclusivePityText(iapShopGui)
    table.clear(exclusivePityTextObjectsByGroup)
    exclusivePityTextObject = nil
    collectExclusivePityTextForGroup(iapShopGui, "Exclusive", ExclusiveRollConfig)

    for groupKey, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        collectExclusivePityTextForGroup(iapShopGui, groupKey, groupConfig)
    end
end

local function getRewardShowDuration()
    local rewardShowConfig = ExclusiveRollConfig.RewardShow or {}
    return math.max(0, tonumber(rewardShowConfig.Duration) or 2)
end

local function getRewardShowMoveDuration()
    local rewardShowConfig = ExclusiveRollConfig.RewardShow or {}
    return math.max(0.05, tonumber(rewardShowConfig.MoveDuration) or 0.45)
end

local function getRewardShowTargetPosition()
    local rewardShowConfig = ExclusiveRollConfig.RewardShow or {}
    if typeof(rewardShowConfig.TargetPosition) == "UDim2" then
        return rewardShowConfig.TargetPosition
    end

    return UDim2.new(0.5, 0, 0.82, 0)
end

local function getExclusiveOutcomeSlots(rollGroup)
    return exclusiveOutcomeSlotsByGroup[getRollGroupKey(rollGroup)] or exclusiveOutcomeSlots
end

local function getExclusiveOutcomeSlotByPlantId(plantId, rollGroup)
    local outcomeIndex = ExclusiveRollConfig.GetOutcomeIndex(plantId, getRollGroupKey(rollGroup))
    if not outcomeIndex then
        return nil
    end

    return getExclusiveOutcomeSlots(rollGroup)[outcomeIndex]
end

local function getExclusiveRewardImage(plantId, rollGroup)
    local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
    if plantDetail and type(plantDetail.IconId) == "string" and plantDetail.IconId ~= "" then
        return plantDetail.IconId
    end

    local slot = getExclusiveOutcomeSlotByPlantId(plantId, rollGroup)
    local imageObject = slot and slot.ImageObject
    if imageObject and type(imageObject.Image) == "string" and imageObject.Image ~= "" then
        return imageObject.Image
    end

    return ""
end

local function clearExclusiveRewardIcons()
    local iconParent = exclusiveRewardFlightLayer or exclusiveRewardShowFrame
    if not iconParent then
        return
    end

    for _, child in ipairs(iconParent:GetChildren()) do
        if child:GetAttribute("ExclusiveRewardShowClone") == true then
            child:Destroy()
        end
    end
end

local function hasExclusiveRewardIcons()
    local iconParent = exclusiveRewardFlightLayer or exclusiveRewardShowFrame
    if not iconParent then
        return false
    end

    for _, child in ipairs(iconParent:GetChildren()) do
        if child:GetAttribute("ExclusiveRewardShowClone") == true then
            return true
        end
    end

    return false
end

local function setGuiTreeZIndex(root, zIndex)
    if root:IsA("GuiObject") then
        root.ZIndex = math.max(root.ZIndex, zIndex)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            descendant.ZIndex = math.max(descendant.ZIndex, zIndex)
        end
    end
end

local function createExclusiveRewardFlightLayer(iapShopGui)
    local rootGui = iapShopGui:IsA("ScreenGui") and iapShopGui or iapShopGui:FindFirstAncestorOfClass("ScreenGui")
    if not rootGui then
        return nil
    end

    local layer = rootGui:FindFirstChild("ExclusiveRewardFlightLayer")
    if not layer then
        layer = Instance.new("Frame")
        layer.Name = "ExclusiveRewardFlightLayer"
        layer.BackgroundTransparency = 1
        layer.BorderSizePixel = 0
        layer.ClipsDescendants = false
        layer.Size = UDim2.fromScale(1, 1)
        layer.Position = UDim2.fromScale(0, 0)
        layer.AnchorPoint = Vector2.new(0, 0)
        layer.Active = false
        layer.ZIndex = 10000
        layer.Parent = rootGui
    end

    layer.Visible = false
    return layer
end

local function collectExclusiveRewardShow(iapShopGui)
    local rewardShowConfig = ExclusiveRollConfig.RewardShow or {}
    exclusiveRewardShowFrame = waitForPath(iapShopGui, rewardShowConfig.ShowPath or { "Show" })
    if not exclusiveRewardShowFrame then
        warn("[IAPShopController] Exclusive reward show frame was not found.")
        return
    end

    local iconName = rewardShowConfig.IconName or "Icon"
    exclusiveRewardIconTemplate = exclusiveRewardShowFrame:WaitForChild(iconName, 10)
    if not exclusiveRewardIconTemplate then
        warn("[IAPShopController] Exclusive reward show icon template was not found.")
        setGuiOpen(exclusiveRewardShowFrame, false)
        return
    end

    if exclusiveRewardIconTemplate:IsA("GuiObject") then
        exclusiveRewardIconTemplate.Visible = false
    end
    exclusiveRewardFlightLayer = createExclusiveRewardFlightLayer(iapShopGui)
    if not exclusiveRewardFlightLayer then
        warn("[IAPShopController] Exclusive reward flight layer could not be created.")
    end
    setGuiOpen(exclusiveRewardShowFrame, false)
end

local function applyExclusiveRewardImage(iconRoot, plantId, rollGroup)
    local imageObject = findImageObject(iconRoot)
    if not imageObject then
        warn("[IAPShopController] Exclusive reward image object was not found.")
        return
    end

    imageObject.Image = getExclusiveRewardImage(plantId, rollGroup)
end

local function applyExclusiveRewardGradient(iconRoot, plantId, rollGroup)
    local stroke = iconRoot and (iconRoot:FindFirstChild("UIStroke") or iconRoot:FindFirstChildWhichIsA("UIStroke", true))
    if not stroke then
        warn("[IAPShopController] Exclusive reward icon UIStroke was not found.")
        return
    end

    for _, child in ipairs(stroke:GetChildren()) do
        if child:IsA("UIGradient") then
            child:Destroy()
        end
    end

    local slot = getExclusiveOutcomeSlotByPlantId(plantId, rollGroup)
    local sourceGradient = slot and slot.Gradient
    if sourceGradient and sourceGradient:IsA("UIGradient") then
        local gradientClone = sourceGradient:Clone()
        gradientClone.Color = originalGradientColors[sourceGradient] or sourceGradient.Color
        gradientClone.Parent = stroke
    else
        warn("[IAPShopController] Exclusive reward source gradient was not found: " .. tostring(plantId))
    end
end

local function showExclusiveRewardResult(result)
    if not (exclusiveRewardShowFrame and exclusiveRewardIconTemplate and exclusiveRewardFlightLayer) then
        return
    end

    local plantId = type(result) == "table" and result.PlantId or nil
    if not plantId then
        return
    end
    local rollGroup = getRollGroupKey(result.RollGroup)

    setGuiOpen(exclusiveRewardShowFrame, true)
    exclusiveRewardFlightLayer.Visible = true

    local iconClone = exclusiveRewardIconTemplate:Clone()
    iconClone.Name = exclusiveRewardIconTemplate.Name
    iconClone:SetAttribute("ExclusiveRewardShowClone", true)
    iconClone.Parent = exclusiveRewardFlightLayer
    if iconClone:IsA("GuiObject") then
        local templatePosition = exclusiveRewardIconTemplate.AbsolutePosition
        local templateSize = exclusiveRewardIconTemplate.AbsoluteSize
        iconClone.AnchorPoint = Vector2.new(0.5, 0.5)
        iconClone.Size = UDim2.fromOffset(templateSize.X, templateSize.Y)
        iconClone.Position = UDim2.fromOffset(
            templatePosition.X + templateSize.X * 0.5,
            templatePosition.Y + templateSize.Y * 0.5
        )
        iconClone.Visible = true
        setGuiTreeZIndex(iconClone, 10001)
    end

    applyExclusiveRewardImage(iconClone, plantId, rollGroup)
    applyExclusiveRewardGradient(iconClone, plantId, rollGroup)

    task.delay(getRewardShowDuration(), function()
        if not iconClone.Parent then
            return
        end

        if iconClone:IsA("GuiObject") then
            local moveTween = TweenService:Create(
                iconClone,
                TweenInfo.new(getRewardShowMoveDuration(), Enum.EasingStyle.Sine, Enum.EasingDirection.In),
                { Position = getRewardShowTargetPosition() }
            )
            moveTween:Play()
            moveTween.Completed:Wait()
        end

        if iconClone.Parent then
            if iconClone:IsA("GuiObject") then
                iconClone.Visible = false
            end
            iconClone:Destroy()
        end

        if not hasExclusiveRewardIcons() then
            setGuiOpen(exclusiveRewardShowFrame, false)
            if exclusiveRewardFlightLayer then
                exclusiveRewardFlightLayer.Visible = false
            end
        end
    end)
end

local function processExclusiveRewardShowQueue()
    while #exclusiveRewardShowQueue > 0 do
        local result = table.remove(exclusiveRewardShowQueue, 1)
        showExclusiveRewardResult(result)
    end
end

local function enqueueExclusiveRewardShow(payload)
    local results = type(payload) == "table" and payload.Results or nil
    if type(results) ~= "table" or #results == 0 then
        return
    end

    local rollGroup = getRollGroupKey(payload.RollGroup)
    for _, result in ipairs(results) do
        if type(result) == "table" and result.RollGroup == nil then
            result.RollGroup = rollGroup
        end
        table.insert(exclusiveRewardShowQueue, result)
    end
    processExclusiveRewardShowQueue()
end

local function setExclusiveOutcomeSelected(selectedIndex, rollGroup)
    local selectedGradientColor = getSelectedGradientColor()

    for index, slot in ipairs(getExclusiveOutcomeSlots(rollGroup)) do
        local gradient = slot and slot.Gradient
        if gradient then
            if index == selectedIndex then
                gradient.Color = selectedGradientColor
            else
                gradient.Color = originalGradientColors[gradient] or gradient.Color
            end
        end
    end
end

local function playSingleExclusiveOutcomeSpin(targetIndex, duration, rollGroup)
    local groupKey = getRollGroupKey(rollGroup)
    local outcomeSlots = getExclusiveOutcomeSlots(groupKey)
    local outcomeCount = #outcomeSlots
    if outcomeCount <= 0 or not targetIndex then
        task.wait(duration)
        return
    end

    local stepCount = math.max(outcomeCount * 2, math.floor(duration / 0.04))
    local weights = {}
    local totalWeight = 0

    for step = 1, stepCount do
        local progress = step / stepCount
        local weight = 0.25 + progress * progress * 2
        weights[step] = weight
        totalWeight += weight
    end

    local startIndex = currentOutcomeIndexByGroup[groupKey] or 0
    for step = 1, stepCount do
        local selectedIndex
        if step == stepCount then
            selectedIndex = targetIndex
        else
            selectedIndex = ((startIndex + step - 1) % outcomeCount) + 1
        end

        setExclusiveOutcomeSelected(selectedIndex, groupKey)
        task.wait(duration * weights[step] / totalWeight)
    end

    currentOutcomeIndexByGroup[groupKey] = targetIndex
    if groupKey == "Exclusive" then
        currentOutcomeIndex = targetIndex
    end
end

local function playExclusiveRollAnimation(payload)
    local results = type(payload) == "table" and payload.Results or nil
    if type(results) ~= "table" or #results == 0 then
        return
    end
    local rollGroup = getRollGroupKey(payload.RollGroup)

    local shouldLockClose = (tonumber(payload.RollCount) or #results) >= 10
    if shouldLockClose then
        setExclusiveRollCloseLocked(true, 45)
    end

    local preAnimationDelay = getPreAnimationDelay()
    if preAnimationDelay > 0 then
        task.wait(preAnimationDelay)
    end

    local perRollDuration = getRollAnimationDuration(payload.ProductKey)
    local resultHoldDuration = getResultHoldDuration()
    for index, result in ipairs(results) do
        local targetIndex = ExclusiveRollConfig.GetOutcomeIndex(result.PlantId, rollGroup)
        playSingleExclusiveOutcomeSpin(targetIndex, perRollDuration, rollGroup)
        enqueueExclusiveRewardShow({
            RollId = payload.RollId,
            ProductKey = payload.ProductKey,
            ProductId = payload.ProductId,
            RollCount = payload.RollCount,
            RollGroup = rollGroup,
            RollIndex = index,
            Results = { result },
        })
        if resultHoldDuration > 0 then
            task.wait(resultHoldDuration)
        end
    end

    if shouldLockClose then
        setExclusiveRollCloseLocked(false)
    end
end

local function processExclusiveAnimationQueue()
    if isPlayingExclusiveAnimation then
        return
    end

    isPlayingExclusiveAnimation = true
    while #exclusiveAnimationQueue > 0 do
        local payload = table.remove(exclusiveAnimationQueue, 1)
        playExclusiveRollAnimation(payload)
    end
    isPlayingExclusiveAnimation = false
end

local function enqueueExclusiveRollAnimation(payload)
    table.insert(exclusiveAnimationQueue, payload)
    task.spawn(processExclusiveAnimationQueue)
end

local function setButtonTreeEnabled(root, enabled)
    if not root then
        return
    end

    if root:IsA("GuiObject") and not enabled then
        root.Visible = false
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            descendant.Active = enabled
            descendant.AutoButtonColor = enabled
        end
    end
end

local function hideConfiguredExclusiveButtons(iapShopGui)
    for _, path in ipairs(ExclusiveRollConfig.HiddenButtonPaths or {}) do
        setButtonTreeEnabled(findPath(iapShopGui, path), false)
    end
end

local function forEachExclusiveRollProduct(callback)
    for productKey, productConfig in pairs(ExclusiveRollConfig.Products or {}) do
        callback(productKey, productConfig)
    end

    for _, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        for productKey, productConfig in pairs(groupConfig.Products or {}) do
            callback(productKey, productConfig)
        end
    end
end

local function ensureExclusiveTicketButton(iapShopGui)
    local ticketConfig = getExclusiveTicketConfig()
    local buttonPath = ticketConfig.ButtonPath or {}
    local buttonRoot = findPath(iapShopGui, buttonPath)

    if not buttonRoot then
        local parentPath = {}
        for index = 1, math.max(0, #buttonPath - 1) do
            parentPath[index] = buttonPath[index]
        end

        local parent = findPath(iapShopGui, parentPath)
        local template = parent and (parent:FindFirstChild("Buttons1") or parent:FindFirstChild("Buttons3") or parent:FindFirstChildWhichIsA("GuiObject"))
        if parent and template then
            buttonRoot = template:Clone()
            buttonRoot.Name = buttonPath[#buttonPath] or "Buttons0"
            if buttonRoot:IsA("GuiObject") then
                buttonRoot.LayoutOrder = (template.LayoutOrder or 1) - 1
                buttonRoot.Visible = true
            end
            buttonRoot.Parent = parent
        end
    end

    if not buttonRoot then
        warn("[IAPShopController] Exclusive ticket button Buttons0 was not found and could not be cloned.")
        return nil
    end

    local priceRoot = findPath(buttonRoot, ticketConfig.PriceTextPath or { "Info", "Price" })
    exclusiveTicketPriceTextObject = findTextObject(priceRoot)
    if not exclusiveTicketPriceTextObject then
        warn("[IAPShopController] Exclusive ticket price text was not found.")
    end

    exclusiveTicketButton = findButton(buttonRoot)
    setExclusiveTicketCount(exclusiveTicketCount)
    return exclusiveTicketButton
end

local function bindExclusiveTicketButton(iapShopGui, onlineGui)
    local button = ensureExclusiveTicketButton(iapShopGui)
    if not button then
        return
    end

    exclusiveTicketRollRF = ReplicatedStorage:WaitForChild(ExclusiveRollConfig.TicketRollRemoteName or "UseExclusiveRollTicketRF", 10)
    if not exclusiveTicketRollRF then
        warn("[IAPShopController] Exclusive ticket roll remote was not found.")
        return
    end

    if button:GetAttribute("ExclusiveTicketRollBound") then
        return
    end

    button:SetAttribute("ExclusiveTicketRollBound", true)
    button.Activated:Connect(function()
        if exclusiveRollCloseLocked or isPlayingExclusiveAnimation then
            UIEffectUtil.ShowTip("Exclusive roll is playing.")
            return
        end

        if exclusiveTicketRollInProgress then
            UIEffectUtil.ShowTip("Exclusive roll is processing.")
            return
        end

        if exclusiveTicketCount <= 0 then
            setGuiOpen(iapShopGui, false)
            setGuiOpen(onlineGui, true)
            UIEffectUtil.ShowTip("Claim online rewards to get roll attempts.")
            return
        end

        exclusiveTicketRollInProgress = true
        local ok, success, message, ticketCount = pcall(function()
            return exclusiveTicketRollRF:InvokeServer()
        end)
        exclusiveTicketRollInProgress = false

        if not ok then
            warn("[IAPShopController] Exclusive ticket roll failed: " .. tostring(success))
            UIEffectUtil.ShowTip("Exclusive roll failed. Please try again.")
            return
        end

        if ticketCount ~= nil then
            setExclusiveTicketCount(ticketCount)
        end

        if not success then
            if exclusiveTicketCount <= 0 then
                setGuiOpen(iapShopGui, false)
                setGuiOpen(onlineGui, true)
            end
            UIEffectUtil.ShowTip(tostring(message or "No exclusive roll attempts."))
        end
    end)
end

local function bindExclusiveFreeRollButtons(iapShopGui)
    for groupKey, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        local currentGroupKey = groupKey
        local freeRollConfig = groupConfig.FreeRoll
        if type(freeRollConfig) ~= "table" then
            continue
        end

        local buttonRoot = waitForPath(iapShopGui, freeRollConfig.ButtonPath or {})
        local button = findButton(buttonRoot)
        local priceRoot = buttonRoot and findPath(buttonRoot, freeRollConfig.PriceTextPath or { "Info", "Price" })
        local priceTextObject = findTextObject(priceRoot)
        local remoteName = freeRollConfig.RemoteName or "UseExclusiveShopFreeRollRF"
        local remote = ReplicatedStorage:WaitForChild(remoteName, 10)

        if not (button and priceTextObject and remote) then
            warn("[IAPShopController] Exclusive free roll binding failed: " .. tostring(groupKey))
            continue
        end

        local cooldownSeconds = math.max(1, math.floor(tonumber(freeRollConfig.CooldownSeconds) or 300))
        local usesSessionTimer = freeRollConfig.UseSessionTimer == true or getExclusiveFreeRollDataKey(freeRollConfig) == nil
        exclusiveFreeRollStates[currentGroupKey] = {
            Button = button,
            PriceTextObject = priceTextObject,
            Remote = remote,
            ReadyAtClock = usesSessionTimer and (os.clock() + cooldownSeconds) or 0,
            ReadyText = freeRollConfig.ReadyText or "Claim",
            CooldownSeconds = cooldownSeconds,
            InProgress = false,
        }
        updateExclusiveFreeRollText(currentGroupKey)
        requestExclusiveFreeRollStatus(currentGroupKey)

        if not button:GetAttribute("ExclusiveFreeRollBound") then
            button:SetAttribute("ExclusiveFreeRollBound", true)
            button.Activated:Connect(function()
                local state = exclusiveFreeRollStates[currentGroupKey]
                if not state then
                    return
                end
                if exclusiveRollCloseLocked or isPlayingExclusiveAnimation then
                    UIEffectUtil.ShowTip("Exclusive roll is playing.")
                    return
                end
                if state.InProgress then
                    UIEffectUtil.ShowTip("Exclusive roll is processing.")
                    return
                end

                local remaining = getExclusiveFreeRollRemaining(currentGroupKey)
                if remaining > 0 then
                    UIEffectUtil.ShowTip(formatExclusiveFreeRollText(remaining, state.ReadyText))
                    return
                end

                state.InProgress = true
                local ok, success, message, remainingSeconds = pcall(function()
                    return state.Remote:InvokeServer("claim")
                end)
                state.InProgress = false

                if not ok then
                    warn("[IAPShopController] Exclusive free roll failed: " .. tostring(success))
                    UIEffectUtil.ShowTip("Exclusive roll failed. Please try again.")
                    requestExclusiveFreeRollStatus(currentGroupKey)
                    return
                end

                if remainingSeconds ~= nil then
                    setExclusiveFreeRollRemaining(currentGroupKey, remainingSeconds, state.CooldownSeconds)
                end
                if not success then
                    UIEffectUtil.ShowTip(tostring(message or "Free roll is not ready."))
                end
            end)
        end
    end

    startExclusiveFreeRollStatusLoop()
end

local function bindExclusiveRollButtons(iapShopGui, player)
    forEachExclusiveRollProduct(function(productKey, productConfig)
        if productConfig.Hidden == true then
            setButtonTreeEnabled(findPath(iapShopGui, productConfig.ButtonPath or {}), false)
        else
            local buttonRoot = waitForPath(iapShopGui, productConfig.ButtonPath or {})
            local button = findButton(buttonRoot)
            local productId = tonumber(productConfig.ProductId)

            if button and productId and productId > 0 then
                button.Activated:Connect(function()
                    if (tonumber(productConfig.RollCount) or 0) >= 10 then
                        setExclusiveRollCloseLocked(true, 45)
                    end
                    MarketplaceService:PromptProductPurchase(player, productId)
                end)
            else
                warn("[IAPShopController] Exclusive roll button binding failed: " .. tostring(productKey))
            end
        end
    end)
end

function IAPShopController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        warn("[IAPShopController] BasicGui was not found.")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", 10)
    local iapShopGui = basicGui:WaitForChild("IAPShopGui", 10)
    local onlineGui = basicGui:WaitForChild("OnlineGui", 10)
    if not (playProperty and iapShopGui) then
        warn("[IAPShopController] PlayProperty or IAPShopGui was not found.")
        return
    end
    if not onlineGui then
        warn("[IAPShopController] OnlineGui was not found; ticket fallback page will not open.")
    end

    local iapShopButtonRoot = playProperty:WaitForChild("IAPShop", 10)
    iapShopNotificationParent = iapShopButtonRoot
    local openButton = findButton(iapShopButtonRoot)
    local closeButton = findButton(waitForPath(iapShopGui, { "Store", "Header", "Buttons", "Close" }))
    local buyButtons = waitForPath(iapShopGui, { "Store", "StoreFrame", "Container", "ServerLuck", "BuyButtons" })
    local x2SunButton = findServerLuckX2Button(buyButtons)

    if not (openButton and closeButton) then
        warn("[IAPShopController] IAP shop UI binding is incomplete.")
        return
    end

    if not x2SunButton then
        warn("[IAPShopController] ServerLuck x2 sun button was not found.")
    end

    if iapShopGui:IsA("ScreenGui") then
        iapShopGui.DisplayOrder = math.max(iapShopGui.DisplayOrder, 100)
    end

    local function ownsX2Sun()
        local ownsPass = false
        local ok, result = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, X2_SUN_GAME_PASS_ID)
        end)
        if ok then
            ownsPass = result == true
        end
        return ownsPass
    end

    local function refreshX2Button()
        if not x2SunButton then
            return
        end

        local ownsPass = ownsX2Sun()
        x2SunButton.Active = not ownsPass
        x2SunButton.AutoButtonColor = not ownsPass
    end

    openButton.Activated:Connect(function()
        setGuiOpen(iapShopGui, true)
        refreshX2Button()
        requestExclusivePityRefresh()
        requestExclusiveFreeRollStatuses()
    end)

    closeButton.Activated:Connect(function()
        if exclusiveRollCloseLocked then
            UIEffectUtil.ShowTip("Exclusive roll is playing.")
            setGuiOpen(iapShopGui, true)
            return
        end

        setGuiOpen(iapShopGui, false)
    end)

    if x2SunButton then
        x2SunButton.Activated:Connect(function()
            if ownsX2Sun() then
                UIEffectUtil.ShowTip("X2 Sun is already active.")
                refreshX2Button()
                return
            end

            MarketplaceService:PromptGamePassPurchase(player, X2_SUN_GAME_PASS_ID)
        end)
    end

    collectExclusiveOutcomeSlots(iapShopGui)
    collectExclusiveRewardShow(iapShopGui)
    collectExclusivePityText(iapShopGui)
    hideConfiguredExclusiveButtons(iapShopGui)
    bindExclusiveTicketButton(iapShopGui, onlineGui)
    bindExclusiveFreeRollButtons(iapShopGui)
    requestExclusivePityRefresh()
    bindExclusiveRollButtons(iapShopGui, player)

    local exclusiveRollResultRE = ReplicatedStorage:WaitForChild(ExclusiveRollConfig.ResultEventName or "ExclusiveRollResultRE", 10)
    if exclusiveRollResultRE then
        exclusiveRollResultRE.OnClientEvent:Connect(function(payload)
            if type(payload) == "table" and (tonumber(payload.RollCount) or 0) >= 10 then
                setExclusiveRollCloseLocked(true, 45)
            end
            setGuiOpen(iapShopGui, true)
            if type(payload) == "table" and payload.Pity ~= nil then
                setExclusivePityText(payload.Pity, payload.RollGroup)
            end
            enqueueExclusiveRollAnimation(payload)
        end)
    else
        warn("[IAPShopController] Exclusive roll result event was not found.")
    end

    local exclusiveRollRewardShowRE = ReplicatedStorage:WaitForChild(ExclusiveRollConfig.RewardShowEventName or "ExclusiveRollRewardShowRE", 10)
    if exclusiveRollRewardShowRE then
        exclusiveRollRewardShowRE.OnClientEvent:Connect(function(payload)
            setGuiOpen(iapShopGui, true)
            enqueueExclusiveRewardShow(payload)
        end)
    else
        warn("[IAPShopController] Exclusive roll reward show event was not found.")
    end

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 10)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function(data)
            refreshExclusivePityFromData(data)
            refreshExclusiveTicketFromData(data)
            refreshExclusiveFreeRollsFromData(data)
        end)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= player.UserId then
            return
        end

        local productConfig = ExclusiveRollConfig.GetProductById(productId)
        if productConfig and (tonumber(productConfig.RollCount) or 0) >= 10 and not isPurchased then
            setExclusiveRollCloseLocked(false)
        end
    end)

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, passId, wasPurchased)
        if purchasingPlayer == player and passId == X2_SUN_GAME_PASS_ID and wasPurchased then
            UIEffectUtil.ShowTip("X2 Sun is now active.")
            refreshX2Button()
        end
    end)
end

return IAPShopController

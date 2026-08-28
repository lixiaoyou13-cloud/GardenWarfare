-- src/client/UI/OnlineRewardController.luau
local OnlineRewardController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnlineRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OnlineRewardConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local rewardSlots = {}
local currentState = nil
local countdownLoopRunning = false
local notificationLoopRunning = false
local isClaiming = false
local onlineRewardOpen = false
local groupRewardsButtonRoot = nil
local groupRewardsNotification = nil
local groupRewardsIcon = nil
local refreshTimeTextObject = nil
local warnedMissingClaimableScriptTemplate = false
local warnedMissingClaimableScriptClone = false

local CLAIMABLE_SCRIPT_ATTRIBUTE = "OnlineRewardClaimableIndicator"

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

local function isGuiOpen(gui)
    if not gui then
        return false
    end

    if gui:IsA("ScreenGui") then
        return gui.Enabled
    end

    if gui:IsA("GuiObject") then
        return gui.Visible
    end

    local enabled = false
    pcall(function()
        enabled = gui.Enabled
    end)
    return enabled == true
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

local function getOrCreateTransparentButton(root, name)
    local button = findButton(root)
    if button then
        return button
    end

    if not (root and root:IsA("GuiObject")) then
        return nil
    end

    button = root:FindFirstChild(name)
    if button and button:IsA("GuiButton") then
        return button
    end

    button = Instance.new("TextButton")
    button.Name = name
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.Text = ""
    button.Size = UDim2.new(1, 0, 1, 0)
    button.Position = UDim2.new(0, 0, 0, 0)
    button.AutoButtonColor = false
    button.ZIndex = root.ZIndex + 1
    button.Parent = root
    return button
end

local function getClaimableScriptTemplate()
    local localFolder = ReplicatedStorage:FindFirstChild("local")
    local template = localFolder and localFolder:FindFirstChild("LocalScript")
    if not template then
        if not warnedMissingClaimableScriptTemplate then
            warnedMissingClaimableScriptTemplate = true
            warn("[OnlineRewardController] ReplicatedStorage.local.LocalScript was not found.")
        end
        return nil
    end

    if not template:IsA("LocalScript") then
        if not warnedMissingClaimableScriptTemplate then
            warnedMissingClaimableScriptTemplate = true
            warn("[OnlineRewardController] ReplicatedStorage.local.LocalScript exists but is not a LocalScript.")
        end
        return nil
    end

    return template
end

local function findClaimableScript(icon)
    if not icon then
        return nil
    end

    for _, child in ipairs(icon:GetChildren()) do
        if child:GetAttribute(CLAIMABLE_SCRIPT_ATTRIBUTE) == true then
            return child
        end
    end

    return nil
end

local function setClaimableScript(icon, enabled)
    if not icon then
        return
    end

    local existing = findClaimableScript(icon)

    if enabled then
        if existing then
            return
        end

        local template = getClaimableScriptTemplate()
        if not template then
            return
        end

        local clone = template:Clone()
        if not clone then
            if not warnedMissingClaimableScriptClone then
                warnedMissingClaimableScriptClone = true
                warn("[OnlineRewardController] ReplicatedStorage.local.LocalScript could not be cloned.")
            end
            return
        end

        clone:SetAttribute(CLAIMABLE_SCRIPT_ATTRIBUTE, true)
        pcall(function()
            clone.Enabled = true
        end)
        pcall(function()
            clone.Disabled = false
        end)
        clone.Parent = icon
    elseif existing then
        existing:Destroy()
    end
end

local function resetGuiRotation(guiObject)
    if guiObject and guiObject:IsA("GuiObject") then
        guiObject.Rotation = 0
    end
end

local function getOrCreateClickButton(root)
    return getOrCreateTransparentButton(root, "OnlineRewardRedeemClickArea")
end

local function findTextObject(root)
    if not root then
        return nil
    end

    local namedText = root:FindFirstChild("TextLabel")
    if namedText and namedText:IsA("TextLabel") then
        return namedText
    end

    namedText = root:FindFirstChild("TextLabel", true)
    if namedText and namedText:IsA("TextLabel") then
        return namedText
    end

    if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
        return root
    end

    return root:FindFirstChildWhichIsA("TextLabel", true)
        or root:FindFirstChildWhichIsA("TextButton", true)
        or root:FindFirstChildWhichIsA("TextBox", true)
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    return string.format("%d:%02d", minutes, remainder)
end

local function formatRefreshDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
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

local function appendMissing(missing, label, value)
    if not value then
        table.insert(missing, label)
    end
end

local function connectGuiOpened(gui, callback)
    if not gui then
        return
    end

    if gui:IsA("ScreenGui") then
        gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if isGuiOpen(gui) then
                callback()
            end
        end)
        return
    end

    if gui:IsA("GuiObject") then
        gui:GetPropertyChangedSignal("Visible"):Connect(function()
            if isGuiOpen(gui) then
                callback()
            end
        end)
    end
end

local function getRewardStateByIndex(index)
    if not (currentState and type(currentState.Rewards) == "table") then
        return nil
    end

    return currentState.Rewards[index] or currentState.Rewards[tostring(index)]
end

local function getAdjustedRemainingSeconds(rewardState)
    if not rewardState then
        return 0
    end

    if rewardState.Claimed then
        return 0
    end

    local remaining = math.max(0, math.floor(tonumber(rewardState.RemainingSeconds) or 0))
    local receivedAt = tonumber(currentState and currentState.ClientReceivedAt)
    if receivedAt then
        remaining -= math.floor(os.clock() - receivedAt)
    end

    return math.max(0, remaining)
end

local function getRefreshRemainingSeconds()
    if type(currentState) ~= "table" then
        return 24 * 60 * 60
    end

    local remaining = math.max(0, math.floor(tonumber(currentState.RefreshRemainingSeconds) or tonumber(currentState.RefreshDurationSeconds) or (24 * 60 * 60)))
    if currentState.RefreshActive == true then
        local receivedAt = tonumber(currentState.ClientReceivedAt)
        if receivedAt then
            remaining -= math.floor(os.clock() - receivedAt)
        end
    end

    return math.max(0, remaining)
end

local function updateRefreshTimeText()
    if refreshTimeTextObject then
        refreshTimeTextObject.Text = "Next rewards refresh in " .. formatRefreshDuration(getRefreshRemainingSeconds())
    end
end

local function hasClaimableReward()
    if not (currentState and type(currentState.Rewards) == "table") then
        return false
    end

    for _, rewardState in pairs(currentState.Rewards) do
        if type(rewardState) == "table"
            and rewardState.Claimed ~= true
            and getAdjustedRemainingSeconds(rewardState) <= 0
        then
            return true
        end
    end

    return false
end

local function updateGroupRewardsClaimableIndicator()
    if groupRewardsNotification then
        groupRewardsNotification.Visible = hasClaimableReward()
    end

    setClaimableScript(groupRewardsIcon, false)
    resetGuiRotation(groupRewardsButtonRoot)
    resetGuiRotation(groupRewardsIcon)
end

local function setButtonInteractable(button, isInteractable)
    if not button then
        return
    end

    button.Active = isInteractable
    button.AutoButtonColor = isInteractable
end

local function applySlotState(slot, rewardState)
    if not slot then
        return
    end

    local textLabel = slot.RedeemText
    local countdownText = slot.CountdownText
    local gradient = slot.Gradient
    local button = slot.Button

    if not rewardState then
        if textLabel then
            textLabel.Text = slot.OriginalRedeemText or "WAIT"
        end
        if countdownText then
            countdownText.Text = "--:--"
        end
        if gradient and slot.OriginalGradient then
            gradient.Color = slot.OriginalGradient
        end
        setButtonInteractable(button, false)
        return
    end

    local remaining = getAdjustedRemainingSeconds(rewardState)
    local claimed = rewardState.Claimed == true
    local canClaim = not claimed and remaining <= 0

    if claimed then
        if textLabel then
            textLabel.Text = "CLAIMED"
        end
        if countdownText then
            countdownText.Text = "CLAIMED"
        end
        if gradient then
            gradient.Color = OnlineRewardConfig.ClaimedGradient
        end
        setButtonInteractable(button, false)
        return
    end

    if canClaim then
        if textLabel then
            textLabel.Text = "CLAIM"
        end
        if countdownText then
            countdownText.Text = "READY"
        end
        if gradient then
            gradient.Color = OnlineRewardConfig.ReadyGradient
        end
        setButtonInteractable(button, true)
        return
    end

    if textLabel then
        textLabel.Text = "WAIT"
    end
    if countdownText then
        countdownText.Text = formatDuration(remaining)
    end
    if gradient then
        gradient.Color = OnlineRewardConfig.ClaimedGradient
    end
    setButtonInteractable(button, false)
end

local function refreshAllSlots()
    for index, slot in pairs(rewardSlots) do
        applySlotState(slot, getRewardStateByIndex(index))
    end
    updateRefreshTimeText()
    updateGroupRewardsClaimableIndicator()
end

local function requestState(stateRemote, silent)
    if not stateRemote then
        currentState = nil
        updateGroupRewardsClaimableIndicator()
        return false
    end

    local ok, state = pcall(function()
        return stateRemote:InvokeServer()
    end)

    if not ok then
        warn("[OnlineRewardController] Get state failed: " .. tostring(state))
        if not silent then
            UIEffectUtil.ShowTip("Online rewards are loading. Please try again.")
        end
        currentState = nil
        updateGroupRewardsClaimableIndicator()
        return false
    end

    if type(state) ~= "table" or type(state.Rewards) ~= "table" then
        currentState = nil
        updateGroupRewardsClaimableIndicator()
        return false
    end

    state.ClientReceivedAt = os.clock()
    currentState = state
    refreshAllSlots()
    return true
end

local function startNotificationLoop(stateRemote)
    if notificationLoopRunning then
        return
    end

    notificationLoopRunning = true
    task.spawn(function()
        while true do
            requestState(stateRemote, true)
            for _ = 1, 10 do
                updateGroupRewardsClaimableIndicator()
                task.wait(1)
            end
        end
    end)
end

local function startCountdownLoop(onlineGui)
    if countdownLoopRunning then
        return
    end

    countdownLoopRunning = true
    task.spawn(function()
        while onlineRewardOpen or isGuiOpen(onlineGui) do
            refreshAllSlots()
            task.wait(1)
        end
        countdownLoopRunning = false
    end)
end

local function collectRewardSlots(timeRewardsRoot)
    table.clear(rewardSlots)

    for index = 1, #OnlineRewardConfig.Rewards do
        local frame = timeRewardsRoot:WaitForChild(tostring(index), 10)
        local redeemRoot = frame and frame:WaitForChild("Redeem", 10)
        local countdownRoot = frame and frame:WaitForChild("Countdown", 10)
        local button = getOrCreateClickButton(redeemRoot)
        local textLabel = findTextObject(redeemRoot)
        local countdownText = findTextObject(countdownRoot)
        local gradient = redeemRoot and redeemRoot:FindFirstChild("UIGradient")

        if frame and redeemRoot and button and textLabel and countdownText then
            rewardSlots[index] = {
                Frame = frame,
                Button = button,
                RedeemText = textLabel,
                CountdownText = countdownText,
                Gradient = gradient,
                OriginalRedeemText = textLabel.Text,
                OriginalGradient = gradient and gradient.Color or nil,
            }
        else
            local missing = {}
            appendMissing(missing, "TimeRewards." .. tostring(index), frame)
            appendMissing(missing, "TimeRewards." .. tostring(index) .. ".Redeem", redeemRoot)
            appendMissing(missing, "TimeRewards." .. tostring(index) .. ".Redeem clickable button", button)
            appendMissing(missing, "TimeRewards." .. tostring(index) .. ".Redeem.TextLabel", textLabel)
            appendMissing(missing, "TimeRewards." .. tostring(index) .. ".Countdown", countdownRoot)
            appendMissing(missing, "TimeRewards." .. tostring(index) .. ".Countdown text", countdownText)
            warn("[OnlineRewardController] Reward slot binding is incomplete: " .. tostring(index) .. ". Missing: " .. table.concat(missing, ", "))
        end
    end
end

local function bindRewardButtons(claimRemote)
    for index, slot in pairs(rewardSlots) do
        local button = slot.Button
        if button and not button:GetAttribute("OnlineRewardBound") then
            button:SetAttribute("OnlineRewardBound", true)
            button.Activated:Connect(function()
                if isClaiming then
                    UIEffectUtil.ShowTip("Claim is processing.")
                    return
                end

                local rewardState = getRewardStateByIndex(index)
                if not rewardState or rewardState.Claimed then
                    return
                end

                if getAdjustedRemainingSeconds(rewardState) > 0 then
                    UIEffectUtil.ShowTip("Reward is not ready yet.")
                    return
                end

                isClaiming = true
                local ok, success, message, state = pcall(function()
                    return claimRemote:InvokeServer(index)
                end)
                isClaiming = false

                if not ok then
                    warn("[OnlineRewardController] Claim failed: " .. tostring(success))
                    UIEffectUtil.ShowTip("Claim failed. Please try again.")
                    return
                end

                if type(state) == "table" then
                    state.ClientReceivedAt = os.clock()
                    currentState = state
                    refreshAllSlots()
                end

                UIEffectUtil.ShowTip(tostring(message or (success and "Claimed." or "Claim failed.")))
            end)
        end
    end
end

function OnlineRewardController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        warn("[OnlineRewardController] BasicGui was not found.")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", 10)
    local onlineGui = basicGui:WaitForChild("OnlineGui", 10)
    if not (playProperty and onlineGui) then
        warn("[OnlineRewardController] PlayProperty or OnlineGui was not found.")
        return
    end

    local groupRewardsRoot = playProperty:WaitForChild("GroupRewards", 10)
    groupRewardsButtonRoot = groupRewardsRoot
    groupRewardsIcon = groupRewardsRoot and groupRewardsRoot:FindFirstChild("Icon")
    groupRewardsNotification = groupRewardsRoot and groupRewardsRoot:FindFirstChild("Notifications")
    if groupRewardsNotification and not groupRewardsNotification:IsA("GuiObject") then
        warn("[OnlineRewardController] BasicGui.PlayProperty.GroupRewards.Notifications exists but is not a GuiObject.")
        groupRewardsNotification = nil
    end
    if groupRewardsRoot and not groupRewardsNotification then
        warn("[OnlineRewardController] BasicGui.PlayProperty.GroupRewards.Notifications was not found; claimable notification cannot be shown.")
    end
    local openButton = getOrCreateTransparentButton(groupRewardsRoot, "OnlineRewardOpenClickArea")

    if onlineGui:IsA("ScreenGui") then
        onlineGui.DisplayOrder = math.max(onlineGui.DisplayOrder, 100)
    end
    setGuiOpen(onlineGui, false)
    onlineRewardOpen = false

    local stateRemote = nil
    if openButton then
        openButton.Activated:Connect(function()
            onlineRewardOpen = true
            setGuiOpen(onlineGui, true)
            if stateRemote then
                requestState(stateRemote)
            end
            startCountdownLoop(onlineGui)
        end)
    end

    connectGuiOpened(onlineGui, function()
        onlineRewardOpen = true
        if stateRemote then
            requestState(stateRemote)
        end
        startCountdownLoop(onlineGui)
    end)

    local timeRewardsRoot = onlineGui:WaitForChild("TimeRewards", 10)
    local timeTextRoot = timeRewardsRoot and timeRewardsRoot:FindFirstChild("TimeText")
        or onlineGui:FindFirstChild("TimeText")
    refreshTimeTextObject = findTextObject(timeTextRoot)
    if not refreshTimeTextObject then
        warn("[OnlineRewardController] BasicGui.OnlineGui.TimeRewards.TimeText text was not found.")
    end
    local rewardHolder = timeRewardsRoot and timeRewardsRoot:WaitForChild("Holder", 10)
    local closeButton = findButton(waitForPath(timeRewardsRoot, { "Top", "Close" }))
        or findButton(waitForPath(onlineGui, { "Top", "Close" }))
    stateRemote = ReplicatedStorage:WaitForChild(OnlineRewardConfig.StateRemoteName or "GetOnlineRewardStateRF", 10)
    local claimRemote = ReplicatedStorage:WaitForChild(OnlineRewardConfig.ClaimRemoteName or "ClaimOnlineRewardRF", 10)

    if not (openButton and closeButton and timeRewardsRoot and rewardHolder and stateRemote and claimRemote) then
        local missing = {}
        appendMissing(missing, "BasicGui.PlayProperty.GroupRewards button", openButton)
        appendMissing(missing, "BasicGui.OnlineGui.TimeRewards.Top.Close button", closeButton)
        appendMissing(missing, "BasicGui.OnlineGui.TimeRewards", timeRewardsRoot)
        appendMissing(missing, "BasicGui.OnlineGui.TimeRewards.Holder", rewardHolder)
        appendMissing(missing, "BasicGui.OnlineGui.TimeRewards.TimeText text", refreshTimeTextObject)
        appendMissing(missing, tostring(OnlineRewardConfig.StateRemoteName or "GetOnlineRewardStateRF"), stateRemote)
        appendMissing(missing, tostring(OnlineRewardConfig.ClaimRemoteName or "ClaimOnlineRewardRF"), claimRemote)
        warn("[OnlineRewardController] Online reward UI binding is incomplete. Missing: " .. table.concat(missing, ", "))
        return
    end

    collectRewardSlots(rewardHolder)
    bindRewardButtons(claimRemote)
    updateRefreshTimeText()
    refreshAllSlots()
    startNotificationLoop(stateRemote)

    local function closeOnlineRewards()
        onlineRewardOpen = false
        setGuiOpen(onlineGui, false)
    end

    closeButton.Activated:Connect(closeOnlineRewards)
end

return OnlineRewardController

-- src/client/UI/PassController.luau
local PassController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local PassRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassRewardConfig"))
local PassShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassShopConfig"))
local PassQuestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassQuestConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local PASS_V1_MAX_LEVEL = 10
local PASS_V1_EXP_PER_LEVEL = 200
local CLAIMED_MARK = utf8.char(0x221A)

local function getPassExpRequired(level, baseExp, maxLevel)
    baseExp = tonumber(baseExp) or PASS_V1_EXP_PER_LEVEL
    maxLevel = tonumber(maxLevel) or PASS_V1_MAX_LEVEL
    level = math.clamp(math.floor(tonumber(level) or 1), 1, maxLevel)
    return baseExp
end

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

local function findTextObject(root)
    if not root then
        return nil
    end

    if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
        return root
    end

    return root:FindFirstChildWhichIsA("TextLabel", true)
        or root:FindFirstChildWhichIsA("TextButton", true)
        or root:FindFirstChildWhichIsA("TextBox", true)
end

local function findGuiObject(root)
    if not root then
        return nil
    end

    if root:IsA("GuiObject") then
        return root
    end

    return root:FindFirstChildWhichIsA("GuiObject", true)
end

local function setVisualEnabled(visual, isEnabled)
    if not visual then
        return
    end

    if visual:IsA("GuiObject") then
        visual.Visible = isEnabled
    end

    pcall(function()
        visual.Enabled = isEnabled
    end)
end

local function formatDuration(seconds)
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

local function findPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        if not current then
            return nil
        end

        current = current:FindFirstChild(name)
    end

    return current
end

local function normalizePassData(passData, expPerLevel, maxLevel)
    expPerLevel = tonumber(expPerLevel) or PASS_V1_EXP_PER_LEVEL
    maxLevel = tonumber(maxLevel) or PASS_V1_MAX_LEVEL

    if type(passData) ~= "table" then
        return 1, 0, getPassExpRequired(1, expPerLevel, maxLevel)
    end

    local level = math.clamp(math.floor(tonumber(passData.Level) or 1), 1, maxLevel)
    local displayLevel = level
    if level >= maxLevel then
        displayLevel += math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0))
    end
    local exp = math.max(0, math.floor(tonumber(passData.Exp) or 0))
    local neededExp = getPassExpRequired(level, expPerLevel, maxLevel)

    if level >= maxLevel then
        exp = math.clamp(exp, 0, neededExp - 1)
    else
        exp = math.clamp(exp, 0, neededExp - 1)
    end

    return displayLevel, exp, neededExp
end

local function formatPassText(passData, expPerLevel, maxLevel)
    local level, exp, neededExp = normalizePassData(passData, expPerLevel, maxLevel)
    return string.format("Level %d (%d/%d)", level, exp, neededExp)
end

local function getPassProgress(passData, expPerLevel, maxLevel)
    local _, exp, neededExp = normalizePassData(passData, expPerLevel, maxLevel)
    if neededExp <= 0 then
        return 0
    end

    return math.clamp(exp / neededExp, 0, 1)
end

local function setGuiObjectVisible(guiObject, isVisible)
    if not guiObject then
        return
    end

    if guiObject:IsA("GuiObject") then
        guiObject.Visible = isVisible
        return
    end

    pcall(function()
        guiObject.Visible = isVisible
    end)
end

local function setButtonEnabled(button, isEnabled)
    if not button then
        return
    end

    button.Active = isEnabled
    button.AutoButtonColor = isEnabled
    button.Selectable = isEnabled
end

local function setButtonText(buttonRoot, text)
    if not buttonRoot then
        return
    end

    local btnTextRoot = buttonRoot:FindFirstChild("btn")
    local textObject = findTextObject(btnTextRoot or buttonRoot)
    if textObject then
        textObject.Text = text
    end
end

local function setTextObjectText(textObject, text)
    if textObject then
        textObject.Text = text
    end
end

function PassController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        warn("[PassController] BasicGui was not found.")
        return
    end

    if PassRewardConfig.ClientVisible == false then
        local playProperty = basicGui:WaitForChild("PlayProperty", 10)
        local passGui = basicGui:FindFirstChild("PassGui") or basicGui:WaitForChild("PassGui", 10)
        local passButtonRoot = playProperty and playProperty:FindFirstChild("Pass")
        local passNotification = passButtonRoot and passButtonRoot:FindFirstChild("Notifications")

        setGuiObjectVisible(passNotification, false)
        setGuiObjectVisible(passButtonRoot, false)
        setGuiOpen(passGui, false)
        return
    end

    local function promptPassExpPurchase()
        UIEffectUtil.ShowTip("Opening pass EXP purchase...")
        print("[PassController] Pass EXP purchase button clicked.")

        local productId = tonumber(PassRewardConfig.ExpProductId)
        if not (productId and productId > 0) then
            UIEffectUtil.ShowTip("Pass EXP purchase is unavailable.")
            return
        end

        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, productId)
        end)
        if not ok then
            warn("[PassController] Failed to prompt pass EXP product: " .. tostring(err))
            UIEffectUtil.ShowTip("Pass EXP purchase failed to open.")
        end
    end

    task.spawn(function()
        local passGuiForExp = basicGui:WaitForChild("PassGui", 10)
        local passRootForExp = passGuiForExp and passGuiForExp:WaitForChild("Pass", 10)
        local giftRoot = passRootForExp and passRootForExp:WaitForChild("Gift", 10)
        local mainRoot = giftRoot and giftRoot:WaitForChild("Main", 10)
        local giftButton = mainRoot and mainRoot:WaitForChild("Gift", 10)

        if not giftButton then
            warn("[PassController] Missing pass EXP product button: BasicGui.PassGui.Pass.Gift.Main.Gift")
            return
        end
        if not giftButton:IsA("GuiButton") then
            warn("[PassController] BasicGui.PassGui.Pass.Gift.Main.Gift must be a GuiButton/TextButton, got " .. giftButton.ClassName)
            return
        end

        giftButton.Active = true
        giftButton.Selectable = true
        giftButton.AutoButtonColor = true
        pcall(function()
            giftButton.Interactable = true
        end)

        if not giftButton:GetAttribute("PassExpPurchaseBound") then
            giftButton:SetAttribute("PassExpPurchaseBound", true)
            local clickLocked = false
            local function onPassExpClicked()
                if clickLocked then
                    return
                end

                clickLocked = true
                promptPassExpPurchase()
                task.delay(1, function()
                    clickLocked = false
                end)
            end

            giftButton.Activated:Connect(onPassExpClicked)
            print("[PassController] Bound pass EXP product button: BasicGui.PassGui.Pass.Gift.Main.Gift")
        end
    end)

    local playProperty = basicGui:WaitForChild("PlayProperty", 10)
    local passGui = basicGui:WaitForChild("PassGui", 10)
    if not (playProperty and passGui) then
        warn("[PassController] PlayProperty or PassGui was not found.")
        return
    end

    local passButtonRoot = playProperty:WaitForChild("Pass", 10)
    local openButton = findButton(passButtonRoot)
    local passNotification = findGuiObject(passButtonRoot and passButtonRoot:FindFirstChild("Notifications"))

    local passRoot = passGui:WaitForChild("Pass", 10)
    local levelRoot = passGui:WaitForChild("Level", 10)
    local questRoot = passGui:WaitForChild("Quest", 10)
    local passShopPage = passGui:WaitForChild("Shop", 10)
    local closeButton = findButton(waitForPath(passRoot, { "Top", "Main", "Containers", "Close" }))
    local openShopButton = findButton(passRoot and passRoot:FindFirstChild("Shop"))
    local closeShopButton = findButton(waitForPath(passShopPage, { "Top", "Close" }))
    local eventEndText = findTextObject(waitForPath(passRoot, { "Top", "Main", "Containers", "TimeDay" }))
    local expAmountText = findTextObject(waitForPath(passGui, { "Level", "Exp", "Main", "ExpAmount" }))
    local expProgressBar = findGuiObject(waitForPath(passGui, { "Level", "Exp", "Main", "Moving" }))
    local premiumBuyButton = findButton(waitForPath(passGui, { "Pass", "Gift", "Main", "BuyFrame", "Buy" }))
    local premiumClaimedFrame = findGuiObject(waitForPath(passGui, { "Pass", "Gift", "Main", "ClaimedFrame" }))
    local tokenCountText = findTextObject(findPath(passRoot, { "Shop", "Icon", "main" }))
        or findTextObject(findPath(passShopPage, { "Icon", "main" }))
    local rewardSlots = {}
    local questSlots = {}
    local passShopSlots = {}
    local currentPlayerData = nil
    local currentPassData = nil
    local currentQuestState = nil
    local isClaimingReward = false
    local isClaimingQuest = false
    local isPurchasingShopItem = false
    local questCountdownLoopRunning = false
    if not openButton then
        warn("[PassController] Missing open button: BasicGui.PlayProperty.Pass")
    end
    if not passNotification then
        warn("[PassController] Missing pass notification: BasicGui.PlayProperty.Pass.Notifications")
    end
    if not closeButton then
        warn("[PassController] Missing close button: BasicGui.PassGui.Pass.Top.Main.Containers.Close")
    end
    if not openShopButton then
        warn("[PassController] Missing shop open button: BasicGui.PassGui.Pass.Shop")
    end
    if not closeShopButton then
        warn("[PassController] Missing shop close button: BasicGui.PassGui.Shop.Top.Close")
    end
    if not questRoot then
        warn("[PassController] Missing quest page: BasicGui.PassGui.Quest")
    end
    if not expAmountText then
        warn("[PassController] Missing level text: BasicGui.PassGui.Level.Exp.Main.ExpAmount")
    end
    if not expProgressBar then
        warn("[PassController] Missing exp progress bar: BasicGui.PassGui.Level.Exp.Main.Moving")
    end
    if not premiumBuyButton then
        warn("[PassController] Missing premium pass buy button: BasicGui.PassGui.Pass.Gift.Main.BuyFrame.Buy")
    end
    if not premiumClaimedFrame then
        warn("[PassController] Missing premium pass claimed frame: BasicGui.PassGui.Pass.Gift.Main.ClaimedFrame")
    end
    if not tokenCountText then
        warn("[PassController] Missing token count text: BasicGui.PassGui.Pass.Shop.Icon.main")
    end
    setTextObjectText(eventEndText, PassRewardConfig.EventEndText or "")

    local function showPassMainPage()
        setGuiOpen(levelRoot, true)
        setGuiOpen(passRoot, true)
        setGuiOpen(questRoot, true)
        setGuiOpen(passShopPage, false)
    end

    local function showPassShopPage()
        setGuiOpen(levelRoot, false)
        setGuiOpen(passRoot, false)
        setGuiOpen(questRoot, false)
        setGuiOpen(passShopPage, true)
    end

    showPassMainPage()

    if passGui:IsA("ScreenGui") then
        passGui.DisplayOrder = math.max(passGui.DisplayOrder, 100)
    end

    local claimPassRewardRF = ReplicatedStorage:WaitForChild(PassRewardConfig.RemoteName, 10)
    if not claimPassRewardRF then
        warn("[PassController] " .. tostring(PassRewardConfig.RemoteName) .. " was not found.")
    end
    local purchasePassShopItemRF = ReplicatedStorage:WaitForChild(PassShopConfig.RemoteName, 10)
    if not purchasePassShopItemRF then
        warn("[PassController] " .. tostring(PassShopConfig.RemoteName) .. " was not found.")
    end
    local getPassQuestStateRF = ReplicatedStorage:WaitForChild(PassQuestConfig.StateRemoteName, 10)
    local claimPassQuestRF = ReplicatedStorage:WaitForChild(PassQuestConfig.ClaimRemoteName, 10)
    if not getPassQuestStateRF then
        warn("[PassController] " .. tostring(PassQuestConfig.StateRemoteName) .. " was not found.")
    end
    if not claimPassQuestRF then
        warn("[PassController] " .. tostring(PassQuestConfig.ClaimRemoteName) .. " was not found.")
    end

    local function isRewardClaimed(passData, trackKey, tier)
        if type(passData) ~= "table" then
            return false
        end

        if tier == PassRewardConfig.RepeatTier then
            local repeatAvailable = math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0))
            local repeatClaimed = trackKey == PassRewardConfig.TrackKeys.Premium
                and math.max(0, math.floor(tonumber(passData.PremiumRepeatClaimed) or 0))
                or math.max(0, math.floor(tonumber(passData.FreeRepeatClaimed) or 0))
            return repeatAvailable > 0 and repeatClaimed >= repeatAvailable
        end

        local claimedMap = trackKey == PassRewardConfig.TrackKeys.Premium and passData.PremiumClaimed or passData.FreeClaimed
        return type(claimedMap) == "table" and claimedMap[tostring(tier)] == true
    end

    local function getRewardSlotState(passData, trackKey, tier)
        local level = normalizePassData(passData)
        local isPremium = trackKey == PassRewardConfig.TrackKeys.Premium
        local ownsPremium = type(passData) == "table" and passData.PremiumOwned == true
        local hasTrackAccess = not isPremium or ownsPremium

        if tier == PassRewardConfig.RepeatTier then
            local repeatAvailable = type(passData) == "table"
                and math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0))
                or 0
            local isUnlocked = hasTrackAccess and repeatAvailable > 0
            return isUnlocked, isUnlocked and isRewardClaimed(passData, trackKey, tier)
        end

        local isUnlocked = level >= tier and hasTrackAccess
        return isUnlocked, isUnlocked and isRewardClaimed(passData, trackKey, tier)
    end

    local function renderRewardSlot(slot, passData)
        local isUnlocked, isRewardSlotClaimed = getRewardSlotState(passData, slot.TrackKey, slot.Tier)
        local isConfiguredReward = not (slot.Reward and slot.Reward.Claimable == false)
        local isClaimed = isConfiguredReward and isRewardSlotClaimed

        if slot.TitleText and slot.Reward then
            local amount = math.max(1, math.floor(tonumber(slot.Reward.Amount) or 1))
            if isConfiguredReward then
                slot.TitleText.Text = tostring(slot.Reward.DisplayName or "Reward") .. " x " .. tostring(amount)
            else
                slot.TitleText.Text = tostring(slot.Reward.DisplayName or "Reward")
            end
        end

        setGuiObjectVisible(slot.Locked, not isUnlocked)
        setGuiObjectVisible(slot.Claimed, isClaimed)
        local claimText = not isConfiguredReward and "No Token" or (isClaimed and "Claimed" or "Claim")
        if slot.ClaimText then
            setTextObjectText(slot.ClaimText, claimText)
        else
            setButtonText(slot.ButtonRoot, claimText)
        end
        setButtonEnabled(slot.Button, isConfiguredReward and isUnlocked and not isClaimed and claimPassRewardRF ~= nil)
    end

    local function hasClaimableReward(passData)
        for _, slot in ipairs(rewardSlots) do
            local isUnlocked, isRewardSlotClaimed = getRewardSlotState(passData, slot.TrackKey, slot.Tier)
            local isConfiguredReward = not (slot.Reward and slot.Reward.Claimable == false)
            if isConfiguredReward and isUnlocked and not isRewardSlotClaimed then
                return true
            end
        end

        return false
    end

    local function getQuestStateById(taskId)
        if not (currentQuestState and type(currentQuestState.Tasks) == "table") then
            return nil
        end

        for _, questState in pairs(currentQuestState.Tasks) do
            if type(questState) == "table" and questState.Id == taskId then
                return questState
            end
        end

        return nil
    end

    local function getQuestResetRemainingSeconds()
        if type(currentQuestState) ~= "table" then
            return PassQuestConfig.RefreshIntervalSeconds
        end

        local remaining = math.max(0, math.floor(tonumber(currentQuestState.ResetRemainingSeconds) or 0))
        local receivedAt = tonumber(currentQuestState.ClientReceivedAt)
        if receivedAt then
            remaining -= math.floor(os.clock() - receivedAt)
        end

        return math.max(0, remaining)
    end

    local function hasClaimableQuest()
        if not (currentQuestState and type(currentQuestState.Tasks) == "table") then
            return false
        end

        for _, questState in pairs(currentQuestState.Tasks) do
            if type(questState) == "table" and questState.CanClaim == true then
                return true
            end
        end

        return false
    end

    local function refreshPassNotification()
        if passNotification then
            setGuiObjectVisible(passNotification, hasClaimableReward(currentPassData) or hasClaimableQuest())
        end
    end

    local function getQuestTitle(taskConfig, questState)
        local progress = math.max(0, math.floor(tonumber(questState and questState.Progress) or 0))
        local target = math.max(1, math.floor(tonumber(questState and questState.Target or taskConfig.Target) or 1))

        if taskConfig.Id == PassQuestConfig.TaskIds.OnlineDuration then
            return string.format("OnlineDuration(%d/%d)", progress, target)
        end
        if taskConfig.Id == PassQuestConfig.TaskIds.DefeatZombies then
            return string.format("Defeat Zombies(%d/%d)", progress, target)
        end
        if taskConfig.Id == PassQuestConfig.TaskIds.HarvestPlants then
            return string.format("Harvest Plants (%d/%d)", progress, target)
        end

        return tostring(taskConfig.DisplayName or "Quest")
    end

    local function renderQuestSlot(slot)
        if not slot then
            return
        end

        local taskConfig = slot.TaskConfig
        local questState = getQuestStateById(taskConfig.Id)
        local rewardExp = math.max(0, math.floor(tonumber(questState and questState.RewardExp or taskConfig.RewardExp) or 0))
        local target = math.max(1, math.floor(tonumber(questState and questState.Target or taskConfig.Target) or 1))
        local progress = math.clamp(math.floor(tonumber(questState and questState.Progress) or 0), 0, target)
        local claimed = questState and questState.Claimed == true
        local canClaim = questState and questState.CanClaim == true or (not claimed and progress >= target)

        if slot.NameText then
            slot.NameText.Text = getQuestTitle(taskConfig, questState)
        end
        if slot.ButtonText then
            slot.ButtonText.Text = claimed and CLAIMED_MARK or (tostring(rewardExp) .. " EXP")
        end

        setVisualEnabled(slot.OnVisual, claimed or canClaim)
        setVisualEnabled(slot.OffVisual, not (claimed or canClaim))
        setButtonEnabled(slot.Button, canClaim and not claimed and claimPassQuestRF ~= nil)
    end

    local function refreshQuestSlots()
        for _, slot in ipairs(questSlots) do
            renderQuestSlot(slot)
        end
        refreshPassNotification()
    end

    local function refreshQuestHeader()
        if questRoot then
            local headerText = findTextObject(findPath(questRoot, { "Container", "TextFrame", "Text" }))
                or findTextObject(findPath(questRoot, { "Header", "Name" }))
            if headerText then
                headerText.Text = "Refresh in " .. formatDuration(getQuestResetRemainingSeconds())
            end
        end
    end

    local function refreshQuestView()
        refreshQuestHeader()
        refreshQuestSlots()
    end

    local function refreshRewardSlots(passData)
        for _, slot in ipairs(rewardSlots) do
            renderRewardSlot(slot, passData)
        end
    end

    local function claimReward(slot)
        if isClaimingReward then
            UIEffectUtil.ShowTip("Claim is processing.")
            return
        end
        if not claimPassRewardRF then
            UIEffectUtil.ShowTip("Pass reward is unavailable.")
            return
        end

        isClaimingReward = true
        local ok, success, message, passData = pcall(function()
            return claimPassRewardRF:InvokeServer(slot.TrackKey, slot.Tier)
        end)
        isClaimingReward = false

        if not ok then
            warn("[PassController] ClaimPassRewardRF failed: " .. tostring(success))
            UIEffectUtil.ShowTip("Claim failed. Please try again.")
            return
        end

        if type(passData) == "table" then
            currentPassData = passData
            refreshRewardSlots(currentPassData)
            refreshPassNotification()
        end

        UIEffectUtil.ShowTip(tostring(message or (success and "Claimed." or "Claim failed.")))
    end

    local function requestQuestStateFromServer(silent)
        if not getPassQuestStateRF then
            if not silent then
                UIEffectUtil.ShowTip("Pass quests are unavailable.")
            end
            return false
        end

        local ok, state = pcall(function()
            return getPassQuestStateRF:InvokeServer()
        end)

        if not ok then
            warn("[PassController] GetPassQuestStateRF failed: " .. tostring(state))
            if not silent then
                UIEffectUtil.ShowTip("Pass quests are loading. Please try again.")
            end
            return false
        end

        if type(state) ~= "table" then
            return false
        end

        state.ClientReceivedAt = os.clock()
        currentQuestState = state
        refreshQuestView()
        return true
    end

    local function claimQuest(slot)
        if isClaimingQuest then
            UIEffectUtil.ShowTip("Claim is processing.")
            return
        end
        if not claimPassQuestRF then
            UIEffectUtil.ShowTip("Pass quest is unavailable.")
            return
        end

        local questState = getQuestStateById(slot.TaskConfig.Id)
        if not questState or questState.Claimed == true then
            return
        end
        if questState.CanClaim ~= true then
            UIEffectUtil.ShowTip("Quest is not complete.")
            return
        end

        isClaimingQuest = true
        local ok, success, message, state = pcall(function()
            return claimPassQuestRF:InvokeServer(slot.TaskConfig.Id)
        end)
        isClaimingQuest = false

        if not ok then
            warn("[PassController] ClaimPassQuestRF failed: " .. tostring(success))
            UIEffectUtil.ShowTip("Claim failed. Please try again.")
            return
        end

        if type(state) == "table" then
            state.ClientReceivedAt = os.clock()
            currentQuestState = state
            refreshQuestView()
        end

        UIEffectUtil.ShowTip(tostring(message or (success and "Claimed." or "Claim failed.")))
    end

    local function bindQuestSlots()
        if not questRoot then
            return
        end

        local container = questRoot:WaitForChild("Container", 10)
        if not container then
            warn("[PassController] Missing quest container: BasicGui.PassGui.Quest.Container")
            return
        end

        table.clear(questSlots)

        local function findQuestGradient(onOffRoot, gradientName)
            if not onOffRoot then
                return nil
            end

            local decorRoot = onOffRoot:FindFirstChild("Decor")
            local studRoot = decorRoot and decorRoot:FindFirstChild("Stud")
            local gradient = studRoot and studRoot:FindFirstChild(gradientName)
            if gradient then
                return gradient
            end

            decorRoot = onOffRoot:FindFirstChild("Decor-Stud")
            gradient = decorRoot and decorRoot:FindFirstChild(gradientName)
            if gradient then
                return gradient
            end

            return onOffRoot:FindFirstChild(gradientName)
        end

        for _, taskConfig in ipairs(PassQuestConfig.Tasks) do
            local slotRoot = container:WaitForChild("Button" .. tostring(taskConfig.Slot), 10)
            local onOffRoot = slotRoot and waitForPath(slotRoot, { "Button", "On/Off" })
            local buttonText = findTextObject(onOffRoot and onOffRoot:FindFirstChild("On/Off"))
                or findTextObject(onOffRoot)
            local button = getOrCreateTransparentButton(onOffRoot, "PassQuestClaimClickArea")
            local slot = {
                TaskConfig = taskConfig,
                Root = slotRoot,
                ButtonRoot = onOffRoot,
                Button = button,
                OnVisual = findQuestGradient(onOffRoot, "On"),
                OffVisual = findQuestGradient(onOffRoot, "Off"),
                ButtonText = buttonText,
                NameText = findTextObject(slotRoot and slotRoot:FindFirstChild("Name")),
            }

            if slotRoot and onOffRoot and button and buttonText and slot.NameText then
                table.insert(questSlots, slot)
                if not button:GetAttribute("PassQuestBound") then
                    button:SetAttribute("PassQuestBound", true)
                    button.Activated:Connect(function()
                        claimQuest(slot)
                    end)
                end
            else
                warn("[PassController] Quest slot binding is incomplete: Button" .. tostring(taskConfig.Slot))
            end
        end
    end

    local function startQuestCountdownLoop()
        if questCountdownLoopRunning then
            return
        end

        questCountdownLoopRunning = true
        task.spawn(function()
            while isGuiOpen(passGui) do
                refreshQuestHeader()
                task.wait(1)
            end
            questCountdownLoopRunning = false
        end)
    end

    local function getCurrentTokenCount()
        if type(currentPlayerData) ~= "table" then
            return 0
        end

        return math.max(0, math.floor(tonumber(currentPlayerData[PassShopConfig.TokenDataKey or "PassShopTokens"]) or 0))
    end

    local function promptPremiumPassPurchase()
        if type(currentPassData) == "table" and currentPassData.PremiumOwned == true then
            UIEffectUtil.ShowTip("Premium pass is already unlocked.")
            return
        end

        local gamePassId = tonumber(PassRewardConfig.PremiumGamePassId)
        if not (gamePassId and gamePassId > 0) then
            UIEffectUtil.ShowTip("Premium pass is unavailable.")
            return
        end

        UIEffectUtil.ShowTip("Opening premium pass purchase...")
        MarketplaceService:PromptGamePassPurchase(player, gamePassId)
    end

    local refreshTokenCount

    local function refreshPassShopSlots()
        local ownsPremium = type(currentPassData) == "table" and currentPassData.PremiumOwned == true
        local tokenCount = getCurrentTokenCount()

        for _, slot in ipairs(passShopSlots) do
            local itemConfig = slot.ItemConfig
            local price = math.max(0, math.floor(tonumber(itemConfig.Price) or 0))
            local canBuy = price > 0
                and (
                    itemConfig.PremiumOnly == true and not ownsPremium
                    or purchasePassShopItemRF ~= nil
                )

            if slot.PriceText then
                slot.PriceText.Text = tostring(price)
            end
            setButtonEnabled(slot.Button, canBuy)
        end
    end

    local function purchasePassShopItem(slot)
        if isPurchasingShopItem then
            UIEffectUtil.ShowTip("Purchase is processing.")
            return
        end

        local itemConfig = slot.ItemConfig
        local ownsPremium = type(currentPassData) == "table" and currentPassData.PremiumOwned == true
        if itemConfig.PremiumOnly == true and not ownsPremium then
            promptPremiumPassPurchase()
            return
        end

        if not purchasePassShopItemRF then
            UIEffectUtil.ShowTip("Pass shop is unavailable.")
            return
        end

        local price = math.max(0, math.floor(tonumber(itemConfig.Price) or 0))
        if getCurrentTokenCount() < price then
            UIEffectUtil.ShowTip("Not enough Token.")
            return
        end

        isPurchasingShopItem = true
        local ok, success, message, tokenCount = pcall(function()
            return purchasePassShopItemRF:InvokeServer(slot.ItemKey or slot.SlotName)
        end)
        isPurchasingShopItem = false

        if not ok then
            warn("[PassController] PurchasePassShopItemRF failed: " .. tostring(success))
            UIEffectUtil.ShowTip("Purchase failed. Please try again.")
            return
        end

        if tokenCount ~= nil then
            currentPlayerData = currentPlayerData or {}
            currentPlayerData[PassShopConfig.TokenDataKey or "PassShopTokens"] = tokenCount
            refreshTokenCount(currentPlayerData)
            refreshPassShopSlots()
        end

        UIEffectUtil.ShowTip(tostring(message or (success and "Purchased." or "Purchase failed.")))
    end

    -- 按配置找到指定期数的商店 Holder，兼容旧版单 Holder 结构。
    local function findPassShopHolder(scrollingFrame, holderName)
        if not scrollingFrame then
            return nil
        end

        holderName = tostring(holderName or "")
        if holderName ~= "" then
            return scrollingFrame:FindFirstChild(holderName)
        end

        return scrollingFrame:FindFirstChild("Holder")
    end

    local function bindPassShopSlots()
        local scrollingFrame = findPath(passShopPage, { "MainScrollingFrame" })
        if not scrollingFrame then
            warn("[PassController] Missing pass shop scrolling frame: BasicGui.PassGui.Shop.MainScrollingFrame")
            return
        end

        table.clear(passShopSlots)

        for _, itemKey in ipairs(PassShopConfig.Order or {}) do
            local itemConfig = PassShopConfig.GetItem(itemKey)
            local holderName = itemConfig and itemConfig.HolderName or "Holder"
            local slotName = itemConfig and itemConfig.SlotName or itemKey
            local holder = findPassShopHolder(scrollingFrame, holderName)
            local slotRoot = itemConfig and holder and holder:WaitForChild(slotName, 10)
            local purchaseRoot = slotRoot and slotRoot:WaitForChild("Purchase", 10)
            local button = getOrCreateTransparentButton(purchaseRoot, "PassShopPurchaseClickArea")
            local priceText = findTextObject(slotRoot and slotRoot:FindFirstChild("Price", true))
                or (purchaseRoot and purchaseRoot:FindFirstChildWhichIsA("TextLabel", true))

            if itemConfig and slotRoot and purchaseRoot and button then
                local slot = {
                    ItemKey = itemKey,
                    SlotName = slotName,
                    HolderName = holderName,
                    ItemConfig = itemConfig,
                    Root = slotRoot,
                    Button = button,
                    PriceText = priceText,
                }
                table.insert(passShopSlots, slot)

                if not button:GetAttribute("PassShopPurchaseBound") then
                    button:SetAttribute("PassShopPurchaseBound", true)
                    button.Activated:Connect(function()
                        purchasePassShopItem(slot)
                    end)
                end
            else
                warn(
                    "[PassController] Pass shop slot binding is incomplete: "
                        .. tostring(holderName)
                        .. "."
                        .. tostring(slotName)
                        .. " ("
                        .. tostring(itemKey)
                        .. ")"
                )
            end
        end

        refreshPassShopSlots()
    end

    local function bindRewardSlots()
        local scrollingRoot = waitForPath(passGui, { "Pass", "Container", "Scrolling" })
        if not scrollingRoot then
            warn("[PassController] Missing reward root: BasicGui.PassGui.Pass.Container.Scrolling")
            return
        end

        for _, trackKey in ipairs({ PassRewardConfig.TrackKeys.Free, PassRewardConfig.TrackKeys.Premium }) do
            local trackRoot = scrollingRoot:WaitForChild(trackKey, 10)
            if not trackRoot then
                warn("[PassController] Missing reward track: BasicGui.PassGui.Pass.Container.Scrolling." .. tostring(trackKey))
                continue
            end

            for tier = 1, PassRewardConfig.MaxLevel do
                local slotRoot = trackRoot:WaitForChild(tostring(tier), 10)
                local contentRoot = slotRoot and waitForPath(slotRoot, { "Frame", "Frame" })
                if not contentRoot then
                    warn("[PassController] Missing reward slot content: " .. tostring(trackKey) .. "." .. tostring(tier))
                    continue
                end

                local closeRoot = contentRoot:FindFirstChild("Close")
                local button = findButton(closeRoot)
                local claimText = findTextObject(findPath(contentRoot, { "Close", "Containers", "Name" }))
                local slot = {
                    TrackKey = trackKey,
                    Tier = tier,
                    Reward = PassRewardConfig.GetReward(trackKey, tier),
                    Locked = contentRoot:FindFirstChild("Locked"),
                    Claimed = contentRoot:FindFirstChild("Claimed"),
                    ButtonRoot = closeRoot,
                    Button = button,
                    ClaimText = claimText,
                    TitleText = findTextObject(contentRoot:FindFirstChild("Title")),
                }
                table.insert(rewardSlots, slot)

                if button and not button:GetAttribute("PassRewardBound") then
                    button:SetAttribute("PassRewardBound", true)
                    button.Activated:Connect(function()
                        claimReward(slot)
                    end)
                end
            end
        end
    end

    bindRewardSlots()
    bindQuestSlots()
    bindPassShopSlots()

    local function refreshPassView(passData, expPerLevel, maxLevel)
        currentPassData = passData

        if expAmountText then
            expAmountText.Text = formatPassText(passData, expPerLevel, maxLevel)
        end

        if expProgressBar then
            local progress = getPassProgress(passData, expPerLevel, maxLevel)
            local currentSize = expProgressBar.Size
            expProgressBar.Size = UDim2.new(progress, 0, currentSize.Y.Scale, currentSize.Y.Offset)
        end

        refreshRewardSlots(currentPassData)

        refreshPassNotification()

        if premiumBuyButton then
            local ownsPremium = type(currentPassData) == "table" and currentPassData.PremiumOwned == true
            setButtonEnabled(premiumBuyButton, not ownsPremium)
        end

        if premiumClaimedFrame then
            local ownsPremium = type(currentPassData) == "table" and currentPassData.PremiumOwned == true
            setGuiObjectVisible(premiumClaimedFrame, ownsPremium)
        end

        refreshPassShopSlots()
    end

    refreshTokenCount = function(playerData)
        local tokenCount = 0
        if type(playerData) == "table" then
            tokenCount = math.max(0, math.floor(tonumber(playerData[PassShopConfig.TokenDataKey or "PassShopTokens"]) or 0))
        end

        if tokenCountText then
            tokenCountText.Text = tostring(tokenCount)
        end
        refreshPassShopSlots()
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 10)
    local function requestPassDataFromServer()
        if not getPlayerDataRF then
            refreshPassView(nil)
            refreshTokenCount(nil)
            return
        end

        local ok, playerData = pcall(function()
            return getPlayerDataRF:InvokeServer()
        end)

        if ok and type(playerData) == "table" then
            currentPlayerData = playerData
            refreshPassView(playerData.PassV1)
            refreshTokenCount(playerData)
        else
            currentPlayerData = nil
            refreshPassView(nil)
            refreshTokenCount(nil)
        end
    end

    requestPassDataFromServer()
    requestQuestStateFromServer(true)

    local updatePassDataRE = ReplicatedStorage:WaitForChild("UpdatePassDataRE", 10)
    if updatePassDataRE then
        updatePassDataRE.OnClientEvent:Connect(function(passData, expPerLevel, maxLevel)
            refreshPassView(passData, expPerLevel, maxLevel)
        end)
    else
        warn("[PassController] UpdatePassDataRE was not found.")
    end

    local updatePassQuestStateRE = ReplicatedStorage:WaitForChild(PassQuestConfig.UpdateRemoteName, 10)
    if updatePassQuestStateRE then
        updatePassQuestStateRE.OnClientEvent:Connect(function(state)
            if type(state) == "table" then
                state.ClientReceivedAt = os.clock()
                currentQuestState = state
                refreshQuestView()
            end
        end)
    else
        warn("[PassController] " .. tostring(PassQuestConfig.UpdateRemoteName) .. " was not found.")
    end

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 10)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function(playerData)
            currentPlayerData = playerData
            refreshTokenCount(playerData)
        end)
    else
        warn("[PassController] UpdateInventoryRE was not found.")
    end

    if premiumBuyButton then
        premiumBuyButton.Activated:Connect(function()
            promptPremiumPassPurchase()
        end)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if tonumber(userId) ~= player.UserId or tonumber(productId) ~= tonumber(PassRewardConfig.ExpProductId) then
            return
        end

        if isPurchased then
            UIEffectUtil.ShowTip("Pass EXP purchased.")
        end
        task.delay(0.5, requestPassDataFromServer)
    end)

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, passId, wasPurchased)
        if purchasingPlayer ~= player or tonumber(passId) ~= tonumber(PassRewardConfig.PremiumGamePassId) then
            return
        end

        if wasPurchased then
            UIEffectUtil.ShowTip("Premium pass unlocked.")
            task.delay(0.5, requestPassDataFromServer)
        else
            task.delay(0.5, requestPassDataFromServer)
        end
    end)

    if openButton then
        openButton.Activated:Connect(function()
            showPassMainPage()
            setGuiOpen(passGui, true)
            requestQuestStateFromServer(true)
            startQuestCountdownLoop()
        end)
    end

    if closeButton then
        closeButton.Activated:Connect(function()
            setGuiOpen(passGui, false)
        end)
    end

    if openShopButton then
        openShopButton.Activated:Connect(function()
            showPassShopPage()
        end)
    end

    if closeShopButton then
        closeShopButton.Activated:Connect(function()
            showPassMainPage()
        end)
    end
end

return PassController

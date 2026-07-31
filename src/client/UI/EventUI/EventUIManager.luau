-- src/client/UI/EventUI/EventUIManager.luau
local EventUIManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local SevenDayPage = require(script.Parent.SevenDayPage)
local AchievePage = require(script.Parent.AchievePage)
local UIEffectUtil = require(script.Parent.Parent.Parent.Utils.UIEffectUtil)
local ZombossShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZombossShopConfig"))

local SIGN_IN_TUTORIAL_STEP_REQUIRED = 8
local ZOMBOSS_STATE_REMOTE_NAME = "GetZombossBossFightStateRF"
local ZOMBOSS_INTRO_UI_LOCK_ATTRIBUTE = "ZombossIntroUILocked"
local ZOMBOSS_FIGHT_UI_LOCK_ATTRIBUTE = "ZombossFightUILocked"

local forceCloseForBossImpl = nil

local function setGuiOpen(gui, isOpen)
    if not gui then
        return
    end

    if gui:IsA("ScreenGui") then
        gui.Enabled = isOpen
    elseif gui:IsA("GuiObject") then
        gui.Visible = isOpen
    end
end

local function hideOverlayInstant(overlay)
    if overlay and overlay:IsA("GuiObject") then
        overlay.BackgroundTransparency = 1
        overlay.Visible = false
        overlay.Active = false
    end
end

local function isClientBossUILocked()
    local player = Players.LocalPlayer
    return player
        and (
            player:GetAttribute(ZOMBOSS_INTRO_UI_LOCK_ATTRIBUTE) == true
            or player:GetAttribute(ZOMBOSS_FIGHT_UI_LOCK_ATTRIBUTE) == true
        )
end

local function isServerBossFightActive()
    local stateRemote = ReplicatedStorage:FindFirstChild(ZOMBOSS_STATE_REMOTE_NAME)
    if not (stateRemote and stateRemote:IsA("RemoteFunction")) then
        return false
    end

    local ok, payload = pcall(function()
        return stateRemote:InvokeServer()
    end)

    return ok and type(payload) == "table" and payload.IsActive == true
end

local function isBossUIBlocked()
    return isClientBossUILocked() or isServerBossFightActive()
end

function EventUIManager.ForceCloseForBoss()
    if forceCloseForBossImpl then
        forceCloseForBossImpl()
        return
    end

    local player = Players.LocalPlayer
    local playerGui = player and player:FindFirstChild("PlayerGui")
    local basicGui = playerGui and playerGui:FindFirstChild("BasicGui")
    if not basicGui then
        return
    end

    local eventPage = basicGui:FindFirstChild("EventPage")
    local overlay = eventPage and eventPage:FindFirstChild("Overlay")
    if eventPage then
        for _, childName in ipairs({"7Day", "Achieve", "ZombossShop", "explanation"}) do
            local child = eventPage:FindFirstChild(childName)
            if child and child:IsA("GuiObject") then
                child.Visible = false
            end
        end

        hideOverlayInstant(overlay)
        setGuiOpen(eventPage, false)
    end

    setGuiOpen(basicGui:FindFirstChild("PlayProperty"), true)
    UIEffectUtil.ForceClearScreenBlur(overlay)
end

local function isTextObject(instance)
    return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function connectPress(guiObject, callback)
    if not guiObject then
        return
    end

    if guiObject:IsA("GuiButton") then
        guiObject.Activated:Connect(callback)
    else
        guiObject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                callback()
            end
        end)
    end
end

local function findNamedTextObject(root, name)
    if not root then
        return nil
    end

    local direct = root:FindFirstChild(name)
    if isTextObject(direct) then
        return direct
    end

    if direct then
        for _, desc in ipairs(direct:GetDescendants()) do
            if isTextObject(desc) then
                return desc
            end
        end
    end

    for _, desc in ipairs(root:GetDescendants()) do
        if desc.Name == name and isTextObject(desc) then
            return desc
        end
    end

    return nil
end

local function findCoinTextObject(zombossShop)
    local banner = zombossShop and zombossShop:FindFirstChild("Banner")
    local canvasGroup = banner and banner:FindFirstChild("CanvasGroup")
    local bg = canvasGroup and canvasGroup:FindFirstChild("BG")
    return findNamedTextObject(bg, "Coin")
end

local function formatRefreshTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainingSeconds = seconds % 60
    return string.format("Shop refreshes in %02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function formatBossAppearTime(seconds, isEnabled)
    if isEnabled == false then
        return "Dr. Zomboss is temporarily unavailable."
    end

    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainingSeconds = seconds % 60
    return string.format("Dr. Zomboss will appear in %02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function formatBossAppearHudTime(seconds, isEnabled)
    if isEnabled == false then
        return "Dr. Zomboss: Offline"
    end

    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainingSeconds = seconds % 60
    return string.format("Dr. Zomboss: %02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function buildFallbackZombossState()
    local now = os.time()
    local offers = {}
    local bossEventEnabled = ZombossShopConfig.IsBossEventEnabled()
    local nextBossSpawnAt = bossEventEnabled and ZombossShopConfig.GetNextBossSpawnAt(now) or nil

    for _, offerId in ipairs(ZombossShopConfig.OfferOrder or {}) do
        local offer = ZombossShopConfig.GetOffer(offerId)
        if offer then
            offers[offerId] = {
                Purchased = 0,
                Limit = offer.Limit,
                Cost = offer.Cost,
                RewardType = offer.RewardType,
                RewardItemId = offer.RewardItemId,
                RewardAmount = offer.RewardAmount,
                RewardMutation = offer.RewardMutation,
            }
        end
    end

    return {
        Tacos = 0,
        RefreshAt = ZombossShopConfig.GetRefreshAt(now),
        RefreshRemainingSeconds = math.max(0, ZombossShopConfig.GetRefreshAt(now) - now),
        ServerNow = now,
        BossEventEnabled = bossEventEnabled,
        NextBossSpawnAt = nextBossSpawnAt,
        BossSpawnRemainingSeconds = nextBossSpawnAt and math.max(0, nextBossSpawnAt - now) or nil,
        Offers = offers,
    }
end

function EventUIManager.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")

    local eventPage = basicGui:WaitForChild("EventPage")
    local overlay = eventPage:FindFirstChild("Overlay")
    local sevenDayFrame = eventPage:FindFirstChild("7Day")
    local achieveFrame = eventPage:FindFirstChild("Achieve")
    local zombossShop = eventPage:FindFirstChild("ZombossShop")
    local explanationFrame = eventPage:FindFirstChild("explanation")

    local playProperty = basicGui:FindFirstChild("PlayProperty")
    local achieveBtn = playProperty and playProperty:FindFirstChild("Achieve")
    local eventBtn = playProperty and playProperty:FindFirstChild("Event")
    local eventTimeText = findNamedTextObject(eventBtn, "Time")

    local remoteNames = ZombossShopConfig.RemoteNames or {}
    local getStateRemoteName = remoteNames.GetState or "GetZombossShopStateRF"
    local buyItemRemoteName = remoteNames.BuyItem or "BuyZombossShopItemRF"
    local getZombossShopStateRF = nil
    local buyZombossShopItemRF = nil

    local tacoAmount = 0
    local refreshAt = nil
    local isRefreshingShop = false
    local isPurchasingShop = false
    local isContainerOpen = false
    local offerWidgets = {}
    local tacoText = findCoinTextObject(zombossShop)
    local banner = zombossShop and zombossShop:FindFirstChild("Banner")
    local timeText = findNamedTextObject(banner, "Time")
    local drTimeText = findNamedTextObject(banner, "DrTime")
    local bossEventEnabled = ZombossShopConfig.IsBossEventEnabled()
    local nextBossSpawnAt = nil
    local serverTimeOffsetSeconds = 0

    local function updateTacoText()
        if tacoText then
            tacoText.Text = UIEffectUtil.FormatNumber(tacoAmount)
        end
    end

    local function updateRefreshCountdownText()
        local remaining = 0
        local serverNow = os.time() + serverTimeOffsetSeconds
        if refreshAt then
            remaining = math.max(0, math.floor(refreshAt - serverNow))
        end

        if timeText then
            timeText.Text = formatRefreshTime(remaining)
        end

        return remaining
    end

    local function updateBossAppearCountdownText()
        if bossEventEnabled == false then
            if drTimeText then
                drTimeText.Text = formatBossAppearTime(nil, false)
            end
            if eventTimeText then
                eventTimeText.Text = formatBossAppearHudTime(nil, false)
            end
            return nil
        end

        local remaining = 0
        local serverNow = os.time() + serverTimeOffsetSeconds
        if nextBossSpawnAt then
            remaining = math.max(0, math.floor(nextBossSpawnAt - serverNow))
        end

        if drTimeText then
            drTimeText.Text = formatBossAppearTime(remaining, true)
        end
        if eventTimeText then
            eventTimeText.Text = formatBossAppearHudTime(remaining, true)
        end

        return remaining
    end

    local function getZombossShopStateRemote()
        if not getZombossShopStateRF or not getZombossShopStateRF.Parent then
            getZombossShopStateRF = ReplicatedStorage:FindFirstChild(getStateRemoteName)
                or ReplicatedStorage:WaitForChild(getStateRemoteName, 5)
        end

        return getZombossShopStateRF
    end

    local function getBuyZombossShopItemRemote()
        if not buyZombossShopItemRF or not buyZombossShopItemRF.Parent then
            buyZombossShopItemRF = ReplicatedStorage:FindFirstChild(buyItemRemoteName)
                or ReplicatedStorage:WaitForChild(buyItemRemoteName, 5)
        end

        return buyZombossShopItemRF
    end

    local function applyZombossShopState(state)
        if type(state) ~= "table" then
            state = buildFallbackZombossState()
        end

        tacoAmount = math.max(0, math.floor(tonumber(state.Tacos) or 0))
        if tonumber(state.ServerNow) then
            serverTimeOffsetSeconds = math.floor(tonumber(state.ServerNow) - os.time())
        end

        refreshAt = tonumber(state.RefreshAt)
        if not refreshAt then
            refreshAt = os.time() + math.max(0, math.floor(tonumber(state.RefreshRemainingSeconds) or 0))
        end
        bossEventEnabled = state.BossEventEnabled ~= false
        if bossEventEnabled then
            nextBossSpawnAt = tonumber(state.NextBossSpawnAt)
            if not nextBossSpawnAt then
                local serverNow = os.time() + serverTimeOffsetSeconds
                nextBossSpawnAt = serverNow + math.max(0, math.floor(tonumber(state.BossSpawnRemainingSeconds) or 0))
            end
        else
            nextBossSpawnAt = nil
        end

        updateTacoText()

        local offers = type(state.Offers) == "table" and state.Offers or {}
        for offerId, widgets in pairs(offerWidgets) do
            local offerState = type(offers[offerId]) == "table" and offers[offerId] or {}
            local offerConfig = ZombossShopConfig.GetOffer(offerId) or {}
            local purchased = math.max(0, math.floor(tonumber(offerState.Purchased) or 0))
            local limit = math.max(0, math.floor(tonumber(offerState.Limit or offerConfig.Limit) or 0))

            if widgets.LimitText then
                widgets.LimitText.Text = "(" .. tostring(purchased) .. "/" .. tostring(limit) .. ")"
            end
            if widgets.RobuxNumberText then
                widgets.RobuxNumberText.Text = "(" .. tostring(purchased) .. "/" .. tostring(limit) .. ")"
            end
        end

        updateRefreshCountdownText()
        updateBossAppearCountdownText()
    end

    local function refreshZombossShopState(silent)
        if isRefreshingShop then
            return
        end

        local stateRemote = getZombossShopStateRemote()
        if not stateRemote then
            if not silent then
                UIEffectUtil.ShowTip("Event shop is not ready.")
            end
            refreshAt = os.time() + 5
            updateRefreshCountdownText()
            updateBossAppearCountdownText()
            return
        end

        isRefreshingShop = true
        local ok, state = pcall(function()
            return stateRemote:InvokeServer()
        end)
        isRefreshingShop = false

        if ok and type(state) == "table" then
            applyZombossShopState(state)
        else
            if not silent then
                UIEffectUtil.ShowTip("Event shop is not ready.")
            end
            refreshAt = os.time() + 5
            updateRefreshCountdownText()
            updateBossAppearCountdownText()
        end
    end

    local function purchaseZombossOffer(offerId)
        if isPurchasingShop then
            UIEffectUtil.ShowTip("Purchase is processing.")
            return
        end

        local buyRemote = getBuyZombossShopItemRemote()
        if not buyRemote then
            UIEffectUtil.ShowTip("Event shop is not ready.")
            return
        end

        isPurchasingShop = true
        local ok, success, message, state = pcall(function()
            return buyRemote:InvokeServer(offerId)
        end)
        isPurchasingShop = false

        if ok then
            if type(state) == "table" then
                applyZombossShopState(state)
            else
                refreshZombossShopState(true)
            end

            UIEffectUtil.ShowTip(tostring(message or (success and "Purchased." or "Purchase failed.")))
        else
            UIEffectUtil.ShowTip("Purchase failed. Please try again.")
            refreshZombossShopState(true)
        end
    end

    local function promptZombossRobuxOffer(offerId)
        local offer = ZombossShopConfig.GetOffer(offerId)
        local productId = offer and tonumber(offer.RobuxProductId)
        if not productId or productId <= 0 then
            UIEffectUtil.ShowTip("Robux purchase is not ready.")
            return
        end

        MarketplaceService:PromptProductPurchase(player, productId)
    end

    if zombossShop then
        local scrollingFrame = zombossShop:FindFirstChild("ScrollingFrame")
        for _, offerId in ipairs(ZombossShopConfig.OfferOrder or {}) do
            local offer = ZombossShopConfig.GetOffer(offerId)
            local templateName = offer and (offer.TemplateName or offerId)
            local template = templateName and scrollingFrame and scrollingFrame:FindFirstChild(templateName)
            if not template and templateName and zombossShop then
                template = zombossShop:FindFirstChild(templateName, true)
            end
            if template then
                local limitText = findNamedTextObject(template, "Limit")
                local tacoBuyButton = template:FindFirstChild("TacoBuy", true)
                local robuxBuyButton = template:FindFirstChild("RobuxBuy", true)
                local robuxNumberText = findNamedTextObject(robuxBuyButton, "Number")
                offerWidgets[offerId] = {
                    LimitText = limitText,
                    TacoBuyButton = tacoBuyButton,
                    RobuxBuyButton = robuxBuyButton,
                    RobuxNumberText = robuxNumberText,
                }

                connectPress(tacoBuyButton, function()
                    purchaseZombossOffer(offerId)
                end)

                if robuxBuyButton then
                    connectPress(robuxBuyButton, function()
                        promptZombossRobuxOffer(offerId)
                    end)
                elseif offer and tonumber(offer.RobuxProductId) and tonumber(offer.RobuxProductId) > 0 then
                    warn("[EventUIManager] Missing ZombossShop RobuxBuy button: " .. tostring(offerId))
                end
            else
                warn("[EventUIManager] Missing ZombossShop offer template: " .. tostring(offerId))
            end
        end
    end

    local function openEventContainer(targetPage)
        if isBossUIBlocked() then
            EventUIManager.ForceCloseForBoss()
            return false
        end

        if not eventPage:IsA("ScreenGui") then
            return false
        end

        eventPage.DisplayOrder = 100
        eventPage.Enabled = true

        if playProperty then
            if playProperty:IsA("ScreenGui") then
                playProperty.Enabled = false
            else
                playProperty.Visible = false
            end
        end

        if overlay then
            overlay.Visible = true
            overlay.BackgroundTransparency = 1
            overlay.Active = true
        end

        if targetPage then targetPage.Visible = true end
        if sevenDayFrame and targetPage ~= sevenDayFrame then sevenDayFrame.Visible = false end
        if achieveFrame and targetPage ~= achieveFrame then achieveFrame.Visible = false end
        if zombossShop and targetPage ~= zombossShop then zombossShop.Visible = false end
        if explanationFrame then explanationFrame.Visible = false end

        if not isContainerOpen then
            isContainerOpen = true
            UIEffectUtil.SetScreenBlur(true, overlay)
        end

        return true
    end

    local function closeEventContainer(immediate)
        if isContainerOpen then
            isContainerOpen = false
            UIEffectUtil.SetScreenBlur(false, overlay)
        end

        if playProperty then
            if playProperty:IsA("ScreenGui") then
                playProperty.Enabled = true
            else
                playProperty.Visible = true
            end
        end

        if immediate then
            if eventPage:IsA("ScreenGui") then
                eventPage.Enabled = false
            end
        else
            task.delay(0.3, function()
                if not isContainerOpen then
                    eventPage.Enabled = false
                end
            end)
        end
    end

    local function forceCloseForBoss()
        if sevenDayFrame then sevenDayFrame.Visible = false end
        if achieveFrame then achieveFrame.Visible = false end
        if zombossShop then zombossShop.Visible = false end
        if explanationFrame then explanationFrame.Visible = false end

        closeEventContainer(true)
        hideOverlayInstant(overlay)
        UIEffectUtil.ForceClearScreenBlur(overlay)
    end

    forceCloseForBossImpl = forceCloseForBoss

    local function onPageClosed()
        local isSevenOpen = sevenDayFrame and sevenDayFrame.Visible
        local isAchieveOpen = achieveFrame and achieveFrame.Visible
        local isZombossShopOpen = zombossShop and zombossShop.Visible

        if not isSevenOpen and not isAchieveOpen and not isZombossShopOpen then
            closeEventContainer()
        end
    end

    if sevenDayFrame then
        sevenDayFrame:GetPropertyChangedSignal("Visible"):Connect(onPageClosed)
    end

    if achieveFrame then
        achieveFrame:GetPropertyChangedSignal("Visible"):Connect(onPageClosed)
    end

    if zombossShop then
        zombossShop:GetPropertyChangedSignal("Visible"):Connect(onPageClosed)
    end

    if achieveBtn then
        achieveBtn.Activated:Connect(function()
            openEventContainer(achieveFrame)
        end)
    end

    if eventBtn then
        connectPress(eventBtn, function()
            if not zombossShop then
                warn("[EventUIManager] Missing BasicGui.EventPage.ZombossShop")
                return
            end

            if openEventContainer(zombossShop) then
                refreshZombossShopState(false)
            end
        end)
    end

    if zombossShop then
        local banner = zombossShop:FindFirstChild("Banner")
        local closeButton = banner and banner:FindFirstChild("Close")
        local title = banner and banner:FindFirstChild("Title")
        local tacoExplanationButton = title and title:FindFirstChild("TacoBuy")
        connectPress(closeButton, function()
            if explanationFrame then
                explanationFrame.Visible = false
            end
            zombossShop.Visible = false
            onPageClosed()
        end)
        connectPress(tacoExplanationButton, function()
            if not explanationFrame then
                warn("[EventUIManager] Missing BasicGui.EventPage.explanation")
                return
            end

            explanationFrame.Visible = true
        end)
        zombossShop.Visible = false

        task.spawn(function()
            while player.Parent do
                task.wait(1)
                local bossRemaining = updateBossAppearCountdownText()
                if zombossShop.Visible then
                    local remaining = updateRefreshCountdownText()
                    if remaining <= 0 or (bossRemaining ~= nil and bossRemaining <= 0) then
                        refreshZombossShopState(true)
                    end
                elseif bossRemaining ~= nil and bossRemaining <= 0 then
                    refreshZombossShopState(true)
                end
            end
        end)
    elseif eventTimeText then
        task.spawn(function()
            while player.Parent do
                task.wait(1)
                local bossRemaining = updateBossAppearCountdownText()
                if bossRemaining ~= nil and bossRemaining <= 0 then
                    applyZombossShopState(buildFallbackZombossState())
                end
            end
        end)
    end

    if explanationFrame then
        local banner = explanationFrame:FindFirstChild("Banner")
        local closeButton = banner and banner:FindFirstChild("Close")
        connectPress(closeButton, function()
            explanationFrame.Visible = false
        end)
        explanationFrame.Visible = false
    end

    local playerDataPatchRE = ReplicatedStorage:FindFirstChild("PlayerDataPatchRE") or ReplicatedStorage:WaitForChild("PlayerDataPatchRE", 5)
    if playerDataPatchRE then
        playerDataPatchRE.OnClientEvent:Connect(function(patch)
            if type(patch) ~= "table" or patch.Tacos == nil then
                return
            end

            tacoAmount = math.max(0, math.floor(tonumber(patch.Tacos) or 0))
            updateTacoText()
        end)
    end

    if eventPage:IsA("ScreenGui") then
        eventPage.Enabled = false
    end

    if sevenDayFrame then
        SevenDayPage.Init(sevenDayFrame)
        sevenDayFrame.Visible = false
    end

    if achieveFrame then
        AchievePage.Init(achieveFrame)
        achieveFrame.Visible = false
    end

    applyZombossShopState(buildFallbackZombossState())
    task.defer(refreshZombossShopState, true)

    local signInAutoOpened = false
    local function tryOpenSignInAfterTutorial(data)
        if signInAutoOpened or not sevenDayFrame then
            return false
        end

        if isBossUIBlocked() then
            return false
        end

        local tutorialStep = math.floor(tonumber(data and data.TutorialStep) or 0)
        if tutorialStep < SIGN_IN_TUTORIAL_STEP_REQUIRED then
            return false
        end

        if openEventContainer(sevenDayFrame) then
            signInAutoOpened = true
            return true
        end

        return false
    end

    task.spawn(function()
        local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 10)
        if not getPlayerDataRF then
            return
        end

        while player.Parent and not signInAutoOpened do
            local ok, data = pcall(function()
                return getPlayerDataRF:InvokeServer()
            end)

            if ok and tryOpenSignInAfterTutorial(data) then
                return
            end

            task.wait(2)
        end
    end)
end

return EventUIManager

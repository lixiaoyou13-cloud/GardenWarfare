local ZombossUICleanup = {}

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIEffectUtil = require(script.Parent.UIEffectUtil)
local EventUIManager = require(script.Parent.Parent.UI.EventUI.EventUIManager)
local NoticeController = require(script.Parent.Parent.UI.NoticeController)
local GiftingController = require(script.Parent.Parent.UI.GiftingController)
local TradeController = require(script.Parent.Parent.UI.TradeController)

local LOCK_ATTRIBUTES = {
    Intro = "ZombossIntroUILocked",
    Fight = "ZombossFightUILocked",
}

local function getPlayerGui()
    local player = Players.LocalPlayer
    return player and (player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5))
end

local function setGuiOpen(instance, isOpen)
    if not instance then
        return
    end

    if instance:IsA("ScreenGui") then
        instance.Enabled = isOpen
    elseif instance:IsA("GuiObject") then
        instance.Visible = isOpen
    end
end

local function hideOverlay(overlay)
    if not (overlay and overlay:IsA("GuiObject")) then
        return
    end

    overlay.BackgroundTransparency = 1
    overlay.Visible = false
    overlay.Active = false
end

local function addOverlay(overlays, overlay)
    if overlay and overlay:IsA("GuiObject") then
        table.insert(overlays, overlay)
        hideOverlay(overlay)
    end
end

local function forceCloseController(controller, controllerName)
    local forceClose = controller and controller.ForceCloseForBoss
    if type(forceClose) ~= "function" then
        return
    end

    local ok, err = pcall(forceClose)
    if not ok then
        warn("[ZombossUICleanup] Failed to close " .. tostring(controllerName) .. ": " .. tostring(err))
    end
end

local function clearBlurEffect(effectName)
    local blur = Lighting:FindFirstChild(effectName)
    if not (blur and blur:IsA("BlurEffect")) then
        return
    end

    blur.Size = 0
    TweenService:Create(blur, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = 0}):Play()
end

local function hideEventPage(basicGui, overlays)
    local eventPage = basicGui and basicGui:FindFirstChild("EventPage")
    if not eventPage then
        return
    end

    for _, childName in ipairs({"7Day", "Achieve", "ZombossShop", "explanation"}) do
        local child = eventPage:FindFirstChild(childName)
        if child and child:IsA("GuiObject") then
            child.Visible = false
        end
    end

    addOverlay(overlays, eventPage:FindFirstChild("Overlay"))
    setGuiOpen(eventPage, false)
end

local function hideModalGui(basicGui, guiName, overlayName, overlays)
    local gui = basicGui and basicGui:FindFirstChild(guiName)
    if not gui then
        return
    end

    addOverlay(overlays, gui:FindFirstChild(overlayName, true))
    setGuiOpen(gui, false)
end

local function clearGlobalOverlay(playerGui, overlays)
    local globalOverlayGui = playerGui and playerGui:FindFirstChild("GlobalOverlayGui")
    local blackMask = globalOverlayGui and globalOverlayGui:FindFirstChild("BlackMask")
    addOverlay(overlays, blackMask)
end

function ZombossUICleanup.SetBossUILock(source, isLocked)
    local attributeName = LOCK_ATTRIBUTES[source]
    local player = Players.LocalPlayer
    if not (attributeName and player) then
        return
    end

    player:SetAttribute(attributeName, isLocked == true)
end

function ZombossUICleanup.ForceCloseBossBlockingUI()
    forceCloseController(EventUIManager, "EventUIManager")
    forceCloseController(NoticeController, "NoticeController")
    forceCloseController(GiftingController, "GiftingController")
    forceCloseController(TradeController, "TradeController")

    local overlays = {}
    local playerGui = getPlayerGui()
    local basicGui = playerGui and playerGui:FindFirstChild("BasicGui")
    if basicGui then
        hideEventPage(basicGui, overlays)
        hideModalGui(basicGui, "NoticeGui", "NoticeBlurOverlay", overlays)
        hideModalGui(basicGui, "GiftingGui", "GiftingBlurOverlay", overlays)
        setGuiOpen(basicGui:FindFirstChild("PlayProperty"), true)
    end

    clearGlobalOverlay(playerGui, overlays)
    UIEffectUtil.ForceClearScreenBlur(overlays)
    clearBlurEffect("UIBlur")
    clearBlurEffect("GlobalUIBlur")
end

return ZombossUICleanup

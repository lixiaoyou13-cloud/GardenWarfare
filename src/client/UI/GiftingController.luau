local GiftingController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
local GiftingConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GiftingConfig"))

local WAIT_TIMEOUT = 10
local BLUR_OVERLAY_NAME = "GiftingBlurOverlay"
local GIFTING_PANEL_MIN_Z_INDEX = 2
local GIFT_CLONE_ATTRIBUTE = "GiftingRewardClone"
local forceCloseForBossImpl = nil

local function warnMissing(path)
    warn("[GiftingController] Missing UI object: " .. tostring(path))
end

local function waitForChild(parent, childName, path)
    if not parent then
        return nil
    end

    local child = parent:WaitForChild(childName, WAIT_TIMEOUT)
    if not child then
        warnMissing(path .. "/" .. childName)
    end
    return child
end

local function findButton(root)
    if root and root:IsA("GuiButton") then
        return root
    end

    if not root then
        return nil
    end

    return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function findGuiObject(root)
    if root and root:IsA("GuiObject") then
        return root
    end

    return nil
end

local function findTextObject(root, childName)
    if not root then
        return nil
    end

    local node = root:FindFirstChild(childName, true)
    if not node then
        return nil
    end

    if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
        return node
    end

    return node:FindFirstChildWhichIsA("TextLabel", true)
        or node:FindFirstChildWhichIsA("TextButton", true)
        or node:FindFirstChildWhichIsA("TextBox", true)
end

local function setText(root, childName, text)
    local textObject = findTextObject(root, childName)
    if not textObject then
        warnMissing(tostring(root and root:GetFullName() or "GiftTemplate") .. "/" .. childName)
        return
    end

    textObject.Text = tostring(text or "")
end

local function hasGiftTemplateFields(template)
    return template
        and template:FindFirstChild("DisplayUser", true) ~= nil
        and template:FindFirstChild("MainUser", true) ~= nil
        and template:FindFirstChild("Confirm", true) ~= nil
end

local function getGiftTemplateSizeScore(template)
    if template and template:IsA("GuiObject") then
        return template.Size.Y.Scale * 100000 + template.Size.Y.Offset
    end

    return -math.huge
end

local function findGiftTemplate(uiTemplates)
    if not uiTemplates then
        return nil
    end

    local firstTemplate = uiTemplates:WaitForChild("GiftTemplate", WAIT_TIMEOUT)
    if not firstTemplate then
        warnMissing("ReplicatedStorage/UITemplates/GiftTemplate")
        return nil
    end

    local bestTemplate = nil
    local bestScore = -math.huge
    local giftTemplateCount = 0

    for _, child in ipairs(uiTemplates:GetChildren()) do
        if child.Name == "GiftTemplate" and child:IsA("GuiObject") then
            giftTemplateCount += 1

            local score = getGiftTemplateSizeScore(child)
            if not hasGiftTemplateFields(child) then
                score -= 100000000
            end

            if score > bestScore then
                bestTemplate = child
                bestScore = score
            end
        end
    end

    if giftTemplateCount > 1 then
        warn("[GiftingController] Multiple GiftTemplate instances found; using the tallest valid template.")
    end

    return bestTemplate or firstTemplate
end

local function clearGiftClones(parent)
    if not parent then
        return
    end

    for _, child in ipairs(parent:GetChildren()) do
        if child:GetAttribute(GIFT_CLONE_ATTRIBUTE) == true then
            child:Destroy()
        end
    end
end

local function hideGiftTemplates(parent)
    if not parent then
        return
    end

    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == "GiftTemplate" and child:IsA("GuiObject") then
            child.Visible = false
        end
    end
end

local function getToggleTarget(giftingGui)
    if not giftingGui then
        return nil
    end
    if giftingGui:IsA("ScreenGui") or giftingGui:IsA("GuiObject") then
        return giftingGui
    end

    local frame = giftingGui:FindFirstChild("Gifting")
    if frame and frame:IsA("GuiObject") then
        return frame
    end

    return nil
end

local function setGuiOpen(giftingGui, isOpen)
    local target = getToggleTarget(giftingGui)
    if not target then
        return
    end

    if target:IsA("ScreenGui") then
        target.Enabled = isOpen
    elseif target:IsA("GuiObject") then
        target.Visible = isOpen
    end
end

local function hideOverlayInstant(overlay)
    if overlay and overlay:IsA("GuiObject") then
        overlay.BackgroundTransparency = 1
        overlay.Visible = false
        overlay.Active = false
    end
end

function GiftingController.ForceCloseForBoss()
    if forceCloseForBossImpl then
        forceCloseForBossImpl()
        return
    end

    local player = Players.LocalPlayer
    local playerGui = player and player:FindFirstChild("PlayerGui")
    local basicGui = playerGui and playerGui:FindFirstChild("BasicGui")
    local giftingGui = basicGui and basicGui:FindFirstChild("GiftingGui")
    if not giftingGui then
        return
    end

    hideOverlayInstant(giftingGui:FindFirstChild(BLUR_OVERLAY_NAME, true))
    setGuiOpen(giftingGui, false)
end

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

function GiftingController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
    if not playerGui then
        warnMissing("PlayerGui")
        return
    end

    local basicGui = waitForChild(playerGui, "BasicGui", "PlayerGui")
    if not basicGui then
        return
    end

    local playProperty = waitForChild(basicGui, "PlayProperty", "PlayerGui/BasicGui")
    local giftingGui = waitForChild(basicGui, "GiftingGui", "PlayerGui/BasicGui")
    if not (playProperty and giftingGui) then
        return
    end

    local giftButtonRoot = playProperty:FindFirstChild("Gift")
    local openButton = findButton(giftButtonRoot)
    if not openButton then
        warnMissing("PlayerGui/BasicGui/PlayProperty/Gift")
        return
    end
    local giftNotification = findGuiObject(giftButtonRoot and giftButtonRoot:FindFirstChild("Notifications"))
    if not giftNotification then
        warnMissing("PlayerGui/BasicGui/PlayProperty/Gift/Notifications")
    end

    local giftingFrame = waitForChild(giftingGui, "Gifting", "PlayerGui/BasicGui/GiftingGui")
    local topFrame = waitForChild(giftingFrame, "Top", "PlayerGui/BasicGui/GiftingGui/Gifting")
    local mainFrame = waitForChild(giftingFrame, "Main", "PlayerGui/BasicGui/GiftingGui/Gifting")
    local closeButton = findButton(topFrame and topFrame:FindFirstChild("Close"))
    if not closeButton then
        warnMissing("PlayerGui/BasicGui/GiftingGui/Gifting/Top/Close")
        return
    end

    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates", WAIT_TIMEOUT)
    if not uiTemplates then
        warnMissing("ReplicatedStorage/UITemplates")
    end

    local giftTemplate = findGiftTemplate(uiTemplates)
    if not giftTemplate then
        warnMissing("ReplicatedStorage/UITemplates/GiftTemplate")
    end

    local getGiftingStateRF = ReplicatedStorage:WaitForChild(GiftingConfig.StateRemoteName, WAIT_TIMEOUT)
    if not getGiftingStateRF then
        warn("[GiftingController] " .. tostring(GiftingConfig.StateRemoteName) .. " was not found.")
    end

    local claimGiftingRewardRF = ReplicatedStorage:WaitForChild(GiftingConfig.ClaimRemoteName, WAIT_TIMEOUT)
    if not claimGiftingRewardRF then
        warn("[GiftingController] " .. tostring(GiftingConfig.ClaimRemoteName) .. " was not found.")
    end

    local giftingUpdateRE = ReplicatedStorage:WaitForChild(GiftingConfig.UpdateRemoteName, WAIT_TIMEOUT)
    if not giftingUpdateRE then
        warn("[GiftingController] " .. tostring(GiftingConfig.UpdateRemoteName) .. " was not found.")
    end

    -- 礼物界面的背景模糊交给全局 UI 管理器处理，这里只清理旧遮罩。
    local blurOverlay = giftingGui:FindFirstChild(BLUR_OVERLAY_NAME, true)
    hideOverlayInstant(blurOverlay)
    raiseGuiTree(giftingFrame, GIFTING_PANEL_MIN_Z_INDEX)
    local isOpen = false
    local isClaiming = false

    local toggleTarget = getToggleTarget(giftingGui)
    if toggleTarget then
        local propertyName
        if toggleTarget:IsA("ScreenGui") then
            propertyName = "Enabled"
        else
            propertyName = "Visible"
        end
        toggleTarget:GetPropertyChangedSignal(propertyName):Connect(function()
            local isActuallyOpen
            if toggleTarget:IsA("ScreenGui") then
                isActuallyOpen = toggleTarget.Enabled
            else
                isActuallyOpen = toggleTarget.Visible
            end
            isOpen = isActuallyOpen
            if not isActuallyOpen then
                hideOverlayInstant(blurOverlay)
            end
        end)
    end

    local function hasClaimableGift(rewards)
        if type(rewards) ~= "table" then
            return false
        end

        for _, reward in ipairs(rewards) do
            if type(reward) == "table" then
                return true
            end
        end

        return false
    end

    local function refreshGiftNotification(rewards)
        if giftNotification then
            giftNotification.Visible = hasClaimableGift(rewards)
        end
    end

    local function renderGifts(rewards)
        refreshGiftNotification(rewards)

        if not (mainFrame and giftTemplate) then
            return
        end

        hideGiftTemplates(mainFrame)
        clearGiftClones(mainFrame)

        if type(rewards) ~= "table" then
            return
        end

        for index, reward in ipairs(rewards) do
            if type(reward) == "table" then
                local giftId = tostring(reward.Id or "")
                local giftItem = giftTemplate:Clone()
                giftItem.Name = "Gift_" .. tostring(index)
                giftItem:SetAttribute(GIFT_CLONE_ATTRIBUTE, true)
                giftItem:SetAttribute("GiftId", giftId)
                if giftItem:IsA("GuiObject") then
                    giftItem.Visible = true
                end

                setText(giftItem, "DisplayUser", reward.Title or "Gift")
                setText(giftItem, "MainUser", reward.RewardText or "Reward")

                local confirmButton = findButton(giftItem:FindFirstChild("Confirm", true))
                if confirmButton then
                    confirmButton:SetAttribute("GiftId", giftId)
                    confirmButton.Activated:Connect(function()
                        if isClaiming then
                            UIEffectUtil.ShowTip("Claim is processing.")
                            return
                        end

                        if giftId == "" or not claimGiftingRewardRF then
                            UIEffectUtil.ShowTip("Gift is not available.")
                            return
                        end

                        isClaiming = true
                        local ok, success, message, state = pcall(function()
                            return claimGiftingRewardRF:InvokeServer(giftId)
                        end)
                        isClaiming = false

                        if not ok then
                            warn("[GiftingController] Claim failed: " .. tostring(success))
                            UIEffectUtil.ShowTip("Claim failed. Please try again.")
                            return
                        end

                        if type(state) == "table" then
                            renderGifts(state)
                        end

                        UIEffectUtil.ShowTip(tostring(message or (success and "Claimed." or "Claim failed.")))
                    end)
                else
                    warnMissing(giftItem:GetFullName() .. "/Confirm")
                end

                giftItem.Parent = mainFrame
            end
        end
    end

    local function refreshGiftsFromServer()
        if not getGiftingStateRF then
            renderGifts({})
            return
        end

        local ok, rewards = pcall(function()
            return getGiftingStateRF:InvokeServer()
        end)

        if not ok then
            warn("[GiftingController] Get gifting state failed: " .. tostring(rewards))
            renderGifts({})
            return
        end

        renderGifts(rewards)
    end

    local function openGifting()
        if isOpen then
            return
        end

        -- 开启后由 init.client 的全局面板逻辑关闭其他界面并处理背景效果。
        setGuiOpen(giftingGui, true)
        isOpen = true
    end

    local function closeGifting()
        if not isOpen then
            setGuiOpen(giftingGui, false)
            return
        end

        isOpen = false
        hideOverlayInstant(blurOverlay)
        setGuiOpen(giftingGui, false)
    end

    local function forceCloseForBoss()
        closeGifting()
        hideOverlayInstant(blurOverlay)
    end

    forceCloseForBossImpl = forceCloseForBoss

    setGuiOpen(giftingGui, false)
    hideGiftTemplates(mainFrame)
    refreshGiftNotification({})

    if not openButton:GetAttribute("GiftingOpenBound") then
        openButton:SetAttribute("GiftingOpenBound", true)
        openButton.Activated:Connect(function()
            openGifting()
        end)
    end

    if not closeButton:GetAttribute("GiftingCloseBound") then
        closeButton:SetAttribute("GiftingCloseBound", true)
        closeButton.Activated:Connect(function()
            closeGifting()
        end)
    end

    if giftingUpdateRE then
        giftingUpdateRE.OnClientEvent:Connect(function(rewards)
            renderGifts(rewards)
        end)
    end

    task.spawn(refreshGiftsFromServer)
end

return GiftingController

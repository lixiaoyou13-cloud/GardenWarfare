-- src/client/Services/FreeRewardClientController.luau
local FreeRewardClientController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_WAIT_TIMEOUT = 10
local CLAIM_ATTRIBUTE = "HasClaimedFreeRewardv1"
local JOIN_COMMUNITY_MESSAGE = "Please join the community and like the game."
local CLAIM_SUCCESS_MESSAGE = "Claimed 10000 Sun + 1x Ice Melon-pult!"

local RED_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 95, 95)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 0, 0)),
})

local GREEN_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 127)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 0)),
})

local function waitForRequired(parent, childName)
    if not parent then
        return nil
    end

    local child = parent:WaitForChild(childName, DEFAULT_WAIT_TIMEOUT)
    if not child then
        warn(("[FreeReward] Missing %s under %s"):format(childName, parent:GetFullName()))
    end
    return child
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

local function setButtonEnabled(button, enabled)
    if not button then
        return
    end

    button.Active = enabled
    button.AutoButtonColor = enabled
    pcall(function()
        button.Interactable = enabled
    end)
end

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

local function setRootVisible(root, isVisible)
    if root and root:IsA("GuiObject") then
        root.Visible = isVisible
    end
end

local function getGradient(root)
    if not root then
        return nil
    end

    local namedGradient = root:FindFirstChild("UIGradient")
    if namedGradient and namedGradient:IsA("UIGradient") then
        return namedGradient
    end

    return root:FindFirstChildWhichIsA("UIGradient", true)
end

function FreeRewardClientController.Init()
    local player = Players.LocalPlayer
    local playerGui = waitForRequired(player, "PlayerGui")
    local basicGui = waitForRequired(playerGui, "BasicGui")
    local playProperty = waitForRequired(basicGui, "PlayProperty")
    local freeRoot = waitForRequired(playProperty, "Free")
    local groupGui = waitForRequired(basicGui, "GroupGui")
    local group = waitForRequired(groupGui, "Group")
    local top = groupGui and groupGui:FindFirstChild("Top") or nil
    if not top then
        top = waitForRequired(group, "Top")
    end
    local closeRoot = waitForRequired(top, "Close")
    local redeemRoot = waitForRequired(group, "Redeem")
    local claimRE = waitForRequired(ReplicatedStorage, "ClaimFreeRewardRE")

    if not (playerGui and basicGui and playProperty and freeRoot and groupGui and top and closeRoot and group and redeemRoot and claimRE) then
        return
    end

    local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
    local freeButton = findButton(freeRoot)
    local closeButton = findButton(closeRoot)
    local redeemButton = findButton(redeemRoot)
    local redeemGradient = getGradient(redeemRoot)

    if not freeButton then
        warn("[FreeReward] PlayProperty.Free does not contain a GuiButton.")
        return
    end

    if not closeButton then
        warn("[FreeReward] GroupGui.Top.Close does not contain a GuiButton.")
        return
    end

    if not redeemButton then
        warn("[FreeReward] GroupGui.Group.Redeem does not contain a GuiButton.")
        return
    end

    if not redeemGradient then
        warn("[FreeReward] GroupGui.Group.Redeem.UIGradient was not found.")
    end

    local claiming = false
    local gradientPulseId = 0

    local function setFreeEntryAvailable(isAvailable)
        setRootVisible(freeRoot, isAvailable)
        setButtonEnabled(freeButton, isAvailable)
    end

    local function closeGroupGui()
        setGuiOpen(groupGui, false)
    end

    local function openGroupGui()
        if player:GetAttribute(CLAIM_ATTRIBUTE) == true then
            setFreeEntryAvailable(false)
            closeGroupGui()
            return
        end

        if basicGui:IsA("ScreenGui") then
            basicGui.Enabled = true
        end
        setGuiOpen(groupGui, true)
    end

    local function updateClaimedState()
        local hasClaimed = player:GetAttribute(CLAIM_ATTRIBUTE)
        if hasClaimed == true then
            setFreeEntryAvailable(false)
            closeGroupGui()
        elseif hasClaimed == false then
            setFreeEntryAvailable(true)
        else
            setFreeEntryAvailable(false)
        end
    end

    local function pulseRedeemFailure()
        if not redeemGradient then
            return
        end

        gradientPulseId += 1
        local myPulseId = gradientPulseId
        redeemGradient.Color = RED_GRADIENT

        task.delay(0.45, function()
            if myPulseId == gradientPulseId and redeemGradient.Parent then
                redeemGradient.Color = GREEN_GRADIENT
            end
        end)
    end

    closeGroupGui()
    updateClaimedState()

    player:GetAttributeChangedSignal(CLAIM_ATTRIBUTE):Connect(updateClaimedState)

    freeButton.Activated:Connect(openGroupGui)

    closeButton.Activated:Connect(function()
        closeGroupGui()
    end)

    redeemButton.Activated:Connect(function()
        if claiming then
            return
        end

        if player:GetAttribute(CLAIM_ATTRIBUTE) == true then
            updateClaimedState()
            return
        end

        claiming = true
        setButtonEnabled(redeemButton, false)
        claimRE:FireServer()
    end)

    claimRE.OnClientEvent:Connect(function(success, message, code)
        claiming = false
        setButtonEnabled(redeemButton, true)

        if success then
            player:SetAttribute(CLAIM_ATTRIBUTE, true)
            UIEffectUtil.ShowTip(message or CLAIM_SUCCESS_MESSAGE)
            updateClaimedState()
            return
        end

        if code == "AlreadyClaimed" then
            player:SetAttribute(CLAIM_ATTRIBUTE, true)
            updateClaimedState()
            return
        end

        if code == "NotInGroup" then
            pulseRedeemFailure()
            UIEffectUtil.ShowTip(message or JOIN_COMMUNITY_MESSAGE)
            return
        end

        UIEffectUtil.ShowTip(message or "Unable to claim. Please try again.")
    end)
end

return FreeRewardClientController

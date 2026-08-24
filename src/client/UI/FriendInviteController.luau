local FriendInviteController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local WAIT_TIMEOUT = 10
local DEFAULT_BOOST_TEXT = "Friend Sun Boost: +0%"

local function warnMissing(path)
    warn("[FriendInviteController] Missing UI path: " .. path)
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

local function findTextTarget(root)
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

local function getBoostPercent(stateOrPercent)
    local percent = 0
    if type(stateOrPercent) == "table" then
        percent = tonumber(stateOrPercent.Percent) or tonumber(stateOrPercent.BoostPercent) or 0
    else
        percent = tonumber(stateOrPercent) or 0
    end

    return math.clamp(math.floor(percent + 0.5), 0, 30)
end

local function getBoostText(percent)
    return "Friend Sun Boost: +" .. tostring(getBoostPercent(percent)) .. "%"
end

local function showTip(message)
    if UIEffectUtil and UIEffectUtil.ShowTip then
        UIEffectUtil.ShowTip(message)
    end
end

function FriendInviteController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
    if not playerGui then
        warnMissing("PlayerGui")
        return
    end

    local basicGui = playerGui:WaitForChild("BasicGui", WAIT_TIMEOUT)
    if not basicGui then
        warnMissing("PlayerGui/BasicGui")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", WAIT_TIMEOUT)
    if not playProperty then
        warnMissing("PlayerGui/BasicGui/PlayProperty")
        return
    end

    local coinLabel = playProperty:FindFirstChild("CoinLabel")
    local currentBoostRoot = coinLabel and coinLabel:FindFirstChild("CurrentBoost")
    local currentBoostText = findTextTarget(currentBoostRoot)
    if currentBoostRoot and currentBoostRoot:IsA("GuiObject") then
        currentBoostRoot.Visible = true
    end
    if currentBoostText then
        currentBoostText.Text = DEFAULT_BOOST_TEXT
    else
        warnMissing("PlayerGui/BasicGui/PlayProperty/CoinLabel/CurrentBoost")
    end

    local function setBoostText(stateOrPercent)
        if currentBoostText then
            currentBoostText.Text = getBoostText(getBoostPercent(stateOrPercent))
        end
    end

    task.spawn(function()
        local stateRF = ReplicatedStorage:WaitForChild("GetFriendSunBoostRF", WAIT_TIMEOUT)
        if not stateRF then
            warn("[FriendInviteController] GetFriendSunBoostRF was not found.")
            return
        end

        local success, state = pcall(function()
            return stateRF:InvokeServer()
        end)
        if success then
            setBoostText(state)
        else
            warn("[FriendInviteController] Failed to fetch friend sun boost: " .. tostring(state))
        end
    end)

    local updateRE = ReplicatedStorage:WaitForChild("FriendSunBoostUpdatedRE", WAIT_TIMEOUT)
    if updateRE then
        updateRE.OnClientEvent:Connect(setBoostText)
    else
        warn("[FriendInviteController] FriendSunBoostUpdatedRE was not found.")
    end

    local inviteRoot = playProperty:FindFirstChild("Invite")
    local inviteButton = findButton(inviteRoot)
    if not inviteButton then
        warnMissing("PlayerGui/BasicGui/PlayProperty/Invite")
        return
    end

    local isPrompting = false
    inviteButton.Activated:Connect(function()
        if isPrompting then
            return
        end
        isPrompting = true

        local canSend = false
        local canSendSuccess, canSendResult = pcall(function()
            return SocialService:CanSendGameInviteAsync(player)
        end)
        if canSendSuccess then
            canSend = canSendResult == true
        else
            warn("[FriendInviteController] CanSendGameInviteAsync failed: " .. tostring(canSendResult))
        end

        if canSend then
            local promptSuccess, promptError = pcall(function()
                SocialService:PromptGameInvite(player)
            end)
            if not promptSuccess then
                warn("[FriendInviteController] PromptGameInvite failed: " .. tostring(promptError))
                showTip("Friend invites are not available right now.")
            end
        else
            showTip("Friend invites are not available right now.")
        end

        isPrompting = false
    end)
end

return FriendInviteController

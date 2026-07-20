local LeaderboardRewardController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LeaderboardRewardConfig"))

local WAIT_TIMEOUT = 10

local player = Players.LocalPlayer
local screenGui = nil
local uiReady = false

--[[ 输出缺失 UI 节点提示。 ]]
local function warnMissing(path)
    warn("[LeaderboardRewardController] Missing UI object: " .. tostring(path))
end

--[[ 设置页面开关状态。 ]]
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

--[[ 按固定路径查找 UI 节点。 ]]
local function findPath(root, path)
    local current = root
    for _, childName in ipairs(path) do
        current = current and current:FindFirstChild(childName)
        if not current then
            return nil
        end
    end

    return current
end

--[[ 查找按钮本体，兼容按钮外层套 Frame 的情况。 ]]
local function findButton(root)
    if not root then
        return nil
    end

    if root:IsA("GuiButton") then
        return root
    end

    return root:FindFirstChildWhichIsA("GuiButton", true)
end

--[[ 绑定关闭按钮。 ]]
local function bindCloseButton()
    local contentName = tostring(LeaderboardRewardConfig.ContentFrameName or "Store")
    local closeRoot = findPath(screenGui, { contentName, "Banner", "Close" })
        or screenGui:FindFirstChild("Close", true)
    local closeButton = findButton(closeRoot)

    if not closeButton then
        warnMissing(tostring(LeaderboardRewardConfig.UiName or "RankingRewards") .. "." .. contentName .. ".Banner.Close")
        return
    end

    if closeButton:GetAttribute("RankingRewardsCloseBound") then
        return
    end

    closeButton:SetAttribute("RankingRewardsCloseBound", true)
    closeButton.Activated:Connect(function()
        setGuiOpen(screenGui, false)
    end)
end

function LeaderboardRewardController.Open()
    if not uiReady then
        warn("[LeaderboardRewardController] RankingRewards UI is not ready.")
        return
    end

    setGuiOpen(screenGui, true)
end

--[[ 绑定 Studio 中制作好的展示页。 ]]
local function bindUi()
    local playerGui = player:WaitForChild("PlayerGui", 30)
    if not playerGui then
        warnMissing("PlayerGui")
        return false
    end

    local basicGui = playerGui:FindFirstChild("BasicGui") or playerGui:WaitForChild("BasicGui", WAIT_TIMEOUT)
    if not basicGui then
        warnMissing("PlayerGui.BasicGui")
        return false
    end

    local uiName = tostring(LeaderboardRewardConfig.UiName or "RankingRewards")
    screenGui = basicGui:FindFirstChild(uiName) or basicGui:WaitForChild(uiName, WAIT_TIMEOUT)
    if not screenGui then
        warnMissing("BasicGui." .. uiName)
        return false
    end

    bindCloseButton()
    setGuiOpen(screenGui, false)
    return true
end

function LeaderboardRewardController.Init()
    local remoteNames = LeaderboardRewardConfig.RemoteNames or {}
    local openRemote = ReplicatedStorage:WaitForChild(remoteNames.Open or "OpenLeaderboardRewardRE", WAIT_TIMEOUT)
    if not (openRemote and openRemote:IsA("RemoteEvent")) then
        warn("[LeaderboardRewardController] Open remote is not ready.")
        return
    end

    uiReady = bindUi()
    if not uiReady then
        return
    end

    openRemote.OnClientEvent:Connect(function()
        LeaderboardRewardController.Open()
    end)

    print("Client: LeaderboardRewardController active.")
end

return LeaderboardRewardController

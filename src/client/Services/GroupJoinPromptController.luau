-- src/client/Services/GroupJoinPromptController.luau
-- 进入游戏一段时间后，使用 Roblox 官方原生群组加入弹窗提示未入群玩家

local GroupJoinPromptController = {}

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local GROUP_ID = 229662289
local PROMPT_DELAY_SECONDS = 60

local hasStarted = false

local function setPromptResult(player, statusName, isJoined, wasPrompted)
    player:SetAttribute("GroupJoinPromptStatus", statusName)
    player:SetAttribute("GroupJoinPromptJoined", isJoined)
    player:SetAttribute("GroupJoinPromptShown", wasPrompted)
end

local function isPlayerInGroup(player)
    local success, inGroup = pcall(function()
        return player:IsInGroup(GROUP_ID)
    end)

    return success and inGroup == true
end

local function promptJoinGroup(player)
    if isPlayerInGroup(player) then
        setPromptResult(player, "AlreadyInGroup", true, false)
        return
    end

    local success, membershipStatus = pcall(function()
        return GroupService:PromptJoinAsync(GROUP_ID)
    end)

    if not success then
        warn("[GroupJoinPrompt] PromptJoinAsync failed: " .. tostring(membershipStatus))
        setPromptResult(player, "PromptFailed", false, false)
        return
    end

    local statusName = membershipStatus and membershipStatus.Name or "Unknown"
    local joined = statusName == "Joined" or statusName == "AlreadyMember" or isPlayerInGroup(player)
    setPromptResult(player, statusName, joined, true)
end

function GroupJoinPromptController.Init()
    if hasStarted then
        return
    end
    hasStarted = true

    local player = Players.LocalPlayer

    task.delay(PROMPT_DELAY_SECONDS, function()
        if not player or player.Parent ~= Players then
            return
        end

        promptJoinGroup(player)
    end)
end

return GroupJoinPromptController
-- src/server/Services/ChatGiftService.luau
local ChatGiftService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local COMMAND = "/gift"
local CLAIM_FLAG = "ChatGiftClaimed_V1"
local REWARD_PLANT_ID = "IceMelonpult"
local REWARD_PLANT_AMOUNT = 1
local REWARD_SUN = 200000

local claimingPlayers = {}

local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
if not showTipRE then
    showTipRE = Instance.new("RemoteEvent")
    showTipRE.Name = "ShowTipRE"
    showTipRE.Parent = ReplicatedStorage
end

local function normalizeCommand(message)
    if type(message) ~= "string" then
        return ""
    end

    local trimmed = string.gsub(message, "^%s*(.-)%s*$", "%1")
    return string.lower(trimmed)
end

local function sendTip(player, message)
    if showTipRE then
        showTipRE:FireClient(player, message)
    end
end

local function claimGift(player)
    if claimingPlayers[player] then
        return
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        sendTip(player, "Gift failed: data is still loading.")
        claimingPlayers[player] = nil
        return
    end

    local success, message = PlayerDataManager.GrantSavedChatGift(
        player,
        CLAIM_FLAG,
        REWARD_PLANT_ID,
        REWARD_PLANT_AMOUNT,
        1,
        REWARD_SUN
    )

    if not success then
        sendTip(player, message or "Gift failed: please try again later.")
        claimingPlayers[player] = nil
        return
    end

    sendTip(player, "Gift claimed: 1x Ice Melon-pult + 200000 Sun!")
    claimingPlayers[player] = nil
end

local function bindPlayer(player)
    player.Chatted:Connect(function(message)
        if normalizeCommand(message) == COMMAND then
            claimGift(player)
        end
    end)
end

function ChatGiftService.Init()
    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayer(player)
    end

    Players.PlayerAdded:Connect(bindPlayer)
    Players.PlayerRemoving:Connect(function(player)
        claimingPlayers[player] = nil
    end)
end

return ChatGiftService

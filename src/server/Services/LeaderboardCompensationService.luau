local LeaderboardCompensationService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local CLAIM_FLAG = "Leaderboard140Compensation_V1"
local REWARD_PLANT_ID = "IceMelonpult"
local REWARD_AMOUNT = 1
local REWARD_MUTATION = 1
local POPUP_MESSAGE = "Because a level selection exploit affected the leaderboard, we had to clear leaderboard records above Level 140.\n\nAs an apology, we are compensating you with 1 Ice Melon-pult.\n\nClick any button to claim it."

local claimingPlayers = {}

local showPopupRE = ReplicatedStorage:FindFirstChild("ShowLeaderboardCompensationPopupRE")
if not showPopupRE then
    showPopupRE = Instance.new("RemoteEvent")
    showPopupRE.Name = "ShowLeaderboardCompensationPopupRE"
    showPopupRE.Parent = ReplicatedStorage
end

local claimRF = ReplicatedStorage:FindFirstChild("ClaimLeaderboardCompensationRF")
if not claimRF then
    claimRF = Instance.new("RemoteFunction")
    claimRF.Name = "ClaimLeaderboardCompensationRF"
    claimRF.Parent = ReplicatedStorage
end

local function showIfUnclaimed(player)
    local data = PlayerDataManager.WaitForPlayerData(player, 20)
    if not player.Parent or not data then
        return
    end

    if data[CLAIM_FLAG] then
        return
    end

    showPopupRE:FireClient(player, POPUP_MESSAGE)
end

local function claim(player)
    if claimingPlayers[player] then
        return false, "Claim is already being processed."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Data is still loading. Please try again later."
    end

    if data[CLAIM_FLAG] then
        claimingPlayers[player] = nil
        return false, "You have already claimed this compensation."
    end

    local success, message = PlayerDataManager.GrantSavedChatGift(
        player,
        CLAIM_FLAG,
        REWARD_PLANT_ID,
        REWARD_AMOUNT,
        REWARD_MUTATION,
        0
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Claim failed. Please try again later."
    end

    return true, "Compensation claimed: 1x Ice Melon-pult."
end

function LeaderboardCompensationService.Init()
    claimRF.OnServerInvoke = claim

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(showIfUnclaimed, player)
    end

    Players.PlayerAdded:Connect(function(player)
        task.spawn(showIfUnclaimed, player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        claimingPlayers[player] = nil
    end)

    print("Server: LeaderboardCompensationService active.")
end

return LeaderboardCompensationService

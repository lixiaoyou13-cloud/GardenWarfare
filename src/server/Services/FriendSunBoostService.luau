local FriendSunBoostService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UPDATE_REMOTE_NAME = "FriendSunBoostUpdatedRE"
local STATE_REMOTE_NAME = "GetFriendSunBoostRF"
local BOOST_PER_FRIEND_PERCENT = 5
local MAX_BOOST_FRIENDS = 6

local initialized = false
local boostStateByUserId = {}
local recalculateGeneration = 0

local function getOrCreateRemoteEvent(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function getOrCreateRemoteFunction(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function buildState(friendCount)
    friendCount = math.clamp(math.floor(tonumber(friendCount) or 0), 0, MAX_BOOST_FRIENDS)

    return {
        FriendCount = friendCount,
        Percent = friendCount * BOOST_PER_FRIEND_PERCENT,
    }
end

local function getStoredState(player)
    if not player then
        return buildState(0)
    end

    return boostStateByUserId[player.UserId] or buildState(0)
end

local function fireBoostState(player)
    if player and player.Parent == Players then
        getOrCreateRemoteEvent(UPDATE_REMOTE_NAME):FireClient(player, getStoredState(player))
    end
end

local function areFriends(player, otherPlayer)
    if not (player and otherPlayer) then
        return false
    end

    local success, result = pcall(function()
        return player:IsFriendsWithAsync(otherPlayer.UserId)
    end)

    if not success then
        success, result = pcall(function()
            return player:IsFriendsWith(otherPlayer.UserId)
        end)
    end

    if not success then
        warn("[FriendSunBoostService] Failed to check friendship between " .. player.Name .. " and " .. otherPlayer.Name .. ": " .. tostring(result))
        return false
    end

    return result == true
end

local function calculateStateForPlayer(player, playerList, generation)
    if not player or player.Parent ~= Players then
        return buildState(0)
    end

    local friendCount = 0
    for _, otherPlayer in ipairs(playerList) do
        if otherPlayer ~= player and otherPlayer.Parent == Players and areFriends(player, otherPlayer) then
            friendCount += 1
            if friendCount >= MAX_BOOST_FRIENDS then
                break
            end
        end
    end

    local state = buildState(friendCount)
    if generation and generation ~= recalculateGeneration then
        return getStoredState(player)
    end

    boostStateByUserId[player.UserId] = state
    fireBoostState(player)

    return state
end

function FriendSunBoostService.GetBoostPercent(player)
    return getStoredState(player).Percent or 0
end

function FriendSunBoostService.GetFriendCount(player)
    return getStoredState(player).FriendCount or 0
end

function FriendSunBoostService.ApplyBoost(player, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return 0, 0
    end

    local boostPercent = FriendSunBoostService.GetBoostPercent(player)
    if boostPercent <= 0 then
        return amount, boostPercent
    end

    local boostedAmount = math.floor(amount * (1 + boostPercent / 100) + 0.5)
    return math.max(amount, boostedAmount), boostPercent
end

function FriendSunBoostService.RecalculateAll()
    recalculateGeneration += 1
    local generation = recalculateGeneration

    task.spawn(function()
        local playerList = Players:GetPlayers()
        for _, player in ipairs(playerList) do
            if generation ~= recalculateGeneration then
                return
            end
            calculateStateForPlayer(player, playerList, generation)
        end
    end)
end

function FriendSunBoostService.Init()
    if initialized then
        return
    end
    initialized = true

    getOrCreateRemoteEvent(UPDATE_REMOTE_NAME)
    getOrCreateRemoteFunction(STATE_REMOTE_NAME).OnServerInvoke = function(player)
        return calculateStateForPlayer(player, Players:GetPlayers())
    end

    Players.PlayerAdded:Connect(function(player)
        boostStateByUserId[player.UserId] = buildState(0)
        fireBoostState(player)
        FriendSunBoostService.RecalculateAll()
    end)

    Players.PlayerRemoving:Connect(function(player)
        boostStateByUserId[player.UserId] = nil
        task.defer(FriendSunBoostService.RecalculateAll)
    end)

    FriendSunBoostService.RecalculateAll()
end

return FriendSunBoostService

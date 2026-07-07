-- src/server/Services/FreeRewardService.lua
local FreeRewardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REWARD_PLANT = "IceMelonpult"
local REWARD_AMOUNT = 1
local REWARD_MUTATION = 1
local REWARD_SUN = 10000
local GROUP_ID = 229662289
local CLAIM_DATA_KEY = "FreeRewardClaimedv1"
local CLAIM_ATTRIBUTE = "HasClaimedFreeRewardv1"

local JOIN_COMMUNITY_MESSAGE = "Please join the community and like the game."
local CLAIM_SUCCESS_MESSAGE = "Claimed 10000 Sun + 1x Ice Melon-pult!"

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

local function normalizeMutationLevel(mutationLevel)
    return math.max(1, math.floor(tonumber(mutationLevel) or 1))
end

local function isMutationUnlocked(data, plantId, mutationLevel)
    if type(data) ~= "table" or type(data.UnlockedMutations) ~= "table" then
        return false
    end

    local mutationMap = data.UnlockedMutations[plantId]
    if type(mutationMap) ~= "table" then
        return false
    end

    local level = normalizeMutationLevel(mutationLevel)
    return mutationMap[level] == true or mutationMap[tostring(level)] == true
end

local function snapshotFreeRewardState(data)
    return {
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        TotalSun = data.TotalSun,
        UnlockedMutations = cloneValue(data.UnlockedMutations),
        FreeRewardClaimedv1 = data[CLAIM_DATA_KEY],
    }
end

local function restoreFreeRewardState(data, snapshot)
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.TotalSun = snapshot.TotalSun
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
    data[CLAIM_DATA_KEY] = snapshot.FreeRewardClaimedv1
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE:FireClient(player, data)
    end
end

local function playUnlockEffect(player, plantId, mutationLevel)
    local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
    if playUnlockAnimRE then
        playUnlockAnimRE:FireClient(player, plantId, mutationLevel)
    end
end

local function getClaimRemote()
    local claimRE = ReplicatedStorage:FindFirstChild("ClaimFreeRewardRE")
    if claimRE then
        if not claimRE:IsA("RemoteEvent") then
            warn("[FreeRewardService] ClaimFreeRewardRE exists but is not a RemoteEvent.")
            return nil
        end
        return claimRE
    end

    claimRE = Instance.new("RemoteEvent")
    claimRE.Name = "ClaimFreeRewardRE"
    claimRE.Parent = ReplicatedStorage
    return claimRE
end

local function syncClaimAttribute(PDManager, player)
    local data = PDManager.GetPlayerData(player)
    if data then
        player:SetAttribute(CLAIM_ATTRIBUTE, data[CLAIM_DATA_KEY] == true)
    end
    return data
end

function FreeRewardService.Init()
    local claimRE = getClaimRemote()
    if not claimRE then
        return
    end

    local PDManager = require(script.Parent.Parent.PlayerDataManager)

    local function bindPlayer(player)
        task.spawn(function()
            local data = syncClaimAttribute(PDManager, player)
            while player.Parent and not data do
                task.wait(0.5)
                data = syncClaimAttribute(PDManager, player)
            end
        end)
    end

    Players.PlayerAdded:Connect(bindPlayer)
    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayer(player)
    end

    claimRE.OnServerEvent:Connect(function(player)
        local data = PDManager.GetPlayerData(player)
        if not data then
            claimRE:FireClient(player, false, "Data is still loading. Please try again.", "DataLoading")
            return
        end

        if not PDManager.IsDataSafeToSave(player) then
            claimRE:FireClient(player, false, "Data is still saving. Please try again later.", "DataSaving")
            return
        end

        if data[CLAIM_DATA_KEY] then
            player:SetAttribute(CLAIM_ATTRIBUTE, true)
            claimRE:FireClient(player, false, "Already claimed.", "AlreadyClaimed")
            return
        end

        local groupCheckOk, inGroup = pcall(function()
            return player:IsInGroup(GROUP_ID)
        end)

        if not groupCheckOk then
            warn("[FreeRewardService] Failed to check group membership for " .. player.Name .. ": " .. tostring(inGroup))
            claimRE:FireClient(player, false, "Unable to verify community membership. Please try again.", "GroupCheckFailed")
            return
        end

        if not inGroup then
            claimRE:FireClient(player, false, JOIN_COMMUNITY_MESSAGE, "NotInGroup")
            return
        end

        local snapshot = snapshotFreeRewardState(data)
        local wasFirstUnlock = not isMutationUnlocked(data, REWARD_PLANT, REWARD_MUTATION)

        PDManager.AddTotalSun(player, REWARD_SUN)
        PDManager.GivePlant(player, REWARD_PLANT, REWARD_AMOUNT, REWARD_MUTATION, true)

        data[CLAIM_DATA_KEY] = true
        player:SetAttribute(CLAIM_ATTRIBUTE, true)

        local saved, saveErr = PDManager.ForceSave(player)
        if not saved then
            warn("[FreeRewardService] Save failed after free reward claim for " .. player.Name .. ": " .. tostring(saveErr))
            restoreFreeRewardState(data, snapshot)
            player:SetAttribute(CLAIM_ATTRIBUTE, data[CLAIM_DATA_KEY] == true)
            fireInventoryUpdate(player, data)

            local rollbackSaved, rollbackErr = PDManager.ForceSave(player)
            if not rollbackSaved and rollbackErr ~= "stale_session" then
                warn("[FreeRewardService] Rollback save failed for " .. player.Name .. ": " .. tostring(rollbackErr))
            end

            claimRE:FireClient(player, false, "Claim failed to save. Please try again.", "SaveFailed")
            return
        end

        fireInventoryUpdate(player, data)
        if wasFirstUnlock then
            playUnlockEffect(player, REWARD_PLANT, REWARD_MUTATION)
        end

        claimRE:FireClient(player, true, CLAIM_SUCCESS_MESSAGE, "Claimed")
    end)
end

return FreeRewardService

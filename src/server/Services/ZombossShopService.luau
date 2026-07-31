local ZombossShopService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local ZombossShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZombossShopConfig"))

local purchaseLocks = {}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function getOrCreateRemoteFunction(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if remote and not remote:IsA("RemoteFunction") then
        warn("[ZombossShopService] " .. tostring(name) .. " exists but is not a RemoteFunction.")
        return nil
    end

    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function fireShopDataPatch(player, data)
    if player and player.Parent and type(data) == "table" then
        PlayerDataManager.FireDataPatch(player, {
            Tacos = data.Tacos,
            ZombossShop = cloneValue(data.ZombossShop),
        })
    end
end

local function waitForPlayerData(player)
    local deadline = os.clock() + 10
    local data = PlayerDataManager.GetPlayerData(player)

    while player and player.Parent and not data and os.clock() < deadline do
        task.wait(0.1)
        data = PlayerDataManager.GetPlayerData(player)
    end

    return data
end

local function normalizeShopData(player, data)
    local changed = PlayerDataManager.NormalizeZombossShopData(data, os.time())
    if changed then
        fireShopDataPatch(player, data)
        PlayerDataManager.RequestSave(player, "zomboss shop window refresh")
    end

    return changed
end

local function buildStateFromData(data)
    local now = os.time()
    local refreshAt = ZombossShopConfig.GetRefreshAt(now)
    local bossEventEnabled = ZombossShopConfig.IsBossEventEnabled()
    local nextBossSpawnAt = bossEventEnabled and ZombossShopConfig.GetNextBossSpawnAt(now) or nil
    local purchases = type(data) == "table"
        and type(data.ZombossShop) == "table"
        and type(data.ZombossShop.Purchases) == "table"
        and data.ZombossShop.Purchases
        or {}

    local offers = {}
    for _, offerId in ipairs(ZombossShopConfig.OfferOrder or {}) do
        local offer = ZombossShopConfig.GetOffer(offerId)
        if offer then
            local purchased = math.max(0, math.floor(tonumber(purchases[offerId]) or 0))
            offers[offerId] = {
                Id = offer.Id,
                TemplateName = offer.TemplateName,
                Cost = offer.Cost,
                Limit = offer.Limit,
                Purchased = math.clamp(purchased, 0, offer.Limit),
                RewardType = offer.RewardType,
                RewardItemId = offer.RewardItemId,
                RewardAmount = offer.RewardAmount,
                RewardMutation = offer.RewardMutation,
            }
        end
    end

    return {
        ServerNow = now,
        Tacos = type(data) == "table" and math.max(0, math.floor(tonumber(data.Tacos) or 0)) or 0,
        WindowId = ZombossShopConfig.GetCurrentWindowId(now),
        RefreshAt = refreshAt,
        RefreshRemainingSeconds = math.max(0, refreshAt - now),
        BossEventEnabled = bossEventEnabled,
        NextBossSpawnAt = nextBossSpawnAt,
        BossSpawnRemainingSeconds = nextBossSpawnAt and math.max(0, nextBossSpawnAt - now) or nil,
        OfferOrder = cloneValue(ZombossShopConfig.OfferOrder),
        Offers = offers,
    }
end

local function buildState(player)
    local data = waitForPlayerData(player)
    if data then
        normalizeShopData(player, data)
    end

    return buildStateFromData(data)
end

local function snapshotPurchaseState(data)
    return {
        Tacos = data.Tacos,
        ZombossShop = cloneValue(data.ZombossShop),
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function restorePurchaseState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data.Tacos = snapshot.Tacos
    data.ZombossShop = cloneValue(snapshot.ZombossShop)
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function rollbackPurchase(player, data, snapshot, context)
    restorePurchaseState(data, snapshot)
    fireInventoryUpdate(player, data)
    fireShopDataPatch(player, data)

    local rollbackQueued, rollbackErr = PlayerDataManager.RequestSave(player, "zomboss shop rollback")
    if not rollbackQueued and rollbackErr ~= "stale_session" then
        warn("[ZombossShopService] Failed to queue rollback save after " .. tostring(context) .. " for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end
end

local function validateOfferReward(offer)
    local rewardType = tostring(offer.RewardType or "Item")
    if rewardType == "Plant" then
        if ItemConfig.Plants and ItemConfig.Plants[offer.RewardItemId] then
            return true
        end

        return false
    end

    return ItemConfig.Items and ItemConfig.Items[offer.RewardItemId] ~= nil
end

local function grantOfferReward(player, offer)
    local rewardType = tostring(offer.RewardType or "Item")
    local rewardAmount = math.max(1, math.floor(tonumber(offer.RewardAmount) or 1))

    if rewardType == "Plant" then
        local mutationLevel = math.max(1, math.floor(tonumber(offer.RewardMutation) or 1))
        PlayerDataManager.GivePlant(player, offer.RewardItemId, rewardAmount, mutationLevel, false)
        return true
    end

    return PlayerDataManager.GiveItem(player, offer.RewardItemId, rewardAmount, false) == true
end

local function purchaseOffer(player, offerId)
    local normalizedOfferId = tostring(offerId or "")
    local offer = ZombossShopConfig.GetOffer(normalizedOfferId)
    if not offer then
        return false, "Offer is unavailable.", buildState(player)
    end

    local data = waitForPlayerData(player)
    if not data then
        return false, "Data is still loading.", buildStateFromData(nil)
    end

    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Save is unavailable. Please try again.", buildStateFromData(data)
    end

    if not validateOfferReward(offer) then
        return false, "Reward config is unavailable.", buildState(player)
    end

    normalizeShopData(player, data)

    local purchases = data.ZombossShop.Purchases
    local purchased = math.max(0, math.floor(tonumber(purchases[normalizedOfferId]) or 0))
    local limit = math.max(0, math.floor(tonumber(offer.Limit) or 0))
    local cost = math.max(0, math.floor(tonumber(offer.Cost) or 0))

    if purchased >= limit then
        return false, "Sold out.", buildStateFromData(data)
    end

    if (tonumber(data.Tacos) or 0) < cost then
        return false, "Not enough Tacos.", buildStateFromData(data)
    end

    local snapshot = snapshotPurchaseState(data)
    data.Tacos = math.max(0, math.floor(tonumber(data.Tacos) or 0)) - cost
    purchases[normalizedOfferId] = purchased + 1

    local granted = grantOfferReward(player, offer)
    if not granted then
        rollbackPurchase(player, data, snapshot, "zomboss shop grant")
        return false, "Purchase failed. Please try again.", buildStateFromData(data)
    end

    fireShopDataPatch(player, data)
    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, "zomboss shop purchase")
    if not saveQueued and saveErr ~= "stale_session" then
        warn("[ZombossShopService] Failed to queue purchase save for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))
    end

    return true, "Purchased.", buildStateFromData(data)
end

local function safePurchaseOffer(player, offerId)
    local userId = player and player.UserId
    if not userId then
        return false, "Player is unavailable.", buildStateFromData(nil)
    end

    if purchaseLocks[userId] then
        return false, "Purchase is processing.", buildState(player)
    end

    purchaseLocks[userId] = true
    local ok, success, message, state = pcall(function()
        return purchaseOffer(player, offerId)
    end)
    purchaseLocks[userId] = nil

    if not ok then
        warn("[ZombossShopService] Purchase crashed for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(success))
        return false, "Purchase failed. Please try again.", buildState(player)
    end

    return success, message, state
end

function ZombossShopService.Init()
    local remoteNames = ZombossShopConfig.RemoteNames or {}
    local getStateRF = getOrCreateRemoteFunction(remoteNames.GetState or "GetZombossShopStateRF")
    local buyItemRF = getOrCreateRemoteFunction(remoteNames.BuyItem or "BuyZombossShopItemRF")

    if getStateRF then
        getStateRF.OnServerInvoke = function(player)
            return buildState(player)
        end
    end

    if buyItemRF then
        buyItemRF.OnServerInvoke = function(player, offerId)
            return safePurchaseOffer(player, offerId)
        end
    end
end

return ZombossShopService

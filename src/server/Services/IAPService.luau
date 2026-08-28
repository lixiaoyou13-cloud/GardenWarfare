-- src/server/Services/IAPService.luau
local IAPService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local ExclusiveRollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ExclusiveRollConfig"))
local PassRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassRewardConfig"))
local ZombossShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZombossShopConfig"))
local InventoryService = require(script.Parent.InventoryService)

local PRODUCT_SEVEN_DAY = 3582734340 -- 七天签到一键领取的内购 ID
local PRODUCT_RARE_ROLL_TICKET = 3599579545 -- 稀有抽奖次数 ID

local PRODUCT_CHEST_OPEN = 3606175579
local PRODUCT_PASS_EXP = PassRewardConfig.ExpProductId
local PRODUCT_PASS_EXP_AMOUNT = PassRewardConfig.ExpProductAmount or 200
local RETIRED_PRODUCT_IDS = {
    [3594585526] = "newbie gift",
}
local receiptSaveStates = {}
local exclusiveShopFreeRollStates = {}
local exclusiveShopFreeRollLifecycleBound = false

local function GetConfiguredProductId(itemDetail)
    if type(itemDetail.ProductId) == "number" and itemDetail.ProductId > 0 then
        return itemDetail.ProductId
    end
    if type(itemDetail.IAPProductId) == "number" and itemDetail.IAPProductId > 0 then
        return itemDetail.IAPProductId
    end
    return nil
end

local function FindShopRewardByProductId(productId)
    for seedId, seedDetail in pairs(ItemConfig.Seeds or {}) do
        local configProductId = GetConfiguredProductId(seedDetail)
        if configProductId == productId then
            local plantId = seedDetail.YieldPlant or seedId
            local plantDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
            return {
                ItemType = "Plant",
                ItemId = plantId,
                Amount = seedDetail.IAPAmount or seedDetail.Amount or 1,
                Mutation = seedDetail.IAPMutation or seedDetail.Mutation or 1,
                Name = (plantDetail and plantDetail.Name) or plantId,
                Quality = (plantDetail and plantDetail.Quality) or seedDetail.Quality,
            }
        end
    end

    for plantId, plantDetail in pairs(ItemConfig.Plants or {}) do
        local configProductId = GetConfiguredProductId(plantDetail)
        if configProductId == productId then
            return {
                ItemType = "Plant",
                ItemId = plantId,
                Amount = plantDetail.IAPAmount or plantDetail.Amount or 1,
                Mutation = plantDetail.IAPMutation or plantDetail.Mutation or 1,
                Name = plantDetail.Name or plantId,
                Quality = plantDetail.Quality,
            }
        end
    end

    return nil
end

local function GrantShopReward(player, reward)
    if reward.ItemType == "Seed" then
        PlayerDataManager.GiveSeed(player, reward.ItemId, reward.Amount, true)
        return true
    elseif reward.ItemType == "Plant" then
        PlayerDataManager.GivePlant(player, reward.ItemId, reward.Amount, reward.Mutation or 1, true)
        return true
    end

    return false
end

local function FindZombossShopRobuxRewardByProductId(productId)
    for _, offerId in ipairs(ZombossShopConfig.OfferOrder or {}) do
        local offer = ZombossShopConfig.GetOffer(offerId)
        if offer and tonumber(offer.RobuxProductId) == productId then
            local rewardType = tostring(offer.RewardType or "Item")
            local rewardItemId = offer.RewardItemId
            local rewardAmount = math.max(1, math.floor(tonumber(offer.RewardAmount) or 1))
            local rewardMutation = math.max(1, math.floor(tonumber(offer.RewardMutation) or 1))

            if rewardType == "Plant" then
                local plantDetail = ItemConfig.Plants and ItemConfig.Plants[rewardItemId]
                if not plantDetail then
                    return nil
                end

                return {
                    OfferId = offerId,
                    ItemType = "Plant",
                    ItemId = rewardItemId,
                    Amount = rewardAmount,
                    Mutation = rewardMutation,
                    Name = plantDetail.Name or rewardItemId,
                    Quality = plantDetail.Quality,
                }
            end

            local itemDetail = ItemConfig.Items and ItemConfig.Items[rewardItemId]
            if not itemDetail then
                return nil
            end

            return {
                OfferId = offerId,
                ItemType = "Item",
                ItemId = rewardItemId,
                Amount = rewardAmount,
                Name = itemDetail.Name or rewardItemId,
                Quality = itemDetail.Quality,
            }
        end
    end

    return nil
end

local function GrantZombossShopRobuxReward(player, reward)
    if reward.ItemType == "Plant" then
        PlayerDataManager.GivePlant(player, reward.ItemId, reward.Amount, reward.Mutation or 1, true)
        return true
    elseif reward.ItemType == "Item" then
        return PlayerDataManager.GiveItem(player, reward.ItemId, reward.Amount, false) == true
    end

    return false
end

local function sendTip(player, message)
    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE then
        showTipRE:FireClient(player, message)
    end
end

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

local function snapshotExclusiveRollTicketState(data, ticketKey, pityKey)
    if type(data) ~= "table" then
        return nil
    end

    return {
        TicketValue = data[ticketKey],
        PityValue = data[pityKey],
        PurchaseCount = data.ExclusiveRollPurchaseCount,
        TotalRolls = data.ExclusiveRollTotalRolls,
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function restoreExclusiveRollTicketState(data, snapshot, ticketKey, pityKey)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data[ticketKey] = snapshot.TicketValue
    data[pityKey] = snapshot.PityValue
    data.ExclusiveRollPurchaseCount = snapshot.PurchaseCount
    data.ExclusiveRollTotalRolls = snapshot.TotalRolls
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function snapshotExclusiveShopFreeRollState(data, dataKey)
    if type(data) ~= "table" then
        return nil
    end

    local snapshot = {
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
    if dataKey ~= nil then
        snapshot.FreeRollNextAt = data[dataKey]
    end

    return snapshot
end

local function restoreExclusiveShopFreeRollState(data, snapshot, dataKey)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    if dataKey ~= nil then
        data[dataKey] = snapshot.FreeRollNextAt
    end
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function getReceiptKey(receiptInfo)
    local purchaseId = receiptInfo and receiptInfo.PurchaseId
    if type(purchaseId) == "string" and purchaseId ~= "" then
        return purchaseId, true
    end

    return tostring(receiptInfo.PlayerId) .. ":" .. tostring(receiptInfo.ProductId), false
end

local function getReceiptSaveStatus(receiptKey)
    local receiptState = receiptSaveStates[receiptKey]
    if type(receiptState) == "table" then
        return receiptState.Status
    end

    return receiptState
end

local function runReceiptSavedCallback(receiptState)
    local callback = type(receiptState) == "table" and receiptState.OnSaved or nil
    if type(callback) ~= "function" then
        return
    end

    local success, err = pcall(callback)
    if not success then
        warn("[IAPService] Receipt saved callback failed: " .. tostring(err))
    end
end

local function finalizeReceiptSave(player, receiptKey, canPersistReceipt, onSaved)
    if canPersistReceipt then
        PlayerDataManager.MarkReceiptProcessed(player, receiptKey)
    end

    local saved = PlayerDataManager.ForceSave(player)
    if saved then
        local receiptState = receiptSaveStates[receiptKey]
        receiptSaveStates[receiptKey] = "saved"
        runReceiptSavedCallback({ OnSaved = onSaved or (type(receiptState) == "table" and receiptState.OnSaved or nil) })
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    receiptSaveStates[receiptKey] = {
        Status = "granted_pending_save",
        OnSaved = onSaved or (type(receiptSaveStates[receiptKey]) == "table" and receiptSaveStates[receiptKey].OnSaved or nil),
    }
    return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function getOrCreateExclusiveRollResultRE()
    local eventName = ExclusiveRollConfig.ResultEventName or "ExclusiveRollResultRE"
    local resultRE = ReplicatedStorage:FindFirstChild(eventName)
    if not resultRE then
        resultRE = Instance.new("RemoteEvent")
        resultRE.Name = eventName
        resultRE.Parent = ReplicatedStorage
    end

    return resultRE
end

local function getOrCreateExclusiveRollRewardShowRE()
    local eventName = ExclusiveRollConfig.RewardShowEventName or "ExclusiveRollRewardShowRE"
    local rewardShowRE = ReplicatedStorage:FindFirstChild(eventName)
    if not rewardShowRE then
        rewardShowRE = Instance.new("RemoteEvent")
        rewardShowRE.Name = eventName
        rewardShowRE.Parent = ReplicatedStorage
    end

    return rewardShowRE
end

local function getOrCreateExclusiveTicketRollRF()
    local remoteName = ExclusiveRollConfig.TicketRollRemoteName or "UseExclusiveRollTicketRF"
    local remote = ReplicatedStorage:FindFirstChild(remoteName)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = remoteName
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function getOrCreateExclusiveShopFreeRollRF(remoteName)
    remoteName = tostring(remoteName or "UseExclusiveShopFreeRollRF")
    local remote = ReplicatedStorage:FindFirstChild(remoteName)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = remoteName
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function getExclusiveProductRollConfig(productConfig)
    if ExclusiveRollConfig.GetProductRollConfig then
        return ExclusiveRollConfig.GetProductRollConfig(productConfig)
    end

    return ExclusiveRollConfig, "Exclusive"
end

local function getExclusiveRollPityConfig(rollConfig)
    local pity = rollConfig and rollConfig.Pity
    if type(pity) == "table" then
        return pity
    end

    return nil
end

local function getWeightedExclusiveRollPlant(rollConfig)
    local totalWeight = 0
    for _, entry in ipairs((rollConfig and rollConfig.Pool) or {}) do
        totalWeight += math.max(0, tonumber(entry.Weight) or 0)
    end

    if totalWeight <= 0 then
        return nil
    end

    local roll = math.random() * totalWeight
    local runningWeight = 0
    for _, entry in ipairs(rollConfig.Pool or {}) do
        runningWeight += math.max(0, tonumber(entry.Weight) or 0)
        if roll <= runningWeight then
            return entry.PlantId
        end
    end

    local lastEntry = rollConfig.Pool and rollConfig.Pool[#rollConfig.Pool]
    return lastEntry and lastEntry.PlantId or nil
end

local function pickExclusiveRollPlant(data, rollConfig)
    rollConfig = rollConfig or ExclusiveRollConfig
    local pity = getExclusiveRollPityConfig(rollConfig)
    if not pity then
        return getWeightedExclusiveRollPlant(rollConfig), false
    end

    local pityKey = pity.DataKey or "ExclusiveRollPity_Rotobaga"
    local pityTarget = pity.TargetPlantId or "Rotobaga"
    local guaranteeAt = math.max(1, math.floor(tonumber(pity.GuaranteeAt) or 100))
    local currentPity = math.max(0, math.floor(tonumber(data[pityKey]) or 0))
    local plantId = nil
    local isPity = false

    if currentPity >= guaranteeAt - 1 then
        plantId = pityTarget
        isPity = true
    else
        plantId = getWeightedExclusiveRollPlant(rollConfig)
    end

    if plantId == pityTarget and pity.ResetWhenHitTarget ~= false then
        data[pityKey] = 0
    else
        data[pityKey] = currentPity + 1
    end

    return plantId, isPity
end

local function grantExclusiveRollPurchase(player, data, productConfig, productKey)
    local rollCount = math.max(1, math.floor(tonumber(productConfig.RollCount) or 1))
    local rollConfig, rollGroup = getExclusiveProductRollConfig(productConfig)
    local rewardConfig = rollConfig.Reward or ExclusiveRollConfig.Reward or {}
    local rewardAmount = math.max(1, math.floor(tonumber(rewardConfig.Amount) or 1))
    local rewardMutation = math.max(1, math.floor(tonumber(rewardConfig.Mutation) or 1))
    local pityConfig = getExclusiveRollPityConfig(rollConfig)
    local pityKey = pityConfig and (pityConfig.DataKey or "ExclusiveRollPity_Rotobaga") or nil
    local originalPity = pityKey and data[pityKey] or nil
    local results = {}
    local anyHighQuality = false

    for _ = 1, rollCount do
        local plantId, isPity = pickExclusiveRollPlant(data, rollConfig)
        local plantDetail = plantId and ItemConfig.Plants and ItemConfig.Plants[plantId]
        if not plantDetail then
            if pityKey then
                data[pityKey] = originalPity
            end
            warn("[IAPService] Exclusive roll plant config missing: " .. tostring(plantId))
            return nil
        end

        anyHighQuality = anyHighQuality or ((tonumber(plantDetail.Quality) or 0) >= 5)

        table.insert(results, {
            PlantId = plantId,
            Name = plantDetail.Name or plantId,
            Quality = plantDetail.Quality,
            Amount = rewardAmount,
            Mutation = rewardMutation,
            IsPity = isPity == true,
            RollGroup = rollGroup,
        })
    end

    if not Players:GetPlayerByUserId(player.UserId) or PlayerDataManager.GetPlayerData(player) ~= data then
        if pityKey then
            data[pityKey] = originalPity
        end
        return nil
    end

    if productConfig.CountsAsPurchase ~= false then
        data.ExclusiveRollPurchaseCount = math.max(0, math.floor(tonumber(data.ExclusiveRollPurchaseCount) or 0)) + 1
    end
    if productConfig.CountsTotalRolls ~= false then
        data.ExclusiveRollTotalRolls = math.max(0, math.floor(tonumber(data.ExclusiveRollTotalRolls) or 0)) + rollCount
    end

    local rollId = HttpService:GenerateGUID(false)
    for _, result in ipairs(results) do
        PlayerDataManager.GivePlant(player, result.PlantId, result.Amount, result.Mutation, true)
    end

    local payload = {
        RollId = rollId,
        ProductKey = productKey,
        ProductId = productConfig.ProductId,
        RollCount = rollCount,
        RollGroup = rollGroup,
        Results = results,
        Pity = pityKey and (data[pityKey] or 0) or nil,
    }

    return results, payload, anyHighQuality
end

local function notifyExclusiveRollPurchase(player, payload, anyHighQuality)
    if not player or not player.Parent or type(payload) ~= "table" then
        return
    end

    getOrCreateExclusiveRollResultRE():FireClient(player, payload)

    local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
    if not playObtainEffectRE then
        return
    end

    local results = payload.Results or {}
    local message = "Exclusive Roll Complete!\nObtained " .. tostring(#results) .. " plants!"
    if #results == 1 and results[1] then
        message = "Exclusive Roll Complete!\nObtained 1x " .. tostring(results[1].Name) .. "!"
    end

    local animationConfig = ExclusiveRollConfig.Animation or {}
    local preAnimationDelay = math.max(0, tonumber(animationConfig.PreAnimationDelay) or 0)
    local animationDuration = preAnimationDelay + ExclusiveRollConfig.GetAnimationDuration(payload.ProductKey, payload.RollCount)
    task.delay(animationDuration, function()
        if player.Parent then
            playObtainEffectRE:FireClient(player, message, anyHighQuality)
        end
    end)
end

local function getExclusiveRollTicketKey()
    local ticketConfig = ExclusiveRollConfig.TicketRoll or {}
    return ticketConfig.DataKey or "ExclusiveRollTickets"
end

local function getExclusiveRollTicketCount(data)
    local ticketKey = getExclusiveRollTicketKey()
    local ticketCount = math.max(0, math.floor(tonumber(data[ticketKey]) or 0))
    data[ticketKey] = ticketCount
    return ticketCount
end

local function useExclusiveRollTicket(player)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading.", 0
    end

    local ticketConfig = ExclusiveRollConfig.TicketRoll or {}
    local ticketKey = getExclusiveRollTicketKey()
    local ticketCount = getExclusiveRollTicketCount(data)
    if ticketCount <= 0 then
        return false, "No exclusive roll attempts.", 0
    end
    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Data save unavailable. Please try again later.", ticketCount
    end

    local pityKey = (ExclusiveRollConfig.Pity and ExclusiveRollConfig.Pity.DataKey) or "ExclusiveRollPity_Rotobaga"
    local rollbackSnapshot = snapshotExclusiveRollTicketState(data, ticketKey, pityKey)
    data[ticketKey] = ticketCount - 1

    local productConfig = {
        RollCount = math.max(1, math.floor(tonumber(ticketConfig.RollCount) or 1)),
        ProductId = 0,
        CountsAsPurchase = ticketConfig.CountsAsPurchase == true,
    }
    local productKey = ticketConfig.ProductKey or "TicketRoll"
    local results, payload, anyHighQuality = grantExclusiveRollPurchase(player, data, productConfig, productKey)
    if not results then
        data[ticketKey] = ticketCount
        return false, "Exclusive roll failed. Please try again.", ticketCount
    end

    fireInventoryUpdate(player, data)

    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, "exclusive ticket roll")
    if not saveQueued and saveErr ~= "stale_session" then
        warn("[IAPService] Failed to queue save after exclusive ticket roll for " .. player.Name .. ": " .. tostring(saveErr))
    end
    if not saveQueued then
        restoreExclusiveRollTicketState(data, rollbackSnapshot, ticketKey, pityKey)
        fireInventoryUpdate(player, data)

        local rollbackSaved, rollbackErr = PlayerDataManager.RequestSave(player, "exclusive ticket roll rollback")
        if not rollbackSaved and rollbackErr ~= "stale_session" then
            warn("[IAPService] Failed to queue exclusive ticket roll rollback save for " .. player.Name .. ": " .. tostring(rollbackErr))
        end

        return false, "Exclusive roll save unavailable. Please try again.", data[ticketKey]
    end

    notifyExclusiveRollPurchase(player, payload, anyHighQuality)
    return true, "Exclusive roll started.", data[ticketKey], payload
end

local function getExclusiveShopFreeRollCooldown(freeRollConfig)
    return math.max(1, math.floor(tonumber(freeRollConfig and freeRollConfig.CooldownSeconds) or 300))
end

local function getExclusiveShopFreeRollDataKey(freeRollConfig)
    local dataKey = type(freeRollConfig) == "table" and freeRollConfig.DataKey or nil
    if type(dataKey) == "string" and dataKey ~= "" then
        return dataKey
    end

    return nil
end

local function usesExclusiveShopSessionTimer(freeRollConfig)
    return type(freeRollConfig) == "table"
        and (freeRollConfig.UseSessionTimer == true or getExclusiveShopFreeRollDataKey(freeRollConfig) == nil)
end

local function getExclusiveShopFreeRollSessionState(player, rollGroup, freeRollConfig)
    if not player then
        return nil
    end

    local userId = player.UserId
    local statesByGroup = exclusiveShopFreeRollStates[userId]
    if type(statesByGroup) ~= "table" then
        statesByGroup = {}
        exclusiveShopFreeRollStates[userId] = statesByGroup
    end

    local groupKey = (type(rollGroup) == "string" and rollGroup ~= "") and rollGroup or "Exclusive"
    local state = statesByGroup[groupKey]
    local cooldown = getExclusiveShopFreeRollCooldown(freeRollConfig)
    if type(state) ~= "table" then
        state = {
            NextReadyAt = os.time() + cooldown,
            InProgress = false,
        }
        statesByGroup[groupKey] = state
    elseif type(state.NextReadyAt) ~= "number" then
        state.NextReadyAt = os.time() + cooldown
    end

    return state
end

local function initializeExclusiveShopFreeRollSessions(player)
    for rollGroup, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        local freeRollConfig = groupConfig.FreeRoll
        if usesExclusiveShopSessionTimer(freeRollConfig) then
            getExclusiveShopFreeRollSessionState(player, rollGroup, freeRollConfig)
        end
    end
end

local function cleanupExclusiveShopFreeRollSessions(player)
    if player then
        exclusiveShopFreeRollStates[player.UserId] = nil
    end
end

local function getExclusiveShopFreeRollRemaining(player, rollGroup, data, freeRollConfig, now)
    now = math.floor(tonumber(now) or os.time())
    if usesExclusiveShopSessionTimer(freeRollConfig) then
        local state = getExclusiveShopFreeRollSessionState(player, rollGroup, freeRollConfig)
        local nextAt = math.max(0, math.floor(tonumber(state and state.NextReadyAt) or 0))
        return math.max(0, nextAt - now), nextAt
    end

    local dataKey = getExclusiveShopFreeRollDataKey(freeRollConfig)
    if not dataKey then
        return 0, 0
    end

    local nextAt = math.max(0, math.floor(tonumber(data and data[dataKey]) or 0))
    return math.max(0, nextAt - now), nextAt
end

local function getExclusiveShopFreeRollStatus(player, rollGroup, groupConfig)
    local freeRollConfig = groupConfig and groupConfig.FreeRoll
    if type(freeRollConfig) ~= "table" then
        return false, "Free roll is not configured.", 0
    end

    local cooldown = getExclusiveShopFreeRollCooldown(freeRollConfig)
    if usesExclusiveShopSessionTimer(freeRollConfig) then
        local remaining = getExclusiveShopFreeRollRemaining(player, rollGroup, nil, freeRollConfig, os.time())
        return true, remaining, cooldown
    end

    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading.", 0
    end

    local remaining = getExclusiveShopFreeRollRemaining(player, rollGroup, data, freeRollConfig, os.time())
    return true, remaining, cooldown
end

local function useExclusiveShopFreeRoll(player, rollGroup, groupConfig)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Data is still loading.", 0
    end

    local freeRollConfig = groupConfig and groupConfig.FreeRoll
    if type(freeRollConfig) ~= "table" then
        return false, "Free roll is not configured.", 0
    end

    local now = os.time()
    local useSessionTimer = usesExclusiveShopSessionTimer(freeRollConfig)
    local sessionState = nil
    if useSessionTimer then
        sessionState = getExclusiveShopFreeRollSessionState(player, rollGroup, freeRollConfig)
        if sessionState and sessionState.InProgress then
            local busyRemaining = getExclusiveShopFreeRollRemaining(player, rollGroup, data, freeRollConfig, now)
            return false, "Exclusive roll is processing.", busyRemaining
        end
    end

    local remaining = getExclusiveShopFreeRollRemaining(player, rollGroup, data, freeRollConfig, now)
    if remaining > 0 then
        return false, "Free roll is not ready.", remaining
    end
    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Data save unavailable. Please try again later.", 0
    end

    local cooldown = getExclusiveShopFreeRollCooldown(freeRollConfig)
    local dataKey = useSessionTimer and nil or getExclusiveShopFreeRollDataKey(freeRollConfig)
    local rollbackSnapshot = snapshotExclusiveShopFreeRollState(data, dataKey)
    if dataKey then
        data[dataKey] = now + cooldown
    end
    if sessionState then
        sessionState.InProgress = true
    end

    local productConfig = {
        ProductId = 0,
        RollCount = math.max(1, math.floor(tonumber(freeRollConfig.RollCount) or 1)),
        RollGroup = rollGroup,
        CountsAsPurchase = false,
        CountsTotalRolls = false,
    }
    local productKey = freeRollConfig.ProductKey or (tostring(rollGroup) .. "FreeRoll")
    local results, payload, anyHighQuality = grantExclusiveRollPurchase(player, data, productConfig, productKey)
    if not results then
        restoreExclusiveShopFreeRollState(data, rollbackSnapshot, dataKey)
        if sessionState then
            sessionState.InProgress = false
        end
        return false, "Free roll failed. Please try again.", 0
    end

    fireInventoryUpdate(player, data)

    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, "exclusive shop free roll")
    if not saveQueued then
        warn("[IAPService] Failed to queue save after exclusive shop free roll for " .. player.Name .. ": " .. tostring(saveErr))
        restoreExclusiveShopFreeRollState(data, rollbackSnapshot, dataKey)
        fireInventoryUpdate(player, data)

        local rollbackSaved, rollbackErr = PlayerDataManager.RequestSave(player, "exclusive shop free roll rollback")
        if not rollbackSaved and rollbackErr ~= "stale_session" then
            warn("[IAPService] Failed to queue exclusive shop free roll rollback save for " .. player.Name .. ": " .. tostring(rollbackErr))
        end

        if sessionState then
            sessionState.InProgress = false
        end
        return false, "Free roll save unavailable. Please try again.", 0
    end

    if sessionState then
        sessionState.NextReadyAt = os.time() + cooldown
        sessionState.InProgress = false
    end
    notifyExclusiveRollPurchase(player, payload, anyHighQuality)
    return true, "Exclusive roll started.", cooldown, payload
end

function IAPService.Init()
    if not exclusiveShopFreeRollLifecycleBound then
        exclusiveShopFreeRollLifecycleBound = true
        Players.PlayerAdded:Connect(initializeExclusiveShopFreeRollSessions)
        Players.PlayerRemoving:Connect(cleanupExclusiveShopFreeRollSessions)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        initializeExclusiveShopFreeRollSessions(player)
    end

    getOrCreateExclusiveRollResultRE()
    getOrCreateExclusiveRollRewardShowRE()
    getOrCreateExclusiveTicketRollRF().OnServerInvoke = function(player)
        return useExclusiveRollTicket(player)
    end
    for rollGroup, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        local currentRollGroup = rollGroup
        local currentGroupConfig = groupConfig
        local freeRollConfig = groupConfig.FreeRoll
        if type(freeRollConfig) == "table" then
            getOrCreateExclusiveShopFreeRollRF(freeRollConfig.RemoteName).OnServerInvoke = function(player, action)
                if action == "status" then
                    return getExclusiveShopFreeRollStatus(player, currentRollGroup, currentGroupConfig)
                end

                return useExclusiveShopFreeRoll(player, currentRollGroup, currentGroupConfig)
            end
        end
    end

    -- 1. 补偿弹窗事件
    local showPopupRE = ReplicatedStorage:FindFirstChild("ShowCompensationPopupRE")
    if not showPopupRE then
        showPopupRE = Instance.new("RemoteEvent")
        showPopupRE.Name = "ShowCompensationPopupRE"
        showPopupRE.Parent = ReplicatedStorage
    end

    -- 2. ：主动购买意向记录事件（用于区分新老订单）
    local markIntentRE = ReplicatedStorage:FindFirstChild("MarkPurchaseIntentRE")
    if not markIntentRE then
        markIntentRE = Instance.new("RemoteEvent")
        markIntentRE.Name = "MarkPurchaseIntentRE"
        markIntentRE.Parent = ReplicatedStorage
    end

    -- 记录玩家近期是否点击过购买按钮
    local activePurchaseIntents = {}
    markIntentRE.OnServerEvent:Connect(function(player)
        local canPurchase = PlayerDataManager.CanPurchaseSignInClaimAll(player)
        if canPurchase then
            activePurchaseIntents[player.UserId] = os.time()
        end
    end)

    local prepareSignInPurchaseRF = ReplicatedStorage:FindFirstChild("PrepareSignInClaimAllPurchaseRF")
    if not prepareSignInPurchaseRF then
        prepareSignInPurchaseRF = Instance.new("RemoteFunction")
        prepareSignInPurchaseRF.Name = "PrepareSignInClaimAllPurchaseRF"
        prepareSignInPurchaseRF.Parent = ReplicatedStorage
    end

    prepareSignInPurchaseRF.OnServerInvoke = function(player)
        local canPurchase, message = PlayerDataManager.CanPurchaseSignInClaimAll(player)
        if canPurchase then
            activePurchaseIntents[player.UserId] = os.time()
        end

        return canPurchase, message
    end

    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local receiptKey, canPersistReceipt = getReceiptKey(receiptInfo)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local receiptSaveState = getReceiptSaveStatus(receiptKey)
        if receiptSaveState == "saved" then
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end
        if receiptSaveState == "granted_pending_save" then
            return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
        end
        if canPersistReceipt and PlayerDataManager.HasProcessedReceipt(player, receiptKey) then
            receiptSaveStates[receiptKey] = "saved"
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        local retiredProductName = RETIRED_PRODUCT_IDS[receiptInfo.ProductId]
        if retiredProductName then
            warn("[IAPService] Retired product receipt ignored: " .. tostring(retiredProductName))
            return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
        end

        if receiptInfo.ProductId == PRODUCT_CHEST_OPEN then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local success, result, status = InventoryService.CompletePreparedChestIAPPurchase(player)
            if not success then
                if status == "Retry" then
                    return Enum.ProductPurchaseDecision.NotProcessedYet
                end

                local chestIAPOpenResultRE = ReplicatedStorage:FindFirstChild("ChestIAPOpenResultRE")
                if chestIAPOpenResultRE then
                    chestIAPOpenResultRE:FireClient(player, false, result or "Chest opening failed.")
                end
                return Enum.ProductPurchaseDecision.PurchaseGranted
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                local chestIAPOpenResultRE = ReplicatedStorage:FindFirstChild("ChestIAPOpenResultRE")
                if chestIAPOpenResultRE then
                    chestIAPOpenResultRE:FireClient(player, true, result)
                end
            end)
        end

        -- 2 判定是否购买了七天签到一键领取
        if receiptInfo.ProductId == PRODUCT_SEVEN_DAY then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local intentTime = activePurchaseIntents[player.UserId] or 0
            local isNewPurchase = (os.time() - intentTime) < 300

            if isNewPurchase then
                local canPurchase, message = PlayerDataManager.CanPurchaseSignInClaimAll(player)
                if not canPurchase then
                    return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                        activePurchaseIntents[player.UserId] = nil
                        sendTip(player, message or "You can purchase all sign-in rewards once per day.")
                    end)
                end
            end

            local claimOk = PlayerDataManager.ClaimRemainingSignInTier(player, {
                SkipImmediateSave = true,
                SuppressInventoryUpdate = true,
            })
            if claimOk then
                if isNewPurchase then
                    PlayerDataManager.MarkSignInClaimAllPurchased(player, os.time(), {
                        SkipImmediateSave = true,
                    })
                end

                -- 无论新老订单，基础的 1-7 天奖励必须发
                if not isNewPurchase then
                    -- 情况 A：历史老订单(系统上线自转动触发，玩家没点击按钮)
                    PlayerDataManager.GivePlant(player, "CobCannon", 1, 1, true)

                    -- 情况 B：今天的新订单(玩家刚刚自己点击了购买按钮)

                    -- 清晰除意向，防止重复判定
                end
            end

            if claimOk then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                    fireInventoryUpdate(player, PlayerDataManager.GetPlayerData(player) or data)

                    if not isNewPurchase then
                        local popupRE = ReplicatedStorage:FindFirstChild("ShowCompensationPopupRE")
                        if popupRE then
                            popupRE:FireClient(player, "A bug occurred with the 7-Day Sign-In rewards.\nPlease accept this Cob Cannon as compensation.\nWe sincerely apologize for the inconvenience!")
                        end
                        print("[System] Player " .. player.Name .. " historical seven-day sign-in order reissued; CobCannon compensation granted.")
                    else
                        local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                        if playObtainEffectRE then
                            playObtainEffectRE:FireClient(player, "7-Day Rewards Unlocked!\nAll items sent to inventory.")
                        end
                        print("[System] Player " .. player.Name .. " purchased seven-day sign-in normally; no extra compensation.")

                        activePurchaseIntents[player.UserId] = nil
                    end
                end)
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
        end

        local exclusiveProduct, exclusiveProductKey = ExclusiveRollConfig.GetProductById(receiptInfo.ProductId)
        if exclusiveProduct then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local results, payload, anyHighQuality = grantExclusiveRollPurchase(player, data, exclusiveProduct, exclusiveProductKey)
            if not results then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                notifyExclusiveRollPurchase(player, payload, anyHighQuality)
            end)
        end

        -- 3 稀有抽奖次数 Developer Product
        if receiptInfo.ProductId == PRODUCT_RARE_ROLL_TICKET then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            if type(data.RollTickets) ~= "table" then
                data.RollTickets = {0, 0}
            end
            data.RollTickets[2] = (tonumber(data.RollTickets[2]) or 0) + 1
            data.RollTickets["2"] = nil

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                fireInventoryUpdate(player, PlayerDataManager.GetPlayerData(player) or data)

                local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                if playObtainEffectRE then
                    playObtainEffectRE:FireClient(player, "Purchase Successful!\nObtained 1x Rare Pull!")
                end
            end)
        end

        -- 4 商店植物/种子 Developer Product 购买
        if receiptInfo.ProductId == PRODUCT_PASS_EXP then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local passData = PlayerDataManager.AddPassExp(player, PRODUCT_PASS_EXP_AMOUNT)
            if not passData then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                sendTip(player, "Pass EXP +" .. tostring(PRODUCT_PASS_EXP_AMOUNT))
            end)
        end

        local zombossShopRobuxReward = FindZombossShopRobuxRewardByProductId(receiptInfo.ProductId)
        if zombossShopRobuxReward then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local granted = GrantZombossShopRobuxReward(player, zombossShopRobuxReward)
            if not granted then
                warn("[IAPService] Failed to grant Zomboss shop Robux reward for productId: " .. tostring(receiptInfo.ProductId))
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                fireInventoryUpdate(player, PlayerDataManager.GetPlayerData(player) or data)

                local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                if playObtainEffectRE then
                    local playFullEffect = (tonumber(zombossShopRobuxReward.Quality) or 0) >= 4
                    playObtainEffectRE:FireClient(
                        player,
                        "Purchase Successful!\nObtained "
                            .. tostring(zombossShopRobuxReward.Amount)
                            .. "x "
                            .. tostring(zombossShopRobuxReward.Name)
                            .. "!",
                        playFullEffect
                    )
                end
            end)
        end

        local shopReward = FindShopRewardByProductId(receiptInfo.ProductId)
        if shopReward then
            if receiptSaveState == "granted_pending_save" then
                return finalizeReceiptSave(player, receiptKey, canPersistReceipt)
            end

            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local granted = GrantShopReward(player, shopReward)
            if not granted then
                warn("[IAPService] Unknown shop reward type for productId: " .. tostring(receiptInfo.ProductId))
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            return finalizeReceiptSave(player, receiptKey, canPersistReceipt, function()
                fireInventoryUpdate(player, PlayerDataManager.GetPlayerData(player) or data)

                local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                if playObtainEffectRE then
                    local playFullEffect = (tonumber(shopReward.Quality) or 0) >= 4
                    playObtainEffectRE:FireClient(
                        player,
                        "Purchase Successful!\nObtained " .. tostring(shopReward.Amount) .. "x " .. tostring(shopReward.Name) .. "!",
                        playFullEffect
                    )
                end
            end)
        end

        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

return IAPService

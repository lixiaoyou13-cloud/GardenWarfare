local GiftingService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChestConfig"))
local GiftingConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GiftingConfig"))
local TitleConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TitleConfig"))

local DATA_KEY = GiftingConfig.DataKey or "PendingGifts"
local CLAIMED_DATA_KEY = GiftingConfig.ClaimedDataKey or "ClaimedGiftIds"
local INBOX_STORE_NAME = GiftingConfig.InboxStoreName or "GiftingInbox_v1"
local ADMIN_COMMAND = GiftingConfig.AdminCommand or "!gift"
local ADMIN_GROUP_MIN_RANK = 250
local InboxStore = DataStoreService:GetDataStore(INBOX_STORE_NAME)

local claimingPlayers = {}
local chatConnections = {}

local function getOrCreateRemoteFunction(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function getOrCreateRemoteEvent(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function sendTip(player, message)
    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE then
        showTipRE:FireClient(player, message)
    end
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE:FireClient(player, data)
    end
end

local function playObtainEffect(player, message)
    local effectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
    if effectRE then
        effectRE:FireClient(player, message, true)
    end
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function restoreTable(target, snapshot)
    for key in pairs(target) do
        target[key] = nil
    end

    for key, value in pairs(snapshot) do
        target[key] = deepCopy(value)
    end
end

local function normalizeAmount(value)
    return math.max(1, math.floor(tonumber(value) or 1))
end

local function normalizeMutation(value)
    return math.max(1, math.floor(tonumber(value) or 1))
end

local function trimText(value)
    if type(value) ~= "string" then
        return ""
    end

    return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local REWARD_TYPE_ALIASES = {
    coin = GiftingConfig.RewardTypes.Coins,
    coins = GiftingConfig.RewardTypes.Coins,
    sun = GiftingConfig.RewardTypes.Coins,
    seed = GiftingConfig.RewardTypes.Seed,
    seeds = GiftingConfig.RewardTypes.Seed,
    plant = GiftingConfig.RewardTypes.Plant,
    plants = GiftingConfig.RewardTypes.Plant,
    chest = GiftingConfig.RewardTypes.Chest,
    chests = GiftingConfig.RewardTypes.Chest,
    title = GiftingConfig.RewardTypes.Title,
    titles = GiftingConfig.RewardTypes.Title,
    ticket = GiftingConfig.RewardTypes.ExclusiveRollTicket,
    exclusiverollticket = GiftingConfig.RewardTypes.ExclusiveRollTicket,
    exclusiveticket = GiftingConfig.RewardTypes.ExclusiveRollTicket,
    passshoptoken = GiftingConfig.RewardTypes.PassShopToken,
    passtoken = GiftingConfig.RewardTypes.PassShopToken,
}

local function normalizeRewardType(value)
    if type(value) ~= "string" then
        return nil
    end

    local cleaned = string.lower(string.gsub(value, "%s+", ""))
    return REWARD_TYPE_ALIASES[cleaned]
end

local function getItemName(rewardType, itemId)
    if rewardType == GiftingConfig.RewardTypes.Seed then
        local seedConfig = ItemConfig.Seeds and ItemConfig.Seeds[itemId]
        return seedConfig and seedConfig.Name or itemId
    end

    if rewardType == GiftingConfig.RewardTypes.Plant then
        local plantConfig = ItemConfig.Plants and ItemConfig.Plants[itemId]
        return plantConfig and plantConfig.Name or itemId
    end

    if rewardType == GiftingConfig.RewardTypes.Chest then
        local chestConfig = (ItemConfig.Chests and ItemConfig.Chests[itemId]) or ChestConfig.GetChest(itemId)
        return chestConfig and chestConfig.Name or itemId
    end

    if rewardType == GiftingConfig.RewardTypes.Title then
        local titleConfig = TitleConfig.GetTitle(itemId)
        return titleConfig and titleConfig.Name or itemId
    end

    return itemId
end

local function buildRewardText(reward)
    local amount = normalizeAmount(reward.Amount)
    local rewardType = reward.RewardType

    if rewardType == GiftingConfig.RewardTypes.Coins then
        return tostring(amount) .. " Sun"
    end

    if rewardType == GiftingConfig.RewardTypes.ExclusiveRollTicket then
        return "Exclusive Roll x" .. tostring(amount)
    end

    if rewardType == GiftingConfig.RewardTypes.PassShopToken then
        return "Pass Token x" .. tostring(amount)
    end

    if rewardType == GiftingConfig.RewardTypes.Title then
        return tostring(getItemName(rewardType, reward.ItemId) or "Title")
    end

    local itemName = getItemName(rewardType, reward.ItemId)
    return tostring(amount) .. "x " .. tostring(itemName or "Reward")
end

local function validateReward(reward)
    local rewardType = reward.RewardType
    if rewardType == GiftingConfig.RewardTypes.Coins
        or rewardType == GiftingConfig.RewardTypes.ExclusiveRollTicket
        or rewardType == GiftingConfig.RewardTypes.PassShopToken then
        return true
    end

    local itemId = reward.ItemId
    if type(itemId) ~= "string" or itemId == "" then
        return false, "Gift failed: reward item is missing."
    end

    if rewardType == GiftingConfig.RewardTypes.Seed then
        return ItemConfig.Seeds and ItemConfig.Seeds[itemId] ~= nil, "Gift failed: seed config not found."
    end

    if rewardType == GiftingConfig.RewardTypes.Plant then
        return ItemConfig.Plants and ItemConfig.Plants[itemId] ~= nil, "Gift failed: plant config not found."
    end

    if rewardType == GiftingConfig.RewardTypes.Chest then
        local exists = (ItemConfig.Chests and ItemConfig.Chests[itemId] ~= nil) or ChestConfig.GetChest(itemId) ~= nil
        return exists, "Gift failed: chest config not found."
    end

    if rewardType == GiftingConfig.RewardTypes.Title then
        return TitleConfig.GetTitle(itemId) ~= nil, "Gift failed: title config not found."
    end

    return false, "Gift failed: unknown reward type."
end

local function normalizeGift(rawGift)
    if type(rawGift) ~= "table" then
        return nil, "Gift failed: reward config is invalid."
    end

    local rewardType = rawGift.RewardType or rawGift.Type
    if type(rewardType) == "string" then
        rewardType = normalizeRewardType(rewardType) or rewardType
    end

    if not rewardType then
        return nil, "Gift failed: reward type is missing."
    end

    local itemId = rawGift.ItemId or rawGift.SeedId or rawGift.PlantId or rawGift.ChestId or rawGift.TitleId
    local gift = {
        Id = tostring(rawGift.Id or HttpService:GenerateGUID(false)),
        Title = trimText(rawGift.Title) ~= "" and trimText(rawGift.Title) or "Gift from GardenWarfare",
        RewardType = rewardType,
        ItemId = type(itemId) == "string" and itemId or nil,
        Amount = normalizeAmount(rawGift.Amount),
        Mutation = normalizeMutation(rawGift.Mutation or rawGift.MutationLevel),
        CreatedAt = math.max(0, math.floor(tonumber(rawGift.CreatedAt) or os.time())),
    }

    local ok, message = validateReward(gift)
    if not ok then
        return nil, message
    end

    local rewardText = trimText(rawGift.RewardText or rawGift.Text or rawGift.Description)
    gift.RewardText = rewardText ~= "" and rewardText or buildRewardText(gift)

    return gift
end

local function normalizePendingGifts(data)
    if type(data) ~= "table" then
        return {}
    end

    if type(data[DATA_KEY]) ~= "table" then
        data[DATA_KEY] = {}
        return data[DATA_KEY]
    end

    local normalized = {}
    local seenGiftIds = {}
    local changed = false
    for _, rawGift in ipairs(data[DATA_KEY]) do
        local gift = normalizeGift(rawGift)
        if gift and not seenGiftIds[gift.Id] then
            seenGiftIds[gift.Id] = true
            table.insert(normalized, gift)
            if gift ~= rawGift then
                changed = true
            end
        else
            changed = true
        end
    end

    if changed or #normalized ~= #data[DATA_KEY] then
        data[DATA_KEY] = normalized
    end

    return data[DATA_KEY]
end

local function serializeGift(gift)
    return {
        Id = gift.Id,
        Title = gift.Title,
        RewardText = gift.RewardText,
        CreatedAt = gift.CreatedAt,
    }
end

local function buildStateFromData(data)
    local gifts = normalizePendingGifts(data)
    local state = {}
    for _, gift in ipairs(gifts) do
        table.insert(state, serializeGift(gift))
    end
    return state
end

local function buildState(player)
    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        return {}
    end

    return buildStateFromData(data)
end

local function fireGiftingUpdate(player, data)
    getOrCreateRemoteEvent(GiftingConfig.UpdateRemoteName):FireClient(player, buildStateFromData(data))
end

local function normalizeClaimedGiftIds(data)
    if type(data) ~= "table" then
        return {}
    end

    if type(data[CLAIMED_DATA_KEY]) ~= "table" then
        data[CLAIMED_DATA_KEY] = {}
    end

    return data[CLAIMED_DATA_KEY]
end

local function buildGiftIdMap(gifts)
    local giftIds = {}
    if type(gifts) ~= "table" then
        return giftIds
    end

    for _, gift in ipairs(gifts) do
        if type(gift) == "table" and type(gift.Id) == "string" and gift.Id ~= "" then
            giftIds[gift.Id] = true
        end
    end

    return giftIds
end

local function normalizeInbox(rawInbox)
    local inbox = type(rawInbox) == "table" and rawInbox or {}
    local rawGifts = type(inbox.Gifts) == "table" and inbox.Gifts or {}
    local giftIds = type(inbox.GiftIds) == "table" and inbox.GiftIds or {}
    local normalizedGifts = {}
    local seenGiftIds = {}

    for _, rawGift in ipairs(rawGifts) do
        local gift = normalizeGift(rawGift)
        if gift and not seenGiftIds[gift.Id] then
            seenGiftIds[gift.Id] = true
            giftIds[gift.Id] = true
            table.insert(normalizedGifts, gift)
        end
    end

    inbox.Gifts = normalizedGifts
    inbox.GiftIds = giftIds
    inbox.UpdatedAt = math.max(0, math.floor(tonumber(inbox.UpdatedAt) or 0))
    return inbox
end

local function cleanupInboxGifts(userId, removableGiftIds)
    if type(removableGiftIds) ~= "table" or next(removableGiftIds) == nil then
        return true
    end

    local success, err = pcall(function()
        InboxStore:UpdateAsync(tostring(userId), function(rawInbox)
            local inbox = normalizeInbox(rawInbox)
            local remainingGifts = {}

            for _, gift in ipairs(inbox.Gifts) do
                if not removableGiftIds[gift.Id] then
                    table.insert(remainingGifts, gift)
                end
            end

            inbox.Gifts = remainingGifts
            inbox.UpdatedAt = os.time()
            return inbox
        end)
    end)

    if not success then
        warn("[GiftingService] Failed to clean gift inbox for userId "
            .. tostring(userId) .. ": " .. tostring(err))
        return false, err
    end

    return true
end

local function importInboxGifts(player, data)
    if not player or not player.Parent or type(data) ~= "table" then
        return false, "missing player data"
    end

    local rawInbox = nil
    local success, err = pcall(function()
        rawInbox = InboxStore:GetAsync(tostring(player.UserId))
    end)

    if not success then
        warn("[GiftingService] Failed to read gift inbox for " .. tostring(player.Name) .. ": " .. tostring(err))
        return false, err
    end

    local inbox = normalizeInbox(rawInbox)
    if #inbox.Gifts <= 0 then
        return true, "empty"
    end

    local gifts = normalizePendingGifts(data)
    local claimedGiftIds = normalizeClaimedGiftIds(data)
    local pendingGiftIds = buildGiftIdMap(gifts)
    local cleanupIds = {}
    local importedCount = 0
    local snapshot = deepCopy(data)

    for _, gift in ipairs(inbox.Gifts) do
        if claimedGiftIds[gift.Id] == true or pendingGiftIds[gift.Id] == true then
            cleanupIds[gift.Id] = true
        else
            table.insert(gifts, deepCopy(gift))
            pendingGiftIds[gift.Id] = true
            cleanupIds[gift.Id] = true
            importedCount += 1
        end
    end

    if importedCount > 0 then
        local saved, saveErr = PlayerDataManager.ForceSave(player)
        if not saved then
            restoreTable(data, snapshot)
            fireInventoryUpdate(player, data)
            warn("[GiftingService] Failed to save imported gift inbox for "
                .. tostring(player.Name) .. ": " .. tostring(saveErr))
            return false, saveErr
        end

        fireGiftingUpdate(player, data)
    end

    cleanupInboxGifts(player.UserId, cleanupIds)
    return true, importedCount
end

local function queueInboxGiftsForUserId(userId, rawGifts)
    userId = tonumber(userId)
    if not userId or userId <= 0 then
        return false, "Gift failed: target user id is invalid."
    end

    if type(rawGifts) ~= "table" then
        return false, "Gift failed: reward config is invalid."
    end

    local giftsToQueue = {}
    for _, rawGift in ipairs(rawGifts) do
        local gift, message = normalizeGift(rawGift)
        if not gift then
            return false, message
        end
        table.insert(giftsToQueue, gift)
    end

    if #giftsToQueue <= 0 then
        return false, "Gift failed: reward config is empty."
    end

    local queuedCount = 0
    local alreadyQueuedCount = 0
    local success, err = pcall(function()
        InboxStore:UpdateAsync(tostring(userId), function(rawInbox)
            local inbox = normalizeInbox(rawInbox)

            for _, gift in ipairs(giftsToQueue) do
                if inbox.GiftIds[gift.Id] == true then
                    alreadyQueuedCount += 1
                else
                    table.insert(inbox.Gifts, gift)
                    inbox.GiftIds[gift.Id] = true
                    queuedCount += 1
                end
            end

            inbox.UpdatedAt = os.time()
            return inbox
        end)
    end)

    if not success then
        return false, "Gift failed: inbox save failed. " .. tostring(err or "")
    end

    local player = Players:GetPlayerByUserId(userId)
    if player then
        task.spawn(function()
            local data = PlayerDataManager.WaitForPlayerData(player, 20)
            if player.Parent and data then
                importInboxGifts(player, data)
            end
        end)
    end

    if queuedCount <= 0 and alreadyQueuedCount > 0 then
        return true, "Gift already queued.", giftsToQueue[1].Id
    end

    return true, "Gift queued: " .. tostring(queuedCount) .. " item(s).", giftsToQueue[1].Id
end

local function queueInboxGiftForUserId(userId, rawGift)
    return queueInboxGiftsForUserId(userId, { rawGift })
end

local function grantReward(player, data, gift)
    local rewardType = gift.RewardType
    local amount = normalizeAmount(gift.Amount)

    if rewardType == GiftingConfig.RewardTypes.Coins then
        PlayerDataManager.GiveCoinsRaw(player, amount)
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.Seed then
        PlayerDataManager.GiveSeed(player, gift.ItemId, amount, true)
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.Plant then
        PlayerDataManager.GivePlant(player, gift.ItemId, amount, gift.Mutation, true)
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.Chest then
        PlayerDataManager.GiveChest(player, gift.ItemId, amount, false)
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.Title then
        local success, message = PlayerDataManager.GiveTitle(player, gift.ItemId)
        if not success then
            return false, message or "Gift failed: title could not be granted."
        end
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.ExclusiveRollTicket then
        data.ExclusiveRollTickets = math.max(0, math.floor(tonumber(data.ExclusiveRollTickets) or 0)) + amount
        fireInventoryUpdate(player, data)
        return true, buildRewardText(gift)
    end

    if rewardType == GiftingConfig.RewardTypes.PassShopToken then
        data.PassShopTokens = math.max(0, math.floor(tonumber(data.PassShopTokens) or 0)) + amount
        fireInventoryUpdate(player, data)
        return true, buildRewardText(gift)
    end

    return false, "Gift failed: unknown reward type."
end

local function queueGift(player, rawGift)
    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        return false, "Gift failed: data is still loading."
    end

    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Gift failed: save unavailable. Please try again later."
    end

    local gift, message = normalizeGift(rawGift)
    if not gift then
        return false, message
    end

    local snapshot = deepCopy(data)
    local gifts = normalizePendingGifts(data)
    table.insert(gifts, gift)

    local saved, saveErr = PlayerDataManager.ForceSave(player)
    if not saved then
        restoreTable(data, snapshot)
        fireInventoryUpdate(player, data)
        return false, "Gift failed: save failed. " .. tostring(saveErr or "")
    end

    fireGiftingUpdate(player, data)
    return true, "Gift queued: " .. tostring(gift.RewardText), gift.Id
end

local function claimGift(player, giftId)
    if claimingPlayers[player] then
        return false, "Claim is already being processed.", buildState(player)
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Data is still loading. Please try again later.", {}
    end

    if not PlayerDataManager.IsDataSafeToSave(player) then
        claimingPlayers[player] = nil
        return false, "Save unavailable. Please try again later.", buildStateFromData(data)
    end

    local gifts = normalizePendingGifts(data)
    local claimedGiftIds = normalizeClaimedGiftIds(data)
    local giftIndex = nil
    local gift = nil
    local targetId = tostring(giftId or "")
    for index, pendingGift in ipairs(gifts) do
        if tostring(pendingGift.Id) == targetId then
            giftIndex = index
            gift = pendingGift
            break
        end
    end

    if not gift then
        claimingPlayers[player] = nil
        return false, "Gift is no longer available.", buildStateFromData(data)
    end

    if claimedGiftIds[gift.Id] == true then
        table.remove(gifts, giftIndex)
        PlayerDataManager.ForceSave(player)
        claimingPlayers[player] = nil
        fireGiftingUpdate(player, data)
        return false, "Gift is no longer available.", buildStateFromData(data)
    end

    local snapshot = deepCopy(data)
    table.remove(gifts, giftIndex)

    local granted, rewardName = grantReward(player, data, gift)
    if not granted then
        restoreTable(data, snapshot)
        claimingPlayers[player] = nil
        fireInventoryUpdate(player, data)
        return false, rewardName or "Claim failed.", buildStateFromData(data)
    end

    claimedGiftIds[gift.Id] = true

    local saved, saveErr = PlayerDataManager.ForceSave(player)
    if not saved then
        restoreTable(data, snapshot)
        PlayerDataManager.ForceSave(player)
        claimingPlayers[player] = nil
        fireInventoryUpdate(player, data)
        fireGiftingUpdate(player, data)
        return false, "Claim failed: save failed. Please try again.", buildStateFromData(data)
    end

    claimingPlayers[player] = nil
    local message = "Claimed " .. tostring(rewardName) .. "!"
    playObtainEffect(player, message)
    fireInventoryUpdate(player, data)
    fireGiftingUpdate(player, data)
    return true, message, buildStateFromData(data)
end

local function isAdmin(player)
    if not player then
        return false
    end

    if RunService:IsStudio() then
        return true
    end

    if game.CreatorType == Enum.CreatorType.User then
        return player.UserId == game.CreatorId
    end

    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        return ok and rank >= ADMIN_GROUP_MIN_RANK
    end

    return false
end

local function splitWords(message)
    local words = {}
    for word in string.gmatch(tostring(message or ""), "%S+") do
        table.insert(words, word)
    end
    return words
end

local function findPlayerByToken(token)
    local normalized = string.lower(tostring(token or ""))
    if normalized == "" then
        return nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if string.lower(player.Name) == normalized or string.lower(player.DisplayName) == normalized then
            return player
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local name = string.lower(player.Name)
        local displayName = string.lower(player.DisplayName)
        if string.sub(name, 1, #normalized) == normalized or string.sub(displayName, 1, #normalized) == normalized then
            return player
        end
    end

    return nil
end

local function buildGiftFromCommand(sender, words)
    local rewardType = normalizeRewardType(words[3])
    if not rewardType then
        return nil, "Usage: !gift player Sun amount | Seed seedId amount | Plant plantId amount mutation | Chest chestId amount | Title titleId"
    end

    local title = "Gift from " .. tostring(sender.DisplayName or sender.Name)
    if rewardType == GiftingConfig.RewardTypes.Coins
        or rewardType == GiftingConfig.RewardTypes.ExclusiveRollTicket
        or rewardType == GiftingConfig.RewardTypes.PassShopToken then
        return normalizeGift({
            Title = title,
            RewardType = rewardType,
            Amount = words[4],
        })
    end

    if rewardType == GiftingConfig.RewardTypes.Title then
        return normalizeGift({
            Title = title,
            RewardType = rewardType,
            ItemId = words[4],
            Amount = 1,
        })
    end

    return normalizeGift({
        Title = title,
        RewardType = rewardType,
        ItemId = words[4],
        Amount = words[5],
        Mutation = words[6],
    })
end

local function handleAdminCommand(player, message)
    local words = splitWords(message)
    if words[1] ~= ADMIN_COMMAND then
        return
    end

    if not isAdmin(player) then
        sendTip(player, "You do not have permission to use gift commands.")
        return
    end

    if #words < 4 then
        sendTip(player, "Usage: !gift player Sun amount | Seed seedId amount | Plant plantId amount mutation | Chest chestId amount | Title titleId")
        return
    end

    local gift, messageOrUsage = buildGiftFromCommand(player, words)
    if not gift then
        sendTip(player, messageOrUsage)
        return
    end

    local targetToken = string.lower(tostring(words[2] or ""))
    local targets = {}
    if targetToken == "all" then
        targets = Players:GetPlayers()
    elseif targetToken == "me" then
        table.insert(targets, player)
    else
        local targetPlayer = findPlayerByToken(words[2])
        if targetPlayer then
            table.insert(targets, targetPlayer)
        end
    end

    if #targets <= 0 then
        sendTip(player, "Gift failed: target player is not online.")
        return
    end

    local successCount = 0
    local lastError = nil
    for _, targetPlayer in ipairs(targets) do
        local success, result = queueInboxGiftForUserId(targetPlayer.UserId, deepCopy(gift))
        if success then
            successCount += 1
        else
            lastError = result
        end
    end

    if successCount > 0 then
        sendTip(player, "Gift sent to " .. tostring(successCount) .. " player(s): " .. tostring(gift.RewardText))
    else
        sendTip(player, lastError or "Gift failed.")
    end
end

local function bindPlayer(player)
    if chatConnections[player] then
        return
    end

    chatConnections[player] = player.Chatted:Connect(function(message)
        handleAdminCommand(player, message)
    end)

    task.spawn(function()
        local data = PlayerDataManager.WaitForPlayerData(player, 20)
        if player.Parent and data then
            normalizeClaimedGiftIds(data)
            normalizePendingGifts(data)
            importInboxGifts(player, data)
            fireGiftingUpdate(player, data)
        end
    end)
end

function GiftingService.QueueGiftForPlayer(player, rawGift)
    if not player or not player.Parent then
        return false, "Gift failed: target player is not online."
    end

    return queueInboxGiftForUserId(player.UserId, rawGift)
end

function GiftingService.QueueGiftForUserId(userId, rawGift)
    return queueInboxGiftForUserId(userId, rawGift)
end

function GiftingService.QueueGiftsForUserId(userId, rawGifts)
    return queueInboxGiftsForUserId(userId, rawGifts)
end

function GiftingService.Init()
    getOrCreateRemoteFunction(GiftingConfig.StateRemoteName).OnServerInvoke = function(player)
        return buildState(player)
    end

    getOrCreateRemoteFunction(GiftingConfig.ClaimRemoteName).OnServerInvoke = function(player, giftId)
        local ok, success, message, state = pcall(claimGift, player, giftId)
        if not ok then
            claimingPlayers[player] = nil
            warn("[GiftingService] Claim failed: " .. tostring(success))
            return false, "Claim failed. Please try again.", buildState(player)
        end

        return success, message, state
    end

    getOrCreateRemoteEvent(GiftingConfig.UpdateRemoteName)

    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayer(player)
    end

    Players.PlayerAdded:Connect(bindPlayer)
    Players.PlayerRemoving:Connect(function(player)
        claimingPlayers[player] = nil
        if chatConnections[player] then
            chatConnections[player]:Disconnect()
            chatConnections[player] = nil
        end
    end)

    print("Server: GiftingService active.")
end

return GiftingService

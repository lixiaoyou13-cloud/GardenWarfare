-- src/server/PlayerDataManager.luau
local PlayerDataManager = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local TitleConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TitleConfig"))
local PassRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassRewardConfig"))
local PassShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassShopConfig"))
local PassQuestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassQuestConfig"))
local NoticeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NoticeConfig"))
local RollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RollConfig"))
local FriendSunBoostService = require(script.Parent.Services.FriendSunBoostService)
-- 引入签到奖励配置
local SignInRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SignInRewardConfig"))

local PlayerDataStore = DataStoreService:GetDataStore("MyGameData_V18")
local sessionData = {}
local dataSaveAllowed = {}
local saveQueueState = {}
local finalSavePending = {}
local X2_SUN_GAME_PASS_ID = 1856661235
local x2SunOwnershipCache = {}
local x2SunOwnershipCacheTime = {}
local X2_SUN_CACHE_TTL = 60
local ROLL_TAB1_CASH_COST = 200000
local onlineRollTimerStarted = false
local passQuestOnlineTimerStarted = false
local AUTO_SAVE_INTERVAL = 300
local SAVE_DEBOUNCE_SECONDS = 8
local SAVE_MIN_INTERVAL_SECONDS = 8
local BIND_TO_CLOSE_TIMEOUT = 25
local SAVE_VERSION_KEY = "_SaveVersion"
local LAST_SAVE_TIME_KEY = "_LastSaveTime"
local ACTIVE_SESSION_ID_KEY = "_ActiveSessionId"
local ACTIVE_SESSION_JOB_ID_KEY = "_ActiveSessionJobId"
local ACTIVE_SESSION_HEARTBEAT_KEY = "_ActiveSessionHeartbeatAt"
local ACTIVE_SESSION_IS_STUDIO_KEY = "_ActiveSessionIsStudio"
local SESSION_HEARTBEAT_INTERVAL = 60
local SESSION_TIMEOUT_SECONDS = 180
local SESSION_ACQUIRE_MAX_ATTEMPTS = 5
local SESSION_ACQUIRE_RETRY_DELAY = 2
local RECEIPT_HISTORY_LIMIT = 100
local PASS_V1_MAX_LEVEL = 10
local PASS_V1_EXP_PER_LEVEL = 200
local DATA_LOAD_KICK_MESSAGE = "Your data could not be loaded. Please rejoin the game."
local STALE_SESSION_KICK_MESSAGE = "Your data is active in a newer server. Please rejoin the game."
local IS_STUDIO = RunService:IsStudio()
local SERVER_SESSION_ID = HttpService:GenerateGUID(false)
local SERVER_JOB_ID = if IS_STUDIO then "Studio-" .. SERVER_SESSION_ID elseif game.JobId and game.JobId ~= "" then game.JobId else SERVER_SESSION_ID

local function isStudioRuntime()
    local ok, isStudioNow = pcall(function()
        return RunService:IsStudio()
    end)

    return IS_STUDIO or (ok and isStudioNow == true)
end

local function kickPlayerForDataIssue(player, message, reasonTag)
    if not player or not player.Parent then
        return
    end

    if isStudioRuntime() then
        warn("[Data] Studio data kick suppressed for " .. player.Name .. ": " .. tostring(reasonTag))
        return
    end

    player:Kick(message)
end

local function getPassExpRequired(level)
    level = math.clamp(math.floor(tonumber(level) or 1), 1, PASS_V1_MAX_LEVEL)
    return PASS_V1_EXP_PER_LEVEL
end

local function kickForDataLoadFailure(player, reason)
    if not player then
        return
    end

    sessionData[player.UserId] = nil
    dataSaveAllowed[player.UserId] = nil
    warn("[Data] Failed to load data for " .. player.Name .. ": " .. tostring(reason))

    kickPlayerForDataIssue(player, DATA_LOAD_KICK_MESSAGE, "data_load_failure")
end

local function kickForActiveSession(player, reason)
    if not player then
        return
    end

    sessionData[player.UserId] = nil
    dataSaveAllowed[player.UserId] = nil
    warn("[Data] Active session blocked load for " .. player.Name .. ": " .. tostring(reason))

    kickPlayerForDataIssue(player, STALE_SESSION_KICK_MESSAGE, "active_session")
end

local function getSaveBlockReason(userId)
    local state = userId and saveQueueState[userId]
    if state and state.StaleSessionInvalidated == true then
        return "stale_session"
    end

    return "save_not_allowed"
end

local function invalidateStaleSession(userId, reason)
    if not userId then
        return
    end

    local state = saveQueueState[userId]
    if state and state.StaleSessionInvalidated == true then
        return
    end

    if not state then
        state = {
            IsSaving = false,
            Dirty = false,
            Generation = 0,
            DeferredScheduled = false,
            LastSaveClock = 0,
            StaleSessionInvalidated = true,
        }
        saveQueueState[userId] = state
    else
        state.StaleSessionInvalidated = true
        state.Dirty = false
        state.DeferredScheduled = false
    end

    dataSaveAllowed[userId] = nil
    warn("[Data] Stale session detected for userId " .. tostring(userId) .. ": " .. tostring(reason))

    local player = Players:GetPlayerByUserId(userId)
    if player then
        task.defer(function()
            kickPlayerForDataIssue(player, STALE_SESSION_KICK_MESSAGE, "stale_session")
        end)
    end
end

local analyticsRE = ReplicatedStorage:FindFirstChild("AnalyticsRE") or Instance.new("RemoteEvent")
analyticsRE.Name = "AnalyticsRE"
analyticsRE.Parent = ReplicatedStorage

analyticsRE.OnServerEvent:Connect(function(player, eventType, eventName, extraData)
    print(string.format("[Analytics] Player: %s | Type: %s | Event: %s", player.Name, tostring(eventType), tostring(eventName)))
    if eventType == "Custom" then
        local logValue = 1
        if type(extraData) == "number" then logValue = extraData end
        AnalyticsService:LogCustomEvent(player, eventName, logValue)
    elseif eventType == "Funnel" then
        if type(extraData) == "table" then
            local sessionId = extraData.SessionId
            local stepIndex = extraData.StepIndex or 1
            AnalyticsService:LogFunnelStepEvent(player, eventName, sessionId, stepIndex, extraData.StepName)
        end
    end
end)

local function getUpdatePassDataRemote()
    local updatePassDataRE = ReplicatedStorage:FindFirstChild("UpdatePassDataRE")
    if not updatePassDataRE then
        updatePassDataRE = Instance.new("RemoteEvent")
        updatePassDataRE.Name = "UpdatePassDataRE"
        updatePassDataRE.Parent = ReplicatedStorage
    end

    return updatePassDataRE
end

local function getUpdatePassQuestStateRemote()
    local updatePassQuestStateRE = ReplicatedStorage:FindFirstChild(PassQuestConfig.UpdateRemoteName)
    if not updatePassQuestStateRE then
        updatePassQuestStateRE = Instance.new("RemoteEvent")
        updatePassQuestStateRE.Name = PassQuestConfig.UpdateRemoteName
        updatePassQuestStateRE.Parent = ReplicatedStorage
    end

    return updatePassQuestStateRE
end

local function normalizePassClaimedMap(value)
    local normalized = {}
    if type(value) ~= "table" then
        return normalized
    end

    for key, isClaimed in pairs(value) do
        if isClaimed == true then
            local tier = tonumber(key)
            if tier then
                tier = math.floor(tier)
                if tier >= 1 and tier <= PASS_V1_MAX_LEVEL then
                    normalized[tostring(tier)] = true
                end
            end
        end
    end

    return normalized
end

local function normalizePassV1Data(data)
    if type(data) ~= "table" then
        return {
            Level = 1,
            Exp = 0,
            FreeClaimed = {},
            PremiumClaimed = {},
            PremiumOwned = false,
            RepeatRewardAvailable = 0,
            FreeRepeatClaimed = 0,
            PremiumRepeatClaimed = 0,
        }
    end

    if type(data.PassV1) ~= "table" then
        data.PassV1 = {}
    end

    local level = math.clamp(math.floor(tonumber(data.PassV1.Level) or 1), 1, PASS_V1_MAX_LEVEL)
    local exp = math.max(0, math.floor(tonumber(data.PassV1.Exp) or 0))
    local repeatRewardAvailable = math.max(0, math.floor(tonumber(data.PassV1.RepeatRewardAvailable) or 0))

    while level < PASS_V1_MAX_LEVEL and exp >= getPassExpRequired(level) do
        exp -= getPassExpRequired(level)
        level += 1
    end

    if level >= PASS_V1_MAX_LEVEL then
        level = PASS_V1_MAX_LEVEL
        while exp >= getPassExpRequired(level) do
            exp -= getPassExpRequired(level)
            repeatRewardAvailable += 1
        end
    else
        exp = math.clamp(exp, 0, getPassExpRequired(level) - 1)
    end

    data.PassV1.Level = level
    data.PassV1.Exp = exp
    data.PassV1.FreeClaimed = normalizePassClaimedMap(data.PassV1.FreeClaimed)
    data.PassV1.PremiumClaimed = normalizePassClaimedMap(data.PassV1.PremiumClaimed)
    data.PassV1.PremiumOwned = data.PassV1.PremiumOwned == true
    data.PassV1.RepeatRewardAvailable = repeatRewardAvailable
    data.PassV1.FreeRepeatClaimed = math.clamp(
        math.floor(tonumber(data.PassV1.FreeRepeatClaimed) or 0),
        0,
        repeatRewardAvailable
    )
    data.PassV1.PremiumRepeatClaimed = math.clamp(
        math.floor(tonumber(data.PassV1.PremiumRepeatClaimed) or 0),
        0,
        repeatRewardAvailable
    )

    return data.PassV1
end

local function normalizePassQuestV1Data(data)
    local dayKey = PassQuestConfig.GetUtcDayKey(os.time())
    if type(data) ~= "table" then
        return {
            DayKey = dayKey,
            Progress = {},
            Claimed = {},
        }, false
    end

    local changed = false
    if type(data.PassQuestV1) ~= "table" then
        data.PassQuestV1 = {}
        changed = true
    end

    local questData = data.PassQuestV1
    if tostring(questData.DayKey or "") ~= dayKey then
        questData.DayKey = dayKey
        questData.Progress = {}
        questData.Claimed = {}
        changed = true
    end

    local rawProgress = type(questData.Progress) == "table" and questData.Progress or {}
    local rawClaimed = type(questData.Claimed) == "table" and questData.Claimed or {}
    local progress = {}
    local claimed = {}

    for _, taskConfig in ipairs(PassQuestConfig.Tasks) do
        local taskId = taskConfig.Id
        local target = math.max(1, math.floor(tonumber(taskConfig.Target) or 1))
        local value = math.clamp(math.floor(tonumber(rawProgress[taskId]) or 0), 0, target)
        progress[taskId] = value

        if rawClaimed[taskId] == true then
            claimed[taskId] = true
        end

        if rawProgress[taskId] ~= value or rawClaimed[taskId] ~= claimed[taskId] then
            changed = true
        end
    end

    questData.Progress = progress
    questData.Claimed = claimed

    return questData, changed
end

local function ensureEnterGamePassQuest(data)
    local questData = normalizePassQuestV1Data(data)
    local taskConfig = PassQuestConfig.GetTaskById(PassQuestConfig.TaskIds.EnterGame)
    if not (questData and taskConfig) then
        return false
    end

    local taskId = taskConfig.Id
    local target = math.max(1, math.floor(tonumber(taskConfig.Target) or 1))
    local current = math.max(0, math.floor(tonumber(questData.Progress[taskId]) or 0))
    if current >= target then
        return false
    end

    questData.Progress[taskId] = target
    return true
end

local function GetDefaultData()
   return {
        Coins = 1000, Level = 1, UnlockedLevel = 1,
        TotalSun = 0,
        UnlockedPlots = 4,
        SignInDays = 0,
        SignInTier = 1,
        LastSignInTime = 0,
        LastSignInPurchaseTime = 0,

        -- 签到重置标签记（新玩家默认已经重置）
        SignInReset_V1 = true,

        Hotbar = {"Tool_Shovel","System_Backpack", "Tool_WeaponBlock"},
        Inventory = { Seeds = { { ID = "Peashooter", Quantity = 1 } }, Plants = {}, Chests = {}, Titles = {} },
        EquippedTitle = "",
        PlantedPlants = {}, CombatPlants = {},
        UnlockedSeeds = { ["Peashooter"] = true },
        TutorialStep = 0,
        UnlockedMutations = {},
        ClaimedAchieve = {},
        RollTickets = {0, 0},
        PassV1 = {
            Level = 1,
            Exp = 0,
            FreeClaimed = {},
            PremiumClaimed = {},
            PremiumOwned = false,
            RepeatRewardAvailable = 0,
            FreeRepeatClaimed = 0,
            PremiumRepeatClaimed = 0,
        },
        PassQuestV1 = {
            DayKey = "",
            Progress = {},
            Claimed = {},
        },

        NewbieGiftStartTime = 0,
        NewbieGiftPurchased = false,
        ChatGiftClaimed_V1 = false,
        ExclusiveRollPity_Rotobaga = 0,
        ExclusiveRollPurchaseCount = 0,
        ExclusiveRollTotalRolls = 0,
        ExclusiveRollTickets = 0,
        PassShopTokens = 0,
        PendingGifts = {},
        ClaimedGiftIds = {},
        RankingSeasonBaselines = {},
        LastSeenNoticeId = "",
        FreeRewardClaimedv1 = false,
        ProcessedReceipts = {},
        ProcessedReceiptOrder = {},
        OnlineRewardDayKey = "",
        OnlineRewardClaimed = {},
        OnlineRewardCycleStartedAt = 0,
        OnlineRewardRefreshAt = 0,
        OnlineRollTimer = 300,
        [SAVE_VERSION_KEY] = 0,
        [LAST_SAVE_TIME_KEY] = 0
    }
end

local function normalizeMutationLevel(mutationLevel)
    return math.max(1, math.floor(tonumber(mutationLevel) or 1))
end

local function ensureUnlockedMutationTable(data, plantId)
    data.UnlockedMutations = data.UnlockedMutations or {}
    if type(data.UnlockedMutations[plantId]) ~= "table" then
        data.UnlockedMutations[plantId] = {}
    end
    return data.UnlockedMutations[plantId]
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

local function markMutationUnlocked(data, plantId, mutationLevel)
    if type(data) ~= "table" or type(plantId) ~= "string" or plantId == "" then
        return
    end

    local level = normalizeMutationLevel(mutationLevel)
    local mutationMap = ensureUnlockedMutationTable(data, plantId)
    mutationMap[level] = true
    mutationMap[tostring(level)] = nil
end

local function normalizeUnlockedMutations(data)
    if type(data) ~= "table" then
        return
    end

    if type(data.UnlockedMutations) ~= "table" then
        data.UnlockedMutations = {}
        return
    end

    for plantId, mutationMap in pairs(data.UnlockedMutations) do
        local normalized = {}

        if type(mutationMap) == "table" then
            for levelKey, unlocked in pairs(mutationMap) do
                if unlocked == true then
                    local level = tonumber(levelKey)
                    if level then
                        normalized[normalizeMutationLevel(level)] = true
                    end
                end
            end
        elseif mutationMap == true then
            normalized[1] = true
        end

        data.UnlockedMutations[plantId] = normalized
    end
end

local function backfillUnlockedMutationsFromOwnedPlants(data)
    if type(data) ~= "table" then
        return
    end

    normalizeUnlockedMutations(data)

    if data.Inventory and type(data.Inventory.Plants) == "table" then
        for _, plantData in ipairs(data.Inventory.Plants) do
            if type(plantData) == "table" and type(plantData.ID) == "string" and (tonumber(plantData.Quantity) or 0) > 0 then
                plantData.Mutation = normalizeMutationLevel(plantData.Mutation or 1)
                markMutationUnlocked(data, plantData.ID, plantData.Mutation)
            end
        end
    end

    if type(data.PlantedPlants) == "table" then
        for _, plantData in pairs(data.PlantedPlants) do
            if type(plantData) == "table" and type(plantData.SeedId) == "string" then
                plantData.Mutation = normalizeMutationLevel(plantData.Mutation or 1)
                local seedConfig = ItemConfig.Seeds and ItemConfig.Seeds[plantData.SeedId]
                local plantId = seedConfig and seedConfig.YieldPlant or plantData.SeedId
                markMutationUnlocked(data, plantId, plantData.Mutation)
            end
        end
    end

    if type(data.CombatPlants) == "table" then
        for _, plantData in pairs(data.CombatPlants) do
            if type(plantData) == "table" and type(plantData.PlantId) == "string" then
                plantData.Mutation = normalizeMutationLevel(plantData.Mutation or 1)
                markMutationUnlocked(data, plantData.PlantId, plantData.Mutation)
            end
        end
    end
end

local function normalizeTitleData(data)
    if type(data) ~= "table" then
        return false
    end

    local changed = false
    if type(data.Inventory) ~= "table" then
        data.Inventory = { Seeds = {}, Plants = {}, Chests = {}, Titles = {} }
        changed = true
    end
    if type(data.Inventory.Seeds) ~= "table" then data.Inventory.Seeds = {}; changed = true end
    if type(data.Inventory.Plants) ~= "table" then data.Inventory.Plants = {}; changed = true end
    if type(data.Inventory.Chests) ~= "table" then data.Inventory.Chests = {}; changed = true end
    if type(data.Inventory.Titles) ~= "table" then
        data.Inventory.Titles = {}
        changed = true
    end

    local normalizedTitles = {}
    local ownedTitleMap = {}
    for _, rawTitle in ipairs(data.Inventory.Titles) do
        local titleId = nil
        if type(rawTitle) == "table" then
            titleId = rawTitle.ID
        elseif type(rawTitle) == "string" then
            titleId = rawTitle
        end

        if type(titleId) == "string" and TitleConfig.GetTitle(titleId) and not ownedTitleMap[titleId] then
            ownedTitleMap[titleId] = true
            table.insert(normalizedTitles, { ID = titleId })
        else
            changed = true
        end
    end

    if #normalizedTitles ~= #data.Inventory.Titles then
        changed = true
    end
    data.Inventory.Titles = normalizedTitles

    if type(data.EquippedTitle) ~= "string" then
        data.EquippedTitle = ""
        changed = true
    elseif data.EquippedTitle ~= "" and not ownedTitleMap[data.EquippedTitle] then
        data.EquippedTitle = ""
        changed = true
    end

    return changed
end

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

local function normalizeProcessedReceipts(data)
    if type(data) ~= "table" then
        return
    end

    local receipts = data.ProcessedReceipts
    if type(receipts) ~= "table" then
        receipts = {}
    end

    local existingOrder = data.ProcessedReceiptOrder
    if type(existingOrder) ~= "table" then
        existingOrder = {}
    end

    local seen = {}
    local orderedKeys = {}
    for _, receiptKey in ipairs(existingOrder) do
        if type(receiptKey) == "string" and receiptKey ~= "" and receipts[receiptKey] == true and not seen[receiptKey] then
            seen[receiptKey] = true
            table.insert(orderedKeys, receiptKey)
        end
    end

    for receiptKey, processed in pairs(receipts) do
        if type(receiptKey) == "string" and receiptKey ~= "" and processed == true and not seen[receiptKey] then
            seen[receiptKey] = true
            table.insert(orderedKeys, receiptKey)
        end
    end

    while #orderedKeys > RECEIPT_HISTORY_LIMIT do
        table.remove(orderedKeys, 1)
    end

    local normalizedReceipts = {}
    for _, receiptKey in ipairs(orderedKeys) do
        normalizedReceipts[receiptKey] = true
    end

    data.ProcessedReceipts = normalizedReceipts
    data.ProcessedReceiptOrder = orderedKeys
end

local function markReceiptProcessedInData(data, receiptKey)
    if type(data) ~= "table" or type(receiptKey) ~= "string" or receiptKey == "" then
        return false
    end

    normalizeProcessedReceipts(data)
    if data.ProcessedReceipts[receiptKey] ~= true then
        data.ProcessedReceipts[receiptKey] = true
        table.insert(data.ProcessedReceiptOrder, receiptKey)
    end

    while #data.ProcessedReceiptOrder > RECEIPT_HISTORY_LIMIT do
        local oldReceiptKey = table.remove(data.ProcessedReceiptOrder, 1)
        data.ProcessedReceipts[oldReceiptKey] = nil
    end

    return true
end

local function getSaveVersion(data)
    if type(data) ~= "table" then
        return 0
    end

    return math.max(0, math.floor(tonumber(data[SAVE_VERSION_KEY]) or 0))
end

local function getActiveSessionId(data)
    if type(data) ~= "table" then
        return nil
    end

    local sessionId = data[ACTIVE_SESSION_ID_KEY]
    if type(sessionId) == "string" and sessionId ~= "" then
        return sessionId
    end

    return nil
end

local function getActiveSessionJobId(data)
    if type(data) ~= "table" then
        return nil
    end

    local jobId = data[ACTIVE_SESSION_JOB_ID_KEY]
    if type(jobId) == "string" and jobId ~= "" then
        return jobId
    end

    return nil
end

local function isStudioRecoverableSession(data)
    if not isStudioRuntime() then
        return false
    end

    local activeSessionId = getActiveSessionId(data)
    if not activeSessionId or activeSessionId == SERVER_SESSION_ID then
        return false
    end

    local jobId = getActiveSessionJobId(data)
    if data[ACTIVE_SESSION_IS_STUDIO_KEY] == true
        or jobId == nil
        or string.sub(jobId, 1, 7) == "Studio-"
    then
        return true
    end

    -- Older Studio test sessions may have written a real-looking JobId before
    -- we started tagging Studio locks. This branch is Studio-only.
    return true
end

local function isCurrentSession(data)
    return getActiveSessionId(data) == SERVER_SESSION_ID
end

local function isActiveSessionExpired(data, now)
    local activeSessionId = getActiveSessionId(data)
    if not activeSessionId or activeSessionId == SERVER_SESSION_ID then
        return true
    end

    local heartbeatAt = tonumber(data[ACTIVE_SESSION_HEARTBEAT_KEY]) or 0
    return heartbeatAt <= 0 or (now - heartbeatAt) >= SESSION_TIMEOUT_SECONDS
end

local function hasActiveOtherSession(data, now)
    local activeSessionId = getActiveSessionId(data)
    if isStudioRecoverableSession(data) then
        return false
    end

    return activeSessionId ~= nil
        and activeSessionId ~= SERVER_SESSION_ID
        and not isActiveSessionExpired(data, now)
end

local function applyCurrentSessionLock(data, now)
    data[ACTIVE_SESSION_ID_KEY] = SERVER_SESSION_ID
    data[ACTIVE_SESSION_JOB_ID_KEY] = SERVER_JOB_ID
    data[ACTIVE_SESSION_HEARTBEAT_KEY] = now
    data[ACTIVE_SESSION_IS_STUDIO_KEY] = isStudioRuntime()
end

local function clearCurrentSessionLock(data)
    if isCurrentSession(data) then
        data[ACTIVE_SESSION_ID_KEY] = nil
        data[ACTIVE_SESSION_JOB_ID_KEY] = nil
        data[ACTIVE_SESSION_HEARTBEAT_KEY] = nil
        data[ACTIVE_SESSION_IS_STUDIO_KEY] = nil
    end
end

local function prepareDataForSave(dataToSave, nextVersion, saveTime)
    local dataForSave = cloneValue(dataToSave)
    dataForSave.Hotbar = {}
    dataForSave[SAVE_VERSION_KEY] = nextVersion
    dataForSave[LAST_SAVE_TIME_KEY] = saveTime
    return dataForSave
end

local function saveWithRetry(userId, dataToSave, options)
    options = options or {}
    local localVersion = getSaveVersion(dataToSave)
    local lastError = nil

    for attempt = 1, 3 do
        local staleWriteBlocked = false
        local blockedSessionId = nil
        local blockedSessionJobId = nil
        local savedVersion = localVersion + 1
        local saveTime = os.time()
        local dataForSave = nil

        local success, err = pcall(function()
            PlayerDataStore:UpdateAsync(userId, function(existingData)
                if hasActiveOtherSession(existingData, saveTime) then
                    staleWriteBlocked = true
                    blockedSessionId = getActiveSessionId(existingData)
                    blockedSessionJobId = getActiveSessionJobId(existingData)
                    return nil
                end

                savedVersion = math.max(getSaveVersion(existingData), localVersion) + 1
                dataForSave = prepareDataForSave(dataToSave, savedVersion, saveTime)
                if options.ReleaseSession == true then
                    clearCurrentSessionLock(dataForSave)
                else
                    applyCurrentSessionLock(dataForSave, saveTime)
                end

                return dataForSave
            end)
        end)

        if success then
            if staleWriteBlocked then
                invalidateStaleSession(userId, "another active session owns the save")
                warn("[Data] Stale save skipped for userId " .. tostring(userId)
                    .. ". Blocked by session: " .. tostring(blockedSessionId)
                    .. ", job: " .. tostring(blockedSessionJobId))
                return false, "stale_session"
            end

            dataToSave[SAVE_VERSION_KEY] = savedVersion
            dataToSave[LAST_SAVE_TIME_KEY] = saveTime
            if options.ReleaseSession == true then
                clearCurrentSessionLock(dataToSave)
            else
                applyCurrentSessionLock(dataToSave, saveTime)
            end
            return true
        end

        lastError = err
        if attempt < 3 then
            task.wait(2)
        end
    end

    warn("[Data] Failed to save data for userId " .. tostring(userId) .. ": " .. tostring(lastError))
    return false, lastError
end

local function acquireSessionData(player)
    local userId = player and player.UserId
    if not userId then
        return false, nil, "invalid_player"
    end

    local lastError = nil
    local blockedSessionId = nil
    local blockedSessionJobId = nil

    for attempt = 1, SESSION_ACQUIRE_MAX_ATTEMPTS do
        local acquiredData = nil
        local blockedBySession = false
        local now = os.time()

        local success, err = pcall(function()
            PlayerDataStore:UpdateAsync(userId, function(existingData)
                if type(existingData) ~= "table" then
                    local defaultData = GetDefaultData()
                    applyCurrentSessionLock(defaultData, now)
                    acquiredData = cloneValue(defaultData)
                    return defaultData
                end

                if hasActiveOtherSession(existingData, now) then
                    blockedBySession = true
                    blockedSessionId = getActiveSessionId(existingData)
                    blockedSessionJobId = getActiveSessionJobId(existingData)
                    return nil
                end

                local dataWithLock = cloneValue(existingData)
                applyCurrentSessionLock(dataWithLock, now)
                acquiredData = cloneValue(dataWithLock)
                return dataWithLock
            end)
        end)

        if success and acquiredData then
            return true, acquiredData, nil
        end

        if success and blockedBySession then
            lastError = "active_session"
            if attempt < SESSION_ACQUIRE_MAX_ATTEMPTS then
                task.wait(SESSION_ACQUIRE_RETRY_DELAY)
            end
        else
            lastError = err
            if attempt < SESSION_ACQUIRE_MAX_ATTEMPTS then
                task.wait(SESSION_ACQUIRE_RETRY_DELAY)
            end
        end
    end

    warn("[Data] Could not acquire session for " .. tostring(player and player.Name or userId)
        .. ". Blocked by session: " .. tostring(blockedSessionId)
        .. ", job: " .. tostring(blockedSessionJobId)
        .. ". Last error: " .. tostring(lastError))
    return false, nil, lastError or "active_session"
end

local function refreshSessionHeartbeat(player)
    local userId = player and player.UserId
    if not userId or dataSaveAllowed[userId] ~= true or not sessionData[userId] then
        return false, "missing_data"
    end

    local heartbeatAt = os.time()
    local staleWriteBlocked = false
    local blockedSessionId = nil
    local blockedSessionJobId = nil

    local success, err = pcall(function()
        PlayerDataStore:UpdateAsync(userId, function(existingData)
            if hasActiveOtherSession(existingData, heartbeatAt) then
                staleWriteBlocked = true
                blockedSessionId = getActiveSessionId(existingData)
                blockedSessionJobId = getActiveSessionJobId(existingData)
                return nil
            end

            if type(existingData) ~= "table" then
                return nil
            end

            local dataWithHeartbeat = cloneValue(existingData)
            applyCurrentSessionLock(dataWithHeartbeat, heartbeatAt)
            return dataWithHeartbeat
        end)
    end)

    if not success then
        return false, err
    end

    if staleWriteBlocked then
        invalidateStaleSession(userId, "another active session owns heartbeat: "
            .. tostring(blockedSessionId) .. ", job: " .. tostring(blockedSessionJobId))
        return false, "stale_session"
    end

    applyCurrentSessionLock(sessionData[userId], heartbeatAt)
    return true
end

local function getSaveState(userId)
    local state = saveQueueState[userId]
    if not state then
        state = {
            IsSaving = false,
            Dirty = false,
            Generation = 0,
            DeferredScheduled = false,
            LastSaveClock = 0,
            StaleSessionInvalidated = false,
        }
        saveQueueState[userId] = state
    end

    return state
end

local function runQueuedSave(userId, dataToSave, options)
    options = options or {}
    local state = getSaveState(userId)

    while state.IsSaving do
        task.wait(0.1)
    end

    if options.RespectMinInterval == true then
        local elapsed = os.clock() - (state.LastSaveClock or 0)
        if elapsed < SAVE_MIN_INTERVAL_SECONDS then
            task.wait(SAVE_MIN_INTERVAL_SECONDS - elapsed)
        end
    end

    state.IsSaving = true
    local observedGeneration = state.Generation or 0
    local success, saveErr = saveWithRetry(userId, dataToSave, options)
    state.IsSaving = false

    if success then
        state.LastSaveClock = os.clock()
        if dataToSave == sessionData[userId] and (state.Generation or 0) <= observedGeneration then
            state.Dirty = false
        end
    end

    if state.Dirty == true and not state.DeferredScheduled and dataSaveAllowed[userId] == true and sessionData[userId] then
        state.DeferredScheduled = true
        task.delay(SAVE_DEBOUNCE_SECONDS, function()
            state.DeferredScheduled = false
            if dataSaveAllowed[userId] ~= true or not sessionData[userId] or state.Dirty ~= true then
                return
            end

            local deferredSuccess, deferredErr = runQueuedSave(userId, sessionData[userId], {
                RespectMinInterval = true,
            })
            if not deferredSuccess and deferredErr ~= "stale_session" then
                warn("[Data] Deferred save failed for userId " .. tostring(userId) .. ": " .. tostring(deferredErr))
            end
        end)
    end

    return success, saveErr
end

local function requestDeferredSave(player, context)
    local userId = player and player.UserId
    if not userId then
        return false, "invalid_player"
    end
    if not sessionData[userId] then
        return false, "missing_data"
    end
    if dataSaveAllowed[userId] ~= true then
        return false, getSaveBlockReason(userId)
    end

    local state = getSaveState(userId)
    state.Dirty = true
    state.Generation = (state.Generation or 0) + 1
    state.Context = context

    if state.DeferredScheduled then
        return true
    end

    state.DeferredScheduled = true
    task.delay(SAVE_DEBOUNCE_SECONDS, function()
        state.DeferredScheduled = false
        if dataSaveAllowed[userId] ~= true or not sessionData[userId] or state.Dirty ~= true then
            return
        end

        local success, saveErr = runQueuedSave(userId, sessionData[userId], {
            RespectMinInterval = true,
        })
        if not success and saveErr ~= "stale_session" then
            warn("[Data] Deferred save failed for " .. tostring(player and player.Name or userId) .. ": " .. tostring(saveErr))
        end
    end)

    return true
end

local function markSessionDataChanged(player, context)
    local saved, saveErr = requestDeferredSave(player, context)
    if not saved
        and saveErr ~= "missing_data"
        and saveErr ~= "save_not_allowed"
        and saveErr ~= "stale_session"
    then
        warn("[Data] Failed to queue save after " .. tostring(context) .. " for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))
    end

    return saved, saveErr
end

local function savePlayerSession(player, options)
    options = options or {}
    local userId = player and player.UserId
    if not userId then
        return false, "invalid_player"
    end

    local dataToSave = sessionData[userId]
    if not dataToSave then
        return false, "missing_data"
    end

    if dataSaveAllowed[userId] ~= true then
        return false, getSaveBlockReason(userId)
    end

    if options.Deferred == true then
        return requestDeferredSave(player, options.Context)
    end

    return runQueuedSave(userId, dataToSave, options)
end

local function startAutoSaveLoop()
    task.spawn(function()
        while true do
            task.wait(AUTO_SAVE_INTERVAL)

            for _, player in ipairs(Players:GetPlayers()) do
                local success, saveErr = savePlayerSession(player, {
                    RespectMinInterval = true,
                })
                if not success and saveErr ~= "missing_data" and saveErr ~= "save_not_allowed" and saveErr ~= "stale_session" then
                    warn("[Data] Autosave failed for " .. player.Name .. ": " .. tostring(saveErr))
                end
                task.wait(0.1)
            end
        end
    end)
end

local function startSessionHeartbeatLoop()
    task.spawn(function()
        while true do
            task.wait(SESSION_HEARTBEAT_INTERVAL)

            for _, player in ipairs(Players:GetPlayers()) do
                local success, heartbeatErr = refreshSessionHeartbeat(player)
                if not success
                    and heartbeatErr ~= "missing_data"
                    and heartbeatErr ~= "save_not_allowed"
                    and heartbeatErr ~= "stale_session"
                then
                    warn("[Data] Session heartbeat failed for " .. player.Name .. ": " .. tostring(heartbeatErr))
                end
                task.wait(0.1)
            end
        end
    end)
end

local function startGlobalOnlineRollTimer()
    if RollConfig.Enabled == false then return end
    if onlineRollTimerStarted then return end
    onlineRollTimerStarted = true

    task.spawn(function()
        while true do
            task.wait(1)

            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            for _, plr in ipairs(Players:GetPlayers()) do
                local pData = sessionData[plr.UserId]
                if pData then
                    pData.OnlineRollTimer = (pData.OnlineRollTimer or 300) - 1

                    if pData.OnlineRollTimer <= 0 then
                        pData.OnlineRollTimer = 300
                        pData.RollTickets = pData.RollTickets or {0, 0}
                        pData.RollTickets[1] = (pData.RollTickets[1] or 0) + 1

                        if updateInventoryRE then
                            updateInventoryRE:FireClient(plr, pData)
                        end
                        markSessionDataChanged(plr, "online roll ticket")
                    end
                end
            end
        end
    end)
end

local firePassQuestState
local addPassQuestProgress

local function startPassQuestOnlineTimer()
    if passQuestOnlineTimerStarted then return end
    passQuestOnlineTimerStarted = true

    task.spawn(function()
        while true do
            task.wait(60)

            for _, player in ipairs(Players:GetPlayers()) do
                local data = sessionData[player.UserId]
                if data then
                    local enterGameChanged = ensureEnterGamePassQuest(data)
                    local _, _, onlineChanged = addPassQuestProgress(player, PassQuestConfig.TaskIds.OnlineDuration, 1, true)
                    if enterGameChanged or onlineChanged then
                        firePassQuestState(player)
                    end
                end
            end
        end
    end)
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

local function parseNoticeDateScore(dateText)
    if type(dateText) ~= "string" then
        return nil
    end

    local year, month, day = string.match(dateText, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    if not (year and month and day) then
        return nil
    end

    if month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end

    return year * 10000 + month * 100 + day
end

local function getNoticeId(notice, index)
    if type(notice) ~= "table" then
        return ""
    end

    return tostring(notice.Id or notice.PublishedAt or notice.TagText or notice.Title or ("Notice_" .. tostring(index)))
end

local function getLatestNoticeId()
    local notices = NoticeConfig.Notices
    if type(notices) ~= "table" or #notices <= 0 then
        return ""
    end

    local latestIndex = 1
    local bestScore = parseNoticeDateScore(notices[1].PublishedAt)
    for index = 2, #notices do
        local score = parseNoticeDateScore(notices[index].PublishedAt)
        if score and (not bestScore or score > bestScore) then
            latestIndex = index
            bestScore = score
        end
    end

    return getNoticeId(notices[latestIndex], latestIndex)
end

local function buildNoticeReadState(player)
    while player and player.Parent and not sessionData[player.UserId] do
        task.wait(0.1)
    end

    local data = player and sessionData[player.UserId]
    local latestNoticeId = getLatestNoticeId()
    local lastSeenNoticeId = data and tostring(data.LastSeenNoticeId or "") or ""

    return {
        LatestNoticeId = latestNoticeId,
        LastSeenNoticeId = lastSeenNoticeId,
        HasUnreadLatest = latestNoticeId ~= "" and lastSeenNoticeId ~= latestNoticeId,
    }
end

local function markLatestNoticeSeen(player, noticeId)
    while player and player.Parent and not sessionData[player.UserId] do
        task.wait(0.1)
    end

    local data = player and sessionData[player.UserId]
    if not data then
        return false, buildNoticeReadState(player)
    end

    local latestNoticeId = getLatestNoticeId()
    if latestNoticeId == "" then
        return true, buildNoticeReadState(player)
    end

    if tostring(noticeId or latestNoticeId) ~= latestNoticeId then
        return false, buildNoticeReadState(player)
    end

    if data.LastSeenNoticeId ~= latestNoticeId then
        data.LastSeenNoticeId = latestNoticeId
        markSessionDataChanged(player, "notice read state")
    end

    return true, buildNoticeReadState(player)
end

local function getPassClaimedMap(passData, trackKey)
    if trackKey == PassRewardConfig.TrackKeys.Premium then
        passData.PremiumClaimed = normalizePassClaimedMap(passData.PremiumClaimed)
        return passData.PremiumClaimed
    end

    passData.FreeClaimed = normalizePassClaimedMap(passData.FreeClaimed)
    return passData.FreeClaimed
end

local function getPassRepeatClaimedCount(passData, trackKey)
    if trackKey == PassRewardConfig.TrackKeys.Premium then
        return math.max(0, math.floor(tonumber(passData.PremiumRepeatClaimed) or 0))
    end

    return math.max(0, math.floor(tonumber(passData.FreeRepeatClaimed) or 0))
end

local function setPassRepeatClaimedCount(passData, trackKey, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if trackKey == PassRewardConfig.TrackKeys.Premium then
        passData.PremiumRepeatClaimed = count
        return
    end

    passData.FreeRepeatClaimed = count
end

local RELIABLE_REWARD_FIELDS = {
    "Coins",
    "TotalSun",
    "RollTickets",
    "Inventory",
    "Hotbar",
    "UnlockedMutations",
    "PassV1",
    "PassQuestV1",
    "PassShopTokens",
    "ExclusiveRollTickets",
    "ClaimedAchieve",
    "SignInDays",
    "SignInTier",
    "LastSignInTime",
    "LastSignInPurchaseTime",
    "NewbieGiftStartTime",
    "NewbieGiftPurchased",
}

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE:FireClient(player, data)
    end
end

local function firePassDataUpdate(player, data)
    local passData = normalizePassV1Data(data)
    getUpdatePassDataRemote():FireClient(player, passData, PASS_V1_EXP_PER_LEVEL, PASS_V1_MAX_LEVEL)
    return passData
end

local function snapshotReliableRewardState(data)
    local snapshot = {}
    for _, fieldName in ipairs(RELIABLE_REWARD_FIELDS) do
        snapshot[fieldName] = cloneValue(data[fieldName])
    end
    return snapshot
end

local function restoreReliableRewardState(data, snapshot)
    for _, fieldName in ipairs(RELIABLE_REWARD_FIELDS) do
        data[fieldName] = cloneValue(snapshot[fieldName])
    end
end

local function rollbackReliableRewardMutation(player, data, snapshot, context)
    restoreReliableRewardState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = savePlayerSession(player)
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[PlayerDataManager] Failed to save rollback after " .. tostring(context) .. " for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end
end

local function saveReliableRewardMutation(player, data, snapshot, context)
    local saved, saveErr = savePlayerSession(player)
    if saved then
        return true
    end

    warn("[PlayerDataManager] Failed to save " .. tostring(context) .. " for "
        .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))
    rollbackReliableRewardMutation(player, data, snapshot, context)
    return false, saveErr
end

local function playUnlockEffect(player, plantId, mutationLevel)
    local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
    if playUnlockAnimRE then
        playUnlockAnimRE:FireClient(player, plantId, mutationLevel)
    end
end

local function playPassObtainEffect(player, itemName, amount)
    local effectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
    if not effectRE then
        return
    end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    itemName = tostring(itemName or "Reward")
    effectRE:FireClient(player, "Congratulations, you obtained " .. tostring(amount) .. "x " .. itemName, true)
end

local function addPassExpToData(data, amount)
    local passData = normalizePassV1Data(data)
    amount = math.max(0, math.floor(tonumber(amount) or 0))

    if amount > 0 then
        passData.Exp += amount

        while passData.Level < PASS_V1_MAX_LEVEL and passData.Exp >= getPassExpRequired(passData.Level) do
            passData.Exp -= getPassExpRequired(passData.Level)
            passData.Level += 1
        end

        if passData.Level >= PASS_V1_MAX_LEVEL then
            passData.Level = PASS_V1_MAX_LEVEL
            while passData.Exp >= getPassExpRequired(passData.Level) do
                passData.Exp -= getPassExpRequired(passData.Level)
                passData.RepeatRewardAvailable = math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0)) + 1
            end
        end
    elseif passData.Level >= PASS_V1_MAX_LEVEL then
        passData.Exp = math.clamp(passData.Exp, 0, getPassExpRequired(passData.Level) - 1)
    end

    return passData, amount > 0
end

local function grantPassReward(player, data, rewardConfig)
    local rewardType = rewardConfig and rewardConfig.Type
    local amount = math.max(1, math.floor(tonumber(rewardConfig and rewardConfig.Amount) or 1))

    if rewardType == PassRewardConfig.RewardTypes.None then
        return false, "This pass tier has no token reward."
    end

    if rewardType == PassRewardConfig.RewardTypes.ExclusiveRollTicket then
        data.ExclusiveRollTickets = math.max(0, math.floor(tonumber(data.ExclusiveRollTickets) or 0)) + amount
        local ticketName = tostring(rewardConfig.DisplayName or "Exclusive Roll Ticket")
        return true, ticketName .. " x" .. tostring(amount), ticketName, amount
    end

    if rewardType == PassRewardConfig.RewardTypes.PassShopToken then
        local tokenKey = PassShopConfig.TokenDataKey or "PassShopTokens"
        data[tokenKey] = math.max(0, math.floor(tonumber(data[tokenKey]) or 0)) + amount
        local tokenName = tostring(rewardConfig.DisplayName or "Token")
        return true, tokenName .. " x" .. tostring(amount), tokenName, amount
    end

    if rewardType == PassRewardConfig.RewardTypes.Seed then
        local seedId = rewardConfig.SeedId or rewardConfig.ItemId
        if not (seedId and ItemConfig.Seeds and ItemConfig.Seeds[seedId]) then
            return false, "Seed reward is not configured."
        end

        PlayerDataManager.GiveSeed(player, seedId, amount, true)
        local seedName = tostring((ItemConfig.Seeds[seedId] and ItemConfig.Seeds[seedId].Name) or seedId)
        return true, seedName .. " x" .. tostring(amount), seedName, amount
    end

    if rewardType == PassRewardConfig.RewardTypes.Plant then
        local plantId = rewardConfig.PlantId or rewardConfig.ItemId
        if not (plantId and ItemConfig.Plants and ItemConfig.Plants[plantId]) then
            return false, "Plant reward is not configured."
        end

        local mutation = math.max(1, math.floor(tonumber(rewardConfig.Mutation) or 1))
        local wasFirstUnlock = not isMutationUnlocked(data, plantId, mutation)
        PlayerDataManager.GivePlant(player, plantId, amount, mutation, true)
        local plantName = tostring((ItemConfig.Plants[plantId] and ItemConfig.Plants[plantId].Name) or plantId)
        return true, plantName .. " x" .. tostring(amount), plantName, amount, wasFirstUnlock and plantId or nil, mutation
    end

    return false, "Pass reward type is not supported."
end

local syncPassPremiumOwnership

local function grantPassShopReward(player, data, itemConfig)
    local rewardConfig = itemConfig and itemConfig.Reward
    if type(rewardConfig) ~= "table" then
        return false, tostring(itemConfig and itemConfig.DisplayName or "Shop item") .. " reward is not configured yet."
    end

    local rewardType = rewardConfig.Type
    local amount = math.max(1, math.floor(tonumber(rewardConfig.Amount) or 1))

    if rewardType == PassShopConfig.RewardTypes.ExclusiveRollTicket then
        data.ExclusiveRollTickets = math.max(0, math.floor(tonumber(data.ExclusiveRollTickets) or 0)) + amount
        return true, "ROLLS x" .. tostring(amount), "ROLLS", amount
    end

    if rewardType == PassShopConfig.RewardTypes.PassShopToken then
        local tokenKey = PassShopConfig.TokenDataKey or "PassShopTokens"
        data[tokenKey] = math.max(0, math.floor(tonumber(data[tokenKey]) or 0)) + amount
        return true, "Token x" .. tostring(amount), "Token", amount
    end

    if rewardType == PassShopConfig.RewardTypes.Seed then
        local seedId = rewardConfig.SeedId or rewardConfig.ItemId
        if not (seedId and ItemConfig.Seeds and ItemConfig.Seeds[seedId]) then
            return false, "Seed reward is not configured."
        end

        PlayerDataManager.GiveSeed(player, seedId, amount, true)
        local seedName = tostring((ItemConfig.Seeds[seedId] and ItemConfig.Seeds[seedId].Name) or seedId)
        return true, seedName .. " x" .. tostring(amount), seedName, amount
    end

    if rewardType == PassShopConfig.RewardTypes.Plant then
        local plantId = rewardConfig.PlantId or rewardConfig.ItemId
        if not (plantId and ItemConfig.Plants and ItemConfig.Plants[plantId]) then
            return false, "Plant reward is not configured."
        end

        local mutation = math.max(1, math.floor(tonumber(rewardConfig.Mutation) or 1))
        local wasFirstUnlock = not isMutationUnlocked(data, plantId, mutation)
        PlayerDataManager.GivePlant(player, plantId, amount, mutation, true)
        local plantName = tostring((ItemConfig.Plants[plantId] and ItemConfig.Plants[plantId].Name) or plantId)
        return true, plantName .. " x" .. tostring(amount), plantName, amount, wasFirstUnlock and plantId or nil, mutation
    end

    if rewardType == PassShopConfig.RewardTypes.Chest then
        local chestId = rewardConfig.ChestId or rewardConfig.ItemId
        if not (chestId and ItemConfig.Chests and ItemConfig.Chests[chestId]) then
            return false, "Chest reward is not configured."
        end
        if type(PlayerDataManager.GiveChest) ~= "function" then
            return false, "Chest reward service is unavailable."
        end

        PlayerDataManager.GiveChest(player, chestId, amount)
        local chestName = tostring((ItemConfig.Chests[chestId] and ItemConfig.Chests[chestId].Name) or chestId)
        return true, chestName .. " x" .. tostring(amount), chestName, amount
    end

    return false, "Pass shop reward type is not supported."
end

local function purchasePassShopItem(player, slotName)
    local data = player and sessionData[player.UserId]
    if not data then
        return false, "Data is still loading.", 0
    end

    local tokenKey = PassShopConfig.TokenDataKey or "PassShopTokens"
    local function getPassShopTokenCount()
        return math.max(0, math.floor(tonumber(data[tokenKey]) or 0))
    end

    if dataSaveAllowed[player.UserId] ~= true then
        return false, "Data is still saving. Please try again later.", getPassShopTokenCount()
    end

    local itemConfig = PassShopConfig.GetItem(slotName)
    if not itemConfig then
        return false, "Invalid shop item.", getPassShopTokenCount()
    end

    local passData = normalizePassV1Data(data)
    if itemConfig.PremiumOnly == true and passData.PremiumOwned ~= true and syncPassPremiumOwnership then
        syncPassPremiumOwnership(player, data)
        passData = normalizePassV1Data(data)
    end

    if itemConfig.PremiumOnly == true and passData.PremiumOwned ~= true then
        return false, "Premium pass is required.", getPassShopTokenCount()
    end

    local tokenCount = getPassShopTokenCount()
    data[tokenKey] = tokenCount

    local price = math.max(0, math.floor(tonumber(itemConfig.Price) or 0))
    if price <= 0 then
        return false, "Shop item price is invalid.", tokenCount
    end
    if tokenCount < price then
        return false, "Not enough Token.", tokenCount
    end

    if type(itemConfig.Reward) ~= "table" then
        return false, tostring(itemConfig.DisplayName or "Shop item") .. " reward is not configured yet.", tokenCount
    end

    local snapshot = snapshotReliableRewardState(data)
    data[tokenKey] = tokenCount - price
    local granted, rewardName, effectName, effectAmount, unlockPlantId, unlockMutation = grantPassShopReward(player, data, itemConfig)
    if not granted then
        restoreReliableRewardState(data, snapshot)
        fireInventoryUpdate(player, data)
        return false, rewardName, tokenCount
    end

    local saved = saveReliableRewardMutation(player, data, snapshot, "pass shop purchase")
    if not saved then
        return false, "Save failed. Please try again.", getPassShopTokenCount()
    end

    fireInventoryUpdate(player, data)
    if unlockPlantId then
        playUnlockEffect(player, unlockPlantId, unlockMutation)
    end
    if effectName then
        playPassObtainEffect(player, effectName, effectAmount)
    end
    return true, "Purchased " .. tostring(rewardName) .. ".", data[tokenKey]
end

local function claimPassReward(player, trackKey, tier)
    local data = player and sessionData[player.UserId]
    if not data then
        return false, "Data is still loading."
    end
    if dataSaveAllowed[player.UserId] ~= true then
        return false, "Data is still saving. Please try again later.", normalizePassV1Data(data)
    end

    trackKey = PassRewardConfig.NormalizeTrackKey(trackKey)
    tier = math.floor(tonumber(tier) or 0)
    local rewardConfig = PassRewardConfig.GetReward(trackKey, tier)
    if not rewardConfig then
        return false, "Invalid pass reward."
    end
    if rewardConfig.Claimable == false then
        return false, "This pass tier has no token reward."
    end

    local passData = normalizePassV1Data(data)
    if trackKey == PassRewardConfig.TrackKeys.Premium and passData.PremiumOwned ~= true and syncPassPremiumOwnership then
        syncPassPremiumOwnership(player, data)
        passData = normalizePassV1Data(data)
    end

    if trackKey == PassRewardConfig.TrackKeys.Premium and passData.PremiumOwned ~= true then
        return false, "Premium pass is not owned.", passData
    end

    if tier == PassRewardConfig.RepeatTier then
        if passData.Level < PASS_V1_MAX_LEVEL then
            return false, "Pass level is not enough.", passData
        end

        local repeatRewardAvailable = math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0))
        local repeatClaimed = getPassRepeatClaimedCount(passData, trackKey)
        if repeatClaimed >= repeatRewardAvailable then
            return false, "No repeat reward is available.", passData
        end

        local snapshot = snapshotReliableRewardState(data)
        local success, rewardName, effectName, effectAmount, unlockPlantId, unlockMutation = grantPassReward(player, data, rewardConfig)
        if not success then
            restoreReliableRewardState(data, snapshot)
            fireInventoryUpdate(player, data)
            return false, rewardName, passData
        end

        setPassRepeatClaimedCount(passData, trackKey, repeatClaimed + 1)

        local saved = saveReliableRewardMutation(player, data, snapshot, "repeat pass reward claim")
        if not saved then
            local restoredPassData = firePassDataUpdate(player, data)
            return false, "Save failed. Please try again.", restoredPassData
        end

        fireInventoryUpdate(player, data)
        passData = firePassDataUpdate(player, data)
        if unlockPlantId then
            playUnlockEffect(player, unlockPlantId, unlockMutation)
        end
        if effectName then
            playPassObtainEffect(player, effectName, effectAmount)
        end
        return true, "Claimed " .. tostring(rewardName), passData
    end

    if passData.Level < tier then
        return false, "Pass level is not enough.", passData
    end

    local claimedMap = getPassClaimedMap(passData, trackKey)
    local tierKey = tostring(tier)
    if claimedMap[tierKey] == true then
        return false, "Reward already claimed.", passData
    end

    local snapshot = snapshotReliableRewardState(data)
    local success, rewardName, effectName, effectAmount, unlockPlantId, unlockMutation = grantPassReward(player, data, rewardConfig)
    if not success then
        restoreReliableRewardState(data, snapshot)
        fireInventoryUpdate(player, data)
        return false, rewardName, passData
    end

    claimedMap[tierKey] = true

    local saved = saveReliableRewardMutation(player, data, snapshot, "pass reward claim")
    if not saved then
        local restoredPassData = firePassDataUpdate(player, data)
        return false, "Save failed. Please try again.", restoredPassData
    end

    fireInventoryUpdate(player, data)
    passData = firePassDataUpdate(player, data)
    if unlockPlantId then
        playUnlockEffect(player, unlockPlantId, unlockMutation)
    end
    if effectName then
        playPassObtainEffect(player, effectName, effectAmount)
    end
    return true, "Claimed " .. tostring(rewardName), passData
end

local passQuestClaimingPlayers = {}

local function buildPassQuestState(player)
    local data = player and sessionData[player.UserId]
    if not data then
        return nil
    end

    ensureEnterGamePassQuest(data)
    local questData = normalizePassQuestV1Data(data)
    local now = os.time()
    local resetAt = PassQuestConfig.GetNextUtcMidnight(now)
    local taskStates = {}

    for _, taskConfig in ipairs(PassQuestConfig.Tasks) do
        local taskId = taskConfig.Id
        local target = math.max(1, math.floor(tonumber(taskConfig.Target) or 1))
        local progress = math.clamp(math.floor(tonumber(questData.Progress[taskId]) or 0), 0, target)
        local claimed = questData.Claimed[taskId] == true

        taskStates[taskConfig.Slot] = {
            Slot = taskConfig.Slot,
            Id = taskId,
            DisplayName = taskConfig.DisplayName,
            RewardExp = math.max(0, math.floor(tonumber(taskConfig.RewardExp) or 0)),
            Target = target,
            Progress = progress,
            Claimed = claimed,
            CanClaim = not claimed and progress >= target,
        }
    end

    return {
        ServerTime = now,
        DayKey = questData.DayKey,
        ResetAtUtc = resetAt,
        ResetRemainingSeconds = math.max(0, resetAt - now),
        Tasks = taskStates,
    }
end

firePassQuestState = function(player)
    local state = buildPassQuestState(player)
    if state then
        getUpdatePassQuestStateRemote():FireClient(player, state)
    end
end

addPassQuestProgress = function(player, taskId, amount, suppressUpdate)
    local data = player and sessionData[player.UserId]
    if not data then
        return nil
    end

    taskId = PassQuestConfig.NormalizeTaskId(taskId)
    local taskConfig = taskId and PassQuestConfig.GetTaskById(taskId)
    if not taskConfig then
        return nil
    end

    local questData = normalizePassQuestV1Data(data)
    local target = math.max(1, math.floor(tonumber(taskConfig.Target) or 1))
    local current = math.clamp(math.floor(tonumber(questData.Progress[taskId]) or 0), 0, target)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 or current >= target then
        return current, target, false
    end

    local nextValue = math.clamp(current + amount, 0, target)
    if nextValue == current then
        return current, target, false
    end

    questData.Progress[taskId] = nextValue
    markSessionDataChanged(player, "pass quest progress")
    if not suppressUpdate then
        firePassQuestState(player)
    end

    return nextValue, target, true
end

local function claimPassQuest(player, taskId)
    local data = player and sessionData[player.UserId]
    if not data then
        return false, "Data is still loading.", nil
    end
    if dataSaveAllowed[player.UserId] ~= true then
        return false, "Data is still saving. Please try again later.", buildPassQuestState(player)
    end

    taskId = PassQuestConfig.NormalizeTaskId(taskId)
    local taskConfig = taskId and PassQuestConfig.GetTaskById(taskId)
    if not taskConfig then
        return false, "Invalid quest.", buildPassQuestState(player)
    end

    if passQuestClaimingPlayers[player] then
        return false, "Claim is already processing.", buildPassQuestState(player)
    end

    passQuestClaimingPlayers[player] = true
    ensureEnterGamePassQuest(data)
    local questData = normalizePassQuestV1Data(data)
    local target = math.max(1, math.floor(tonumber(taskConfig.Target) or 1))
    local progress = math.clamp(math.floor(tonumber(questData.Progress[taskId]) or 0), 0, target)

    if questData.Claimed[taskId] == true then
        passQuestClaimingPlayers[player] = nil
        return false, "Quest already claimed.", buildPassQuestState(player)
    end

    if progress < target then
        passQuestClaimingPlayers[player] = nil
        return false, "Quest is not complete.", buildPassQuestState(player)
    end

    local snapshot = snapshotReliableRewardState(data)
    questData.Claimed[taskId] = true
    local rewardExp = math.max(0, math.floor(tonumber(taskConfig.RewardExp) or 0))
    if rewardExp > 0 then
        addPassExpToData(data, rewardExp)
    end

    local saved = saveReliableRewardMutation(player, data, snapshot, "pass quest claim")
    if not saved then
        local restoredState = buildPassQuestState(player)
        firePassDataUpdate(player, data)
        getUpdatePassQuestStateRemote():FireClient(player, restoredState)
        passQuestClaimingPlayers[player] = nil
        return false, "Save failed. Please try again.", restoredState
    end

    local state = buildPassQuestState(player)
    if rewardExp > 0 then
        firePassDataUpdate(player, data)
    end
    getUpdatePassQuestStateRemote():FireClient(player, state)
    passQuestClaimingPlayers[player] = nil

    return true, "Claimed " .. tostring(rewardExp) .. " EXP.", state
end

syncPassPremiumOwnership = function(player, data)
    if not (player and type(data) == "table") then
        return false
    end

    local passData = normalizePassV1Data(data)
    if passData.PremiumOwned == true then
        return false
    end

    local gamePassId = tonumber(PassRewardConfig.PremiumGamePassId)
    if not (gamePassId and gamePassId > 0) then
        return false
    end

    local ok, ownsPass = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end)
    if not ok then
        warn("[PlayerDataManager] Failed to check premium pass ownership for " .. player.Name .. ": " .. tostring(ownsPass))
        return false
    end

    if ownsPass == true then
        passData.PremiumOwned = true
        getUpdatePassDataRemote():FireClient(player, passData, PASS_V1_EXP_PER_LEVEL, PASS_V1_MAX_LEVEL)
        return true
    end

    return false
end

local function onPlayerAdded(player)
    local isLoaded = false

    task.spawn(function()
        local success, savedData, loadErr = acquireSessionData(player)
        if not isLoaded then
            isLoaded = true
            if success then
                if savedData then
                savedData.Hotbar = {"Tool_Shovel", "System_Backpack", "Tool_WeaponBlock"}
                if type(savedData.Inventory) ~= "table" then savedData.Inventory = { Seeds = {}, Plants = {}, Chests = {}, Titles = {} } end
                if type(savedData.Inventory.Seeds) ~= "table" then savedData.Inventory.Seeds = {} end
                if type(savedData.Inventory.Plants) ~= "table" then savedData.Inventory.Plants = {} end
                if type(savedData.Inventory.Chests) ~= "table" then savedData.Inventory.Chests = {} end
                if type(savedData.Inventory.Titles) ~= "table" then savedData.Inventory.Titles = {} end
                if type(savedData.EquippedTitle) ~= "string" then savedData.EquippedTitle = "" end
                normalizeTitleData(savedData)
                if not savedData.PlantedPlants then savedData.PlantedPlants = {} end
                if not savedData.CombatPlants then savedData.CombatPlants = {} end
                if type(savedData.UnlockedSeeds) ~= "table" then savedData.UnlockedSeeds = { ["Peashooter"] = true } end
                if type(savedData.UnlockedMutations) ~= "table" then savedData.UnlockedMutations = {} end
                backfillUnlockedMutationsFromOwnedPlants(savedData)
                if type(savedData.ClaimedAchieve) ~= "table" then savedData.ClaimedAchieve = {} end
                if type(savedData.NewbieGiftStartTime) ~= "number" then savedData.NewbieGiftStartTime = 0 end
                if type(savedData.NewbieGiftPurchased) ~= "boolean" then savedData.NewbieGiftPurchased = false end
                if type(savedData.ChatGiftClaimed_V1) ~= "boolean" then savedData.ChatGiftClaimed_V1 = false end
                if type(savedData.ExclusiveRollPity_Rotobaga) ~= "number" then savedData.ExclusiveRollPity_Rotobaga = 0 end
                if type(savedData.ExclusiveRollPurchaseCount) ~= "number" then savedData.ExclusiveRollPurchaseCount = 0 end
                if type(savedData.ExclusiveRollTotalRolls) ~= "number" then savedData.ExclusiveRollTotalRolls = 0 end
                if type(savedData.ExclusiveRollTickets) ~= "number" then savedData.ExclusiveRollTickets = 0 end
                if type(savedData.PassShopTokens) ~= "number" then savedData.PassShopTokens = 0 end
                if type(savedData.PendingGifts) ~= "table" then savedData.PendingGifts = {} end
                if type(savedData.ClaimedGiftIds) ~= "table" then savedData.ClaimedGiftIds = {} end
                if type(savedData.RankingSeasonBaselines) ~= "table" then savedData.RankingSeasonBaselines = {} end
                if type(savedData.LastSeenNoticeId) ~= "string" then savedData.LastSeenNoticeId = "" end
                normalizeProcessedReceipts(savedData)
                if type(savedData.RollTickets) ~= "table" then savedData.RollTickets = {0, 0} end
                if type(savedData.OnlineRewardDayKey) ~= "string" then savedData.OnlineRewardDayKey = "" end
                if type(savedData.OnlineRewardClaimed) ~= "table" then savedData.OnlineRewardClaimed = {} end
                if type(savedData.OnlineRewardCycleStartedAt) ~= "number" then savedData.OnlineRewardCycleStartedAt = 0 end
                if type(savedData.OnlineRewardRefreshAt) ~= "number" then savedData.OnlineRewardRefreshAt = 0 end
                normalizePassV1Data(savedData)
                normalizePassQuestV1Data(savedData)
                ensureEnterGamePassQuest(savedData)
                syncPassPremiumOwnership(player, savedData)
                savedData[SAVE_VERSION_KEY] = getSaveVersion(savedData)
                savedData[LAST_SAVE_TIME_KEY] = tonumber(savedData[LAST_SAVE_TIME_KEY]) or 0
                applyCurrentSessionLock(savedData, os.time())

                -- 兼容老玩家数据
                if type(savedData.OnlineRollTimer) ~= "number" then savedData.OnlineRollTimer = 300 end
                local hadCompletedLegacySignIn = type(savedData.SignInTier) ~= "number"
                    and (tonumber(savedData.SignInDays) or 0) >= SignInRewardConfig.DaysPerTier
                -- 强制重置所有老玩家的七日签到进度（只触发一次数）
                if not savedData.SignInReset_V1 then
                    savedData.SignInDays = 0 -- 签到天数归零
                    savedData.LastSignInTime = 0 -- 签到时间归零
                    savedData.SignInReset_V1 = true -- 打上标签记，防止下次数登录再次数被重置
                    print("[Data] Player " .. player.Name .. " seven-day sign-in progress forcibly reset!")
                end
                if type(savedData.SignInDays) ~= "number" then savedData.SignInDays = 0 end
                if type(savedData.LastSignInTime) ~= "number" then savedData.LastSignInTime = 0 end
                if type(savedData.LastSignInPurchaseTime) ~= "number" then savedData.LastSignInPurchaseTime = 0 end
                if type(savedData.SignInTier) ~= "number" then
                    if hadCompletedLegacySignIn then
                        savedData.SignInTier = 2
                        savedData.SignInDays = 0
                    else
                        savedData.SignInTier = 1
                    end
                else
                    savedData.SignInTier = SignInRewardConfig.NormalizeTier(savedData.SignInTier)
                    if savedData.SignInDays >= SignInRewardConfig.DaysPerTier then
                        savedData.SignInTier = SignInRewardConfig.GetNextTier(savedData.SignInTier)
                        savedData.SignInDays = 0
                    end
                end
                sessionData[player.UserId] = savedData
                dataSaveAllowed[player.UserId] = true
                print("[Data] Player " .. player.Name .. " data loaded successfully!")

                if (savedData.TutorialStep or 0) == 0 then
                    AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 1, "Step_1_Enter_Game")
                end
            else
                if loadErr == "active_session" then
                    kickForActiveSession(player, loadErr)
                else
                    kickForDataLoadFailure(player, loadErr or "missing session data after acquire")
                end
            end
            else
                if loadErr == "active_session" then
                    kickForActiveSession(player, loadErr)
                else
                    kickForDataLoadFailure(player, loadErr or savedData)
                end
            end
        end
    end)

    task.delay(25, function()
        if not isLoaded then
            isLoaded = true
            kickForDataLoadFailure(player, "DataStore session acquire timed out")
        end
    end)
end

local function onPlayerRemoving(player)
    local userId = player.UserId
    local dataToSave = sessionData[userId]
    if dataToSave then
        sessionData[userId] = nil
        x2SunOwnershipCache[userId] = nil
        x2SunOwnershipCacheTime[userId] = nil
        passQuestClaimingPlayers[player] = nil
        local canSave = dataSaveAllowed[userId] == true
        dataSaveAllowed[userId] = nil
        if not canSave then
            saveQueueState[userId] = nil
            return
        end

        finalSavePending[userId] = true
        local ok, success, saveErr = pcall(function()
            return runQueuedSave(userId, dataToSave, {
                RespectMinInterval = false,
                ReleaseSession = true,
            })
        end)
        if not ok then
            warn("[Data] Final save crashed for " .. player.Name .. ": " .. tostring(success))
        elseif not success and saveErr ~= "stale_session" then
            warn("[Data] Final save failed for " .. player.Name .. ": " .. tostring(saveErr))
        end
        finalSavePending[userId] = nil
        saveQueueState[userId] = nil
    end
end

function PlayerDataManager.Init()
    startGlobalOnlineRollTimer()
    startPassQuestOnlineTimer()
    startSessionHeartbeatLoop()
    startAutoSaveLoop()

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function() onPlayerAdded(player) end)
    end
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
        if passId == X2_SUN_GAME_PASS_ID then
            if wasPurchased then
                x2SunOwnershipCache[player.UserId] = true
                x2SunOwnershipCacheTime[player.UserId] = os.clock()
            else
                x2SunOwnershipCache[player.UserId] = nil
                x2SunOwnershipCacheTime[player.UserId] = nil
            end
        elseif tonumber(passId) == tonumber(PassRewardConfig.PremiumGamePassId) and wasPurchased then
            local data = sessionData[player.UserId]
            if data then
                local passData = normalizePassV1Data(data)
                passData.PremiumOwned = true
                getUpdatePassDataRemote():FireClient(player, passData, PASS_V1_EXP_PER_LEVEL, PASS_V1_MAX_LEVEL)

                local saved, saveErr = savePlayerSession(player, {
                    Deferred = true,
                    Context = "premium pass purchase",
                })
                if not saved and saveErr ~= "stale_session" then
                    warn("[PlayerDataManager] Failed to save premium pass purchase for " .. player.Name .. ": " .. tostring(saveErr))
                end
            end
        end
    end)

    game:BindToClose(function()
        local pendingSaves = 0

        for _, player in ipairs(Players:GetPlayers()) do
            if dataSaveAllowed[player.UserId] == true and sessionData[player.UserId] then
                pendingSaves += 1
                task.spawn(function()
                    local ok, success, saveErr = pcall(function()
                        return savePlayerSession(player, {
                            ReleaseSession = true,
                        })
                    end)
                    if not ok then
                        warn("[Data] BindToClose save crashed for " .. player.Name .. ": " .. tostring(success))
                    elseif not success and saveErr ~= "stale_session" then
                        warn("[Data] BindToClose save failed for " .. player.Name .. ": " .. tostring(saveErr))
                    end
                    pendingSaves -= 1
                end)
            end
        end

        local deadline = os.clock() + BIND_TO_CLOSE_TIMEOUT
        while (pendingSaves > 0 or next(finalSavePending) ~= nil) and os.clock() < deadline do
            task.wait(0.1)
        end
    end)

    local getPlayerDataRF = Instance.new("RemoteFunction")
    getPlayerDataRF.Name = "GetPlayerDataRF"
    getPlayerDataRF.Parent = ReplicatedStorage
    getPlayerDataRF.OnServerInvoke = function(player)
        while not sessionData[player.UserId] do task.wait(0.1) end
        syncPassPremiumOwnership(player, sessionData[player.UserId])
        return sessionData[player.UserId]
    end

    if not ReplicatedStorage:FindFirstChild("UpdateInventoryRE") then
        local updateInventoryRE = Instance.new("RemoteEvent")
        updateInventoryRE.Name = "UpdateInventoryRE"
        updateInventoryRE.Parent = ReplicatedStorage
    end

    getUpdatePassDataRemote()
    getOrCreateRemoteFunction(PassRewardConfig.RemoteName).OnServerInvoke = function(player, trackKey, tier)
        return claimPassReward(player, trackKey, tier)
    end
    getOrCreateRemoteFunction(PassShopConfig.RemoteName).OnServerInvoke = function(player, slotName)
        return purchasePassShopItem(player, slotName)
    end
    getUpdatePassQuestStateRemote()
    getOrCreateRemoteFunction(PassQuestConfig.StateRemoteName).OnServerInvoke = function(player)
        while not sessionData[player.UserId] do task.wait(0.1) end
        return buildPassQuestState(player)
    end
    getOrCreateRemoteFunction(PassQuestConfig.ClaimRemoteName).OnServerInvoke = function(player, taskId)
        return claimPassQuest(player, taskId)
    end
    getOrCreateRemoteFunction(NoticeConfig.StateRemoteName or "GetNoticeReadStateRF").OnServerInvoke = function(player)
        return buildNoticeReadState(player)
    end
    getOrCreateRemoteFunction(NoticeConfig.MarkSeenRemoteName or "MarkNoticeSeenRF").OnServerInvoke = function(player, noticeId)
        return markLatestNoticeSeen(player, noticeId)
    end

    if not ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE") then
        local animRE = Instance.new("RemoteEvent")
        animRE.Name = "PlayUnlockAnimRE"
        animRE.Parent = ReplicatedStorage
    end

    if not ReplicatedStorage:FindFirstChild("UpdateTutorialRE") then
        local tutorialRE = Instance.new("RemoteEvent")
        tutorialRE.Name = "UpdateTutorialRE"
        tutorialRE.Parent = ReplicatedStorage
        tutorialRE.OnServerEvent:Connect(function(plr, step)
                local data = sessionData[plr.UserId]
                if data then
                    if step > (data.TutorialStep or 0) then
                        data.TutorialStep = step
                        markSessionDataChanged(plr, "tutorial progress")
                    end
                end
            end)
    end

    if not ReplicatedStorage:FindFirstChild("PlayObtainEffectRE") then
        local effectRE = Instance.new("RemoteEvent")
        effectRE.Name = "PlayObtainEffectRE"
        effectRE.Parent = ReplicatedStorage
    end

    -- 处理服务端抽奖扣除与发奖逻辑
    local performRollRF = ReplicatedStorage:FindFirstChild("PerformRollRF")
    if not performRollRF then
        performRollRF = Instance.new("RemoteFunction")
        performRollRF.Name = "PerformRollRF"
        performRollRF.Parent = ReplicatedStorage
    end

    performRollRF.OnServerInvoke = function(player, tabIndex)
        if RollConfig.Enabled == false then
            return false, RollConfig.DisabledMessage or "Roll lottery is currently unavailable."
        end

        tabIndex = tonumber(tabIndex) or 1
        if tabIndex ~= 1 and tabIndex ~= 2 then
            return false, "Invalid roll tab"
        end

        local data = sessionData[player.UserId]
        if not data then return false, "Data is still loading..." end
        if dataSaveAllowed[player.UserId] ~= true then
            return false, "Data is still saving. Please try again later."
        end
        if not data.RollTickets then data.RollTickets = {0, 0} end
        local snapshot = snapshotReliableRewardState(data)

        -- 兼容旧数据/异常数据里 RollTickets 使用字符串键的情况，避免误判为 0 后先扣阳光
        local tickets = tonumber(data.RollTickets[tabIndex]) or tonumber(data.RollTickets[tostring(tabIndex)]) or 0
        data.RollTickets[tabIndex] = tickets
        data.RollTickets[tostring(tabIndex)] = nil

        if tickets > 0 then
            -- 1. 永远优先扣除对应池子的免费次数；只有没有免费次数时才会进入阳光扣费分支
            data.RollTickets[tabIndex] = tickets - 1
        elseif tabIndex == 1 then
            -- 第 1 页没有免费次数时间，允许消耗 200K 阳光继续抽奖
            if (data.Coins or 0) < ROLL_TAB1_CASH_COST then
                return false, "Not enough Sun!"
            end
            data.Coins -= ROLL_TAB1_CASH_COST
        else
            return false, "Not enough roll attempts!"
        end

        -- 2. 获取真正的随机奖励
        local RollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RollConfig"))
        local finalPrize = RollConfig.GetRandomPrize(tabIndex)

        -- 3. 发放种子奖励 (传入 suppressEffect = true，抑制立即弹出提示，让客户端在动画播完后再自己弹)
        PlayerDataManager.GiveSeed(player, finalPrize, 1, true)

        local saved = saveReliableRewardMutation(player, data, snapshot, "roll reward")
        if not saved then
            return false, "Save failed. Please try again."
        end

        -- 4. 同步最新数据（更新 UI 上的次数和红点）
        fireInventoryUpdate(player, data)

        -- 5. 将结果返回给客户端用于播放转盘动画
        return true, finalPrize
    end
    local startNewbieGiftRF = ReplicatedStorage:FindFirstChild("StartNewbieGiftRF")
    if not startNewbieGiftRF then
        startNewbieGiftRF = Instance.new("RemoteFunction")
        startNewbieGiftRF.Name = "StartNewbieGiftRF"
        startNewbieGiftRF.Parent = ReplicatedStorage
    end
    startNewbieGiftRF.OnServerInvoke = function(player)
        local data = sessionData[player.UserId]
        -- 如果玩家存在，且计时未开始，则记录当前真实服务器时间
        if data and data.NewbieGiftStartTime == 0 then
            data.NewbieGiftStartTime = os.time()

            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

            markSessionDataChanged(player, "newbie gift timer")
            return true, data.NewbieGiftStartTime
        end
        return false, data and data.NewbieGiftStartTime or 0
    end
end

function PlayerDataManager.GetPlayerData(player) return sessionData[player.UserId] end

function PlayerDataManager.AddPassExp(player, amount)
    local data = player and sessionData[player.UserId]
    if not data then
        return nil
    end

    local passData = normalizePassV1Data(data)
    amount = math.max(0, math.floor(tonumber(amount) or 0))

    if amount > 0 then
        passData.Exp += amount

        while passData.Level < PASS_V1_MAX_LEVEL and passData.Exp >= getPassExpRequired(passData.Level) do
            passData.Exp -= getPassExpRequired(passData.Level)
            passData.Level += 1
        end

        if passData.Level >= PASS_V1_MAX_LEVEL then
            passData.Level = PASS_V1_MAX_LEVEL
            while passData.Exp >= getPassExpRequired(passData.Level) do
                passData.Exp -= getPassExpRequired(passData.Level)
                passData.RepeatRewardAvailable = math.max(0, math.floor(tonumber(passData.RepeatRewardAvailable) or 0)) + 1
            end
        end
    elseif passData.Level >= PASS_V1_MAX_LEVEL then
        passData.Exp = math.clamp(passData.Exp, 0, getPassExpRequired(passData.Level) - 1)
    end

    local updatePassDataRE = getUpdatePassDataRemote()
    updatePassDataRE:FireClient(player, passData, PASS_V1_EXP_PER_LEVEL, PASS_V1_MAX_LEVEL)

    if amount > 0 then
        markSessionDataChanged(player, "pass exp")
    end

    return passData
end

function PlayerDataManager.AddPassQuestProgress(player, taskId, amount)
    return addPassQuestProgress(player, taskId, amount)
end

function PlayerDataManager.GetPassQuestState(player)
    return buildPassQuestState(player)
end

function PlayerDataManager.ForceSave(player)
    return savePlayerSession(player)
end

function PlayerDataManager.RequestSave(player, context)
    return requestDeferredSave(player, context)
end

function PlayerDataManager.HasProcessedReceipt(player, receiptKey)
    local data = player and sessionData[player.UserId]
    if not data then
        return false
    end

    normalizeProcessedReceipts(data)
    return data.ProcessedReceipts[receiptKey] == true
end

function PlayerDataManager.MarkReceiptProcessed(player, receiptKey)
    local data = player and sessionData[player.UserId]
    return markReceiptProcessedInData(data, receiptKey)
end

function PlayerDataManager.IsDataSafeToSave(player)
    return player ~= nil and dataSaveAllowed[player.UserId] == true
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function addPlantToData(data, plantId, amount, mutationLevel)
    data.Inventory = data.Inventory or { Seeds = {}, Plants = {}, Chests = {}, Titles = {} }
    data.Inventory.Seeds = data.Inventory.Seeds or {}
    data.Inventory.Plants = data.Inventory.Plants or {}
    data.Inventory.Chests = data.Inventory.Chests or {}
    data.Inventory.Titles = data.Inventory.Titles or {}
    mutationLevel = normalizeMutationLevel(mutationLevel)

    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and normalizeMutationLevel(plantData.Mutation or 1) == mutationLevel then
            plantData.Quantity += amount
            plantData.Mutation = mutationLevel
            found = true
            break
        end
    end

    if not found then
        table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount, Mutation = mutationLevel })
    end

    if data.Hotbar then
        local itemKey = "Plant_" .. plantId .. "_" .. mutationLevel
        local alreadyEquipped = false
        for _, v in ipairs(data.Hotbar) do
            if v == itemKey then
                alreadyEquipped = true
                break
            end
        end
        if not alreadyEquipped and #data.Hotbar < 9 then
            table.insert(data.Hotbar, itemKey)
        end
    end

    markMutationUnlocked(data, plantId, mutationLevel)
end

function PlayerDataManager.GrantSavedChatGift(player, claimFlag, plantId, plantAmount, mutationLevel, coins)
    local userId = player and player.UserId
    local data = userId and sessionData[userId]
    if not data then
        return false, "Gift failed: data is still loading."
    end
    if dataSaveAllowed[userId] ~= true then
        return false, "Gift failed: data is still loading. Please try again later."
    end
    if data[claimFlag] then
        return false, "You have already claimed this gift."
    end

    mutationLevel = normalizeMutationLevel(mutationLevel)
    local wasFirstUnlock = not isMutationUnlocked(data, plantId, mutationLevel)

    local dataForGiftSave = deepCopy(data)
    dataForGiftSave[claimFlag] = true
    addPlantToData(dataForGiftSave, plantId, plantAmount, mutationLevel)
    dataForGiftSave.Coins = (tonumber(dataForGiftSave.Coins) or 0) + coins

    local saved = runQueuedSave(userId, dataForGiftSave, {
        RespectMinInterval = false,
    })
    if not saved then
        return false, "Gift failed: please try again later."
    end

    data[claimFlag] = true
    addPlantToData(data, plantId, plantAmount, mutationLevel)
    data.Coins = (tonumber(data.Coins) or 0) + coins
    data[SAVE_VERSION_KEY] = dataForGiftSave[SAVE_VERSION_KEY]
    data[LAST_SAVE_TIME_KEY] = dataForGiftSave[LAST_SAVE_TIME_KEY]

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    if wasFirstUnlock then
        local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
        if playUnlockAnimRE then
            playUnlockAnimRE:FireClient(player, plantId, mutationLevel)
        end
    end

    return true
end

function PlayerDataManager.GrantSavedPlantBundle(player, claimFlag, rewards)
    local userId = player and player.UserId
    local data = userId and sessionData[userId]
    if not data then
        return false, "Gift failed: data is still loading."
    end
    if dataSaveAllowed[userId] ~= true then
        return false, "Gift failed: data is still loading. Please try again later."
    end
    if data[claimFlag] then
        return false, "You have already claimed this code."
    end
    if type(rewards) ~= "table" or #rewards <= 0 then
        return false, "Gift failed: reward config is empty."
    end

    local normalizedRewards = {}
    local firstUnlocks = {}
    for _, reward in ipairs(rewards) do
        if type(reward) ~= "table" or type(reward.PlantId) ~= "string" or reward.PlantId == "" then
            return false, "Gift failed: reward config is invalid."
        end

        local plantId = reward.PlantId
        local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))
        local mutationLevel = normalizeMutationLevel(reward.Mutation)

        table.insert(normalizedRewards, {
            PlantId = plantId,
            Amount = amount,
            Mutation = mutationLevel,
        })

        if not isMutationUnlocked(data, plantId, mutationLevel) then
            table.insert(firstUnlocks, {
                PlantId = plantId,
                Mutation = mutationLevel,
            })
        end
    end

    local dataForBundleSave = deepCopy(data)
    dataForBundleSave[claimFlag] = true
    for _, reward in ipairs(normalizedRewards) do
        addPlantToData(dataForBundleSave, reward.PlantId, reward.Amount, reward.Mutation)
    end

    local saved = runQueuedSave(userId, dataForBundleSave, {
        RespectMinInterval = false,
    })
    if not saved then
        return false, "Gift failed: please try again later."
    end

    data[claimFlag] = true
    for _, reward in ipairs(normalizedRewards) do
        addPlantToData(data, reward.PlantId, reward.Amount, reward.Mutation)
    end
    data[SAVE_VERSION_KEY] = dataForBundleSave[SAVE_VERSION_KEY]
    data[LAST_SAVE_TIME_KEY] = dataForBundleSave[LAST_SAVE_TIME_KEY]

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
    if playUnlockAnimRE then
        for _, unlock in ipairs(firstUnlocks) do
            playUnlockAnimRE:FireClient(player, unlock.PlantId, unlock.Mutation)
        end
    end

    return true
end

function PlayerDataManager.WaitForPlayerData(player, timeout)
    timeout = timeout or 10
    local startTime = os.clock()

    while player and player.Parent do
        local data = sessionData[player.UserId]
        if data then
            return data
        end

        if os.clock() - startTime >= timeout then
            break
        end

        task.wait(0.1)
    end

    return sessionData[player.UserId]
end

function PlayerDataManager.ClearTransientPlotData(player)
    local data = sessionData[player.UserId]
    if not data then return end
    data.PlantedPlants = {}
    data.CombatPlants = {}
    markSessionDataChanged(player, "clear plot data")
end

function PlayerDataManager.UpdatePlantedPlant(player, soilName, seedId, plantedTime)
    local data = sessionData[player.UserId]
    if not data then return end

    local existingPlant = data.PlantedPlants[soilName]
    local mutationLevel = existingPlant and normalizeMutationLevel(existingPlant.Mutation)

    if not mutationLevel then
        mutationLevel = 1
        if ItemConfig.MutationProb then
            local totalWeight = 0
            for _, weight in pairs(ItemConfig.MutationProb) do totalWeight += weight end
            local roll = math.random() * totalWeight
            local currentWeight = 0
            for level, weight in pairs(ItemConfig.MutationProb) do
                currentWeight += weight
                if roll <= currentWeight then
                    mutationLevel = level
                    break
                end
            end
        end
    end

    data.PlantedPlants[soilName] = {
        SeedId = seedId,
        PlantedTime = plantedTime,
        Mutation = mutationLevel
    }
    markSessionDataChanged(player, "planted plant update")
end

function PlayerDataManager.MarkPlantAsDropped(player, soilName)
    local data = sessionData[player.UserId]
    if not data or not data.PlantedPlants[soilName] then return end
    data.PlantedPlants[soilName].HasDropped = true
    markSessionDataChanged(player, "plant drop state")
end

function PlayerDataManager.RemovePlantedPlant(player, soilName)
    local data = sessionData[player.UserId]
    if not data then return end
    data.PlantedPlants[soilName] = nil
    markSessionDataChanged(player, "planted plant removal")
end

-- 增加了一个可选参数 suppressEffect
local MAX_HOTBAR_ITEMS = 10

local function ensureInventoryTables(data)
    if not data then return nil end
    if type(data.Inventory) ~= "table" then
        data.Inventory = { Seeds = {}, Plants = {}, Chests = {}, Titles = {} }
    end
    if type(data.Inventory.Seeds) ~= "table" then data.Inventory.Seeds = {} end
    if type(data.Inventory.Plants) ~= "table" then data.Inventory.Plants = {} end
    if type(data.Inventory.Chests) ~= "table" then data.Inventory.Chests = {} end
    if type(data.Inventory.Titles) ~= "table" then data.Inventory.Titles = {} end
    if type(data.EquippedTitle) ~= "string" then data.EquippedTitle = "" end
    return data.Inventory
end

local function addOrReplaceHotbarItem(data, compositeId, replaceWhenFull)
    if not data then return false end
    if type(data.Hotbar) ~= "table" then data.Hotbar = {} end

    for _, existingId in ipairs(data.Hotbar) do
        if existingId == compositeId then
            return true
        end
    end

    if #data.Hotbar < MAX_HOTBAR_ITEMS then
        table.insert(data.Hotbar, compositeId)
        return true
    end

    if replaceWhenFull then
        for i = #data.Hotbar, 1, -1 do
            if data.Hotbar[i] ~= "System_Backpack" then
                data.Hotbar[i] = compositeId
                return true
            end
        end
    end

    return false
end

function PlayerDataManager.GiveChest(player, chestId, amount, autoEquip)
    local data = sessionData[player.UserId]
    if not data then return false end
    if not (ItemConfig.Chests and ItemConfig.Chests[chestId]) then
        warn("[PlayerDataManager] Unknown chest id: " .. tostring(chestId))
        return false
    end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local inventory = ensureInventoryTables(data)

    local found = false
    for _, chestData in ipairs(inventory.Chests) do
        if chestData.ID == chestId then
            chestData.Quantity += amount
            found = true
            break
        end
    end

    if not found then
        table.insert(inventory.Chests, { ID = chestId, Quantity = amount })
    end

    local compositeId = "Chest_" .. chestId
    addOrReplaceHotbarItem(data, compositeId, autoEquip == true)

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    if autoEquip then
        local forceSelectRE = ReplicatedStorage:FindFirstChild("ForceSelectRE")
        if forceSelectRE then
            task.delay(0.1, function()
                if player and player.Parent then
                    forceSelectRE:FireClient(player, compositeId)
                end
            end)
        end
    end

    markSessionDataChanged(player, "chest grant")
    return true, compositeId
end

function PlayerDataManager.ConsumeChest(player, chestId, amount)
    local data = sessionData[player.UserId]
    local inventory = ensureInventoryTables(data)
    if not inventory then return false end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    for i, chestData in ipairs(inventory.Chests) do
        if chestData.ID == chestId then
            if chestData.Quantity < amount then
                return false
            end

            chestData.Quantity -= amount
            if chestData.Quantity <= 0 then
                table.remove(inventory.Chests, i)
                if data.Hotbar then
                    for j = #data.Hotbar, 1, -1 do
                        local parts = string.split(data.Hotbar[j], "_")
                        if parts[1] == "Chest" and parts[2] == chestId then
                            table.remove(data.Hotbar, j)
                        end
                    end
                end
            end

            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
            markSessionDataChanged(player, "chest consume")
            return true
        end
    end

    return false
end

local function playerOwnsTitle(data, titleId)
    if type(titleId) ~= "string" or titleId == "" then
        return false
    end

    normalizeTitleData(data)
    local titles = data and data.Inventory and data.Inventory.Titles
    if type(titles) ~= "table" then
        return false
    end

    for _, titleData in ipairs(titles) do
        if type(titleData) == "table" and titleData.ID == titleId then
            return true
        end
    end

    return false
end

function PlayerDataManager.GiveTitle(player, titleId)
    local data = player and sessionData[player.UserId]
    if not data then
        return false, "Data is still loading."
    end
    if not TitleConfig.GetTitle(titleId) then
        warn("[PlayerDataManager] Unknown title id: " .. tostring(titleId))
        return false, "Unknown title."
    end

    normalizeTitleData(data)
    if playerOwnsTitle(data, titleId) then
        return true, "Already owned."
    end

    table.insert(data.Inventory.Titles, { ID = titleId })

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    markSessionDataChanged(player, "title grant")
    return true, "Title granted."
end

function PlayerDataManager.ToggleTitle(player, titleId)
    local data = player and sessionData[player.UserId]
    if not data then
        return false, "", "Data is still loading."
    end
    if not TitleConfig.GetTitle(titleId) then
        return false, data.EquippedTitle or "", "Unknown title."
    end

    normalizeTitleData(data)
    if not playerOwnsTitle(data, titleId) then
        return false, data.EquippedTitle or "", "You do not own this title."
    end

    if data.EquippedTitle == titleId then
        data.EquippedTitle = ""
    else
        data.EquippedTitle = titleId
    end

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    markSessionDataChanged(player, "title equip")
    return true, data.EquippedTitle, "Title updated."
end

function PlayerDataManager.GetEquippedTitle(player)
    local data = player and sessionData[player.UserId]
    if not data then
        return ""
    end

    normalizeTitleData(data)
    return data.EquippedTitle or ""
end

function PlayerDataManager.GiveSeed(player, seedId, amount, suppressEffect)
    local data = sessionData[player.UserId]
    if not data then return end

    local found = false
    for _, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then
            seedData.Quantity += amount
            found = true
            break
        end
    end

    if not found then
        table.insert(data.Inventory.Seeds, { ID = seedId, Quantity = amount })
    end

    if data.Hotbar then
        local itemKey = "Seed_" .. seedId
        local alreadyEquipped = false
        for _, v in ipairs(data.Hotbar) do
            if v == itemKey then
                alreadyEquipped = true
                break
            end
        end
        if not alreadyEquipped and #data.Hotbar < 9 then
            table.insert(data.Hotbar, itemKey)
        end
    end

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    -- 如果被抑制了，就不在这里触发特效（比如抽奖需要等转盘转完再触发）
    if not suppressEffect then
        local effectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
        if effectRE then
            local itemDetail = ItemConfig.Seeds[seedId]
            local itemName = itemDetail and itemDetail.Name or seedId
            local playFullEffect = (tonumber(itemDetail and itemDetail.Quality) or 0) >= 4
            effectRE:FireClient(player, "Congratulations, you obtained " .. amount .. "x " .. itemName, playFullEffect)
        end
    end
    markSessionDataChanged(player, "seed grant")
end

function PlayerDataManager.ConsumeSeed(player, seedId, amount)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Seeds then return false end
    for i, seedData in ipairs(data.Inventory.Seeds) do
        if seedData.ID == seedId then
            if seedData.Quantity >= amount then
                seedData.Quantity -= amount
                if seedData.Quantity <= 0 then
                    table.remove(data.Inventory.Seeds, i)
                    if data.Hotbar then
                        for j = #data.Hotbar, 1, -1 do
                            local parts = string.split(data.Hotbar[j], "_")
                            if parts[1] == "Seed" and parts[2] == seedId then
                                table.remove(data.Hotbar, j)
                            end
                        end
                    end
                end
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                markSessionDataChanged(player, "seed consume")
                return true
            end
            break
        end
    end
    return false
end

function PlayerDataManager.GivePlant(player, plantId, amount, mutationLevel, suppressUnlockAnim)
   local data = sessionData[player.UserId]
    if not data then return end
    mutationLevel = normalizeMutationLevel(mutationLevel)

    local found = false
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and normalizeMutationLevel(plantData.Mutation or 1) == mutationLevel then
            plantData.Quantity += amount
            plantData.Mutation = mutationLevel
            found = true
            break
        end
    end

    if not found then
        table.insert(data.Inventory.Plants, { ID = plantId, Quantity = amount, Mutation = mutationLevel })
    end

    if data.Hotbar then
        local itemKey = "Plant_" .. plantId .. "_" .. mutationLevel
        local alreadyEquipped = false
        for _, v in ipairs(data.Hotbar) do
            if v == itemKey then
                alreadyEquipped = true
                break
            end
        end
        if not alreadyEquipped and #data.Hotbar < 9 then
            table.insert(data.Hotbar, itemKey)
        end
    end

    PlayerDataManager.UnlockMutation(player, plantId, mutationLevel, suppressUnlockAnim)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    markSessionDataChanged(player, "plant grant")
end

function PlayerDataManager.UnlockMutation(player, plantId, mutationLevel, suppressUnlockAnim)
    local data = sessionData[player.UserId]
    if not data then return end

    mutationLevel = normalizeMutationLevel(mutationLevel)
    local isFirstTimeUnlock = not isMutationUnlocked(data, plantId, mutationLevel)
    markMutationUnlocked(data, plantId, mutationLevel)

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end

    if isFirstTimeUnlock and not suppressUnlockAnim then
        local playUnlockAnimRE = ReplicatedStorage:FindFirstChild("PlayUnlockAnimRE")
        if playUnlockAnimRE then
            playUnlockAnimRE:FireClient(player, plantId, mutationLevel)
        end
    end

    if isFirstTimeUnlock then
        markSessionDataChanged(player, "mutation unlock")
    end
end

function PlayerDataManager.ConsumeCoins(player, amount)
    local data = sessionData[player.UserId];
    if not data then return false end
    if data.Coins >= amount then
        data.Coins -= amount
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        markSessionDataChanged(player, "coins consume")
        return true
    end
    return false
end

function PlayerDataManager.GiveCoins(player, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    local finalAmount = amount
    if PlayerDataManager.IsX2SunActive(player) then
        finalAmount = amount * 2
    end
    data.Coins += finalAmount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    markSessionDataChanged(player, "coins grant")
    return finalAmount
end

function PlayerDataManager.GiveCoinsRaw(player, amount)
    local data = sessionData[player.UserId];
    if not data then return end
    data.Coins += amount
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    markSessionDataChanged(player, "raw coins grant")
    return amount
end

function PlayerDataManager.IsX2SunActive(player)
    if not player then return false end
    local userId = player.UserId
    local cachedValue = x2SunOwnershipCache[userId]
    local cachedAt = x2SunOwnershipCacheTime[userId]
    if cachedValue ~= nil and (cachedValue == true or (cachedAt and os.clock() - cachedAt < X2_SUN_CACHE_TTL)) then
        return cachedValue
    end

    local ownsPass = false
    local success, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, X2_SUN_GAME_PASS_ID)
    end)
    if success then
        ownsPass = result == true
        x2SunOwnershipCache[userId] = ownsPass
        x2SunOwnershipCacheTime[userId] = os.clock()
    else
        warn("[PlayerDataManager] Failed to check X2Sun game pass ownership for " .. player.Name .. ": " .. tostring(result))
    end

    return ownsPass
end

function PlayerDataManager.ConsumePlant(player, plantId, amount, mutationLevel)
    local data = sessionData[player.UserId]
    if not data or not data.Inventory or not data.Inventory.Plants then return false end
    mutationLevel = normalizeMutationLevel(mutationLevel)

    for i, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and normalizeMutationLevel(plantData.Mutation or 1) == mutationLevel then
            plantData.Mutation = mutationLevel
            if plantData.Quantity >= amount then
                plantData.Quantity -= amount
                if plantData.Quantity <= 0 then
                    table.remove(data.Inventory.Plants, i)
                    if data.Hotbar then
                        for j = #data.Hotbar, 1, -1 do
                            local parts = string.split(data.Hotbar[j], "_")
                            local mLevel = tonumber(parts[3]) or 1
                            if parts[1] == "Plant" and parts[2] == plantId and mLevel == mutationLevel then
                                table.remove(data.Hotbar, j)
                            end
                        end
                    end
                end
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                markSessionDataChanged(player, "plant consume")
                return true
            end
            break
        end
    end
    return false
end

function PlayerDataManager.UnlockNextLevel(player, completedLevelId)
    local data = sessionData[player.UserId]
    if not data then return end

    -- 只有当玩家打通了他们当前的最高关卡时，才需要升级和更新 UI
    if completedLevelId >= (data.UnlockedLevel or 1) then
        data.UnlockedLevel = completedLevelId + 1

        -- 实时更新玩家头顶的最高关卡 UI
        local character = player.Character
        if character then
            local head = character:FindFirstChild("Head")
            if head then
                local titleGui = head:FindFirstChild("PlayerTitleGui")
                if titleGui then
                    local textLabel = titleGui:FindFirstChildWhichIsA("TextLabel")
                    if textLabel then
                        -- 直接显示当前解锁层数
                        local maxCleared = data.UnlockedLevel or 1
                        textLabel.Text = "MAX  " .. tostring(maxCleared)
                    end
                end
            end
        end

        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        markSessionDataChanged(player, "level unlock")
    end
end

function PlayerDataManager.AddCombatPlant(player, gridName, plantId, hp, mutationLevel)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        data.CombatPlants[gridName] = { PlantId = plantId, Mutation = mutationLevel or 1 }
        markSessionDataChanged(player, "combat plant add")
    end
end

function PlayerDataManager.UpdateCombatPlantHP(player, gridName, hp) end

function PlayerDataManager.RemoveCombatPlant(player, gridName)
    local data = sessionData[player.UserId]
    if data and data.CombatPlants then
        data.CombatPlants[gridName] = nil
        markSessionDataChanged(player, "combat plant removal")
    end
end

function PlayerDataManager.UnlockSeed(player, seedId)
    local data = sessionData[player.UserId]
    if not data then return end
    if not data.UnlockedSeeds then data.UnlockedSeeds = {} end
    data.UnlockedSeeds[seedId] = true
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
    markSessionDataChanged(player, "seed unlock")
end

function PlayerDataManager.ApplyBattleRewards(player, coins, seeds)
    local data = sessionData[player.UserId]
    if not data then return end
    PlayerDataManager.GiveCoins(player, coins)
    if seeds > 0 then PlayerDataManager.GiveSeed(player, "RandomSeed", seeds) end
end

function PlayerDataManager.AddTotalSun(player, amount)
    local data = sessionData[player.UserId]
    if data then
        data.TotalSun = (data.TotalSun or 0) + amount
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        markSessionDataChanged(player, "total sun add")
    end
end

function PlayerDataManager.ApplyFriendSunBoost(player, amount)
    return FriendSunBoostService.ApplyBoost(player, amount)
end

function PlayerDataManager.CollectAllSun(player)
    local data = sessionData[player.UserId]
    if data and data.TotalSun and data.TotalSun > 0 then
        local amount = data.TotalSun
        data.TotalSun = 0
        local boostedAmount = PlayerDataManager.ApplyFriendSunBoost(player, amount)
        local finalAmount = PlayerDataManager.GiveCoins(player, boostedAmount) or boostedAmount

        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        markSessionDataChanged(player, "sun collection")

        AnalyticsService:LogEconomyEvent(
            player,
            Enum.AnalyticsEconomyFlowType.Source,
            "Coins",
            finalAmount,
            data.Coins,
            Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
            "Sunflower_Collect"
        )
        return finalAmount
    end
    return 0
end

function PlayerDataManager.GetUnlockedPlots(player)
    local data = sessionData[player.UserId]
    return data and data.UnlockedPlots or 4
end

function PlayerDataManager.IncrementUnlockedPlots(player)
    local data = sessionData[player.UserId]
    if data then
        data.UnlockedPlots = (data.UnlockedPlots or 4) + 1
        local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
        if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
        markSessionDataChanged(player, "plot unlock")
    end
end

local claimAllBattleRF = Instance.new("RemoteFunction")
claimAllBattleRF.Name = "ClaimAllBattleRF"
claimAllBattleRF.Parent = ReplicatedStorage

local claimSignInRF = ReplicatedStorage:FindFirstChild("ClaimSignInRF")
if not claimSignInRF then
    claimSignInRF = Instance.new("RemoteFunction")
    claimSignInRF.Name = "ClaimSignInRF"
    claimSignInRF.Parent = ReplicatedStorage
end

local function normalizeSignInTier(data)
    data.SignInTier = SignInRewardConfig.NormalizeTier(data.SignInTier or 1)
    data.SignInDays = math.clamp(math.floor(tonumber(data.SignInDays) or 0), 0, SignInRewardConfig.DaysPerTier)
    if type(data.LastSignInPurchaseTime) ~= "number" then
        data.LastSignInPurchaseTime = 0
    end
    return data.SignInTier, data.SignInDays
end

local function advanceSignInTier(data)
    data.SignInTier = SignInRewardConfig.GetNextTier(data.SignInTier or 1)
    data.SignInDays = 0
end

local function isSameCalendarDay(firstTime, secondTime)
    firstTime = tonumber(firstTime) or 0
    secondTime = tonumber(secondTime) or 0
    if firstTime <= 0 or secondTime <= 0 then
        return false
    end

    local firstDate = os.date("*t", firstTime)
    local secondDate = os.date("*t", secondTime)
    return firstDate.year == secondDate.year
        and firstDate.month == secondDate.month
        and firstDate.day == secondDate.day
end

function PlayerDataManager.CanPurchaseSignInClaimAll(player)
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Loading data..."
    end

    normalizeSignInTier(data)
    if isSameCalendarDay(data.LastSignInPurchaseTime, os.time()) then
        return false, "You can purchase all sign-in rewards once per day."
    end

    return true
end

function PlayerDataManager.MarkSignInClaimAllPurchased(player, timestamp, options)
    options = options or {}
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        return false, "Loading data..."
    end

    local shouldSaveImmediately = options.SkipImmediateSave ~= true
    local snapshot = nil
    if shouldSaveImmediately then
        if not PlayerDataManager.IsDataSafeToSave(player) then
            return false, "Save unavailable. Please try again."
        end
        snapshot = snapshotReliableRewardState(data)
    end

    data.LastSignInPurchaseTime = tonumber(timestamp) or os.time()
    if shouldSaveImmediately then
        local saved = saveReliableRewardMutation(player, data, snapshot, "sign-in purchase timestamp")
        if not saved then
            return false, "Save failed. Please try again."
        end
    else
        markSessionDataChanged(player, "sign-in purchase timestamp")
    end

    return true
end

function PlayerDataManager.GrantSignInReward(player, day, tier, options)
    options = options or {}
    local data = sessionData[player.UserId]
    tier = tier or (data and data.SignInTier) or 1
    local rewardData = SignInRewardConfig.GetReward(tier, day)
    if not rewardData then return end

    if rewardData.RewardType == "Coins" then
        PlayerDataManager.GiveCoins(player, rewardData.Amount)
    elseif rewardData.RewardType == "Seed" then
        PlayerDataManager.GiveSeed(player, rewardData.ItemId, rewardData.Amount, options.SuppressEffect == true)
    elseif rewardData.RewardType == "Sun" then
        PlayerDataManager.AddTotalSun(player, rewardData.Amount)
    end

    return rewardData
end

function PlayerDataManager.ClaimRemainingSignInTier(player, options)
    options = options or {}
    local data = PlayerDataManager.GetPlayerData(player)
    if not data then return false, "Loading data..." end

    local shouldSaveImmediately = options.SkipImmediateSave ~= true
    local snapshot = nil
    if shouldSaveImmediately then
        if not PlayerDataManager.IsDataSafeToSave(player) then
            return false, "Save unavailable. Please try again."
        end
        snapshot = snapshotReliableRewardState(data)
    end

    local tier, currentDays = normalizeSignInTier(data)
    if currentDays >= SignInRewardConfig.DaysPerTier then
        advanceSignInTier(data)
        tier, currentDays = normalizeSignInTier(data)
    end

    for day = currentDays + 1, SignInRewardConfig.DaysPerTier do
        PlayerDataManager.GrantSignInReward(player, day, tier, {
            SuppressEffect = true,
        })
    end

    advanceSignInTier(data)
    data.LastSignInTime = os.time()

    if shouldSaveImmediately then
        local saved = saveReliableRewardMutation(player, data, snapshot, "sign-in claim all")
        if not saved then
            return false, "Save failed. Please try again."
        end

        if options.SuppressInventoryUpdate ~= true then
            fireInventoryUpdate(player, data)
        end
    else
        if options.SuppressInventoryUpdate ~= true then
            fireInventoryUpdate(player, data)
        end
        markSessionDataChanged(player, "sign-in claim all")
    end

    return true, "Claim successful with one click!"
end

claimAllBattleRF.OnServerInvoke = function(player)
    return PlayerDataManager.CanPurchaseSignInClaimAll(player)
end

claimSignInRF.OnServerInvoke = function(player)
    local data = sessionData[player.UserId]
    if not data then return false end

    if not PlayerDataManager.IsDataSafeToSave(player) then
        return false, "Save unavailable. Please try again."
    end

    local snapshot = snapshotReliableRewardState(data)
    local signInTier, signInDays = normalizeSignInTier(data)
    if signInDays >= SignInRewardConfig.DaysPerTier then
        advanceSignInTier(data)
        signInTier, signInDays = normalizeSignInTier(data)
    end

    if isSameCalendarDay(data.LastSignInTime, os.time()) then return false end

    local claimDay = signInDays + 1
    data.LastSignInTime = os.time()

    PlayerDataManager.GrantSignInReward(player, claimDay, signInTier, {
        SuppressEffect = true,
    })

    if claimDay >= SignInRewardConfig.DaysPerTier then
        advanceSignInTier(data)
    else
        data.SignInDays = claimDay
    end

    local saved = saveReliableRewardMutation(player, data, snapshot, "sign-in claim")
    if not saved then
        return false, "Save failed. Please try again."
    end

    fireInventoryUpdate(player, data)

    return true, signInTier, claimDay
end

local claimLevelRewardRF = ReplicatedStorage:FindFirstChild("ClaimLevelRewardRF")
if not claimLevelRewardRF then
    claimLevelRewardRF = Instance.new("RemoteFunction")
    claimLevelRewardRF.Name = "ClaimLevelRewardRF"
    claimLevelRewardRF.Parent = ReplicatedStorage
end

claimLevelRewardRF.OnServerInvoke = function(player, targetLevel)
    local data = sessionData[player.UserId]
    if not data then return false, "Data still loading..." end
    if dataSaveAllowed[player.UserId] ~= true then
        return false, "Data is still saving. Please try again later."
    end

    if not data.ClaimedAchieve then data.ClaimedAchieve = {} end

    local currentUnlocked = data.UnlockedLevel or 1
    if currentUnlocked <= targetLevel then
        return false, "Progress not enough to claim!"
    end

    if data.ClaimedAchieve[tostring(targetLevel)] then
        return false, "You have already claimed this reward!"
    end

    local LevelRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardConfig"))
    local rewardData = LevelRewardConfig[targetLevel]
    if not rewardData then return false, "Configuration does not exist" end

    local snapshot = snapshotReliableRewardState(data)
    local msg = "Reward Claimed: "
    local seedEffectName = nil
    local seedEffectAmount = nil
    if rewardData.Seed then
        seedEffectAmount = rewardData.SeedCount or 1
        PlayerDataManager.GiveSeed(player, rewardData.Seed, seedEffectAmount, true)
        seedEffectName = tostring((ItemConfig.Seeds[rewardData.Seed] and ItemConfig.Seeds[rewardData.Seed].Name) or rewardData.Seed)
        msg = msg .. seedEffectAmount .. "x " .. rewardData.Seed .. " "
    end
    if rewardData.Sun then
        PlayerDataManager.AddTotalSun(player, rewardData.Sun)
        msg = msg .. rewardData.Sun .. " Sun"
    end

    data.ClaimedAchieve[tostring(targetLevel)] = true

    local saved = saveReliableRewardMutation(player, data, snapshot, "level reward claim")
    if not saved then
        return false, "Save failed. Please try again."
    end

    fireInventoryUpdate(player, data)
    if seedEffectName then
        playPassObtainEffect(player, seedEffectName, seedEffectAmount)
    end

    return true, msg
end


return PlayerDataManager

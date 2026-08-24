-- src/server/Services/RankingService.luau
local RankingService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local RankingSeasonConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankingSeasonConfig"))

local CURRENT_STORE_NAME = RankingSeasonConfig.CurrentStoreName or "LevelRanking_v2"
local RankingStore = DataStoreService:GetOrderedDataStore(CURRENT_STORE_NAME)
local ResetStateStore = DataStoreService:GetDataStore(RankingSeasonConfig.CurrentStoreResetStateStoreName or "RankingStoreResetState_v1")
local MIGRATION_SOURCE_STORE_NAME = RankingSeasonConfig.CurrentStoreMigrationSourceName or RankingSeasonConfig.PreviousStoreName or CURRENT_STORE_NAME
local MigrationSourceStore = DataStoreService:GetOrderedDataStore(MIGRATION_SOURCE_STORE_NAME)
local MigrationStateStore = DataStoreService:GetDataStore(RankingSeasonConfig.CurrentStoreMigrationStateStoreName or "RankingStoreMigrationState_v1")
local LAZY_MIGRATION_SOURCE_STORE_NAME = RankingSeasonConfig.LazyRankingMigrationSourceStoreName or "LevelRanking_v2"
local LazyMigrationSourceStore = DataStoreService:GetOrderedDataStore(LAZY_MIGRATION_SOURCE_STORE_NAME)

local EntryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("EntryTemplate")

-- 配置
local UPDATE_INTERVAL = 300 -- 每 5 分钟刷新一次显示，降低 DataStore 和 UI 重建压力
local TOP_COUNT = RankingSeasonConfig.TopCount or 60

local rankingListsCache = nil
local rankingListsDirty = true
local profileCache = {}
local profileWaiters = {}
local lastSyncedScores = {}
local rankingSyncStates = {}
local lazyMigrationStates = {}
local departingPlayers = setmetatable({}, { __mode = "k" })
local displayRefreshQueued = false
local currentStoreResetRunning = false
local currentStoreMigrationRunning = false
local RESET_LOCK_TIMEOUT_SECONDS = 1800
local RESET_STATE_POLL_SECONDS = 5
local MIGRATION_LOCK_TIMEOUT_SECONDS = 3600
local MIGRATION_STATE_POLL_SECONDS = 5
local LAZY_MIGRATION_INITIAL_RETRY_SECONDS = math.max(1,
    tonumber(RankingSeasonConfig.LazyRankingMigrationInitialRetryDelaySeconds) or 30)
local LAZY_MIGRATION_RETRY_SECONDS = math.max(1,
    tonumber(RankingSeasonConfig.LazyRankingMigrationRetryIntervalSeconds) or 5)

local function IsRankingRoot(obj)
    return string.sub(obj.Name, 1, #"Ranking_Level") == "Ranking_Level"
end

local function CouldAffectRankingList(obj)
    if IsRankingRoot(obj) or obj.Name == "RankingGui" or obj.Name == "List" then
        return true
    end

    local ancestor = obj.Parent
    while ancestor and ancestor ~= Workspace do
        if IsRankingRoot(ancestor) then
            return true
        end
        ancestor = ancestor.Parent
    end

    return false
end

local function MarkRankingListsDirty(obj)
    if CouldAffectRankingList(obj) then
        rankingListsDirty = true
    end
end

local function RebuildRankingLists()
    local lists = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if IsRankingRoot(obj) then
            local rankingGui = obj:FindFirstChild("RankingGui", true)
            local list = rankingGui and rankingGui:FindFirstChild("List", true)
            if list then
                table.insert(lists, list)
            end
        end
    end

    rankingListsCache = lists
    rankingListsDirty = false
    return lists
end

local function GetRankingLists()
    if rankingListsDirty or not rankingListsCache then
        return RebuildRankingLists()
    end

    for i = #rankingListsCache, 1, -1 do
        if not rankingListsCache[i].Parent then
            table.remove(rankingListsCache, i)
        end
    end

    return rankingListsCache
end

local function ClearList(list)
    -- 清理旧列表 ( UIListLayout 等非 Frame UI 组件)
    for _, child in pairs(list:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

local function getMigrationCapLevel()
    return math.floor(tonumber(RankingSeasonConfig.CurrentStoreMigrationCapClearedLevel)
        or tonumber(RankingSeasonConfig.SeasonCarryOverMaxClearedLevel)
        or 1000)
end

local function getLazyMigrationCapLevel()
    return math.floor(tonumber(RankingSeasonConfig.LazyRankingMigrationCapClearedLevel)
        or tonumber(RankingSeasonConfig.SeasonCarryOverMaxClearedLevel)
        or 1000)
end

local function readTopRankingEntries(store)
    local success, pagesOrErr = pcall(function()
        return store:GetSortedAsync(false, TOP_COUNT)
    end)
    if not success or not pagesOrErr then
        return nil, pagesOrErr
    end

    local pageSuccess, entriesOrErr = pcall(function()
        return pagesOrErr:GetCurrentPage()
    end)
    if not pageSuccess or type(entriesOrErr) ~= "table" then
        return nil, entriesOrErr
    end

    return entriesOrErr, nil
end

local function buildMigrationDisplayEntries(entries)
    local capLevel = getMigrationCapLevel()
    local displayEntries = {}

    for _, entry in ipairs(entries) do
        local sourceScore = math.max(0, math.floor(tonumber(entry.value) or 0))
        local displayScore = capLevel > 0 and math.min(sourceScore, capLevel) or sourceScore
        table.insert(displayEntries, {
            key = entry.key,
            value = displayScore,
        })
    end

    return displayEntries
end

local function ApplyProfile(item, profile)
    if not item.Parent then
        return
    end

    local nameLabel = item:FindFirstChild("NameLabel")
    if nameLabel then
        nameLabel.Text = profile.Name or "Unknown"
    end

    local avatar = item:FindFirstChild("Avatar")
    if avatar and profile.Avatar then
        avatar.Image = profile.Avatar
    end
end

local function QueueProfileLoad(userId, item)
    if not userId then
        ApplyProfile(item, { Name = "Unknown" })
        return
    end

    local cachedProfile = profileCache[userId]
    if cachedProfile then
        ApplyProfile(item, cachedProfile)
        return
    end

    local nameLabel = item:FindFirstChild("NameLabel")
    if nameLabel then
        nameLabel.Text = "Loading..."
    end

    if profileWaiters[userId] then
        table.insert(profileWaiters[userId], item)
        return
    end

    profileWaiters[userId] = { item }

    task.spawn(function()
        local successName, name = pcall(function()
            return Players:GetNameFromUserIdAsync(userId)
        end)

        local successAvatar, avatar = pcall(function()
            return Players:GetUserThumbnailAsync(
                userId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size420x420
            )
        end)

        local profile = {
            Name = successName and name or "Unknown",
            Avatar = successAvatar and avatar or nil,
        }

        profileCache[userId] = profile

        local waiters = profileWaiters[userId] or {}
        profileWaiters[userId] = nil

        for _, waitingItem in ipairs(waiters) do
            ApplyProfile(waitingItem, profile)
        end
    end)
end

local function PopulateList(list, rankingData)
    ClearList(list)

    for rank, entry in ipairs(rankingData) do
        local userId = tonumber(entry.key)
        local level = entry.value

        -- 克隆模板并设置基础信息
        local item = EntryTemplate:Clone()
        item.Name = "Rank_" .. rank
        item.RankLabel.Text = "#" .. rank
        item.ValueLabel.Text = tostring(RankingSeasonConfig.RankValuePrefix or "Lv.") .. tostring(level)
        item.Parent = list

        QueueProfileLoad(userId, item)

        -- 样式美化：前三名特殊背景色
        if rank == 1 then
            item.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- 金色
        elseif rank == 2 then
            item.BackgroundColor3 = Color3.fromRGB(192, 192, 192) -- 银色
        elseif rank == 3 then
            item.BackgroundColor3 = Color3.fromRGB(205, 127, 50) -- 铜色
        end
    end
end

-- 功能 刷新排行榜显示
local function RefreshDisplay()
    if currentStoreResetRunning then
        return
    end

    local data
    if currentStoreMigrationRunning then
        local sourceData, sourceErr = readTopRankingEntries(MigrationSourceStore)
        if sourceData and #sourceData > 0 then
            data = buildMigrationDisplayEntries(sourceData)
        else
            local currentData, currentErr = readTopRankingEntries(RankingStore)
            if currentData and #currentData > 0 then
                data = currentData
            else
                warn("[RankingMigration] Failed to refresh temporary ranking display. Source: "
                    .. tostring(sourceErr or "empty") .. "; current: " .. tostring(currentErr or "empty"))
                return
            end
        end
    else
        data = readTopRankingEntries(RankingStore)
        if not data then
            return
        end
    end

    -- 2. 每次刷新时间重新遍历 Workspace，找到所有 Ranking_Level* 排行榜对象
    local lists = GetRankingLists()

    -- 3. 对每个 RankingGui.List 都清晰空，并克隆同一份排行榜数据进行显示
    for _, list in ipairs(lists) do
        PopulateList(list, data)
    end
end

local function acquireCurrentStoreResetLock(resetId)
    local now = os.time()
    local acquired = false
    local completed = false

    local success, err = pcall(function()
        ResetStateStore:UpdateAsync(resetId, function(state)
            if type(state) ~= "table" then
                state = {}
            end

            if state.Completed == true then
                completed = true
                return state
            end

            local lockedAt = tonumber(state.LockedAt) or 0
            if state.Status == "InProgress" and now - lockedAt < RESET_LOCK_TIMEOUT_SECONDS then
                return state
            end

            acquired = true
            state.Status = "InProgress"
            state.LockedAt = now
            state.JobId = game.JobId
            state.StoreName = CURRENT_STORE_NAME
            return state
        end)
    end)

    if not success then
        return false, completed, err
    end

    return acquired, completed, nil
end

local function markCurrentStoreResetComplete(resetId, removedCount, pageCount)
    local success, err = pcall(function()
        ResetStateStore:UpdateAsync(resetId, function(state)
            if type(state) ~= "table" then
                state = {}
            end

            state.Completed = true
            state.Status = "Completed"
            state.CompletedAt = os.time()
            state.RemovedCount = removedCount
            state.PageCount = pageCount
            state.StoreName = CURRENT_STORE_NAME
            state.JobId = game.JobId
            return state
        end)
    end)

    if not success then
        warn("[RankingReset] Failed to mark reset complete: " .. tostring(err))
        return false
    end

    return true
end

local function getCurrentStoreResetState(resetId)
    local success, stateOrErr = pcall(function()
        return ResetStateStore:GetAsync(resetId)
    end)

    if not success then
        return nil, stateOrErr
    end

    return stateOrErr, nil
end

local function waitForCurrentStoreResetCompletion(resetId)
    local deadline = os.time() + RESET_LOCK_TIMEOUT_SECONDS

    while os.time() < deadline do
        local state, err = getCurrentStoreResetState(resetId)
        if err then
            warn("[RankingReset] Failed to read reset state while waiting: " .. tostring(err))
        end

        if type(state) == "table" and state.Completed == true then
            print("[RankingReset] Reset completed by another server: " .. resetId)
            return true
        end

        if type(state) ~= "table" or state.Status ~= "InProgress" then
            return false
        end

        local lockedAt = tonumber(state.LockedAt) or 0
        if lockedAt > 0 and os.time() - lockedAt >= RESET_LOCK_TIMEOUT_SECONDS then
            return false
        end

        task.wait(RESET_STATE_POLL_SECONDS)
    end

    return false
end

local function refreshAndSyncOnlinePlayers()
    lastSyncedScores = {}
    RefreshDisplay()

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            RankingService.SyncData(player)
        end)
    end
end

local function resumeRankingAfterCurrentStoreReset()
    currentStoreResetRunning = false
    refreshAndSyncOnlinePlayers()
end

local function resumeRankingAfterCurrentStoreMigration()
    currentStoreMigrationRunning = false
    refreshAndSyncOnlinePlayers()
end

local function clearCurrentRankingStore()
    local pageSize = math.clamp(math.floor(tonumber(RankingSeasonConfig.CurrentStoreResetPageSize) or 100), 1, 100)
    local maxPages = math.max(1, math.floor(tonumber(RankingSeasonConfig.CurrentStoreResetMaxPages) or 50))
    local removedCount = 0
    local pageCount = 0

    while pageCount < maxPages do
        local success, pagesOrErr = pcall(function()
            return RankingStore:GetSortedAsync(false, pageSize)
        end)

        if not success or not pagesOrErr then
            return false, tostring(pagesOrErr), removedCount, pageCount
        end

        local entries = pagesOrErr:GetCurrentPage()
        if #entries <= 0 then
            return true, nil, removedCount, pageCount
        end

        pageCount += 1
        for _, entry in ipairs(entries) do
            local key = tostring(entry.key)
            local removed = pcall(function()
                RankingStore:RemoveAsync(key)
            end)
            if removed then
                removedCount += 1
            end
            task.wait(0.05)
        end

        task.wait(1)
    end

    return false, "max pages reached", removedCount, pageCount
end

local function runCurrentStoreResetIfNeeded()
    if RankingSeasonConfig.CurrentStoreResetEnabled ~= true then
        return
    end

    if RunService:IsStudio() and RankingSeasonConfig.CurrentStoreResetInStudio ~= true then
        warn("[RankingReset] Skipped in Studio. Current store reset only runs in live servers.")
        return
    end

    local resetId = tostring(RankingSeasonConfig.CurrentStoreResetId or "")
    if resetId == "" then
        warn("[RankingReset] CurrentStoreResetId is missing.")
        return
    end

    currentStoreResetRunning = true

    while true do
        local acquired, completed, lockErr = acquireCurrentStoreResetLock(resetId)
        if completed then
            print("[RankingReset] Already completed: " .. resetId)
            resumeRankingAfterCurrentStoreReset()
            return
        end

        if acquired then
            local success, err, removedCount, pageCount = clearCurrentRankingStore()
            if success then
                while not markCurrentStoreResetComplete(resetId, removedCount, pageCount) do
                    warn("[RankingReset] Store cleared but completion mark failed; ranking writes remain paused.")
                    task.wait(RESET_STATE_POLL_SECONDS)
                end

                print("[RankingReset] Cleared " .. CURRENT_STORE_NAME .. " once. Removed " .. tostring(removedCount) .. " entries.")
                resumeRankingAfterCurrentStoreReset()
                return
            end

            warn("[RankingReset] Reset incomplete for " .. CURRENT_STORE_NAME .. ": " .. tostring(err)
                .. " removed=" .. tostring(removedCount) .. " pages=" .. tostring(pageCount))
        elseif lockErr then
            warn("[RankingReset] Failed to acquire reset lock: " .. tostring(lockErr))
        else
            print("[RankingReset] Another server is resetting " .. CURRENT_STORE_NAME .. "; pausing writes.")
        end

        local completedWhileWaiting = waitForCurrentStoreResetCompletion(resetId)
        if completedWhileWaiting then
            resumeRankingAfterCurrentStoreReset()
            return
        end

        warn("[RankingReset] Reset wait ended before completion; retrying lock for " .. resetId .. ".")
        task.wait(1)
    end
end

local function acquireCurrentStoreMigrationLock(migrationId)
    local now = os.time()
    local acquired = false
    local completed = false

    local success, err = pcall(function()
        MigrationStateStore:UpdateAsync(migrationId, function(state)
            if type(state) ~= "table" then
                state = {}
            end

            if state.Completed == true then
                completed = true
                return state
            end

            local lockedAt = tonumber(state.LockedAt) or 0
            if state.Status == "InProgress" and now - lockedAt < MIGRATION_LOCK_TIMEOUT_SECONDS then
                return state
            end

            acquired = true
            state.Status = "InProgress"
            state.LockedAt = now
            state.JobId = game.JobId
            state.SourceStoreName = MIGRATION_SOURCE_STORE_NAME
            state.TargetStoreName = CURRENT_STORE_NAME
            return state
        end)
    end)

    if not success then
        return false, completed, err
    end

    return acquired, completed, nil
end

local function markCurrentStoreMigrationComplete(migrationId, migratedCount, cappedCount, pageCount)
    local success, err = pcall(function()
        MigrationStateStore:UpdateAsync(migrationId, function(state)
            if type(state) ~= "table" then
                state = {}
            end

            state.Completed = true
            state.Status = "Completed"
            state.CompletedAt = os.time()
            state.MigratedCount = migratedCount
            state.CappedCount = cappedCount
            state.PageCount = pageCount
            state.SourceStoreName = MIGRATION_SOURCE_STORE_NAME
            state.TargetStoreName = CURRENT_STORE_NAME
            state.JobId = game.JobId
            return state
        end)
    end)

    if not success then
        warn("[RankingMigration] Failed to mark migration complete: " .. tostring(err))
        return false
    end

    return true
end

local function getCurrentStoreMigrationState(migrationId)
    local success, stateOrErr = pcall(function()
        return MigrationStateStore:GetAsync(migrationId)
    end)

    if not success then
        return nil, stateOrErr
    end

    return stateOrErr, nil
end

local function waitForCurrentStoreMigrationCompletion(migrationId)
    local deadline = os.time() + MIGRATION_LOCK_TIMEOUT_SECONDS

    while os.time() < deadline do
        local state, err = getCurrentStoreMigrationState(migrationId)
        if err then
            warn("[RankingMigration] Failed to read migration state while waiting: " .. tostring(err))
        end

        if type(state) == "table" and state.Completed == true then
            print("[RankingMigration] Migration completed by another server: " .. migrationId)
            return true
        end

        if type(state) ~= "table" or state.Status ~= "InProgress" then
            return false
        end

        local lockedAt = tonumber(state.LockedAt) or 0
        if lockedAt > 0 and os.time() - lockedAt >= MIGRATION_LOCK_TIMEOUT_SECONDS then
            return false
        end

        task.wait(MIGRATION_STATE_POLL_SECONDS)
    end

    return false
end

local function migrateCurrentRankingStore()
    local pageSize = math.clamp(math.floor(tonumber(RankingSeasonConfig.CurrentStoreMigrationPageSize) or 100), 1, 100)
    local maxPages = math.max(1, math.floor(tonumber(RankingSeasonConfig.CurrentStoreMigrationMaxPages) or 1000))
    local writeDelaySeconds = math.max(0, tonumber(RankingSeasonConfig.CurrentStoreMigrationWriteDelaySeconds) or 0.05)
    local capLevel = getMigrationCapLevel()
    local migratedCount = 0
    local cappedCount = 0
    local pageCount = 0

    local success, pagesOrErr = pcall(function()
        return MigrationSourceStore:GetSortedAsync(false, pageSize)
    end)

    if not success or not pagesOrErr then
        return false, tostring(pagesOrErr), migratedCount, cappedCount, pageCount
    end

    local pages = pagesOrErr
    while pageCount < maxPages do
        local entries = pages:GetCurrentPage()
        if #entries <= 0 then
            return true, nil, migratedCount, cappedCount, pageCount
        end

        pageCount += 1
        for _, entry in ipairs(entries) do
            local key = tostring(entry.key)
            local oldScore = math.max(0, math.floor(tonumber(entry.value) or 0))
            local cappedScore = capLevel > 0 and math.min(oldScore, capLevel) or oldScore

            if cappedScore > 0 then
                local writeOk, writeErr = pcall(function()
                    RankingStore:UpdateAsync(key, function(currentScore)
                        local currentNumber = math.max(0, math.floor(tonumber(currentScore) or 0))
                        return math.max(currentNumber, cappedScore)
                    end)
                end)

                if not writeOk then
                    return false, tostring(writeErr), migratedCount, cappedCount, pageCount
                end
            end

            migratedCount += 1
            if cappedScore ~= oldScore then
                cappedCount += 1
            end
            task.wait(writeDelaySeconds)
        end

        if pages.IsFinished then
            return true, nil, migratedCount, cappedCount, pageCount
        end

        local advanceOk, advanceErr = pcall(function()
            pages:AdvanceToNextPageAsync()
        end)
        if not advanceOk then
            return false, tostring(advanceErr), migratedCount, cappedCount, pageCount
        end

        task.wait(1)
    end

    return false, "max pages reached", migratedCount, cappedCount, pageCount
end

local function runCurrentStoreMigrationIfNeeded()
    if RankingSeasonConfig.CurrentStoreMigrationEnabled ~= true then
        return
    end

    if CURRENT_STORE_NAME == MIGRATION_SOURCE_STORE_NAME then
        warn("[RankingMigration] Skipped because source and target stores are the same: " .. CURRENT_STORE_NAME)
        return
    end

    if RunService:IsStudio() and RankingSeasonConfig.CurrentStoreMigrationInStudio ~= true then
        warn("[RankingMigration] Skipped in Studio. Current store migration only runs in live servers.")
        return
    end

    local migrationId = tostring(RankingSeasonConfig.CurrentStoreMigrationId or "")
    if migrationId == "" then
        warn("[RankingMigration] CurrentStoreMigrationId is missing.")
        return
    end

    currentStoreMigrationRunning = true
    RefreshDisplay()

    while true do
        local acquired, completed, lockErr = acquireCurrentStoreMigrationLock(migrationId)
        if completed then
            print("[RankingMigration] Already completed: " .. migrationId)
            resumeRankingAfterCurrentStoreMigration()
            return
        end

        if acquired then
            local success, err, migratedCount, cappedCount, pageCount = migrateCurrentRankingStore()
            if success then
                while not markCurrentStoreMigrationComplete(migrationId, migratedCount, cappedCount, pageCount) do
                    warn("[RankingMigration] Store migrated but completion mark failed; ranking writes remain paused.")
                    task.wait(MIGRATION_STATE_POLL_SECONDS)
                end

                print("[RankingMigration] Migrated " .. MIGRATION_SOURCE_STORE_NAME .. " to " .. CURRENT_STORE_NAME
                    .. ". Entries=" .. tostring(migratedCount) .. " capped=" .. tostring(cappedCount) .. ".")
                resumeRankingAfterCurrentStoreMigration()
                return
            end

            warn("[RankingMigration] Migration incomplete from " .. MIGRATION_SOURCE_STORE_NAME .. " to " .. CURRENT_STORE_NAME
                .. ": " .. tostring(err) .. " migrated=" .. tostring(migratedCount)
                .. " capped=" .. tostring(cappedCount) .. " pages=" .. tostring(pageCount))
        elseif lockErr then
            warn("[RankingMigration] Failed to acquire migration lock: " .. tostring(lockErr))
        else
            print("[RankingMigration] Another server is migrating " .. MIGRATION_SOURCE_STORE_NAME
                .. " to " .. CURRENT_STORE_NAME .. "; pausing writes.")
        end

        local completedWhileWaiting = waitForCurrentStoreMigrationCompletion(migrationId)
        if completedWhileWaiting then
            resumeRankingAfterCurrentStoreMigration()
            return
        end

        warn("[RankingMigration] Migration wait ended before completion; retrying lock for " .. migrationId .. ".")
        task.wait(1)
    end
end

local function QueueDisplayRefresh()
    if displayRefreshQueued then
        return
    end

    displayRefreshQueued = true
    task.delay(5, function()
        displayRefreshQueued = false
        RefreshDisplay()
    end)
end

-- 功能 同步在线玩家数据
local function writeRankingScoreMax(userId, score)
    local normalizedScore = math.max(0, math.floor(tonumber(score) or 0))
    if normalizedScore <= 0 then
        return true, nil
    end

    local success, resultOrErr = pcall(function()
        return RankingStore:UpdateAsync(tostring(userId), function(currentScore)
            local currentNumber = math.max(0, math.floor(tonumber(currentScore) or 0))
            return math.max(currentNumber, normalizedScore)
        end)
    end)
    if not success then
        return false, resultOrErr
    end

    return true, nil
end

local function shouldRunLazyRankingMigration()
    if RankingSeasonConfig.LazyRankingMigrationEnabled ~= true then
        return false
    end

    if RunService:IsStudio() and RankingSeasonConfig.LazyRankingMigrationInStudio ~= true then
        return false
    end

    return LAZY_MIGRATION_SOURCE_STORE_NAME ~= CURRENT_STORE_NAME
end

local function isLazyMigrationStateActive(userId, state)
    local player = state and state.Player
    return lazyMigrationStates[userId] == state
        and player ~= nil
        and player.Parent == Players
        and departingPlayers[player] ~= true
end

local function runLazyRankingMigration(userId, state)
    while isLazyMigrationStateActive(userId, state) do
        local retryDelaySeconds = LAZY_MIGRATION_RETRY_SECONDS

        if state.LegacyReadCompleted ~= true then
            local readOk, legacyScoreOrErr = pcall(function()
                return LazyMigrationSourceStore:GetAsync(tostring(userId))
            end)

            if not isLazyMigrationStateActive(userId, state) then
                return
            end

            if readOk then
                local legacyScore = math.max(0, math.floor(tonumber(legacyScoreOrErr) or 0))
                local capLevel = getLazyMigrationCapLevel()
                state.LegacyScore = capLevel > 0 and math.min(legacyScore, capLevel) or legacyScore
                state.LegacyReadCompleted = true
            else
                state.ReadFailures += 1
                if state.ReadFailures == 1 or state.ReadFailures % 12 == 0 then
                    warn("[RankingLazyMigration] Failed to read legacy score for user " .. tostring(userId)
                        .. ": " .. tostring(legacyScoreOrErr))
                end
                retryDelaySeconds = state.ReadFailures == 1
                    and LAZY_MIGRATION_INITIAL_RETRY_SECONDS
                    or LAZY_MIGRATION_RETRY_SECONDS
            end
        end

        if state.LegacyReadCompleted == true then
            local player = state.Player
            local playerData = PlayerDataManager.GetPlayerData(player)
            if playerData then
                local personalScore = RankingSeasonConfig.GetSeasonClearedLevel(playerData)
                local mergedScore = math.max(
                    math.max(0, math.floor(tonumber(personalScore) or 0)),
                    math.max(0, math.floor(tonumber(state.LegacyScore) or 0))
                )
                if not isLazyMigrationStateActive(userId, state) then
                    return
                end

                local writeOk, writeErr = writeRankingScoreMax(userId, mergedScore)
                if writeOk then
                    if isLazyMigrationStateActive(userId, state) then
                        state.Completed = true
                        state.Running = false
                        QueueDisplayRefresh()
                    end
                    return
                end

                state.WriteFailures += 1
                if state.WriteFailures == 1 or state.WriteFailures % 12 == 0 then
                    warn("[RankingLazyMigration] Failed to write migrated score for user " .. tostring(userId)
                        .. ": " .. tostring(writeErr))
                end
            end
        end

        if isLazyMigrationStateActive(userId, state) then
            task.wait(retryDelaySeconds)
        end
    end
end

local function scheduleLazyRankingMigration(player)
    if not shouldRunLazyRankingMigration()
        or not player
        or player.Parent ~= Players
        or departingPlayers[player] == true then
        return
    end

    local userId = player.UserId
    local existingState = lazyMigrationStates[userId]
    if existingState and existingState.Player == player then
        return
    end

    local state = {
        Player = player,
        Running = true,
        Completed = false,
        LegacyReadCompleted = false,
        LegacyScore = 0,
        ReadFailures = 0,
        WriteFailures = 0,
        Thread = nil,
    }
    lazyMigrationStates[userId] = state

    state.Thread = task.spawn(function()
        local success, err = xpcall(function()
            runLazyRankingMigration(userId, state)
        end, debug.traceback)

        if not success then
            warn("[RankingLazyMigration] Unexpected migration error for user " .. tostring(userId)
                .. ": " .. tostring(err))
        end

        if lazyMigrationStates[userId] == state and state.Completed ~= true then
            lazyMigrationStates[userId] = nil
        end
    end)
end

local function cancelLazyRankingMigration(player)
    local userId = player and player.UserId
    local state = userId and lazyMigrationStates[userId]
    if not state or state.Player ~= player then
        return
    end

    lazyMigrationStates[userId] = nil
    local thread = state.Thread
    if thread and coroutine.status(thread) ~= "dead" then
        pcall(task.cancel, thread)
    end
end

local function syncOnePlayerRanking(player)
    local playerData = PlayerDataManager.GetPlayerData(player)
    if not playerData then
        return
    end

    local userId = player.UserId
    local seasonScore = math.max(0,
        math.floor(tonumber(RankingSeasonConfig.GetSeasonClearedLevel(playerData)) or 0))
    if lastSyncedScores[userId] ~= seasonScore then
        local writeOk, writeErr = writeRankingScoreMax(userId, seasonScore)
        if writeOk then
            if departingPlayers[player] ~= true then
                lastSyncedScores[userId] = seasonScore
            end
            QueueDisplayRefresh()
        else
            warn("[RankingService] Failed to sync score for user " .. tostring(userId)
                .. ": " .. tostring(writeErr))
        end
    end

    scheduleLazyRankingMigration(player)
end

function RankingService.SyncData(player)
    if currentStoreResetRunning or currentStoreMigrationRunning or not player then
        return
    end

    local userId = player.UserId
    local existingState = rankingSyncStates[userId]
    if existingState then
        existingState.PendingPlayer = player
        return
    end

    local state = {
        PendingPlayer = nil,
    }
    rankingSyncStates[userId] = state

    local success, err = xpcall(function()
        local currentPlayer = player
        while currentPlayer do
            state.PendingPlayer = nil
            if currentStoreResetRunning or currentStoreMigrationRunning then
                break
            end

            syncOnePlayerRanking(currentPlayer)
            currentPlayer = state.PendingPlayer
        end
    end, debug.traceback)

    if rankingSyncStates[userId] == state then
        rankingSyncStates[userId] = nil
    end

    if not success then
        warn("[RankingService] Unexpected sync error for user " .. tostring(userId)
            .. ": " .. tostring(err))
    end
end

function RankingService.Init()
    if RankingSeasonConfig.CurrentStoreMigrationEnabled == true then
        task.spawn(runCurrentStoreMigrationIfNeeded)
    end
    task.spawn(runCurrentStoreResetIfNeeded)

    Workspace.DescendantAdded:Connect(MarkRankingListsDirty)
    Workspace.DescendantRemoving:Connect(MarkRankingListsDirty)

    -- 定时间刷新循环
    task.spawn(function()
        while true do
            RefreshDisplay()
            task.wait(UPDATE_INTERVAL)
        end
    end)

    -- 玩家离开时间保持存
    Players.PlayerRemoving:Connect(function(player)
        departingPlayers[player] = true
        cancelLazyRankingMigration(player)
        RankingService.SyncData(player)
        lastSyncedScores[player.UserId] = nil
    end)

    Players.PlayerAdded:Connect(function(player)
        departingPlayers[player] = nil
        task.spawn(function()
            PlayerDataManager.WaitForPlayerData(player, 30)
            if player.Parent then
                RankingService.SyncData(player)
            end
        end)
    end)

    -- 定期为在线玩家自转动保持存 (每5分钟)
    task.spawn(function()
        while true do
            task.wait(300)
            for _, player in ipairs(Players:GetPlayers()) do
                RankingService.SyncData(player)
            end
        end
    end)

    print("Server: ranking system (avatar version) active.")
end

return RankingService

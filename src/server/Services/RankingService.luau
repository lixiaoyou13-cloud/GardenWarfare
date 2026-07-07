-- src/server/Services/RankingService.luau
local RankingService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local RankingSeasonConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankingSeasonConfig"))

local CURRENT_STORE_NAME = RankingSeasonConfig.CurrentStoreName or "LevelRanking_v2"
local CURRENT_SEASON_ID = RankingSeasonConfig.SeasonId or CURRENT_STORE_NAME
local RankingStore = DataStoreService:GetOrderedDataStore(CURRENT_STORE_NAME)

local EntryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("EntryTemplate")

-- 配置
local UPDATE_INTERVAL = 300 -- 每 5 分钟刷新一次显示，降低 DataStore 和 UI 重建压力
local TOP_COUNT = RankingSeasonConfig.TopCount or 60

local rankingListsCache = nil
local rankingListsDirty = true
local profileCache = {}
local profileWaiters = {}
local lastSyncedScores = {}

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
        item.ValueLabel.Text = tostring(RankingSeasonConfig.RankValuePrefix or "Lv.+") .. tostring(level)
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
    -- 1. 从数据库获取排行榜数据
    local success, pages = pcall(function()
        return RankingStore:GetSortedAsync(false, TOP_COUNT) -- false 为降序
    end)

    if not success or not pages then return end

    local data = pages:GetCurrentPage()

    -- 2. 每次刷新时间重新遍历 Workspace，找到所有 Ranking_Level* 排行榜对象
    local lists = GetRankingLists()

    -- 3. 对每个 RankingGui.List 都清晰空，并克隆同一份排行榜数据进行显示
    for _, list in ipairs(lists) do
        PopulateList(list, data)
    end
end

-- 功能 同步在线玩家数据
function RankingService.SyncData(player)
    local pData = PlayerDataManager.GetPlayerData(player)
    if pData and pData.UnlockedLevel then
        if type(pData.RankingSeasonBaselines) ~= "table" then
            pData.RankingSeasonBaselines = {}
        end

        local unlockedLevel = math.max(1, math.floor(tonumber(pData.UnlockedLevel) or 1))
        local baseline = tonumber(pData.RankingSeasonBaselines[CURRENT_SEASON_ID])
        if not baseline then
            pData.RankingSeasonBaselines[CURRENT_SEASON_ID] = unlockedLevel
            PlayerDataManager.RequestSave(player, "ranking season baseline")
            baseline = unlockedLevel
        end

        local seasonScore = math.max(0, unlockedLevel - baseline)
        if lastSyncedScores[player.UserId] == seasonScore then
            return
        end
        if seasonScore <= 0 then
            lastSyncedScores[player.UserId] = 0
            return
        end

        local success = pcall(function()
            RankingStore:SetAsync(tostring(player.UserId), seasonScore)
        end)

        if success then
            lastSyncedScores[player.UserId] = seasonScore
        end
    end
end

function RankingService.Init()
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
        RankingService.SyncData(player)
        lastSyncedScores[player.UserId] = nil
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

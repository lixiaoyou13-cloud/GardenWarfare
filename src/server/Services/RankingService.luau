-- src/server/Services/RankingService.luau
local RankingService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RankingStore = DataStoreService:GetOrderedDataStore("LevelRanking_v1")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local EntryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("EntryTemplate")

-- 配置
local UPDATE_INTERVAL = 60 -- 每分钟刷新一次显示
local TOP_COUNT = 60 -- 显示前10名

local function GetRankingLists()
    local lists = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if string.sub(obj.Name, 1, #"Ranking_Level") == "Ranking_Level" then
            local rankingGui = obj:FindFirstChild("RankingGui", true)
            local list = rankingGui and rankingGui:FindFirstChild("List", true)
            if list then
                table.insert(lists, list)
            end
        end
    end

    return lists
end

local function ClearList(list)
    -- 清理旧列表 (保留 UIListLayout 等非 Frame UI 组件)
    for _, child in pairs(list:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
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
        item.ValueLabel.Text = "Lv." .. level
        
        -- 获取并设置玩家名称与头像
        task.spawn(function()
            local successName, name = pcall(function()
                return Players:GetNameFromUserIdAsync(userId)
            end)
            item.NameLabel.Text = successName and name or "Unknown"

            -- 获取头像 URL (420x420, 头像特写)
            local successAvatar, content = pcall(function()
                return Players:GetUserThumbnailAsync(
                    userId, 
                    Enum.ThumbnailType.HeadShot, 
                    Enum.ThumbnailSize.Size420x420
                )
            end)
            if successAvatar then
                item.Avatar.Image = content
            end
        end)

        -- 样式美化：前三名特殊背景色
        if rank == 1 then
            item.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- 金色
        elseif rank == 2 then
            item.BackgroundColor3 = Color3.fromRGB(192, 192, 192) -- 银色
        elseif rank == 3 then
            item.BackgroundColor3 = Color3.fromRGB(205, 127, 50) -- 铜色
        end

        item.Parent = list
    end
end

-- [核心功能] 刷新排行榜显示
local function RefreshDisplay()
    -- 1. 从数据库获取排行榜数据
    local success, pages = pcall(function()
        return RankingStore:GetSortedAsync(false, TOP_COUNT) -- false 为降序
    end)

    if not success or not pages then return end

    local data = pages:GetCurrentPage()

    -- 2. 每次刷新时重新遍历 Workspace，找到所有 Ranking_Level* 排行榜对象
    local lists = GetRankingLists()

    -- 3. 对每个 RankingGui.List 都清空，并克隆同一份排行榜数据进行显示
    for _, list in ipairs(lists) do
        PopulateList(list, data)
    end
end

-- [核心功能] 同步在线玩家数据
function RankingService.SyncData(player)
    local pData = PlayerDataManager.GetPlayerData(player)
    if pData and pData.UnlockedLevel then
        pcall(function()
            RankingStore:SetAsync(tostring(player.UserId), pData.UnlockedLevel)
        end)
    end
end

function RankingService.Init()
    -- 定时刷新循环
    task.spawn(function()
        while true do
            RefreshDisplay()
            task.wait(UPDATE_INTERVAL)
        end
    end)

    -- 玩家离开时保存
    Players.PlayerRemoving:Connect(function(player)
        RankingService.SyncData(player)
    end)
    
    -- 定期为在线玩家自动保存 (每5分钟)
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
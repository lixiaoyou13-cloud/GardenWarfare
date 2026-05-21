-- src/server/Services/RankingService.luau
local RankingService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RankingStore = DataStoreService:GetOrderedDataStore("LevelRanking_v1")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

-- 定位场景中的组件 (匹配你的图片结构)
local RankingPart = game.Workspace:WaitForChild("Ranking_Level")
local RankingGui = RankingPart:WaitForChild("RankingGui")
local List = RankingGui:WaitForChild("List")
local EntryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("EntryTemplate")

-- 配置
local UPDATE_INTERVAL = 60 -- 每分钟刷新一次显示
local TOP_COUNT = 60 -- 显示前10名

-- [核心功能] 刷新排行榜显示
local function RefreshDisplay()
    -- 1. 从数据库获取前10名数据
    local success, pages = pcall(function()
        return RankingStore:GetSortedAsync(false, TOP_COUNT) -- false 为降序
    end)

    if not success or not pages then return end
    
    -- 2. 清理旧列表 (保留 UIListLayout)
    for _, child in pairs(List:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local data = pages:GetCurrentPage()
    
    for rank, entry in ipairs(data) do
        local userId = tonumber(entry.key)
        local level = entry.value
        
        -- 3. 克隆模板并设置基础信息
        local item = EntryTemplate:Clone()
        item.Name = "Rank_" .. rank
        item.RankLabel.Text = "#" .. rank
        item.ValueLabel.Text = "Lv." .. level
        
        -- 4. 获取并设置玩家名称与头像
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

        -- 5. 样式美化：前三名特殊背景色
        if rank == 1 then
            item.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- 金色
        elseif rank == 2 then
            item.BackgroundColor3 = Color3.fromRGB(192, 192, 192) -- 银色
        elseif rank == 3 then
            item.BackgroundColor3 = Color3.fromRGB(205, 127, 50) -- 铜色
        end

        item.Parent = List
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

    print("服务端：排行榜系统 (带头像版) 已激活！")
end

return RankingService
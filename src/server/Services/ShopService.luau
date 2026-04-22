-- src/server/Services/ShopService.luau
local ShopService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local SHOP_SLOT_COUNT = 10     
local REFRESH_INTERVAL = 300   -- 5分钟补货一次

local currentShopStock = {}
local nextRefreshTime = 0

-- [🌟 核心逻辑：精准补货数量判定]
function ShopService.RefreshStock()
    currentShopStock = {}
    
    -- 获取配置中所有的种子并按 ID 排序
    local seedKeys = {}
    for k, _ in pairs(ItemConfig.Seeds) do table.insert(seedKeys, k) end
    table.sort(seedKeys, function(a, b) return (ItemConfig.Seeds[a].Id or 0) < (ItemConfig.Seeds[b].Id or 0) end)

    for i = 1, SHOP_SLOT_COUNT do
        local seedId = seedKeys[i]
        if seedId then
            local itemDetail = ItemConfig.Seeds[seedId]
            local restockAmount = 1 -- 默认补 1
            
            -- 根据 ID 判定补货量
            if itemDetail.Id == 1 then
                restockAmount = 5
            elseif itemDetail.Id == 2 then
                restockAmount = 3
            end

            table.insert(currentShopStock, {
                SeedId = seedId,
                Stock = restockAmount
            })
        else
            -- 种子配置不足 10 个时，放入空位占位
            table.insert(currentShopStock, { SeedId = nil, Stock = 0 })
        end
    end
    
    nextRefreshTime = os.time() + REFRESH_INTERVAL
    
    -- 通知所有玩家：货补好了！
    local updateShopRE = ReplicatedStorage:FindFirstChild("UpdateShopRE")
    if updateShopRE then updateShopRE:FireAllClients(currentShopStock, nextRefreshTime) end
end

function ShopService.Init()
    local updateShopRE = ReplicatedStorage:FindFirstChild("UpdateShopRE") or Instance.new("RemoteEvent")
    updateShopRE.Name = "UpdateShopRE"
    updateShopRE.Parent = ReplicatedStorage

    local getShopDataRF = ReplicatedStorage:FindFirstChild("GetShopDataRF") or Instance.new("RemoteFunction")
    getShopDataRF.Name = "GetShopDataRF"
    getShopDataRF.Parent = ReplicatedStorage
    
    getShopDataRF.OnServerInvoke = function(player)
        return currentShopStock, nextRefreshTime
    end

    local buyItemRF = ReplicatedStorage:FindFirstChild("BuyItemRF") or Instance.new("RemoteFunction")
    buyItemRF.Name = "BuyItemRF"
    buyItemRF.Parent = ReplicatedStorage

    buyItemRF.OnServerInvoke = function(player, slotIndex, amount)
        amount = amount or 1 
        local slotData = currentShopStock[slotIndex]
        if not slotData or not slotData.SeedId then return false, "商品无效" end
        
        local itemDetail = ItemConfig.Seeds[slotData.SeedId]
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return false, "存档加载中" end

        -- 关卡判定
        if data.UnlockedLevel < (itemDetail.UnlockLevel or 1) then
            return false, "关卡不足，请先推关！"
        end

        -- 库存判定
        if slotData.Stock < amount then return false, "库存卖光啦，等补货吧！" end

        local totalCost = itemDetail.BuyPrice * amount
        if data.Coins >= totalCost then
            data.Coins = data.Coins - totalCost
            slotData.Stock = slotData.Stock - amount 
            
            PlayerDataManager.GiveSeed(player, slotData.SeedId, amount)
            -- 全服同步库存减少
            if updateShopRE then updateShopRE:FireAllClients(currentShopStock, nextRefreshTime) end
            return true, "购买成功"
        else
            return false, "金币不够哦"
        end
    end

    -- 启动补货循环
    task.spawn(function()
        ShopService.RefreshStock() 
        while true do
            task.wait(1)
            if os.time() >= nextRefreshTime then
                ShopService.RefreshStock()
            end
        end
    end)
end

return ShopService
-- src/server/Services/ShopService.luau
local ShopService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

function ShopService.Init()
    local buyItemRF = Instance.new("RemoteFunction")
    buyItemRF.Name = "BuyItemRF"
    buyItemRF.Parent = ReplicatedStorage

    buyItemRF.OnServerInvoke = function(player, seedId, amount)
        amount = amount or 1 
        
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return false, "数据异常" end

        local itemDetail = ItemConfig.Seeds[seedId]
        if not itemDetail then return false, "物品不存在" end

        local totalCost = itemDetail.BuyPrice * amount

        if data.Coins >= totalCost then
            data.Coins = data.Coins - totalCost
            PlayerDataManager.GiveSeed(player, seedId, amount)
            

           
            -- ==========================================
            
            print("【商店系统】" .. player.Name .. " 花费 " .. totalCost .. " 金币购买了 " .. amount .. " 个 " .. itemDetail.Name)
            return true, "购买成功"
        else
            print("【商店系统】" .. player.Name .. " 金币不足，购买失败！")
            return false, "金币不足"
        end
    end

    print("服务端：ShopService 加载完毕！新手任务监听已挂载。")
end

return ShopService

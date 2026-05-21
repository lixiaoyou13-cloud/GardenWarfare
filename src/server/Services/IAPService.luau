-- src/server/Services/IAPService.luau
local IAPService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local PRODUCT_NEWBIE_GIFT = 3594585526 -- 你的内购商品 ID

function IAPService.Init()
    -- 监听玩家支付完成的回调
    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = game.Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player then
            -- 如果玩家断线，保留订单，等他下次上线再处理
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        -- 判定是否购买了【新手限时礼包】
        if receiptInfo.ProductId == PRODUCT_NEWBIE_GIFT then
            local data = PlayerDataManager.GetPlayerData(player)
            if data and not data.NewbieGiftPurchased then
                -- 发放奖励: 6个 CoconutTree 种子
                -- 这里的 true 抑制了默认提示，我们在下方手动触发更隆重的礼包提示
                PlayerDataManager.GiveSeed(player, "CoconutTree", 6, true)
                
                -- 标记已购买
                data.NewbieGiftPurchased = true
                
                -- 同步数据给客户端（客户端收到已购买状态会自动销毁 UI）
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                
                print("玩家 " .. player.Name .. " 购买限时礼包成功！奖励已发。")

                -- ==========================================
                -- 🌟 新增：触发全屏礼花、震动与文字提示
                -- ==========================================
                local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                if playObtainEffectRE then
                    -- 这里的文字会显示在屏幕正中，你可以自定义修改
                    playObtainEffectRE:FireClient(player, "Purchase Successful! Obtained 6x CoconutTree!") 
                end
            end
            
            -- 返回购买成功，通知 Roblox 扣款
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        -- 默认不处理未知商品
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

return IAPService
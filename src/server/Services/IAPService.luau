-- src/server/Services/IAPService.luau
local IAPService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local PRODUCT_NEWBIE_GIFT = 3594585526 -- 新手礼包 ID
local PRODUCT_SEVEN_DAY = 3582734340   -- 七天签到一键领取的内购 ID

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
            return {
                ItemType = "Seed",
                ItemId = seedId,
                Amount = seedDetail.IAPAmount or seedDetail.Amount or 1,
                Name = seedDetail.Name or seedId,
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
        PlayerDataManager.GivePlant(player, reward.ItemId, reward.Amount, reward.Mutation or 1)
        return true
    end

    return false
end

function IAPService.Init()
    -- 1. 补偿弹窗事件
    local showPopupRE = ReplicatedStorage:FindFirstChild("ShowCompensationPopupRE")
    if not showPopupRE then
        showPopupRE = Instance.new("RemoteEvent")
        showPopupRE.Name = "ShowCompensationPopupRE"
        showPopupRE.Parent = ReplicatedStorage
    end

    -- 2. 🌟 新增：主动购买意向记录事件（用于精准区分新老订单）
    local markIntentRE = ReplicatedStorage:FindFirstChild("MarkPurchaseIntentRE")
    if not markIntentRE then
        markIntentRE = Instance.new("RemoteEvent")
        markIntentRE.Name = "MarkPurchaseIntentRE"
        markIntentRE.Parent = ReplicatedStorage
    end

    -- 记录玩家近期是否点过购买按钮
    local activePurchaseIntents = {}
    markIntentRE.OnServerEvent:Connect(function(player)
        activePurchaseIntents[player.UserId] = os.time()
    end)

    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        -- ==========================================
        -- [1] 判定是否购买了【新手限时礼包】
        -- ==========================================
        if receiptInfo.ProductId == PRODUCT_NEWBIE_GIFT then
            local data = PlayerDataManager.GetPlayerData(player)
            if data and not data.NewbieGiftPurchased then
                PlayerDataManager.GiveSeed(player, "CoconutTree", 6, true)
                data.NewbieGiftPurchased = true
                
                local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                
                local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                if playObtainEffectRE then
                    playObtainEffectRE:FireClient(player, "Purchase Successful!\nObtained 6x CoconutTree!") 
                end
            end
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        -- ==========================================
        -- [2] 判定是否购买了【七天签到一键领取】
        -- ==========================================
        if receiptInfo.ProductId == PRODUCT_SEVEN_DAY then
            local data = PlayerDataManager.GetPlayerData(player)
            if data then
                local currentDays = data.SignInDays or 0
                if currentDays < 7 then
                    -- 无论新老订单，基础的 1-7 天奖励必须发
                    for day = currentDays + 1, 7 do
                        PlayerDataManager.GrantSignInReward(player, day)
                    end
                    
                    data.SignInDays = 7
                    data.LastSignInTime = os.time()
                    
                    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                    if updateInventoryRE then updateInventoryRE:FireClient(player, data) end
                    
                    -- 🌟 核心判断：检查玩家在过去 5 分钟内是否主动点过“购买”按钮
                    local intentTime = activePurchaseIntents[player.UserId] or 0
                    local isNewPurchase = (os.time() - intentTime) < 300 
                    
                    if not isNewPurchase then
                        -- 【情况 A：历史老订单】(系统上线自动触发，玩家没点按钮)
                        PlayerDataManager.GivePlant(player, "CobCannon", 1, 1)
                        
                        local popupRE = ReplicatedStorage:FindFirstChild("ShowCompensationPopupRE")
                        if popupRE then
                            popupRE:FireClient(player, "A bug occurred with the 7-Day Sign-In rewards.\nPlease accept this Cob Cannon as compensation.\nWe sincerely apologize for the inconvenience!")
                        end
                        print("【系统】玩家 " .. player.Name .. " 历史七天签到订单补发完成，已发加农炮补偿。")
                    else
                        -- 【情况 B：今天的新订单】(玩家刚刚自己点了购买按钮)
                        local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
                        if playObtainEffectRE then
                            playObtainEffectRE:FireClient(player, "7-Day Rewards Unlocked!\nAll items sent to inventory.") 
                        end
                        print("【系统】玩家 " .. player.Name .. " 正常购买七天签到，无额外补偿。")
                        
                        -- 清除意向，防止重复判定
                        activePurchaseIntents[player.UserId] = nil
                    end
                end
            end
            
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        -- ==========================================
        -- [3] 商店植物/种子 Developer Product 购买
        -- ==========================================
        local shopReward = FindShopRewardByProductId(receiptInfo.ProductId)
        if shopReward then
            local data = PlayerDataManager.GetPlayerData(player)
            if not data then
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local granted = GrantShopReward(player, shopReward)
            if not granted then
                warn("[IAPService] Unknown shop reward type for productId: " .. tostring(receiptInfo.ProductId))
                return Enum.ProductPurchaseDecision.NotProcessedYet
            end

            local playObtainEffectRE = ReplicatedStorage:FindFirstChild("PlayObtainEffectRE")
            if playObtainEffectRE then
                playObtainEffectRE:FireClient(
                    player,
                    "Purchase Successful!\nObtained " .. tostring(shopReward.Amount) .. "x " .. tostring(shopReward.Name) .. "!"
                )
            end

            return Enum.ProductPurchaseDecision.PurchaseGranted
        end

        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

return IAPService
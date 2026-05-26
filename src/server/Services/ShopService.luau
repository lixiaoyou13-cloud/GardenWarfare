-- src/server/Services/ShopService.luau
local ShopService = {}
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
   
local REFRESH_INTERVAL = 300 -- 5分钟补货一次

local currentShopItems = {} 
local playerSpecificStock = {} 
local nextRefreshTime = 0

function ShopService.RefreshStock()
    currentShopItems = {}
    playerSpecificStock = {} 

    for _, seedId in ipairs(ItemConfig.IdToSeedKey or {}) do
        if seedId then
            local itemDetail = ItemConfig.Seeds[seedId]
            if itemDetail and itemDetail.IsSellable ~= false then
                local restockById = {
                    [1] = 20, 
                    [2] = 15, 
                    [3] = 10,
                    [4] = 6,
                    [5] = 6,
                    [6] = 6,
                    [7] = 20,
                    [8] = 6,
                    [9] = 6,
                    [10] = 6,
                    [11] = 6,
                    [12] = 6, 
                    [13] = 6, 
                    [14] = 6, 
                    [15] = 6, 
                    [16] = 3, 
                    [17] = 3, 
                    [18] = 2,
                    [19] = 1,

                }

                local restockAmount = restockById[itemDetail.Id] or 1
                table.insert(currentShopItems, { SeedId = seedId, MaxStock = restockAmount })
            end
        end
    end
    
    nextRefreshTime = os.time() + REFRESH_INTERVAL
    ShopService.BroadcastStockUpdate()
end

local function GetPlayerStockData(player)
    if not playerSpecificStock[player.UserId] then
        local personal = {}
        for i, item in ipairs(currentShopItems) do
            table.insert(personal, { SeedId = item.SeedId, Stock = item.MaxStock })
        end
        playerSpecificStock[player.UserId] = personal
    end
    return playerSpecificStock[player.UserId]
end

function ShopService.BroadcastStockUpdate()
    local updateShopRE = ReplicatedStorage:FindFirstChild("UpdateShopRE")
    if not updateShopRE then return end
    
    for _, player in ipairs(game.Players:GetPlayers()) do
        updateShopRE:FireClient(player, GetPlayerStockData(player), nextRefreshTime)
    end
end

-- 🌟 新增：服务端校验价格计算器 (防止外挂篡改价格)
local function CalculateItemPrice(compositeId)
    if not compositeId or compositeId == "" then return 0 end
    
    local parts = string.split(compositeId, "_")
    local itemType = parts[1]
    local realId = parts[2]
    local mutLvl = tonumber(parts[3]) or 1

    if itemType ~= "Seed" and itemType ~= "Plant" then return 0 end

    local seedDetail = ItemConfig.Seeds[realId]
    if not seedDetail then return 0 end

    local baseBuyPrice = seedDetail.BuyPrice or 0

    if itemType == "Seed" then
        return math.floor(baseBuyPrice * 0.8)
    elseif itemType == "Plant" then
        local price = baseBuyPrice * 1.2
        if mutLvl == 2 then price = price * 2
        elseif mutLvl == 3 then price = price * 3
        elseif mutLvl == 4 then price = price * 4
        end
        return math.floor(price)
    end
    return 0
end


function ShopService.Init()
    local updateShopRE = ReplicatedStorage:FindFirstChild("UpdateShopRE") or Instance.new("RemoteEvent")
    updateShopRE.Name = "UpdateShopRE"; updateShopRE.Parent = ReplicatedStorage

    local getShopDataRF = ReplicatedStorage:FindFirstChild("GetShopDataRF") or Instance.new("RemoteFunction")
    getShopDataRF.Name = "GetShopDataRF"; getShopDataRF.Parent = ReplicatedStorage
    getShopDataRF.OnServerInvoke = function(player) return GetPlayerStockData(player), nextRefreshTime end

    local buyItemRF = ReplicatedStorage:FindFirstChild("BuyItemRF") or Instance.new("RemoteFunction")
    buyItemRF.Name = "BuyItemRF"; buyItemRF.Parent = ReplicatedStorage

    buyItemRF.OnServerInvoke = function(player, slotIndex, amount)
        amount = amount or 1
        local personalStock = GetPlayerStockData(player)
        local slotData = personalStock[slotIndex]
        
        if not slotData or not slotData.SeedId then return false, "Invalid item" end
        
        local itemDetail = ItemConfig.Seeds[slotData.SeedId]
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return false, "Data loading..." end

        if data.UnlockedLevel < (itemDetail.UnlockLevel or 1) then return false, "Level too low!" end
        if slotData.Stock < amount then return false, "Out of stock!" end

        local totalCost = itemDetail.BuyPrice * amount
        if data.Coins >= totalCost then
            data.Coins = data.Coins - totalCost
            slotData.Stock = slotData.Stock - amount
            
            PlayerDataManager.GiveSeed(player, slotData.SeedId, amount)
            
            local shopSessionId = player:GetAttribute("CurrentShopSessionId")
            if shopSessionId then
                AnalyticsService:LogFunnelStepEvent(player, "Shop_Purchase_Flow", shopSessionId, 2, "Step_2_Buy_Success")
                player:SetAttribute("CurrentShopSessionId", nil) 
            end

            AnalyticsService:LogEconomyEvent(
                player,
                Enum.AnalyticsEconomyFlowType.Sink,  
                "Coins",                             
                totalCost,                            
                data.Coins,                           
                Enum.AnalyticsEconomyTransactionType.Shop.Name, 
                tostring(slotData.SeedId)             
            )
  
            updateShopRE:FireClient(player, personalStock, nextRefreshTime) 

            local updateInvRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            if updateInvRE then 
                updateInvRE:FireClient(player, data) 
            end
            
            return true, "Purchase successful!"
        else
            return false, "Not enough coins"
        end
    end

    -- 🌟 新增：处理单件出售逻辑
    local sellEquippedRF = Instance.new("RemoteFunction")
    sellEquippedRF.Name = "SellEquippedRF"
    sellEquippedRF.Parent = ReplicatedStorage
    sellEquippedRF.OnServerInvoke = function(player)
        local char = player.Character
        local equippedId = char and char:GetAttribute("EquippedSeed")
        
        if not equippedId or equippedId == "" then 
            return false, "Please equip a plant or seed" 
        end

        local price = CalculateItemPrice(equippedId)
        if price <= 0 then return false, "This item cannot be sold" end

        local parts = string.split(equippedId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1

        -- 调用你已经写好的 Consume 函数（会自动清理 Hotbar 如果用光）
        local consumeSuccess = false
        if itemType == "Seed" then
            consumeSuccess = PlayerDataManager.ConsumeSeed(player, realId, 1)
        elseif itemType == "Plant" then
            consumeSuccess = PlayerDataManager.ConsumePlant(player, realId, 1, mutLvl)
        end

        if consumeSuccess then
            PlayerDataManager.GiveCoins(player, price)
            
            AnalyticsService:LogEconomyEvent(
                player, Enum.AnalyticsEconomyFlowType.Source, "Coins", price, 
                PlayerDataManager.GetPlayerData(player).Coins,
                Enum.AnalyticsEconomyTransactionType.Shop.Name, "Sell_" .. equippedId
            )
            return true, "Earned $" .. tostring(price)
        else
            return false, "Item not found in inventory"
        end
    end

    -- 🌟 新增：处理批量出售快捷栏所有物品逻辑
    local sellAllHotbarRF = Instance.new("RemoteFunction")
    sellAllHotbarRF.Name = "SellAllHotbarRF"
    sellAllHotbarRF.Parent = ReplicatedStorage
    sellAllHotbarRF.OnServerInvoke = function(player)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data or not data.Hotbar then return false, "Data loading..." end

        local totalEarned = 0
        local soldCount = 0
        local newHotbar = {} -- 保存不可出售的工具

        -- 遍历快捷栏
        for _, compositeId in ipairs(data.Hotbar) do
            local parts = string.split(compositeId, "_")
            local itemType = parts[1]
            local realId = parts[2]
            local mutLvl = tonumber(parts[3]) or 1

            local unitPrice = CalculateItemPrice(compositeId)
            
            if unitPrice > 0 then
                -- 在背包中寻找这个物品，并将所有的存量一次性全部卖出
                if itemType == "Seed" and data.Inventory.Seeds then
                    for i = #data.Inventory.Seeds, 1, -1 do
                        local seedData = data.Inventory.Seeds[i]
                        if seedData.ID == realId then
                            totalEarned = totalEarned + (unitPrice * seedData.Quantity)
                            table.remove(data.Inventory.Seeds, i)
                            soldCount = soldCount + 1
                            break
                        end
                    end
                elseif itemType == "Plant" and data.Inventory.Plants then
                    for i = #data.Inventory.Plants, 1, -1 do
                        local plantData = data.Inventory.Plants[i]
                        if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl then
                            totalEarned = totalEarned + (unitPrice * plantData.Quantity)
                            table.remove(data.Inventory.Plants, i)
                            soldCount = soldCount + 1
                            break
                        end
                    end
                end
            else
                -- 不可出售的物品（如铲子 Tool_Shovel）保留在快捷栏中
                table.insert(newHotbar, compositeId)
            end
        end

        if soldCount > 0 then
            data.Hotbar = newHotbar
            
            -- 清空手上的装备，防止拿着幽灵物品
            local char = player.Character
            if char then
                local currentEq = char:GetAttribute("EquippedSeed")
                if currentEq and not string.find(currentEq, "Tool") then
                    ReplicatedStorage:WaitForChild("HoldItemRE"):FireClient(player, nil) -- 告诉客户端放下
                end
            end

            PlayerDataManager.GiveCoins(player, totalEarned)

            AnalyticsService:LogEconomyEvent(
                player, Enum.AnalyticsEconomyFlowType.Source, "Coins", totalEarned, 
                data.Coins, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Sell_All_Hotbar"
            )

            local updateInvRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
            if updateInvRE then updateInvRE:FireClient(player, data) end

            return true, "Earned $" .. tostring(totalEarned)
        else
            return false, "No items to sell in Hotbar"
        end
    end

    task.spawn(function()
        ShopService.RefreshStock() 
        while true do
            task.wait(1)
            if os.time() >= nextRefreshTime then ShopService.RefreshStock() end
        end
    end)
end

return ShopService
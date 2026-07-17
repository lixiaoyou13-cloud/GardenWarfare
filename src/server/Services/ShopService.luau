-- src/server/Services/ShopService.luau
local ShopService = {}
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local REFRESH_INTERVAL = 300 -- 5分钟补货一次数

local currentShopItems = {}
local playerSpecificStock = {}
local nextRefreshTime = 0

local function getSpecialShopConfig(seedDetail)
    local specialShop = seedDetail and seedDetail.SpecialShop
    if type(specialShop) ~= "table" then
        return nil
    end

    local chance = math.clamp(tonumber(specialShop.Chance) or 0, 0, 1)
    return {
        Chance = chance,
        Stock = math.max(1, math.floor(tonumber(specialShop.Stock) or 1)),
        Style = specialShop.Style,
    }
end

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function snapshotShopTransactionState(data)
    if type(data) ~= "table" then
        return nil
    end

    return {
        Coins = data.Coins,
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function restoreShopTransactionState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data.Coins = snapshot.Coins
    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function fireInventoryUpdate(player, data)
    local updateInvRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInvRE and player and player.Parent then
        updateInvRE:FireClient(player, data)
    end
end

local function saveShopTransaction(player, data, snapshot, stockSnapshot, context)
    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, context)
    if saveQueued then
        return true
    end

    warn("[ShopService] Failed to queue save after " .. tostring(context) .. " for "
        .. tostring(player and player.Name or "unknown") .. ": " .. tostring(saveErr))

    restoreShopTransactionState(data, snapshot)
    if stockSnapshot and player then
        playerSpecificStock[player.UserId] = cloneValue(stockSnapshot)
    end

    fireInventoryUpdate(player, data)

    local updateShopRE = ReplicatedStorage:FindFirstChild("UpdateShopRE")
    if updateShopRE and stockSnapshot and player and player.Parent then
        updateShopRE:FireClient(player, playerSpecificStock[player.UserId], nextRefreshTime)
    end

    local rollbackSaved, rollbackErr = PlayerDataManager.RequestSave(player, "rollback " .. tostring(context))
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[ShopService] Failed to queue rollback save after " .. tostring(context) .. " for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end

    return false, saveErr
end

function ShopService.RefreshStock()
    currentShopItems = {}
    playerSpecificStock = {}
    local stockedSeeds = {}

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
                    [24] = 1,

                }

                local restockAmount = restockById[itemDetail.Id] or 1
                table.insert(currentShopItems, { SeedId = seedId, MaxStock = restockAmount })
                stockedSeeds[seedId] = true
            end
        end
    end

    local specialSeedIds = {}
    for seedId, itemDetail in pairs(ItemConfig.Seeds or {}) do
        local specialShop = getSpecialShopConfig(itemDetail)
        if specialShop and not stockedSeeds[seedId] then
            table.insert(specialSeedIds, seedId)
        end
    end

    table.sort(specialSeedIds, function(a, b)
        local aDetail = ItemConfig.Seeds[a]
        local bDetail = ItemConfig.Seeds[b]
        return (tonumber(aDetail and aDetail.Id) or 9999) < (tonumber(bDetail and bDetail.Id) or 9999)
    end)

    for _, seedId in ipairs(specialSeedIds) do
        local itemDetail = ItemConfig.Seeds[seedId]
        local specialShop = getSpecialShopConfig(itemDetail)
        if specialShop then
            -- 特殊商店格子常驻；概率只决定本轮是否有库存，未刷出时显示为 0。
            local rolledStock = math.random() < specialShop.Chance and specialShop.Stock or 0
            table.insert(currentShopItems, {
                SeedId = seedId,
                MaxStock = rolledStock,
                SpecialShop = true,
                ShopStyle = specialShop.Style,
            })
            stockedSeeds[seedId] = true
        end
    end

    nextRefreshTime = os.time() + REFRESH_INTERVAL
    ShopService.BroadcastStockUpdate()
end

local function GetPlayerStockData(player)
    if not playerSpecificStock[player.UserId] then
        local personal = {}
        for i, item in ipairs(currentShopItems) do
            table.insert(personal, {
                SeedId = item.SeedId,
                Stock = item.MaxStock,
                SpecialShop = item.SpecialShop == true,
                ShopStyle = item.ShopStyle,
            })
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

-- 服务端校验价格计算器 (防止外挂篡改价格)
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
        return math.floor(baseBuyPrice * 0.3)
    elseif itemType == "Plant" then
        local price = baseBuyPrice * 0.4
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
        amount = math.max(1, math.floor(tonumber(amount) or 1))
        local personalStock = GetPlayerStockData(player)
        local slotData = personalStock[slotIndex]

        if not slotData or not slotData.SeedId then return false, "Invalid item" end

        local itemDetail = ItemConfig.Seeds[slotData.SeedId]
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return false, "Data loading..." end
        if not PlayerDataManager.IsDataSafeToSave(player) then return false, "Save unavailable. Please try again." end

        if data.UnlockedLevel < (itemDetail.UnlockLevel or 1) then return false, "Level too low!" end
        if slotData.Stock < amount then return false, "Out of stock!" end

        local totalCost = itemDetail.BuyPrice * amount
        if data.Coins >= totalCost then
            local dataSnapshot = snapshotShopTransactionState(data)
            local stockSnapshot = cloneValue(personalStock)

            data.Coins = data.Coins - totalCost
            slotData.Stock = slotData.Stock - amount

            PlayerDataManager.GiveSeed(player, slotData.SeedId, amount, true)

            local saved = saveShopTransaction(player, data, dataSnapshot, stockSnapshot, "shop purchase")
            if not saved then
                return false, "Save failed. Please try again."
            end

            local shopSessionId = player:GetAttribute("CurrentShopSessionId")
            if shopSessionId then
                AnalyticsService:LogFunnelStepEvent(player, "Shop_Purchase_Flow", shopSessionId, 2, "Step_2_Buy_Success")
                player:SetAttribute("CurrentShopSessionId", nil)
            end

            updateShopRE:FireClient(player, personalStock, nextRefreshTime)

            fireInventoryUpdate(player, data)

            return true, "Purchase successful!"
        else
            return false, "Not enough coins"
        end
    end

    -- 处理单件出售逻辑
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

        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return false, "Data loading..." end
        if not PlayerDataManager.IsDataSafeToSave(player) then return false, "Save unavailable. Please try again." end

        local dataSnapshot = snapshotShopTransactionState(data)

        local parts = string.split(equippedId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1

        -- 调用你已经写好的 Consume 函数（会自转动清理 Hotbar 如果用光）
        local consumeSuccess = false
        if itemType == "Seed" then
            consumeSuccess = PlayerDataManager.ConsumeSeed(player, realId, 1)
        elseif itemType == "Plant" then
            consumeSuccess = PlayerDataManager.ConsumePlant(player, realId, 1, mutLvl)
        end

        if consumeSuccess then
            PlayerDataManager.GiveCoinsRaw(player, price)

            local saved = saveShopTransaction(player, data, dataSnapshot, nil, "sell equipped item")
            if not saved then
                return false, "Save failed. Please try again."
            end

            return true, "Earned $" .. tostring(price)
        else
            return false, "Item not found in inventory"
        end
    end

    -- 处理批量出售快捷栏所有物品逻辑
    local sellAllHotbarRF = Instance.new("RemoteFunction")
    sellAllHotbarRF.Name = "SellAllHotbarRF"
    sellAllHotbarRF.Parent = ReplicatedStorage
    sellAllHotbarRF.OnServerInvoke = function(player)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data or not data.Hotbar then return false, "Data loading..." end
        if not PlayerDataManager.IsDataSafeToSave(player) then return false, "Save unavailable. Please try again." end

        local dataSnapshot = snapshotShopTransactionState(data)
        local totalEarned = 0
        local soldCount = 0
        local shouldClearHeldItem = false
        local newHotbar = {} -- 保持存不可出售的工具

        -- 遍历快捷栏
        for _, compositeId in ipairs(data.Hotbar) do
            local parts = string.split(compositeId, "_")
            local itemType = parts[1]
            local realId = parts[2]
            local mutLvl = tonumber(parts[3]) or 1

            local unitPrice = CalculateItemPrice(compositeId)

            if unitPrice > 0 then
                -- 在背包中寻找这个物品，并将所有的存量一次数性全部卖出
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
                -- 不可出售的物品（如铲子 Tool_Shovel）在快捷栏中
                table.insert(newHotbar, compositeId)
            end
        end

        if soldCount > 0 then
            data.Hotbar = newHotbar

            -- 清晰空手上的装备，防止拿着幽灵物品
            local char = player.Character
            if char then
                local currentEq = char:GetAttribute("EquippedSeed")
                if currentEq and not string.find(currentEq, "Tool") then
                    shouldClearHeldItem = true
                end
            end

            PlayerDataManager.GiveCoinsRaw(player, totalEarned)

            local saved = saveShopTransaction(player, data, dataSnapshot, nil, "sell all hotbar")
            if not saved then
                return false, "Save failed. Please try again."
            end

            if shouldClearHeldItem then
                ReplicatedStorage:WaitForChild("HoldItemRE"):FireClient(player, nil)
            end

            fireInventoryUpdate(player, data)

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

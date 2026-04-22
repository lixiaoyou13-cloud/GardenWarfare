-- src/server/Services/InventoryService.luau
local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

-- [🌟 核心优化：垃圾回收系统，返回是否进行了清理]
local function CleanUpGhostItems(data)
    if not data or not data.Hotbar then return false end
    local validHotbar = {}
    local changed = false
    
    for _, compositeId in ipairs(data.Hotbar) do
        local parts = string.split(compositeId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1
        
        local isValid = false
        if itemType == "Tool" or itemType == "System" then
            isValid = true 
        elseif itemType == "Seed" and data.Inventory.Seeds then
            for _, seedData in ipairs(data.Inventory.Seeds) do
                if seedData.ID == realId and seedData.Quantity > 0 then 
                    isValid = true; break 
                end
            end
        elseif itemType == "Plant" and data.Inventory.Plants then
            for _, plantData in ipairs(data.Inventory.Plants) do
                if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl and plantData.Quantity > 0 then 
                    isValid = true; break 
                end
            end
        end
        
        if isValid then
            table.insert(validHotbar, compositeId)
        else
            changed = true -- 发现了幽灵物品并准备剔除
        end
    end
    
    if changed then
        data.Hotbar = validHotbar
    end
    return changed
end

function InventoryService.Init()
    local equipItemRE = Instance.new("RemoteEvent")
    equipItemRE.Name = "EquipItemRE"
    equipItemRE.Parent = ReplicatedStorage

    local forceSelectRE = Instance.new("RemoteEvent")
    forceSelectRE.Name = "ForceSelectRE"
    forceSelectRE.Parent = ReplicatedStorage

    local removeHotbarRE = Instance.new("RemoteEvent")
    removeHotbarRE.Name = "RemoveHotbarRE"
    removeHotbarRE.Parent = ReplicatedStorage

    -- 移除物品逻辑
    removeHotbarRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if data and data.Hotbar then
            local found = false
            for i, id in ipairs(data.Hotbar) do
                if id == compositeId then
                    table.remove(data.Hotbar, i) 
                    found = true
                    break
                end
            end
            -- 顺便清理一下其他的幽灵
            if CleanUpGhostItems(data) or found then
                ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
            end
        end
    end)

    -- 装备/添加物品逻辑
    equipItemRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

        -- [🌟 核心修复 1]：先清理幽灵物品，如果清理了，立刻同步给客户端释放 UI 格子
        local cleaned = CleanUpGhostItems(data)
        if cleaned then
            ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
        end

        local parts = string.split(compositeId, "_")
        local itemType = parts[1]  
        local realId = parts[2]    
        local mutLvl = tonumber(parts[3]) or 1 

        local hasItem = false
        if itemType == "Seed" then
            if data.Inventory.Seeds then
                for _, seedData in ipairs(data.Inventory.Seeds) do
                    if seedData.ID == realId and seedData.Quantity > 0 then hasItem = true break end
                end
            end
        elseif itemType == "Plant" then
            if data.Inventory.Plants then
                for _, plantData in ipairs(data.Inventory.Plants) do
                    if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl and plantData.Quantity > 0 then 
                        hasItem = true break 
                    end
                end
            end
        end

        if hasItem then
            if not data.Hotbar then data.Hotbar = {} end
            local inHotbar = false
            for _, id in ipairs(data.Hotbar) do
                if id == compositeId then inHotbar = true break end
            end

            if inHotbar then
                forceSelectRE:FireClient(player, compositeId) 
            else
                -- [🌟 核心修复 2]：将上限提升至 10 (容纳更多变异品种)
                if #data.Hotbar < 10 then
                    table.insert(data.Hotbar, compositeId) 
                    ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
                else
                    -- 可选：给玩家发个通知说快捷栏满了
                    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                    if showNotifRE then
                        showNotifRE:FireClient(player, "⚠️ 快捷栏已满", "请先在背包中右键移除一些不常用的物品。")
                    end
                end
            end
        end
    end)

    print("服务端：InventoryService 加载完毕！溢出与幽灵物品 Bug 已根治！")
end

return InventoryService
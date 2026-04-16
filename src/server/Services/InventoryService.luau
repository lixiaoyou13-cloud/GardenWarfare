-- src/server/Services/InventoryService.luau
local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)


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

    removeHotbarRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if data and data.Hotbar then
            for i, id in ipairs(data.Hotbar) do
                if id == compositeId then
                    table.remove(data.Hotbar, i) 
                    ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
                    break
                end
            end
        end
    end)

    equipItemRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

        -- [🌟 核心原理 1：拆解标签] 比如把 "Plant_Peashooter" 拆成 "Plant" 和 "Peashooter"
        local parts = string.split(compositeId, "_")
        local itemType = parts[1]  -- 获取物品大类 (Seed 或 Plant)
        local realId = parts[2]    -- 获取真实 ID (Peashooter)

        local hasItem = false
        
        -- [🌟 核心原理 2：精准查房] 根据标签去对应的包裹里检查玩家是否真的有这个物品
        if itemType == "Seed" then
            if data.Inventory.Seeds then
                for _, seedData in ipairs(data.Inventory.Seeds) do
                    if seedData.ID == realId and seedData.Quantity > 0 then hasItem = true break end
                end
            end
        elseif itemType == "Plant" then
            if data.Inventory.Plants then
                for _, plantData in ipairs(data.Inventory.Plants) do
                    if plantData.ID == realId and plantData.Quantity > 0 then hasItem = true break end
                end
            end
        end

        -- [🌟 核心原理 3：登记入册] 把带有前缀的完整复合ID存入快捷栏
        if hasItem then
            if not data.Hotbar then data.Hotbar = {} end
            local inHotbar = false
            for _, id in ipairs(data.Hotbar) do
                if id == compositeId then inHotbar = true break end
            end

            if inHotbar then
                forceSelectRE:FireClient(player, compositeId) 
            else
                if #data.Hotbar < 9 then
                    table.insert(data.Hotbar, compositeId) 
                    ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
                    
                end
            end
        end
    end)

    print("服务端：InventoryService (背包服务) 加载完毕！双重标签系统上线！")
end

return InventoryService
-- src/server/Services/InventoryService.luau
local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))

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
            changed = true 
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

    -- ==========================================
    -- [战斗植物交换引擎 (F键)]
    -- ==========================================
    local swapCombatPlantRE = Instance.new("RemoteEvent")
    swapCombatPlantRE.Name = "SwapCombatPlantRE"
    swapCombatPlantRE.Parent = ReplicatedStorage

    -- 👇 [🌟 核心修改：接受 isCombatSwap 参数判定是否需要扣钱]
    swapCombatPlantRE.OnServerEvent:Connect(function(player, oldPlantModel, equippedCompositeId, isCombatSwap)
        if not oldPlantModel or not oldPlantModel.Parent then return end
        if not oldPlantModel:GetAttribute("IsCombatPlant") then return end
        
        local parts = string.split(equippedCompositeId, "_")
        if parts[1] ~= "Plant" then return end
        
        -- 👇 [🌟 新增：战斗置换服务端强校验，扣除 1000 阳光（金币）]
        if isCombatSwap then
            if not PlayerDataManager.ConsumeCoins(player, 1000) then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then 
                    showNotifRE:FireClient(player, "Notice", "Not enough Sun!") 
                end
                return -- 如果阳光不够，直接拦截置换行为
            end
        end
        -- 👆 新增结束

        local newPlantId = parts[2]
        local newMutLevel = tonumber(parts[3]) or 1

        local oldPlantId = oldPlantModel.Name
        local oldMutLevel = oldPlantModel:GetAttribute("MutationLevel") or 1
        local gridPart = oldPlantModel.Parent

        -- 库存数据转移 (扣掉准备种的，收回要挖掉的)
        if PlayerDataManager.ConsumePlant(player, newPlantId, 1, newMutLevel) then
            -- 👇 [🌟 静默收回旧植物]
            PlayerDataManager.GivePlant(player, oldPlantId, 1, oldMutLevel)

            -- 进行 3D 物理模型的替换
            local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
            local newTemplate = ItemModels and (ItemModels:FindFirstChild(newPlantId .. "_Plant") or ItemModels:FindFirstChild(newPlantId))
            
            if newTemplate then
                local cframe = oldPlantModel:GetPivot()
                PlayerDataManager.RemoveCombatPlant(player, gridPart.Name)
                oldPlantModel:Destroy()

                local newPlant = newTemplate:Clone()
                newPlant.Parent = gridPart
                newPlant:PivotTo(cframe)

                -- 👇 [🌟 核心修复：防止植物被踢飞，兼容动画]
                local plantConfig = ItemConfig.Plants[newPlantId]
                local targetAnimId = plantConfig and plantConfig.IdleAnimId

                for _, part in ipairs(newPlant:GetDescendants()) do
                    if part:IsA("BasePart") then
                        -- 1. 关闭碰撞，玩家会直接穿模，绝对无法踢飞植物
                        part.CanCollide = false 
                        
                        -- 2. 兼容动画的锚固逻辑（仅锚固主节点和特效，释放四肢交给动画控制）
                        if targetAnimId and newPlant.PrimaryPart and part == newPlant.PrimaryPart then
                            part.Anchored = true
                        elseif part.Name == "Glow" or part.Name == "HolyLight" or part.Name == "Lightning" then
                            part.Anchored = true
                        else
                            part.Anchored = not targetAnimId 
                        end
                    end
                end

                -- 3. 补充播放动画的逻辑，确保置换出来的植物也是活蹦乱跳的
                if targetAnimId then
                    local animController = newPlant:FindFirstChildOfClass("AnimationController") or newPlant:FindFirstChildOfClass("Humanoid")
                    if not animController then 
                        animController = Instance.new("AnimationController")
                        animController.Parent = newPlant 
                    end
                    local animator = animController:FindFirstChildOfClass("Animator")
                    if not animator then 
                        animator = Instance.new("Animator")
                        animator.Parent = animController 
                    end
                    local anim = Instance.new("Animation")
                    anim.AnimationId = targetAnimId
                    local track = animator:LoadAnimation(anim)
                    track.Priority = Enum.AnimationPriority.Idle
                    track.Looped = true
                    track:Play()
                end
                -- 👆 新增结束

                newPlant:SetAttribute("IsCombatPlant", true)
                newPlant:SetAttribute("MutationLevel", newMutLevel)
                
                if plantConfig then
                    local hp = plantConfig.HP or 100
                    local mutStats = ItemConfig.MutationStats and ItemConfig.MutationStats[newMutLevel]
                    if mutStats then hp = hp * (mutStats.HPMul or 1) end
                    newPlant:SetAttribute("MaxHealth", hp)
                    newPlant:SetAttribute("Health", hp)
                end
                
                EffectUtil.ApplyMutationEffects(newPlant, newMutLevel)
                
                PlayerDataManager.AddCombatPlant(player, gridPart.Name, newPlantId, newPlant:GetAttribute("Health"), newMutLevel)
            end
        end
    end)


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
            if CleanUpGhostItems(data) or found then
                ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
            end
        end
    end)

    equipItemRE.OnServerEvent:Connect(function(player, compositeId)
        local data = PlayerDataManager.GetPlayerData(player)
        if not data then return end

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
                    if seedData.ID == realId and seedData.Quantity > 0 then 
                        hasItem = true 
                        break 
                    end
                end
            end
        elseif itemType == "Plant" then
            if data.Inventory.Plants then
                for _, plantData in ipairs(data.Inventory.Plants) do
                    if plantData.ID == realId and (plantData.Mutation or 1) == mutLvl and plantData.Quantity > 0 then 
                        hasItem = true 
                        break 
                    end
                end
            end
        end

        if hasItem then
            if not data.Hotbar then data.Hotbar = {} end
                local inHotbar = false
                for _, id in ipairs(data.Hotbar) do
                    if id == compositeId then inHotbar = true 
                    break 
                end
            end

            if inHotbar then
                forceSelectRE:FireClient(player, compositeId) 
            else
                if #data.Hotbar < 10 then
                    table.insert(data.Hotbar, compositeId) 
                    ReplicatedStorage.UpdateInventoryRE:FireClient(player, data)
                    forceSelectRE:FireClient(player, compositeId)
                 else
                    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                    if showNotifRE then
                        showNotifRE:FireClient(player, "⚠️ Hotbar Full", "Please unequip some items from your hotbar first.")
                    end
                end
            end
        end
    end)

    print("服务端：InventoryService 加载完毕！无缝静默交换系统(SwapPlant)已上线！")
end

return InventoryService
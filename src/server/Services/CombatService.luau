-- src/server/Services/CombatService.luau
local CombatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local EquipmentService = require(script.Parent.EquipmentService)
local PlotService = require(script.Parent.PlotService)

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))

-- [🌟 引入植物 AI 大脑]
local PlantCombatAI = require(script.Parent.PlantCombatAI)

-- ==========================================
-- [核心：生成战斗植物并分发 AI]
-- ==========================================
local function SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel)
    local itemDetail = ItemConfig.Plants[plantId]
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local combatModel = itemModelsFolder:FindFirstChild(plantId .. "_Plant") or itemModelsFolder:FindFirstChild(plantId)
    
    if not combatModel or not itemDetail then return end

    local newFighter = combatModel:Clone()
    newFighter.Name = plantId
    
    newFighter:SetAttribute("IsCombatPlant", true)
    newFighter:SetAttribute("Health", currentHP)
    newFighter:SetAttribute("MaxHealth", maxHP)
    newFighter:SetAttribute("MutationLevel", mutationLevel or 1)
    
    -- 绑定地块格子的名字
    newFighter:SetAttribute("GridName", lawnPart.Name)
    if newFighter.PrimaryPart then newFighter.PrimaryPart:SetAttribute("GridName", lawnPart.Name) end

    -- 朝向与定位计算
    local plotNum = tonumber(string.match(lawnPart.Parent.Parent.Name, "%d+")) or 1
    local yRotation = (plotNum <= 4) and CFrame.Angles(0, math.rad(0), 0) or CFrame.Angles(0, math.rad(180), 0)
    local spawnCFrame = lawnPart.CFrame * CFrame.new(0, lawnPart.Size.Y/2 + (newFighter.PrimaryPart and newFighter.PrimaryPart.Size.Y/2 or 2), 0) * yRotation
    
    if newFighter:IsA("Model") then
        newFighter:PivotTo(spawnCFrame)
    else
        newFighter.CFrame = spawnCFrame
    end

    -- 碰撞与锚定设定
    local hasAnyAnim = itemDetail.IdleAnimation or itemDetail.AttackAnimation or itemDetail.RiseAnimation
    for _, part in pairs(newFighter:GetDescendants()) do
        if part:IsA("BasePart") then 
            part.CanCollide = false 
            part.CanQuery = true 
            part.Anchored = (not hasAnyAnim or part == newFighter.PrimaryPart)
        end
    end
    
    -- 激活发光特效
    EffectUtil.ApplyMutationEffects(newFighter, mutationLevel)
    
    newFighter.Parent = lawnPart
    lawnPart:SetAttribute("OccupiedBy", plantId)

    -- 隐藏种植提示符
    local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
    if prompt then prompt.Enabled = false end

    -- 播放待机动画 (如果有)
    local animator = newFighter:FindFirstChildOfClass("AnimationController") or newFighter:FindFirstChildOfClass("Humanoid")
    if animator then animator = animator:FindFirstChildOfClass("Animator") or Instance.new("Animator", animator) end

    if itemDetail.IdleAnimation and itemDetail.IdleAnimation ~= "" and animator then
        local anim = Instance.new("Animation")
        anim.AnimationId = itemDetail.IdleAnimation
        local idleTrack = animator:LoadAnimation(anim)
        idleTrack.Priority = Enum.AnimationPriority.Idle
        idleTrack.Looped = true
        idleTrack:Play() 
    end

    -- [🌟 智能移交控制权给 PlantCombatAI]
    local plot = lawnPart.Parent.Parent
    if itemDetail.ExplosionType then
        PlantCombatAI.StartExplosiveAI(newFighter, itemDetail, mutationLevel)
    elseif itemDetail.CanAttack then
        PlantCombatAI.StartShooterAI(newFighter, itemDetail, mutationLevel, plot)
    end
end

-- ==========================================
-- [初始化战斗服务：加载存档与部署植物逻辑]
-- ==========================================
function CombatService.Init()
    local plotsFolder = Workspace:WaitForChild("Plots")

    -- 1. 玩家进服：加载保存的战斗植物
    Players.PlayerAdded:Connect(function(player)
        local data = PlayerDataManager.GetPlayerData(player)
        local waitLimit = 0
       
        while not data and waitLimit < 20 do 
            task.wait(0.5)
            waitLimit += 1
            data = PlayerDataManager.GetPlayerData(player)
        end
        
        if not data then return end

        local plot = nil
        for i = 1, 20 do
            plot = PlotService.GetPlayerPlot(player)
            if plot then break end
            task.wait(0.5)
        end
        if not plot then return end

        if not data.CombatPlants then return end

        local lawnFolder = plot:FindFirstChild("Lawn")
        if not lawnFolder then return end

        for gridName, plantInfo in pairs(data.CombatPlants) do
            local lawnPart = lawnFolder:FindFirstChild(gridName)
            if lawnPart then
                local itemDetail = ItemConfig.Plants[plantInfo.PlantId]
                if itemDetail then
                    -- [🌟 载入存档植物 1.5 倍血量判定]
                    local baseMaxHP = itemDetail.HP or 300
                    local maxHP = (plantInfo.Mutation > 1) and math.floor(baseMaxHP * 1.5) or baseMaxHP
                    SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP, plantInfo.Mutation or 1)
                end
            end
        end
    end)

    -- 2. 给草坪挂载 F 键互动，让玩家可以部署植物
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not string.match(plot.Name, "Plot") then continue end

        local lawnFolder = plot:FindFirstChild("Lawn")
        if not lawnFolder then continue end

        for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
            if lawnPart:IsA("BasePart") then
                local prompt = Instance.new("ProximityPrompt")
                prompt.ActionText = "部署"
                prompt.ObjectText = "草坪"
                prompt.KeyboardKeyCode = Enum.KeyCode.F
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 8 
                prompt.Parent = lawnPart
                prompt.HoldDuration = 0.2 

                prompt.Triggered:Connect(function(player)
                    local myPlot = PlotService.GetPlayerPlot(player)
                    if myPlot ~= plot then return end
                    
                    if plot:GetAttribute("IsLevelActive") then
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then showNotifRE:FireClient(player, "⚠️ 无法操作", "战斗已经开始，无法在此时部署新植物！") end
                        return 
                    end
                    if lawnPart:GetAttribute("OccupiedBy") then return end

                    local character = player.Character
                    if not character then return end
                 
                    local equippedCompositeId = character:GetAttribute("EquippedSeed")
                    if not equippedCompositeId then return end

                    local parts = string.split(equippedCompositeId, "_")
                    local itemType = parts[1]
                    local plantId = parts[2]
                    local targetMutation = tonumber(parts[3]) or 1

                    if itemType ~= "Plant" then return end

                    if PlayerDataManager.ConsumePlant(player, plantId, 1, targetMutation) then
                        local data = PlayerDataManager.GetPlayerData(player)
                        local hasStock = false
                        if data and data.Inventory.Plants then
                            for _, pData in ipairs(data.Inventory.Plants) do
                                if pData.ID == plantId and (pData.Mutation or 1) == targetMutation and pData.Quantity > 0 then 
                                    hasStock = true; break 
                                end
                            end
                        end
               
                        if not hasStock then
                            EquipmentService.UpdateHoldItem(player, nil)
                            local holdItemRE = ReplicatedStorage:FindFirstChild("HoldItemRE")
                            if holdItemRE then holdItemRE:FireClient(player, nil) end
                        end

                        local itemDetail = ItemConfig.Plants[plantId]
                        -- [🌟 部署植物 1.5 倍血量判定]
                        local baseMaxHP = itemDetail.HP or 300
                        local maxHP = (targetMutation > 1) and math.floor(baseMaxHP * 1.5) or baseMaxHP
                        
                        SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation)
                        PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
                    end
                end)
            end
        end
    end
    print("服务端：CombatService 加载完毕！变异等级 1.5 倍加成和 PlantCombatAI 均实装完成！")
end

return CombatService
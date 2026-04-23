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

local PlantCombatAI = require(script.Parent.PlantCombatAI)

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
    newFighter:SetAttribute("GridName", lawnPart.Name)

    -- [朝向判定：0 和 180]
    local plotModel = lawnPart:FindFirstAncestorWhichIsA("Model") or lawnPart.Parent.Parent
    local plotName = plotModel.Name
    local plotNum = tonumber(string.match(plotName, "%d+")) or 1
    
    local basePos = lawnPart.Position + Vector3.new(0, lawnPart.Size.Y/2, 0)
    local yAngle = (plotNum <= 4) and 0 or math.rad(180) 
    local finalCFrame = CFrame.new(basePos) * CFrame.Angles(0, yAngle, 0)
    
    if newFighter.PrimaryPart then
        finalCFrame = finalCFrame * CFrame.new(0, newFighter.PrimaryPart.Size.Y/2, 0)
        newFighter:PivotTo(finalCFrame)
    else
        newFighter:SetPrimaryPartCFrame(finalCFrame)
    end

    -- [碰撞与锚定设定]
    local hasAnyAnim = itemDetail.IdleAnimId or itemDetail.AttackAnimation or itemDetail.RiseAnimation
    for _, part in pairs(newFighter:GetDescendants()) do
        if part:IsA("BasePart") then 
            part.CanCollide = false 
            part.CanQuery = true 
            part.Anchored = (not hasAnyAnim or part == newFighter.PrimaryPart)
        end
    end
    
    EffectUtil.ApplyMutationEffects(newFighter, mutationLevel)
    newFighter.Parent = lawnPart
    lawnPart:SetAttribute("OccupiedBy", plantId)

    local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
    if prompt then prompt.Enabled = false end

    -- [🌟 严谨的 Animator 创建逻辑，完美读取原版配置]
    local animController = newFighter:FindFirstChildOfClass("AnimationController") or newFighter:FindFirstChildOfClass("Humanoid")
    if not animController then 
        animController = Instance.new("AnimationController")
        animController.Parent = newFighter 
    end
    local animator = animController:FindFirstChildOfClass("Animator")
    if not animator then 
        animator = Instance.new("Animator")
        animator.Parent = animController 
    end

    if itemDetail.IdleAnimId and itemDetail.IdleAnimId ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = itemDetail.IdleAnimId
        local idleTrack = animator:LoadAnimation(anim)
        idleTrack.Priority = Enum.AnimationPriority.Idle
        idleTrack.Looped = true
        idleTrack:Play() 
    end

    -- 移交控制权
    if itemDetail.ExplosionType then
        PlantCombatAI.StartExplosiveAI(newFighter, itemDetail, mutationLevel)
    elseif itemDetail.CanAttack then
        PlantCombatAI.StartShooterAI(newFighter, itemDetail, mutationLevel, plotModel)
    end
end

function CombatService.Init()
    local plotsFolder = Workspace:WaitForChild("Plots")

    Players.PlayerAdded:Connect(function(player)
        local data = PlayerDataManager.GetPlayerData(player)
        local waitLimit = 0
        while not data and waitLimit < 20 do task.wait(0.5); waitLimit += 1; data = PlayerDataManager.GetPlayerData(player) end
        if not data then return end

        local plot = nil
        for i = 1, 20 do plot = PlotService.GetPlayerPlot(player); if plot then break end; task.wait(0.5) end
        if not plot or not data.CombatPlants then return end

        local lawnFolder = plot:FindFirstChild("Lawn")
        if not lawnFolder then return end

        for gridName, plantInfo in pairs(data.CombatPlants) do
            local lawnPart = lawnFolder:FindFirstChild(gridName)
            if lawnPart then
                local itemDetail = ItemConfig.Plants[plantInfo.PlantId]
                if itemDetail then
                    local baseMaxHP = itemDetail.HP or 300
                    local maxHP = (plantInfo.Mutation > 1) and math.floor(baseMaxHP * 1.5) or baseMaxHP
                    SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP, plantInfo.Mutation or 1)
                end
            end
        end
    end)

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local lawnFolder = plot:WaitForChild("Lawn", 10)
        if not lawnFolder then continue end

        for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
            if lawnPart:IsA("BasePart") then
                local prompt = Instance.new("ProximityPrompt")
                prompt.ActionText = "部署"; prompt.ObjectText = "草坪"
                prompt.KeyboardKeyCode = Enum.KeyCode.F
                prompt.MaxActivationDistance = 8; prompt.Parent = lawnPart
                prompt.HoldDuration = 0.2

                prompt.Triggered:Connect(function(player)
                    local myPlot = PlotService.GetPlayerPlot(player)
                    if myPlot ~= plot or plot:GetAttribute("IsLevelActive") or lawnPart:GetAttribute("OccupiedBy") then return end

                    local character = player.Character
                    local equippedCompositeId = character and character:GetAttribute("EquippedSeed")
                    if not equippedCompositeId then return end

                    local parts = string.split(equippedCompositeId, "_")
                    local plantId, targetMutation = parts[2], tonumber(parts[3]) or 1
                    
                    if parts[1] == "Plant" and PlayerDataManager.ConsumePlant(player, plantId, 1, targetMutation) then
                        local itemDetail = ItemConfig.Plants[plantId]
                        local baseMaxHP = itemDetail.HP or 300
                        local maxHP = (targetMutation > 1) and math.floor(baseMaxHP * 1.5) or baseMaxHP
                        
                        SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation)
                        PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
                    end
                end)
            end
        end
    end
end

return CombatService
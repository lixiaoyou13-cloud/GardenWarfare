-- src/server/Services/CombatService.luau
local CombatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local EquipmentService = require(script.Parent.EquipmentService)
local PlotService = require(script.Parent.PlotService)
local Debris = game:GetService("Debris")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- [🌟 全局辅助：通用特效激活系统]
local function ApplyMutationEffects(model, mutationLevel)
    mutationLevel = mutationLevel or 1
    local effectMap = { [2] = "Glow", [3] = "Lightning", [4] = "HolyLight" }
    
    for _, fxName in pairs(effectMap) do
        for _, node in ipairs(model:GetDescendants()) do
            if node.Name == fxName then
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                        child.Enabled = false
                    end
                end
            end
        end
    end
    
    local targetFx = effectMap[mutationLevel]
    if targetFx then
        for _, node in ipairs(model:GetDescendants()) do
            if node.Name == targetFx then
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                        child.Enabled = true
                    end
                end
            end
        end
    end
end

local function SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel)
    local itemDetail = ItemConfig.Plants[plantId]
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local combatModel = itemModelsFolder:FindFirstChild(plantId .. "_Plant") or itemModelsFolder:FindFirstChild(plantId)
    
    if combatModel and itemDetail then
        local newFighter = combatModel:Clone()
        newFighter.Name = plantId
       
        newFighter:SetAttribute("IsCombatPlant", true)
        newFighter:SetAttribute("Health", currentHP)
        newFighter:SetAttribute("MaxHealth", maxHP)
        newFighter:SetAttribute("MutationLevel", mutationLevel or 1)

        newFighter.PrimaryPart:SetAttribute("GridName", lawnPart.Name)
        newFighter:SetAttribute("GridName", lawnPart.Name)
        
        if newFighter:IsA("Model") and newFighter.PrimaryPart then
            newFighter:PivotTo(lawnPart.CFrame * CFrame.new(0, lawnPart.Size.Y/2 + newFighter.PrimaryPart.Size.Y/2, 0))
        end

        local targetAnimId = itemDetail.IdleAnimId
        local attackAnimId = itemDetail.AttackAnimation
        
        local hasAnyAnim = false
        if (targetAnimId and targetAnimId ~= "") or (attackAnimId and attackAnimId ~= "") then
            hasAnyAnim = true
        end

        local animController = nil
        local animator = nil

        if hasAnyAnim then
            animController = newFighter:FindFirstChildOfClass("AnimationController") or newFighter:FindFirstChildOfClass("Humanoid")
            if not animController then 
                animController = Instance.new("AnimationController")
                animController.Parent = newFighter 
            end
            animator = animController:FindFirstChildOfClass("Animator")
            if not animator then 
                animator = Instance.new("Animator")
                animator.Parent = animController 
            end
        end

        for _, part in pairs(newFighter:GetDescendants()) do
            if part:IsA("BasePart") then 
                part.CanCollide = false 
                part.CanQuery = true 
             
                if hasAnyAnim and newFighter.PrimaryPart and part == newFighter.PrimaryPart then
                    part.Anchored = true
                else
                    part.Anchored = not hasAnyAnim 
                end
            end
        end
        
        ApplyMutationEffects(newFighter, mutationLevel)

        newFighter.Parent = lawnPart
        lawnPart:SetAttribute("OccupiedBy", plantId)
        
        local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Enabled = false end

        local idleAnimTrack = nil
        if targetAnimId and targetAnimId ~= "" and animator then
            local anim = Instance.new("Animation"); anim.AnimationId = targetAnimId
            idleAnimTrack = animator:LoadAnimation(anim)
            idleAnimTrack.Priority = Enum.AnimationPriority.Idle
            idleAnimTrack.Looped = true
            idleAnimTrack:Play() 
        end

        if itemDetail.ExplosionType then
            local connection
            connection = newFighter:GetAttributeChangedSignal("Health"):Connect(function()
                local hp = newFighter:GetAttribute("Health")
                if hp <= 0 and not newFighter:GetAttribute("Exploded") then
                    newFighter:SetAttribute("Exploded", true)
                    
                    local rootPart = newFighter.PrimaryPart or newFighter:FindFirstChildWhichIsA("BasePart")
                    if not rootPart then return end

                    local checkCFrame = rootPart.CFrame
                    local checkSize = Vector3.new(14, 10, 14)
                    
                    if itemDetail.ExplosionType == "Row" then
                        checkSize = Vector3.new(4, 15, 100) 
                    end

                    local overlapParams = OverlapParams.new()
                    local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
                    local damagedZombies = {} 

                    for _, part in ipairs(hitParts) do
                        if part.CollisionGroup == "Zombies" then
                            local zModel = part:FindFirstAncestorOfClass("Model")
                            if zModel and not damagedZombies[zModel] then
                                damagedZombies[zModel] = true
                                local zHum = zModel:FindFirstChildOfClass("Humanoid")
                                
                                if zHum and zHum.Health > 0 then
                                    zHum.Health = zHum.Health - (itemDetail.ExplosionDamage or 1800)
                                    for _, p in pairs(zModel:GetDescendants()) do
                                        if p:IsA("BasePart") then p.Color = Color3.fromRGB(20, 20, 20) end
                                    end
                                end
                            end
                        end
                    end

                    local effectPart = Instance.new("Part")
                    effectPart.Anchored = true; effectPart.CanCollide = false; effectPart.Transparency = 1
                    effectPart.Parent = Workspace

                    if itemDetail.ExplosionType == "Row" then
                        effectPart.Size = Vector3.new(6, 1, 100) 
                        effectPart.Position = rootPart.Position - Vector3.new(0, 1.5, 0)
                        
                        local particles = Instance.new("ParticleEmitter", effectPart)
                        particles.Enabled = false 
                        particles.Texture = "rbxassetid://248625108" 
                        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
                        particles.Lifetime = NumberRange.new(0.05, 0.12)
                        particles.LightEmission = 1
                        particles.EmissionDirection = Enum.NormalId.Top 
                        particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10)})
                        particles.Speed = NumberRange.new(60, 100)
                        particles.Drag = 10
                        
                        task.delay(0.05, function() if particles then particles:Emit(100) end end)
                    else
                        effectPart.Position = rootPart.Position
                        local attachment = Instance.new("Attachment", effectPart)
                        local particles = Instance.new("ParticleEmitter", attachment)
                        particles.Enabled = false 
                        particles.Texture = "rbxassetid://248625108" 
                        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
                        particles.LightEmission = 1
                        particles.Lifetime = NumberRange.new(0.2, 0.4) 
                        particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12)})
                        particles.Speed = NumberRange.new(30, 50)
                        
                        task.delay(0.05, function() if particles then particles:Emit(60) end end)
                    end
                    Debris:AddItem(effectPart, 2)
                end
            end)
        end

        if itemDetail.CanAttack then
            task.spawn(function()
                local attackInterval = itemDetail.AttackInterval or 1.5
                local attackDamage = itemDetail.Attack or 20
                local plot = lawnPart.Parent.Parent 
                
                local attackAnimTrack = nil
                if attackAnimId and attackAnimId ~= "" and animator then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = attackAnimId
                    attackAnimTrack = animator:LoadAnimation(anim)
                    attackAnimTrack.Priority = Enum.AnimationPriority.Action
                    attackAnimTrack.Looped = false 
                end

                while newFighter.Parent do
                    local hp = newFighter:GetAttribute("Health") or 0
                    if hp <= 0 or newFighter:GetAttribute("IsDead") then
                        task.wait(0.5)
                        continue
                    end

                    local speedMult = plot:GetAttribute("GameSpeed") or 1
                    local rootPart = newFighter.PrimaryPart or newFighter:FindFirstChildWhichIsA("BasePart")
                    if not rootPart then task.wait(0.5); continue end

                    local overlapParams = OverlapParams.new()
                    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
                    overlapParams.FilterDescendantsInstances = {newFighter}
                    
                    local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -50)
                    local checkSize = Vector3.new(4, 5, 100) 
                    local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
                    
                    local targetZombieModel = nil
                    local targetHum = nil
                    local targetRoot = nil
                    local minDistance = math.huge

                    for _, part in ipairs(hitParts) do
                        if part.CollisionGroup == "Zombies" then
                            local zModel = part:FindFirstAncestorOfClass("Model")
                            local zHum = zModel and zModel:FindFirstChildOfClass("Humanoid")
                            if zHum and zHum.Health > 0 then
                                local zRoot = zModel.PrimaryPart or zModel:FindFirstChild("HumanoidRootPart")
                                if zRoot then
                                    local dist = (zRoot.Position - rootPart.Position).Magnitude
                                    if dist < minDistance then
                                        minDistance = dist
                                        targetZombieModel = zModel
                                        targetHum = zHum
                                        targetRoot = zRoot
                                    end
                                end
                            end
                        end
                    end

                    if targetZombieModel and targetHum and targetRoot then
                        
                        if attackAnimTrack then
                            if idleAnimTrack then idleAnimTrack:Stop(0.1) end 
                            attackAnimTrack:Stop() 
                            attackAnimTrack:Play(0.1)
                            attackAnimTrack:AdjustSpeed(speedMult) 
                        end

                        local windUpTime = math.min(0.3, attackInterval * 0.2) / speedMult
                        task.wait(windUpTime)

                        if newFighter.Parent and (newFighter:GetAttribute("Health") or 0) > 0 then
                            local projName = itemDetail.ProjectileName
                            local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo")
                            local projTemplate = ammoFolder and ammoFolder:FindFirstChild(projName)
                            
                            if projTemplate then 
                                local projectile = projTemplate:Clone()
                                projectile.CanCollide = false 
                                projectile.Anchored = true

                                local fireCFrame = rootPart.CFrame * CFrame.new(0, 1.5, -1.5) 
                                local posNode = newFighter:FindFirstChild("pos", true) or newFighter:FindFirstChild("Pos", true)
                                
                                if posNode then
                                    if posNode:IsA("Attachment") then
                                        fireCFrame = posNode.WorldCFrame
                                    elseif posNode:IsA("BasePart") then
                                        fireCFrame = posNode.CFrame
                                    end
                                end
                                
                                projectile.CFrame = fireCFrame
                                projectile.Parent = Workspace

                                Debris:AddItem(projectile, 10)

                                task.spawn(function()
                                    local baseSpeed = 25 
                                    local hasHit = false
                                    
                                    local startPos = projectile.Position
                                    local initialTargetPos = targetRoot.Position + Vector3.new(0, 1, 0)
                                    local initialDist = (initialTargetPos - startPos).Magnitude
                                    local flightTime = initialDist / baseSpeed
                                    local elapsedTime = 0
                                    local arcHeight = itemDetail.ArcHeight or 0
                                    
                                    while projectile and projectile.Parent do
                                        if not targetZombieModel.Parent or targetHum.Health <= 0 then
                                            projectile:Destroy()
                                            break
                                        end

                                        local currentSpeedMult = plot:GetAttribute("GameSpeed") or 1
                                        local dtLoop = task.wait() 
                                        local targetPos = targetRoot.Position + Vector3.new(0, 1, 0)
                                        
                                        if arcHeight > 0 then
                                            elapsedTime += dtLoop * currentSpeedMult
                                            local t = math.clamp(elapsedTime / flightTime, 0, 1)
                                            
                                            local p0 = startPos
                                            local p2 = targetPos
                                            local p1 = p0:Lerp(p2, 0.5) + Vector3.new(0, arcHeight, 0)
                                            
                                            local currentPos = (1-t)^2 * p0 + 2*(1-t)*t * p1 + t^2 * p2
                                            
                                            if t < 1 then
                                                local nextT = math.clamp(t + 0.05, 0, 1)
                                                local nextPos = (1-nextT)^2 * p0 + 2*(1-nextT)*nextT * p1 + nextT^2 * p2
                                                if (nextPos - currentPos).Magnitude > 0.001 then
                                                    projectile.CFrame = CFrame.lookAt(currentPos, nextPos)
                                                else
                                                    projectile.Position = currentPos
                                                end
                                            else
                                                hasHit = true
                                                break
                                            end
                                        else
                                            local currentPos = projectile.Position
                                            local direction = (targetPos - currentPos)
                                            local distanceToTarget = direction.Magnitude
                                            local moveStep = baseSpeed * currentSpeedMult * dtLoop
                                            
                                            if distanceToTarget <= moveStep then
                                                hasHit = true; break
                                            else
                                                projectile.CFrame = CFrame.lookAt(currentPos + direction.Unit * moveStep, targetPos)
                                            end
                                        end
                                    end
                                    
                                    if projectile and projectile.Parent then projectile:Destroy() end
                                
                                    if hasHit and targetHum and targetHum.Health > 0 then
                                        local hitPos = projectile.Position
                                        projectile:Destroy() 
                                        targetHum.Health = targetHum.Health - attackDamage
                                        
                                        local effectPart = Instance.new("Part")
                                        effectPart.Size = Vector3.new(1, 1, 1); effectPart.Transparency = 1
                                        effectPart.Anchored = true; effectPart.CanCollide = false
                                        effectPart.Position = hitPos; effectPart.Parent = Workspace
                                        
                                        local attachment = Instance.new("Attachment", effectPart)
                                        local particles = Instance.new("ParticleEmitter", attachment)
                                        particles.Texture = itemDetail.HitEffectTexture or "rbxassetid://243098098"
                                        local effectColor = itemDetail.HitEffectColor or Color3.fromRGB(255, 215, 0)
                                        particles.Color = ColorSequence.new(effectColor)
                                        particles.Size = NumberSequence.new(1, 0)
                                        particles.Rate = 500; particles.Speed = NumberRange.new(5, 10)
                                        particles.Lifetime = NumberRange.new(0.1, 0.3)
                                        
                                        particles:Emit(15) 
                                        Debris:AddItem(effectPart, 0.5) 
                                        
                                        for _, p in pairs(targetZombieModel:GetDescendants()) do
                                            if p:IsA("BasePart") then
                                                if not p:GetAttribute("OriginalColor") then p:SetAttribute("OriginalColor", p.Color) end
                                                p.Color = Color3.fromRGB(255, 0, 0)
                                                task.delay(0.1, function()
                                                    if p and p.Parent and targetHum and targetHum.Health > 0 then 
                                                        p.Color = p:GetAttribute("OriginalColor") 
                                                    end
                                                end)
                                            end
                                        end
                                    end
                                end)
                            end
                        end

                        local remainingTime = (attackInterval / speedMult) - windUpTime
                        if remainingTime > 0 then
                            task.wait(remainingTime)
                        end

                        if attackAnimTrack then
                            attackAnimTrack:Stop(0.1)
                            if idleAnimTrack and not idleAnimTrack.IsPlaying then
                                idleAnimTrack:Play(0.1)
                            end
                        end
                    else
                        if idleAnimTrack and not idleAnimTrack.IsPlaying then
                            idleAnimTrack:Play(0.1)
                        end
                        task.wait(0.1 / speedMult)
                    end
                end
            end)
        end

        return newFighter
    end
end

function CombatService.Init()
    local plotsFolder = Workspace:WaitForChild("Plots")

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
                    local maxHP = itemDetail.HP or 300
                    SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP, plantInfo.Mutation or 1)
                end
            end
        end
    end)

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
                                -- [🌟 核心修复 1：加上了 (pData.Mutation or 1) == targetMutation 的精准判定！]
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
                        local maxHP = itemDetail.HP or 300
                        
                        SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation)
                        PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
                    end
                end)
            end
        end
    end
    print("服务端：CombatService 加载完毕！实体变异特效解析及库存清空 Bug 已修复！")
end

return CombatService
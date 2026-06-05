-- src/server/Services/PlantCombatAI.luau
local PlantCombatAI = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local plantAttackVisualRE = ReplicatedStorage:FindFirstChild("PlantAttackVisualRE")
if not plantAttackVisualRE then
    plantAttackVisualRE = Instance.new("RemoteEvent")
    plantAttackVisualRE.Name = "PlantAttackVisualRE"
    plantAttackVisualRE.Parent = ReplicatedStorage
end

local PROJECTILE_SPEED = 25
local warnedProjectileIssues = {}

local function warnProjectileOnce(projectileName, message)
    local key = tostring(projectileName) .. ":" .. message
    if warnedProjectileIssues[key] then return end
    warnedProjectileIssues[key] = true
    warn(("[PlantCombatAI] %s: %s"):format(tostring(projectileName), message))
end

local function GetSafeGameSpeed(plot)
    local speedMult = plot and tonumber(plot:GetAttribute("GameSpeed")) or 1
    if speedMult ~= 1 and speedMult ~= 2 and speedMult ~= 4 then
        return 1
    end
    return speedMult
end

-- ==========================================
-- [1. 伤害文字与受击特效通用函数]
-- ==========================================
function PlantCombatAI.ShowDamageText(zombieModel, damage)
    local rootPart = zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart
    local head = zombieModel:FindFirstChild("Head") or rootPart
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DamageText"
    billboard.Size = UDim2.new(0, 60, 0, 25)
    
    local rx = math.random(-10, 10) / 10
    local ry = math.random(5, 15) / 10
    local rz = math.random(-10, 10) / 10
    billboard.StudsOffset = Vector3.new(rx, 1.5 + ry, rz)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 150

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "-" .. tostring(damage)
    textLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.FredokaOne
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.Parent = billboard

    billboard.Parent = head

    local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    local tween = TweenService:Create(billboard, tweenInfo, { StudsOffset = billboard.StudsOffset + Vector3.new(0, 1.5, 0) })
    local textTween = TweenService:Create(textLabel, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })

    tween:Play()
    textTween:Play()
    Debris:AddItem(billboard, 1.0) 
end

-- ==========================================
-- [2. 子弹开火与命中逻辑]
-- ==========================================
local function FireProjectile(plant, targetZombieModel, targetHum, itemDetail, attackDamage, plot)
    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    local targetRoot = targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart
    if not rootPart or not targetRoot then return end

    local projName = itemDetail.ProjectileName
    if type(projName) ~= "string" or projName == "" then return end

    local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo")
    local projTemplate = ammoFolder and ammoFolder:FindFirstChild(projName)
    if not projTemplate then
        warnProjectileOnce(projName, "ReplicatedStorage.Ammo template not found on server")
        return
    end

    local fireCFrame = rootPart.CFrame * CFrame.new(0, 1.5, -1.5) 
    local posNode = plant:FindFirstChild("pos", true) or plant:FindFirstChild("Pos", true)
    if posNode then
        if posNode:IsA("Attachment") then fireCFrame = posNode.WorldCFrame
        elseif posNode:IsA("BasePart") then fireCFrame = posNode.CFrame end
    end

    local speedMult = GetSafeGameSpeed(plot)
    local initialTargetPos = targetRoot.Position + Vector3.new(0, 1, 0)
    local initialDist = (initialTargetPos - fireCFrame.Position).Magnitude
    local flightTime = math.max(0.05, initialDist / (PROJECTILE_SPEED * speedMult))
    local arcHeight = itemDetail.ArcHeight or 0

    plantAttackVisualRE:FireAllClients(
        "Projectile",
        projName,
        fireCFrame,
        initialTargetPos,
        targetZombieModel,
        arcHeight,
        speedMult
    )

    task.delay(flightTime, function()
        if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then return end
        if not targetZombieModel.Parent or not targetHum.Parent or targetHum.Health <= 0 then return end

        targetRoot = targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart
        if not targetRoot then return end

        targetHum.Health = targetHum.Health - attackDamage

        local zombieChestPos = targetRoot.Position + Vector3.new(0, 1, 0)
        local currentRootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
        local toPlantDir = currentRootPart and (currentRootPart.Position - targetRoot.Position) or Vector3.new(1, 0, 0)
        local flatDir = Vector3.new(toPlantDir.X, 0, toPlantDir.Z)
        if flatDir.Magnitude > 0.001 then flatDir = flatDir.Unit else flatDir = Vector3.new(1, 0, 0) end
        local hitPos = zombieChestPos + flatDir * 1.2

        plantAttackVisualRE:FireAllClients(
            "Hit",
            targetZombieModel,
            attackDamage,
            hitPos,
            itemDetail.HitEffectTexture,
            itemDetail.HitEffectColor
        )
    end)
end

-- ==========================================
-- [3. 射手类植物 AI]
-- ==========================================
function PlantCombatAI.StartIdleAnimation(plant, itemDetail)
    if plant:GetAttribute("PlantCombatIdleStarted") then
        return
    end
    plant:SetAttribute("PlantCombatIdleStarted", true)

    task.spawn(function()
        local idleAnimTrack = nil
        local animController = plant:FindFirstChildOfClass("AnimationController") or plant:FindFirstChildOfClass("Humanoid")
        local animator = animController and (animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController))

        if itemDetail.IdleAnimId and itemDetail.IdleAnimId ~= "" and animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = itemDetail.IdleAnimId
            idleAnimTrack = animator:LoadAnimation(anim)
            idleAnimTrack.Priority = Enum.AnimationPriority.Idle
            idleAnimTrack.Looped = true
            idleAnimTrack:Play(0.1)
            anim:Destroy()
        end

        while plant.Parent and (plant:GetAttribute("Health") or 1) > 0 and not plant:GetAttribute("IsDead") do
            task.wait(1)
        end

        if idleAnimTrack then
            idleAnimTrack:Stop(0.1)
            idleAnimTrack:Destroy()
        end
        if plant then
            plant:SetAttribute("PlantCombatIdleStarted", nil)
        end
    end)
end

function PlantCombatAI.StartShooterAI(plant, itemDetail, mutationLevel, plot)
    if plant:GetAttribute("ShooterAIStarted") then
        return
    end
    plant:SetAttribute("ShooterAIStarted", true)

    task.spawn(function()
        local attackInterval = itemDetail.AttackInterval or 1.5
        local baseAttackDamage = itemDetail.Attack or 20
        local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
        local attackDamage = math.floor(baseAttackDamage * stats.DamageMul)
        
        local animController = plant:FindFirstChildOfClass("AnimationController") or plant:FindFirstChildOfClass("Humanoid")
        local animator = animController and animController:FindFirstChildOfClass("Animator")

        local idleAnimTrack = nil
        if itemDetail.IdleAnimId and itemDetail.IdleAnimId ~= "" and animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = itemDetail.IdleAnimId
            idleAnimTrack = animator:LoadAnimation(anim)
            idleAnimTrack.Priority = Enum.AnimationPriority.Idle
            idleAnimTrack.Looped = true
            anim:Destroy()
        end

        while plant.Parent do
            local hp = plant:GetAttribute("Health") or 0
            if hp <= 0 or plant:GetAttribute("IsDead") then task.wait(0.5); continue end

            local speedMult = GetSafeGameSpeed(plot)
            local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
            if not rootPart then task.wait(0.5); continue end

            local overlapParams = OverlapParams.new()
            overlapParams.FilterType = Enum.RaycastFilterType.Exclude
            overlapParams.FilterDescendantsInstances = {plant}
            
            local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -50)
            local checkSize = Vector3.new(4, 5, 100) 
            local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
            
            local targetZombieModel, targetHum = nil, nil
            local minDistance = math.huge 

            for _, part in ipairs(hitParts) do
                if part.CollisionGroup == "Zombies" then
                    local zModel = part:FindFirstAncestorOfClass("Model")
                    if zModel then
                       -- ==========================================
                        -- 👇 [🌟 核心修复 1]：对比僵尸和地块的主人 ID
                        local zombieOwnerId = zModel:GetAttribute("OwnerId")
                        local plotOwnerId = plot and plot:GetAttribute("OwnerId")
                        
                        -- 如果僵尸有主人，地块也有主人，且两者不是同一个人，说明是别人家的僵尸！忽略！
                        if zombieOwnerId and plotOwnerId and zombieOwnerId ~= plotOwnerId then
                            continue 
                        end
                        -- ==========================================

                        local zHum = zModel:FindFirstChildOfClass("Humanoid")
                        local zRoot = zModel:FindFirstChild("HumanoidRootPart") or zModel.PrimaryPart
                       
                        if zHum and zHum.Health > 0 and zRoot then
                            local dist = (zRoot.Position - rootPart.Position).Magnitude
                            if dist < minDistance then
                                minDistance = dist
                                targetZombieModel = zModel
                                targetHum = zHum
                            end
                        end
                    end
                end
            end

            if targetZombieModel and targetHum then
                if itemDetail.AttackAnimation and itemDetail.AttackAnimation ~= "" then
                    plantAttackVisualRE:FireAllClients("Attack", plant, itemDetail.AttackAnimation, speedMult)
                end

                local windUpTime = math.min(0.3, attackInterval * 0.2) / speedMult
                task.wait(windUpTime)

                if plant.Parent and (plant:GetAttribute("Health") or 0) > 0 then
                    FireProjectile(plant, targetZombieModel, targetHum, itemDetail, attackDamage, plot)
                end
                
                local cooldown = math.max(0.1, attackInterval - windUpTime) / speedMult
                task.wait(cooldown)
                
                if idleAnimTrack and not idleAnimTrack.IsPlaying then
                    idleAnimTrack:Play(0.1)
                end
            else
                if idleAnimTrack and not idleAnimTrack.IsPlaying then
                    idleAnimTrack:Play(0.1)
                end
                task.wait(0.1 / speedMult)
            end
        end

        if idleAnimTrack then
            idleAnimTrack:Stop(0.1)
            idleAnimTrack:Destroy()
        end
        if plant then
            plant:SetAttribute("ShooterAIStarted", nil)
        end
    end)
end

-- ==========================================
-- [4. 爆炸类植物 AI (🌟 已重构：纯起爆逻辑)]
-- ==========================================
function PlantCombatAI.TriggerExplosion(plant, itemDetail, mutationLevel)
    -- 防多次起爆锁
    if plant:GetAttribute("Exploded") then return end
    plant:SetAttribute("Exploded", true)
    
    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    if not rootPart then return end

    local checkCFrame = rootPart.CFrame
    local checkSize = Vector3.new(14, 10, 14)
    if itemDetail.ExplosionType == "Row" then checkSize = Vector3.new(4, 15, 100) end

    local overlapParams = OverlapParams.new()
    local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
    local damagedZombies = {} 

    for _, part in ipairs(hitParts) do
        if part.CollisionGroup == "Zombies" then
            local zModel = part:FindFirstAncestorOfClass("Model")
            if zModel and not damagedZombies[zModel] then
                -- 不炸别人家的僵尸
                local myPlot = plant.Parent and plant.Parent.Parent and plant.Parent.Parent.Parent
                local plotOwnerId = myPlot and myPlot:GetAttribute("OwnerId")
                local zombieOwnerId = zModel:GetAttribute("OwnerId")

                if zombieOwnerId and plotOwnerId and zombieOwnerId ~= plotOwnerId then
                    continue 
                end

                damagedZombies[zModel] = true
                local zHum = zModel:FindFirstChildOfClass("Humanoid")
                
                if zHum and zHum.Health > 0 then
                    local baseExplosionDamage = itemDetail.ExplosionDamage or 1800
                    local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
                    local explosionDamage = math.floor(baseExplosionDamage * stats.DamageMul)
                    
                    zHum.Health = zHum.Health - explosionDamage
                    
                    PlantCombatAI.ShowDamageText(zModel, explosionDamage)
                    
                    -- ==========================================
                    -- 👇 瞬间变黑，不再调用 FlashZombieRed
                    -- ==========================================
                    zModel:SetAttribute("IsCharred", true)
                    
                    for _, p in pairs(zModel:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Color = Color3.fromRGB(30, 30, 30)
                            p.Material = Enum.Material.Slate -- 变成粗糙的焦炭质感
                        end
                        if p:IsA("MeshPart") then
                            p.TextureID = "" -- 剥离模型自带的彩色贴图
                        end
                        if p:IsA("Decal") or p:IsA("Texture") then
                            p.Transparency = 1 -- 隐藏脸部/表面贴图
                        end
                        if p:IsA("Clothing") or p:IsA("Shirt") or p:IsA("Pants") or p:IsA("ShirtGraphic") or p:IsA("CharacterMesh") then
                            p:Destroy() -- 把衣服瞬间烧光
                        end
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
        particles.Texture = "rbxassetid://248625108" 
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
        particles.Lifetime = NumberRange.new(0.05, 0.12)
        particles.LightEmission = 1
        particles.EmissionDirection = Enum.NormalId.Top 
        particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10)})
        particles.Rate = 2000
        particles.Speed = NumberRange.new(15, 30)
        task.delay(0.5, function() particles.Enabled = false end)
    else
        effectPart.Position = rootPart.Position
        local attachment = Instance.new("Attachment", effectPart)
        local particles = Instance.new("ParticleEmitter", attachment)
        particles.Texture = "rbxassetid://243098098"
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0))
        particles.Size = NumberSequence.new(1, 15)
        particles.Rate = 500
        particles.Speed = NumberRange.new(10, 20)
        particles.Lifetime = NumberRange.new(0.2, 0.4)
        particles.SpreadAngle = Vector2.new(180, 180)
        task.delay(0.2, function() particles.Enabled = false end)
    end

    Debris:AddItem(effectPart, 2)
    
    for _, p in pairs(plant:GetDescendants()) do
        if p:IsA("BasePart") then 
            p.Transparency = 1 
        elseif p:IsA("ParticleEmitter") or p:IsA("Light") or p:IsA("Beam") or p:IsA("Highlight") or p:IsA("Trail") then
            p.Enabled = false
        end
    end
    task.delay(1, function() if plant then plant:Destroy() end end)
end

return PlantCombatAI

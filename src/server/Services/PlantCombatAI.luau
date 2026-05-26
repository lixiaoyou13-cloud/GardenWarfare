-- src/server/Services/PlantCombatAI.luau
local PlantCombatAI = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
-- 👇 [🌟 增加这一行，把特效工具箱拿过来]
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))

-- ==========================================
-- [🌟 新增：受击变红反馈逻辑]
-- ==========================================
local function FlashZombieRed(zombieModel)
    -- 如果僵尸已经处于变红状态，直接返回，不再记录颜色
    if zombieModel:GetAttribute("IsFlashing") then return end
    zombieModel:SetAttribute("IsFlashing", true)
    
    local originalColors = {}
    
    -- 记录并变红
    for _, p in pairs(zombieModel:GetDescendants()) do
        if p:IsA("BasePart") then
            originalColors[p] = p.Color
            p.Color = Color3.fromRGB(255, 80, 80) -- 明显的受击红
        end
    end
    
    -- 0.15秒后恢复原色
    task.delay(0.15, function()
        -- 核心防御：如果僵尸已被销毁，不再执行恢复逻辑
        if not zombieModel or not zombieModel.Parent then return end
        
        -- 👇 [🌟 核心修复]：检查僵尸是否在此期间被炸弹炸成了焦黑状态
        local isCharred = zombieModel:GetAttribute("IsCharred")
        
        for p, color in pairs(originalColors) do
            if p and p.Parent then
                -- 如果被炸黑了，强制保持焦黑色 (30,30,30)；否则正常恢复原色
                p.Color = isCharred and Color3.fromRGB(30, 30, 30) or color
            end
        end
        
        -- 解除状态锁
        zombieModel:SetAttribute("IsFlashing", false)
    end)
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
-- [🌟 极简特效函数：直接复制，原汁原味]
-- ==========================================
local function PlayHitEffect(hitPos, itemDetail)
    local effectPart = Instance.new("Part")
    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
    effectPart.Transparency = 1
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.Position = hitPos
    effectPart.Parent = Workspace

    local hitEffectName = itemDetail and itemDetail.HitEffectTexture
    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local hitEffectPrefab = nil

    if typeof(hitEffectName) == "string" and hitEffectName ~= "" and hitFolder then
        local template = hitFolder:FindFirstChild(hitEffectName)
        if template and template:IsA("BasePart") then
            hitEffectPrefab = template
        end
    end

    if hitEffectPrefab then
        local clone = hitEffectPrefab:Clone()
        clone.Anchored = true
        clone.CanCollide = false
        clone.CFrame = CFrame.new(hitPos)
        clone.Parent = Workspace

        -- 等一瞬间让客户端先渲染出克隆体，避免 Roblox 吞掉瞬发 Emit
        task.wait(0.05)

        for _, child in ipairs(clone:GetDescendants()) do
            if child:IsA("ParticleEmitter") then
                local emitCount = child:GetAttribute("EmitCount")
                if not emitCount then
                    local countValueNode = child:FindFirstChild("EmitCount")
                    if countValueNode and (countValueNode:IsA("IntValue") or countValueNode:IsA("NumberValue")) then
                        emitCount = countValueNode.Value
                    end
                end

                emitCount = tonumber(emitCount)
                if not emitCount or emitCount <= 0 then
                    emitCount = 15
                end

                child.Enabled = true
                child:Emit(emitCount)
                task.delay(0.15, function()
                    if child and child.Parent then
                        child.Enabled = false
                    end
                end)
            elseif child:IsA("Light") then
                child.Enabled = true
                task.delay(0.15, function()
                    if child and child.Parent then
                        child.Enabled = false
                    end
                end)
            end
        end

        Debris:AddItem(clone, 1.5)
    else
        local attachment = Instance.new("Attachment", effectPart)
        local particles = Instance.new("ParticleEmitter", attachment)
        particles.Texture = (itemDetail and itemDetail.HitEffectTexture) or "rbxassetid://243098098"
        particles.Color = ColorSequence.new((itemDetail and itemDetail.HitEffectColor) or Color3.fromRGB(255, 215, 0))
        particles.Size = NumberSequence.new(1, 0)
        particles.Rate = 0
        particles.Speed = NumberRange.new(5, 10)
        particles.Lifetime = NumberRange.new(0.1, 0.3)
        particles:Emit(15)
    end
    
    Debris:AddItem(effectPart, 1.5)
end

-- ==========================================
-- [2. 子弹开火与命中逻辑]
-- ==========================================
local function FireProjectile(plant, targetZombieModel, targetHum, itemDetail, attackDamage, plot)
    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    local targetRoot = targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart
    if not rootPart or not targetRoot then return end

    local projName = itemDetail.ProjectileName
    local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo")
    local projTemplate = ammoFolder and ammoFolder:FindFirstChild(projName)
    if not projTemplate then return end

    local projectile = projTemplate:Clone()
    projectile.CanCollide = false 
    projectile.Anchored = true

    local fireCFrame = rootPart.CFrame * CFrame.new(0, 1.5, -1.5) 
    local posNode = plant:FindFirstChild("pos", true) or plant:FindFirstChild("Pos", true)
    if posNode then
        if posNode:IsA("Attachment") then fireCFrame = posNode.WorldCFrame
        elseif posNode:IsA("BasePart") then fireCFrame = posNode.CFrame end
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
                local currentPosUpdate = (1-t)^2 * p0 + 2*(1-t)*t * p1 + t^2 * p2
                
                if t < 1 then
                    local nextT = math.clamp(t + 0.05, 0, 1)
                    local nextPos = (1-nextT)^2 * p0 + 2*(1-nextT)*nextT * p1 + nextT^2 * p2
                    if (nextPos - currentPosUpdate).Magnitude > 0.001 then
                        projectile.CFrame = CFrame.lookAt(currentPosUpdate, nextPos)
                    else
                        projectile.Position = currentPosUpdate
                    end
                else
                    hasHit = true
                    break
                end
            else
                local currentPosUpdate = projectile.Position
                local direction = (targetPos - currentPosUpdate)
                local distanceToTarget = direction.Magnitude
                local moveStep = baseSpeed * currentSpeedMult * dtLoop
                
                if distanceToTarget <= moveStep then
                    hasHit = true; break
                else
                    projectile.CFrame = CFrame.lookAt(currentPosUpdate + direction.Unit * moveStep, targetPos)
                end
            end
        end
        
        if projectile and projectile.Parent then projectile:Destroy() end
        
        -- [子弹命中处理]
        if hasHit and targetHum and targetHum.Health > 0 then
            targetHum.Health = targetHum.Health - attackDamage
            
            -- [🌟 修复：呼叫变红反馈和伤害数字]
            FlashZombieRed(targetZombieModel)
            PlantCombatAI.ShowDamageText(targetZombieModel, attackDamage)
            
            local zombieChestPos = targetRoot.Position + Vector3.new(0, 1, 0) 
            local toPlantDir = (rootPart.Position - targetRoot.Position) 
            local flatDir = Vector3.new(toPlantDir.X, 0, toPlantDir.Z)
            
            if flatDir.Magnitude > 0.001 then flatDir = flatDir.Unit else flatDir = Vector3.new(1, 0, 0) end
            local hitPos = zombieChestPos + flatDir * 1.2
            
            PlayHitEffect(hitPos, itemDetail)
        end
    end)
end

-- ==========================================
-- [3. 射手类植物 AI]
-- ==========================================
function PlantCombatAI.StartShooterAI(plant, itemDetail, mutationLevel, plot)
    task.spawn(function()
        local attackInterval = itemDetail.AttackInterval or 1.5
        local baseAttackDamage = itemDetail.Attack or 20
        local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
        local attackDamage = math.floor(baseAttackDamage * stats.DamageMul)
        
        local animController = plant:FindFirstChildOfClass("AnimationController") or plant:FindFirstChildOfClass("Humanoid")
        local animator = animController and animController:FindFirstChildOfClass("Animator")
        
        local attackAnimTrack = nil
        if itemDetail.AttackAnimation and itemDetail.AttackAnimation ~= "" and animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = itemDetail.AttackAnimation
            attackAnimTrack = animator:LoadAnimation(anim)
            attackAnimTrack.Priority = Enum.AnimationPriority.Action
            attackAnimTrack.Looped = false

            -- ==========================================
            -- 👇 [🌟 新增：在这里监听攻击动画打好的关键帧！]
            -- ==========================================
            attackAnimTrack:GetMarkerReachedSignal("VFX"):Connect(function()
             
                EffectUtil.PlayAttackVFX(plant)
            end)
            -- ==========================================
        end

        local idleAnimTrack = nil
        if itemDetail.IdleAnimId and itemDetail.IdleAnimId ~= "" and animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = itemDetail.IdleAnimId
            idleAnimTrack = animator:LoadAnimation(anim)
            idleAnimTrack.Priority = Enum.AnimationPriority.Idle
            idleAnimTrack.Looped = true
        end

        while plant.Parent do
            local hp = plant:GetAttribute("Health") or 0
            if hp <= 0 or plant:GetAttribute("IsDead") then task.wait(0.5); continue end

            local speedMult = plot:GetAttribute("GameSpeed") or 1
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
                if attackAnimTrack then
                    if idleAnimTrack then idleAnimTrack:Stop(0.1) end
                    attackAnimTrack:Stop()
                    attackAnimTrack:Play(0.1)
                    attackAnimTrack:AdjustSpeed(speedMult)
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
                -- 【🌟修复2】：如果没有僵尸，立刻停止可能残留的攻击动作
                if attackAnimTrack and attackAnimTrack.IsPlaying then
                    attackAnimTrack:Stop(0.1)
                end

                if idleAnimTrack and not idleAnimTrack.IsPlaying then
                    idleAnimTrack:Play(0.1)
                end
                task.wait(0.1 / speedMult)
            end
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
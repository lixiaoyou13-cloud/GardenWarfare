-- src/client/Services/PlantAttackVisualController.luau
local PlantAttackVisualController = {}

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))
local localPlayer = Players.LocalPlayer

local PROJECTILE_SPEED = 25
local HIT_EFFECT_POOL_LIMIT = 30
local DAMAGE_TEXT_POOL_LIMIT = 80
local ATTACK_TRACK_CACHE_LIMIT = 24
local ATTACK_TRACK_IDLE_CACHE_TARGET = 12
local LOCAL_OWNER_ATTACK_ANIMATION_DISTANCE = 180
local OTHER_OWNER_ATTACK_ANIMATION_DISTANCE = 90
local OFFSCREEN_ATTACK_ANIMATION_DISTANCE = 60

local attackTracks = setmetatable({}, { __mode = "k" })
local flashingZombies = setmetatable({}, { __mode = "k" })
local warnedProjectileIssues = {}
local warnedAnimationIssues = {}
local failedAnimationIds = {}
local hitEffectPools = {}
local damageTextPool = {}
local visualConnection = nil
local visualSettings = {
    EffectsSelf = true,
    EffectsOthers = true,
    PlantSelf = true,
    PlantOthers = true,
}

local function warnProjectileOnce(projectileName, message)
    local key = tostring(projectileName) .. ":" .. message
    if warnedProjectileIssues[key] then return end
    warnedProjectileIssues[key] = true
    warn(("[PlantAttackVisual] %s: %s"):format(tostring(projectileName), message))
end

local function warnAnimationOnce(animationId, message)
    local key = tostring(animationId) .. ":" .. message
    if warnedAnimationIssues[key] then return end
    warnedAnimationIssues[key] = true
    warn(("[PlantAttackVisual] Animation %s: %s"):format(tostring(animationId), message))
end

local function getPool(poolMap, key)
    local pool = poolMap[key]
    if not pool then
        pool = {}
        poolMap[key] = pool
    end

    return pool
end

local function getEmitCount(emitter, fallback)
    local emitCount = emitter:GetAttribute("EmitCount")
    if not emitCount then
        local countValueNode = emitter:FindFirstChild("EmitCount")
        if countValueNode and (countValueNode:IsA("IntValue") or countValueNode:IsA("NumberValue")) then
            emitCount = countValueNode.Value
        end
    end

    emitCount = tonumber(emitCount)
    if not emitCount or emitCount <= 0 then
        return fallback
    end

    return emitCount
end

local function deactivateVisualEffects(instance)
    if not instance then return end

    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            desc.Enabled = false
            pcall(function()
                desc:Clear()
            end)
        elseif desc:IsA("Trail") then
            desc.Enabled = false
            pcall(function()
                desc:Clear()
            end)
        elseif desc:IsA("Beam") or desc:IsA("Light") then
            desc.Enabled = false
        end
    end
end

local function getOwnerUserIdFromInstance(instance)
    local current = instance
    while current and current ~= game do
        local ownerId = current:GetAttribute("OwnerId")
        if ownerId then
            return tonumber(ownerId)
        end

        current = current.Parent
    end

    return nil
end

local function isLocalOwner(ownerUserId)
    return tonumber(ownerUserId) == localPlayer.UserId
end

local function areEffectsEnabled(ownerUserId)
    if isLocalOwner(ownerUserId) then
        return visualSettings.EffectsSelf ~= false
    end

    return visualSettings.EffectsOthers ~= false
end

local function arePlantAnimationsEnabled(ownerUserId)
    if isLocalOwner(ownerUserId) then
        return visualSettings.PlantSelf ~= false
    end

    return visualSettings.PlantOthers ~= false
end

local function getInstancePosition(instance)
    if not instance or not instance.Parent then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Model") then
        return instance:GetPivot().Position
    end

    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function isPlantAnimationImportant(plant, ownerUserId)
    local position = getInstancePosition(plant)
    local camera = Workspace.CurrentCamera
    if not position or not camera then
        return isLocalOwner(ownerUserId)
    end

    local distance = (camera.CFrame.Position - position).Magnitude
    local maxDistance = isLocalOwner(ownerUserId) and LOCAL_OWNER_ATTACK_ANIMATION_DISTANCE or OTHER_OWNER_ATTACK_ANIMATION_DISTANCE
    if distance > maxDistance then
        return false
    end

    local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
    if onScreen and viewportPoint.Z > 0 then
        return true
    end

    return distance <= OFFSCREEN_ATTACK_ANIMATION_DISTANCE
end

local function cleanupAttackTrack(plant)
    local cached = attackTracks[plant]
    if not cached then return end

    if cached.markerConnection then cached.markerConnection:Disconnect() end
    if cached.cleanupConnection then cached.cleanupConnection:Disconnect() end
    if cached.track then
        cached.track:Stop(0.05)
        cached.track:Destroy()
    end

    attackTracks[plant] = nil
end

local function countAttackTracks()
    local count = 0
    for plant in pairs(attackTracks) do
        if not plant or not plant.Parent then
            cleanupAttackTrack(plant)
        else
            count += 1
        end
    end
    return count
end

local function pruneAttackTracksForNewTrack(exceptPlant)
    local activeCount = 0
    local pruneCandidates = {}
    for plant, cached in pairs(attackTracks) do
        if not plant or not plant.Parent or not cached.track then
            cleanupAttackTrack(plant)
        else
            activeCount += 1
            if plant ~= exceptPlant then
                local ownerUserId = tonumber(cached.ownerUserId) or getOwnerUserIdFromInstance(plant)
                local important = isPlantAnimationImportant(plant, ownerUserId)
                local isPlaying = cached.track.IsPlaying == true
                local priority = 0

                if important then
                    priority += 2
                end
                if isPlaying then
                    priority += 1
                end

                table.insert(pruneCandidates, {
                    Plant = plant,
                    Priority = priority,
                    LastUsedAt = tonumber(cached.lastUsedAt) or 0,
                })
            end
        end
    end

    if activeCount < ATTACK_TRACK_CACHE_LIMIT then
        return true
    end

    table.sort(pruneCandidates, function(first, second)
        if first.Priority ~= second.Priority then
            return first.Priority < second.Priority
        end

        return first.LastUsedAt < second.LastUsedAt
    end)

    for _, candidate in ipairs(pruneCandidates) do
        cleanupAttackTrack(candidate.Plant)
        activeCount -= 1
        if activeCount < ATTACK_TRACK_CACHE_LIMIT then
            return true
        end
    end

    return activeCount < ATTACK_TRACK_CACHE_LIMIT
end

local function scheduleIdleAttackTrackCleanup(plant, cached, speedMult)
    cached.cleanupToken = (tonumber(cached.cleanupToken) or 0) + 1
    local cleanupToken = cached.cleanupToken
    local track = cached.track
    local length = track and tonumber(track.Length) or 0
    local cleanupDelay = math.max(2, (length > 0 and (length / math.max(speedMult, 0.01)) or 1.5) + 0.75)

    task.delay(cleanupDelay, function()
        local current = attackTracks[plant]
        if current ~= cached or current.cleanupToken ~= cleanupToken then
            return
        end

        if current.track and current.track.IsPlaying then
            return
        end

        if countAttackTracks() > ATTACK_TRACK_IDLE_CACHE_TARGET then
            cleanupAttackTrack(plant)
        end
    end)
end

local function getAnimator(model)
    if not model or not model.Parent then return nil end

    local animController = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
    if not animController then return nil end

    local animator = animController:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = animController
    end

    return animator
end

local function playAttackAnimation(plant, animationId, speedMult, ownerUserId)
    if not plant or not plant.Parent then return end
    if type(animationId) ~= "string" or animationId == "" then return end
    if failedAnimationIds[animationId] then return end

    ownerUserId = tonumber(ownerUserId) or getOwnerUserIdFromInstance(plant)
    if not arePlantAnimationsEnabled(ownerUserId) then
        cleanupAttackTrack(plant)
        return
    end

    if not isPlantAnimationImportant(plant, ownerUserId) then
        cleanupAttackTrack(plant)
        return
    end

    speedMult = tonumber(speedMult) or 1
    local animator = getAnimator(plant)
    if not animator then return end

    local cached = attackTracks[plant]
    if not cached or cached.animationId ~= animationId or cached.animator ~= animator then
        cleanupAttackTrack(plant)

        if not pruneAttackTracksForNewTrack(plant) then
            return
        end

        local anim = Instance.new("Animation")
        anim.AnimationId = animationId

        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        anim:Destroy()

        if not ok or not track then
            failedAnimationIds[animationId] = true
            warnAnimationOnce(animationId, "failed to load; skipping future attempts for this client")
            return
        end

        track.Priority = Enum.AnimationPriority.Action
        track.Looped = false

        cached = {
            animationId = animationId,
            animator = animator,
            track = track,
            ownerUserId = ownerUserId,
            lastUsedAt = os.clock(),
        }

        cached.markerConnection = track:GetMarkerReachedSignal("VFX"):Connect(function()
            local currentOwnerId = tonumber(ownerUserId) or getOwnerUserIdFromInstance(plant)
            if plant and plant.Parent and areEffectsEnabled(currentOwnerId) then
                EffectUtil.PlayAttackVFX(plant)
            end
        end)

        cached.cleanupConnection = plant.AncestryChanged:Connect(function(_, parent)
            if not parent then
                cleanupAttackTrack(plant)
            end
        end)

        attackTracks[plant] = cached
    end

    local track = cached.track
    if not track then return end

    cached.ownerUserId = ownerUserId
    cached.lastUsedAt = os.clock()
    track:Stop(0)
    track:Play(0.05)
    track:AdjustSpeed(speedMult)
    scheduleIdleAttackTrackCleanup(plant, cached, speedMult)
end

local function getProjectileParts(projectile)
    local parts = {}

    if projectile:IsA("BasePart") then
        table.insert(parts, projectile)
    end

    for _, desc in ipairs(projectile:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
        end
    end

    return parts
end

local function prepProjectile(projectile)
    if projectile:IsA("BasePart") then
        projectile.Anchored = true
        projectile.CanCollide = false
        projectile.CanTouch = false
        projectile.CanQuery = false

        for _, desc in ipairs(projectile:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
            end
        end

        return
    end

    for _, part in ipairs(getProjectileParts(projectile)) do
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
    end
end

local function setProjectileCFrame(projectile, cf)
    if projectile:IsA("BasePart") then
        projectile.CFrame = cf
    elseif projectile:IsA("Model") then
        projectile:PivotTo(cf)
    end
end

local function getProjectilePosition(projectile)
    if projectile:IsA("BasePart") then
        return projectile.Position
    elseif projectile:IsA("Model") then
        return projectile:GetPivot().Position
    end

    return nil
end

local function createEffectCarrier(projectileName, clone)
    local carrier = Instance.new("Part")
    carrier.Name = projectileName .. "Projectile"
    carrier.Size = Vector3.new(0.2, 0.2, 0.2)
    carrier.Transparency = 1
    carrier.Anchored = true
    carrier.CanCollide = false
    carrier.CanTouch = false
    carrier.CanQuery = false

    if clone:IsA("Attachment") then
        clone.Parent = carrier
    else
        local attachment = Instance.new("Attachment")
        attachment.Parent = carrier
        clone.Parent = attachment
    end

    warnProjectileOnce(projectileName, "template has no BasePart or Model; using an invisible carrier for effects")
    return carrier
end

local function createProjectileVisual(template, projectileName)
    local clone = template:Clone()

    if clone:IsA("BasePart") or clone:IsA("Model") then
        return clone
    end

    local parts = getProjectileParts(clone)
    if #parts > 0 then
        local wrapper = Instance.new("Model")
        wrapper.Name = projectileName .. "Projectile"
        clone.Parent = wrapper
        return wrapper
    end

    return createEffectCarrier(projectileName, clone)
end

local function activateProjectileEffects(projectile, projectileName, effectsEnabled)
    local hasVisiblePart = false
    local hasEffect = false

    for _, part in ipairs(getProjectileParts(projectile)) do
        if part.Transparency < 1 and part.Size.Magnitude > 0 then
            hasVisiblePart = true
        end
    end

    if not effectsEnabled then
        return
    end

    for _, desc in ipairs(projectile:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            hasEffect = true
            desc.Enabled = true

            local emitCount = getEmitCount(desc)
            if emitCount and emitCount > 0 then
                desc:Emit(emitCount)
            end
        elseif desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") then
            hasEffect = true
            desc.Enabled = true
        end
    end

    if not hasVisiblePart and not hasEffect then
        warnProjectileOnce(projectileName, "template has no visible BasePart and no enabled effect")
    end
end

local function getTargetRoot(targetZombieModel)
    if not targetZombieModel or not targetZombieModel.Parent then return nil end
    return targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart
end

local function getTargetHumanoid(targetZombieModel)
    if not targetZombieModel or not targetZombieModel.Parent then return nil end
    return targetZombieModel:FindFirstChildOfClass("Humanoid")
end

local function spawnProjectileVisual(projectileName, fireCFrame, initialTargetPos, targetZombieModel, arcHeight, speedMult, ownerUserId, projectileVisualConfig)
    if type(projectileName) ~= "string" or projectileName == "" then return end
    if typeof(fireCFrame) ~= "CFrame" then return end
    if typeof(initialTargetPos) ~= "Vector3" then return end

    local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo") or ReplicatedStorage:WaitForChild("Ammo", 1)
    local template = ammoFolder and (ammoFolder:FindFirstChild(projectileName) or ammoFolder:WaitForChild(projectileName, 1))
    if not template then
        warnProjectileOnce(projectileName, "ReplicatedStorage.Ammo template not found on client")
        return
    end

    ownerUserId = tonumber(ownerUserId)

    local projectile = createProjectileVisual(template, projectileName)
    prepProjectile(projectile)
    setProjectileCFrame(projectile, fireCFrame)
    projectile.Parent = Workspace
    activateProjectileEffects(projectile, projectileName, areEffectsEnabled(ownerUserId))
    Debris:AddItem(projectile, 10)

    task.spawn(function()
        speedMult = tonumber(speedMult) or 1
        arcHeight = tonumber(arcHeight) or 0

        local startPos = fireCFrame.Position
        local targetRoot = getTargetRoot(targetZombieModel)

        local initialDist = (initialTargetPos - startPos).Magnitude
        local flightTime = math.max(0.05, initialDist / (PROJECTILE_SPEED * speedMult))
        local elapsedTime = 0
        local continuePastTarget = type(projectileVisualConfig) == "table" and projectileVisualConfig.ContinuePastTarget == true
        local visualDirection = nil
        local maxDistance = initialDist
        local destroyBeyondPosition = nil

        if continuePastTarget then
            visualDirection = projectileVisualConfig.Direction
            if typeof(visualDirection) ~= "Vector3" or visualDirection.Magnitude <= 0.001 then
                visualDirection = initialTargetPos - startPos
            end
            if visualDirection.Magnitude > 0.001 then
                visualDirection = visualDirection.Unit
            else
                visualDirection = fireCFrame.LookVector
            end

            maxDistance = math.max(initialDist, tonumber(projectileVisualConfig.MaxDistance) or initialDist)
            if typeof(projectileVisualConfig.DestroyBeyondPosition) == "Vector3" then
                destroyBeyondPosition = projectileVisualConfig.DestroyBeyondPosition
            end
        end

        while projectile and projectile.Parent do
            local humanoid = getTargetHumanoid(targetZombieModel)
            targetRoot = getTargetRoot(targetZombieModel)
            if humanoid and humanoid.Health <= 0 and not continuePastTarget then
                projectile:Destroy()
                break
            end

            local dt = RunService.Heartbeat:Wait()
            local targetPos = targetRoot and (targetRoot.Position + Vector3.new(0, 1, 0)) or initialTargetPos

            if arcHeight > 0 then
                elapsedTime += dt
                local t = math.clamp(elapsedTime / flightTime, 0, 1)
                local p0 = startPos
                local p2 = targetPos
                local p1 = p0:Lerp(p2, 0.5) + Vector3.new(0, arcHeight, 0)
                local currentPos = (1 - t) ^ 2 * p0 + 2 * (1 - t) * t * p1 + t ^ 2 * p2
                local nextT = math.clamp(t + 0.05, 0, 1)
                local nextPos = (1 - nextT) ^ 2 * p0 + 2 * (1 - nextT) * nextT * p1 + nextT ^ 2 * p2

                if (nextPos - currentPos).Magnitude > 0.001 then
                    setProjectileCFrame(projectile, CFrame.lookAt(currentPos, nextPos))
                else
                    setProjectileCFrame(projectile, CFrame.new(currentPos))
                end

                if t >= 1 then
                    projectile:Destroy()
                    break
                end
            else
                local currentPos = getProjectilePosition(projectile)
                if not currentPos then
                    projectile:Destroy()
                    break
                end

                local moveStep = PROJECTILE_SPEED * speedMult * dt

                if continuePastTarget then
                    local nextPos = currentPos + visualDirection * moveStep
                    setProjectileCFrame(projectile, CFrame.lookAt(nextPos, nextPos + visualDirection))

                    local traveledDistance = (nextPos - startPos):Dot(visualDirection)
                    local reachedMaxDistance = traveledDistance >= maxDistance
                    local reachedBoundary = destroyBeyondPosition and (nextPos - destroyBeyondPosition):Dot(visualDirection) >= 0
                    if reachedMaxDistance or reachedBoundary then
                        projectile:Destroy()
                        break
                    end
                else
                    local direction = targetPos - currentPos
                    local dist = direction.Magnitude

                    if dist <= moveStep or dist <= 0.001 then
                        projectile:Destroy()
                        break
                    end

                    local nextPos = currentPos + direction.Unit * moveStep
                    setProjectileCFrame(projectile, CFrame.lookAt(nextPos, targetPos))
                end
            end
        end
    end)
end

local function flashZombieRed(zombieModel)
    if not zombieModel or not zombieModel.Parent then return end
    if flashingZombies[zombieModel] then return end
    flashingZombies[zombieModel] = true

    local originalColors = {}
    for _, p in ipairs(zombieModel:GetDescendants()) do
        if p:IsA("BasePart") then
            originalColors[p] = p.Color
            p.Color = Color3.fromRGB(255, 80, 80)
        end
    end

    task.delay(0.15, function()
        if not zombieModel or not zombieModel.Parent then return end

        local isCharred = zombieModel:GetAttribute("IsCharred")
        for p, color in pairs(originalColors) do
            if p and p.Parent then
                p.Color = isCharred and Color3.fromRGB(30, 30, 30) or color
            end
        end

        flashingZombies[zombieModel] = nil
    end)
end

local function createDamageTextBillboard()
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DamageText"
    billboard.Size = UDim2.new(0, 60, 0, 25)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 150

    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "TextLabel"
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.FredokaOne
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.Parent = billboard

    return billboard
end

local function acquireDamageTextBillboard()
    while #damageTextPool > 0 do
        local billboard = table.remove(damageTextPool)
        if billboard then
            return billboard
        end
    end

    return createDamageTextBillboard()
end

local function recycleDamageTextBillboard(billboard)
    if not billboard then return end

    local ok = pcall(function()
        billboard.Parent = nil
    end)
    if not ok then return end

    if #damageTextPool < DAMAGE_TEXT_POOL_LIMIT then
        table.insert(damageTextPool, billboard)
    else
        billboard:Destroy()
    end
end

local function showDamageText(zombieModel, damage)
    if not zombieModel or not zombieModel.Parent then return end

    local rootPart = zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart
    local head = zombieModel:FindFirstChild("Head") or rootPart
    if not head then return end

    local billboard = acquireDamageTextBillboard()
    local textLabel = billboard:FindFirstChild("TextLabel")
    if not textLabel or not textLabel:IsA("TextLabel") then
        billboard:Destroy()
        billboard = createDamageTextBillboard()
        textLabel = billboard:FindFirstChild("TextLabel")
    end

    local startOffset = Vector3.new(math.random(-10, 10) / 10, 1.5 + math.random(5, 15) / 10, math.random(-10, 10) / 10)
    billboard.StudsOffset = startOffset
    textLabel.Text = "-" .. tostring(damage)
    textLabel.TextTransparency = 0
    textLabel.TextStrokeTransparency = 0
    billboard.Parent = head

    local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    TweenService:Create(billboard, tweenInfo, { StudsOffset = startOffset + Vector3.new(0, 1.5, 0) }):Play()
    TweenService:Create(textLabel, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

    task.delay(1.0, function()
        recycleDamageTextBillboard(billboard)
    end)
end

local function createFallbackHitEffect()
    local effectPart = Instance.new("Part")
    effectPart.Name = "FallbackHitEffect"
    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
    effectPart.Transparency = 1
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.CanQuery = false

    local attachment = Instance.new("Attachment")
    attachment.Parent = effectPart

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "FallbackHitParticles"
    particles.Rate = 0
    particles.Size = NumberSequence.new(1, 0)
    particles.Speed = NumberRange.new(5, 10)
    particles.Lifetime = NumberRange.new(0.1, 0.3)
    particles.Parent = attachment

    return effectPart
end

local function acquireHitEffect(key, createFn)
    local pool = getPool(hitEffectPools, key)

    while #pool > 0 do
        local effect = table.remove(pool)
        if effect then
            return effect
        end
    end

    return createFn()
end

local function recycleHitEffect(key, effect)
    if not effect then return end

    deactivateVisualEffects(effect)

    local ok = pcall(function()
        effect.Parent = nil
    end)
    if not ok then return end

    local pool = getPool(hitEffectPools, key)
    if #pool < HIT_EFFECT_POOL_LIMIT then
        table.insert(pool, effect)
    else
        effect:Destroy()
    end
end

local function emitHitEffect(effect)
    for _, child in ipairs(effect:GetDescendants()) do
        if child:IsA("ParticleEmitter") then
            child.Enabled = true
            child:Emit(getEmitCount(child, 15))
            task.delay(0.15, function()
                if child and child.Parent then child.Enabled = false end
            end)
        elseif child:IsA("Light") then
            child.Enabled = true
            task.delay(0.15, function()
                if child and child.Parent then child.Enabled = false end
            end)
        end
    end
end

local function playHitEffect(hitPos, hitEffectTexture, hitEffectColor)
    if typeof(hitPos) ~= "Vector3" then return end

    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local hitEffectPrefab = nil

    if typeof(hitEffectTexture) == "string" and hitEffectTexture ~= "" and hitFolder then
        local template = hitFolder:FindFirstChild(hitEffectTexture)
        if template and template:IsA("BasePart") then
            hitEffectPrefab = template
        end
    end

    local key = hitEffectPrefab and ("prefab:" .. hitEffectPrefab.Name) or "fallback"
    local effect = acquireHitEffect(key, function()
        if hitEffectPrefab then
            local clone = hitEffectPrefab:Clone()
            prepProjectile(clone)
            return clone
        end

        return createFallbackHitEffect()
    end)

    prepProjectile(effect)
    deactivateVisualEffects(effect)

    if hitEffectPrefab then
        effect.CFrame = CFrame.new(hitPos)
    else
        effect.Position = hitPos

        local particles = effect:FindFirstChild("FallbackHitParticles", true)
        if particles and particles:IsA("ParticleEmitter") then
            particles.Texture = hitEffectTexture or "rbxassetid://243098098"
            particles.Color = ColorSequence.new(hitEffectColor or Color3.fromRGB(255, 215, 0))
        end
    end

    effect.Parent = Workspace
    emitHitEffect(effect)

    task.delay(1.5, function()
        recycleHitEffect(key, effect)
    end)
end

local function playHitVisual(targetZombieModel, damage, hitPos, hitEffectTexture, hitEffectColor, ownerUserId)
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    flashZombieRed(targetZombieModel)
    showDamageText(targetZombieModel, damage)
    playHitEffect(hitPos, hitEffectTexture, hitEffectColor)
end

local function playDamageTextVisual(targetZombieModel, damage, ownerUserId)
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    flashZombieRed(targetZombieModel)
    showDamageText(targetZombieModel, damage)
end

function PlantAttackVisualController.SetVisualSettings(newSettings)
    if type(newSettings) ~= "table" then
        return
    end

    for key, value in pairs(newSettings) do
        if visualSettings[key] ~= nil then
            visualSettings[key] = value ~= false
        end
    end

    for plant in pairs(attackTracks) do
        local ownerUserId = getOwnerUserIdFromInstance(plant)
        if not arePlantAnimationsEnabled(ownerUserId) then
            cleanupAttackTrack(plant)
        end
    end
end

function PlantAttackVisualController.Init()
    if visualConnection then
        return
    end

    local visualRE = ReplicatedStorage:WaitForChild("PlantAttackVisualRE", 10)
    if not visualRE then
        warn("[PlantAttackVisual] PlantAttackVisualRE was not found within 10 seconds; visuals disabled.")
        return
    end

    visualConnection = visualRE.OnClientEvent:Connect(function(action, ...)
        if action == "Attack" then
            playAttackAnimation(...)
        elseif action == "Projectile" then
            spawnProjectileVisual(...)
        elseif action == "Hit" then
            playHitVisual(...)
        elseif action == "DamageText" then
            playDamageTextVisual(...)
        end
    end)
end

return PlantAttackVisualController

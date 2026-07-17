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
local GROUND_EFFECT_POOL_LIMIT_PER_TYPE = 12
local LOCAL_OWNER_PROJECTILE_LIMIT = 120
local OTHER_OWNER_PROJECTILE_LIMIT = 45
local GLOBAL_PROJECTILE_LIMIT = 180
local OTHER_OWNER_PROJECTILE_DISTANCE = 140
local ATTACK_TRACK_CACHE_LIMIT = 24
local ATTACK_TRACK_IDLE_CACHE_TARGET = 12
local LOCAL_OWNER_ATTACK_ANIMATION_DISTANCE = 180
local OTHER_OWNER_ATTACK_ANIMATION_DISTANCE = 90
local OFFSCREEN_ATTACK_ANIMATION_DISTANCE = 60
local SUNSHROOM_HEAL_VFX_DEBUG = false

local attackTracks = setmetatable({}, { __mode = "k" })
local flashingZombies = setmetatable({}, { __mode = "k" })
local warnedProjectileIssues = {}
local warnedAnimationIssues = {}
local failedAnimationIds = {}
local hitEffectPools = {}
local groundEffectPools = {}
local damageTextPool = {}
local visualCache = setmetatable({}, { __mode = "k" })
local zombiePartCache = setmetatable({}, { __mode = "k" })
local activeGroundEffects = {}
local activeProjectileCounts = {
    Self = 0,
    Others = 0,
    Total = 0,
}
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

local function getVisualCache(instance)
    if not instance then
        return {
            BaseParts = {},
            Effects = {},
            OriginalTransparencies = {},
        }
    end

    local cached = visualCache[instance]
    if cached then
        return cached
    end

    cached = {
        BaseParts = {},
        Effects = {},
        OriginalTransparencies = {},
    }

    if instance:IsA("BasePart") then
        table.insert(cached.BaseParts, instance)
        cached.OriginalTransparencies[instance] = instance.Transparency
    end

    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(cached.BaseParts, desc)
            cached.OriginalTransparencies[desc] = desc.Transparency
        elseif desc:IsA("ParticleEmitter")
            or desc:IsA("Trail")
            or desc:IsA("Beam")
            or desc:IsA("Light")
            or desc:IsA("Highlight")
        then
            table.insert(cached.Effects, desc)
        end
    end

    visualCache[instance] = cached
    return cached
end

local function getCachedZombieParts(zombieModel)
    if not zombieModel then
        return {}
    end

    local parts = zombiePartCache[zombieModel]
    if parts then
        return parts
    end

    parts = {}
    if zombieModel:IsA("BasePart") then
        table.insert(parts, zombieModel)
    end

    for _, desc in ipairs(zombieModel:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
        end
    end

    zombiePartCache[zombieModel] = parts
    return parts
end

local function deactivateVisualEffects(instance)
    if not instance then return end

    for _, desc in ipairs(getVisualCache(instance).Effects) do
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
        elseif desc:IsA("Beam") or desc:IsA("Light") or desc:IsA("Highlight") then
            desc.Enabled = false
        end
    end
end

local function setVisualPartsVisible(instance, visible)
    if not instance then return end

    local cached = getVisualCache(instance)
    for _, part in ipairs(cached.BaseParts) do
        if part and part.Parent then
            if visible then
                local originalTransparency = cached.OriginalTransparencies[part]
                if originalTransparency == nil then
                    originalTransparency = part.Transparency
                    cached.OriginalTransparencies[part] = originalTransparency
                end
                part.Transparency = originalTransparency
            else
                part.Transparency = 1
            end
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

local function getLocalRootPosition()
    local character = localPlayer.Character
    local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    return rootPart and rootPart.Position or nil
end

local function getProjectileOwnerBucket(ownerUserId)
    if isLocalOwner(ownerUserId) then
        return "Self"
    end

    return "Others"
end

local function shouldRenderProjectile(ownerUserId, firePosition)
    if activeProjectileCounts.Total >= GLOBAL_PROJECTILE_LIMIT then
        return nil
    end

    local bucket = getProjectileOwnerBucket(ownerUserId)
    if bucket == "Self" then
        if activeProjectileCounts.Self >= LOCAL_OWNER_PROJECTILE_LIMIT then
            return nil
        end

        return bucket
    end

    if activeProjectileCounts.Others >= OTHER_OWNER_PROJECTILE_LIMIT then
        return nil
    end

    local localRootPosition = getLocalRootPosition()
    if localRootPosition and typeof(firePosition) == "Vector3" then
        if (localRootPosition - firePosition).Magnitude > OTHER_OWNER_PROJECTILE_DISTANCE then
            return nil
        end
    end

    return bucket
end

local function incrementProjectileCount(bucket)
    activeProjectileCounts.Total += 1
    if bucket == "Self" then
        activeProjectileCounts.Self += 1
    else
        activeProjectileCounts.Others += 1
    end
end

local function decrementProjectileCount(bucket)
    activeProjectileCounts.Total = math.max(0, activeProjectileCounts.Total - 1)
    if bucket == "Self" then
        activeProjectileCounts.Self = math.max(0, activeProjectileCounts.Self - 1)
    else
        activeProjectileCounts.Others = math.max(0, activeProjectileCounts.Others - 1)
    end
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

-- 播放植物模型自身的 VFX 节点特效，用于无攻击动画的表现。
local function playPlantVFX(plant, ownerUserId)
    if not plant or not plant.Parent then
        if SUNSHROOM_HEAL_VFX_DEBUG then
            print("[SunShroomHealVFX][Client] PlantVFX received, but plant is nil or not replicated")
        end
        return
    end

    local currentOwnerId = tonumber(ownerUserId) or getOwnerUserIdFromInstance(plant)
    local effectsEnabled = areEffectsEnabled(currentOwnerId)
    local isSunShroom = plant.Name == "SunShroom" or plant:GetAttribute("PlantId") == "SunShroom"
    if isSunShroom and SUNSHROOM_HEAL_VFX_DEBUG then
        print(("[SunShroomHealVFX][Client] PlantVFX received plant=%s owner=%s effectsEnabled=%s"):format(
            plant:GetFullName(),
            tostring(currentOwnerId),
            tostring(effectsEnabled)
        ))
    end

    if effectsEnabled then
        EffectUtil.PlayAttackVFX(plant)
    end
end

local function getProjectileParts(projectile)
    return getVisualCache(projectile).BaseParts
end

local function prepProjectile(projectile)
    setVisualPartsVisible(projectile, true)

    for _, part in ipairs(getProjectileParts(projectile)) do
        if part and part.Parent then
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
        end
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

local function acquireProjectileVisual(projectileName, template)
    return createProjectileVisual(template, projectileName)
end

local function destroyProjectileVisual(projectile)
    if not projectile then
        return
    end

    deactivateVisualEffects(projectile)
    setVisualPartsVisible(projectile, false)
    visualCache[projectile] = nil

    pcall(function()
        projectile.Parent = nil
        projectile:Destroy()
    end)
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

    for _, desc in ipairs(getVisualCache(projectile).Effects) do
        if desc:IsA("ParticleEmitter") then
            hasEffect = true
            desc.Enabled = true

            local emitCount = getEmitCount(desc)
            if emitCount and emitCount > 0 then
                desc:Emit(emitCount)
            end
        elseif desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") or desc:IsA("Highlight") then
            hasEffect = true
            desc.Enabled = true
        end
    end

    if not hasVisiblePart and not hasEffect then
        warnProjectileOnce(projectileName, "template has no visible BasePart and no enabled effect")
    end
end

local function getProjectileVisualEndPosition(startPos, initialTargetPos, projectileVisualConfig)
    local initialOffset = initialTargetPos - startPos
    local initialDistance = initialOffset.Magnitude
    if type(projectileVisualConfig) ~= "table" or projectileVisualConfig.ContinuePastTarget ~= true then
        return initialTargetPos, false, initialDistance
    end

    local visualDirection = initialDistance > 0.001 and initialOffset.Unit or nil
    if not visualDirection and typeof(projectileVisualConfig.Direction) == "Vector3" then
        local configuredDirection = projectileVisualConfig.Direction
        if configuredDirection.Magnitude > 0.001 then
            visualDirection = configuredDirection.Unit
        end
    end

    if not visualDirection then
        return initialTargetPos, false, initialDistance
    end

    local maxDistance = math.max(initialDistance, tonumber(projectileVisualConfig.MaxDistance) or initialDistance)
    if typeof(projectileVisualConfig.DestroyBeyondPosition) == "Vector3"
        and typeof(projectileVisualConfig.Direction) == "Vector3"
        and projectileVisualConfig.Direction.Magnitude > 0.001
    then
        local flatDirection = Vector3.new(projectileVisualConfig.Direction.X, 0, projectileVisualConfig.Direction.Z)
        if flatDirection.Magnitude > 0.001 then
            flatDirection = flatDirection.Unit
            local flatStart = Vector3.new(startPos.X, 0, startPos.Z)
            local flatDestroy = Vector3.new(projectileVisualConfig.DestroyBeyondPosition.X, 0, projectileVisualConfig.DestroyBeyondPosition.Z)
            local destroyDistance = (flatDestroy - flatStart):Dot(flatDirection)
            if destroyDistance > initialDistance and destroyDistance < maxDistance then
                maxDistance = destroyDistance
            end
        end
    end

    return startPos + visualDirection * maxDistance, true, maxDistance
end

local function getTrajectoryPosition(startPos, endPos, arcHeight, alpha)
    if arcHeight > 0 then
        local controlPos = startPos:Lerp(endPos, 0.5) + Vector3.new(0, arcHeight, 0)
        return (1 - alpha) ^ 2 * startPos + 2 * (1 - alpha) * alpha * controlPos + alpha ^ 2 * endPos
    end

    return startPos:Lerp(endPos, alpha)
end

local function spawnProjectileVisual(projectileName, fireCFrame, initialTargetPos, _targetZombieModel, arcHeight, speedMult, ownerUserId, projectileVisualConfig)
    if type(projectileName) ~= "string" or projectileName == "" then return end
    if typeof(fireCFrame) ~= "CFrame" then return end
    if typeof(initialTargetPos) ~= "Vector3" then return end

    ownerUserId = tonumber(ownerUserId)
    if not isLocalOwner(ownerUserId) then
        return
    end

    local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo") or ReplicatedStorage:WaitForChild("Ammo", 1)
    local template = ammoFolder and (ammoFolder:FindFirstChild(projectileName) or ammoFolder:WaitForChild(projectileName, 1))
    if not template then
        warnProjectileOnce(projectileName, "ReplicatedStorage.Ammo template not found on client")
        return
    end

    local bucket = shouldRenderProjectile(ownerUserId, fireCFrame.Position)
    if not bucket then
        return
    end

    local projectile = acquireProjectileVisual(projectileName, template)
    prepProjectile(projectile)
    setProjectileCFrame(projectile, fireCFrame)
    projectile.Parent = Workspace
    incrementProjectileCount(bucket)
    activateProjectileEffects(projectile, projectileName, areEffectsEnabled(ownerUserId))

    task.spawn(function()
        local finished = false
        local function finishProjectile()
            if finished then
                return
            end

            finished = true
            destroyProjectileVisual(projectile)
            decrementProjectileCount(bucket)
        end

        speedMult = math.max(tonumber(speedMult) or 1, 0.01)
        arcHeight = tonumber(arcHeight) or 0

        local startPos = fireCFrame.Position
        local visualEndPos, continuesPastTarget, visualDistance = getProjectileVisualEndPosition(startPos, initialTargetPos, projectileVisualConfig)
        if not continuesPastTarget then
            visualEndPos = initialTargetPos
        end

        local flightTime = math.max(0.05, visualDistance / (PROJECTILE_SPEED * speedMult))
        local maxLifetime = math.clamp(flightTime + 0.5, 0.25, 10)
        local startedAt = os.clock()
        local elapsedTime = 0

        while projectile and projectile.Parent do
            if os.clock() - startedAt >= maxLifetime then
                finishProjectile()
                break
            end

            local dt = RunService.Heartbeat:Wait()
            elapsedTime += dt
            local t = math.clamp(elapsedTime / flightTime, 0, 1)
            local currentPos = getTrajectoryPosition(startPos, visualEndPos, arcHeight, t)
            local nextT = math.clamp(t + 0.03, 0, 1)
            local nextPos = getTrajectoryPosition(startPos, visualEndPos, arcHeight, nextT)

            if (nextPos - currentPos).Magnitude > 0.001 then
                setProjectileCFrame(projectile, CFrame.lookAt(currentPos, nextPos))
            else
                setProjectileCFrame(projectile, CFrame.new(currentPos))
            end

            if t >= 1 then
                finishProjectile()
                break
            end
        end

        finishProjectile()
    end)
end

local function flashZombieRed(zombieModel)
    if not zombieModel or not zombieModel.Parent then return end
    if zombieModel:GetAttribute("IsEventZomboss") == true then return end
    if flashingZombies[zombieModel] then return end
    flashingZombies[zombieModel] = true

    local originalColors = {}
    for _, p in ipairs(getCachedZombieParts(zombieModel)) do
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
    setVisualPartsVisible(effect, false)

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
    for _, child in ipairs(getVisualCache(effect).Effects) do
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

local function positionGroundEffect(effect, lawnCFrame, lawnSize)
    if not effect or typeof(lawnCFrame) ~= "CFrame" or typeof(lawnSize) ~= "Vector3" then
        return
    end

    local yOffset = lawnSize.Y * 0.5
    if effect:IsA("BasePart") then
        effect.CFrame = lawnCFrame * CFrame.new(0, yOffset + effect.Size.Y * 0.5, 0)
    elseif effect:IsA("Model") then
        local _, size = effect:GetBoundingBox()
        effect:PivotTo(lawnCFrame * CFrame.new(0, yOffset + size.Y * 0.5, 0))
    end
end

local function activateGroundEffect(effect)
    for _, desc in ipairs(getVisualCache(effect).Effects) do
        if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") or desc:IsA("Highlight") then
            desc.Enabled = true
        end
    end
end

local function acquireGroundEffect(effectName)
    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local template = hitFolder and hitFolder:FindFirstChild(effectName)
    if not template then
        warnProjectileOnce(effectName, "ReplicatedStorage.Hit ground effect not found on client")
        return nil
    end

    local pool = getPool(groundEffectPools, effectName)
    while #pool > 0 do
        local effect = table.remove(pool)
        if effect then
            return effect
        end
    end

    local effect = template:Clone()
    prepProjectile(effect)
    return effect
end

local function recycleGroundEffect(effectName, effect)
    if not effect then
        return
    end

    deactivateVisualEffects(effect)
    setVisualPartsVisible(effect, false)

    local ok = pcall(function()
        effect.Parent = nil
    end)
    if not ok then
        return
    end

    local pool = getPool(groundEffectPools, effectName)
    if #pool < GROUND_EFFECT_POOL_LIMIT_PER_TYPE then
        table.insert(pool, effect)
    else
        visualCache[effect] = nil
        effect:Destroy()
    end
end

local function stopGroundEffectVisual(visualId)
    local state = activeGroundEffects[visualId]
    if not state then
        return
    end

    activeGroundEffects[visualId] = nil
    recycleGroundEffect(state.EffectName, state.Effect)
end

local function startGroundEffectVisual(visualId, effectName, lawnCFrame, lawnSize, duration, ownerUserId)
    if type(visualId) ~= "string" or type(effectName) ~= "string" or effectName == "" then
        return
    end
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    stopGroundEffectVisual(visualId)

    local effect = acquireGroundEffect(effectName)
    if not effect then
        return
    end

    positionGroundEffect(effect, lawnCFrame, lawnSize)
    deactivateVisualEffects(effect)
    activateGroundEffect(effect)
    effect.Parent = Workspace

    local state = {
        Effect = effect,
        EffectName = effectName,
        ExpiresAt = os.clock() + math.max(0.1, tonumber(duration) or 2),
        Token = 0,
    }
    activeGroundEffects[visualId] = state

    task.spawn(function()
        while activeGroundEffects[visualId] == state do
            if os.clock() >= state.ExpiresAt then
                stopGroundEffectVisual(visualId)
                break
            end

            task.wait(0.2)
        end
    end)
end

local function refreshGroundEffectVisual(visualId, duration)
    local state = activeGroundEffects[visualId]
    if not state then
        return
    end

    state.ExpiresAt = os.clock() + math.max(0.1, tonumber(duration) or 2)
end

local function playEffectBurst(effectName, effectCFrame, ownerUserId)
    if type(effectName) ~= "string" or effectName == "" or typeof(effectCFrame) ~= "CFrame" then
        return
    end
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local template = hitFolder and hitFolder:FindFirstChild(effectName)
    if not template then
        warnProjectileOnce(effectName, "ReplicatedStorage.Hit burst effect not found on client")
        return
    end

    local key = "burst:" .. effectName
    local effect = acquireHitEffect(key, function()
        local clone = template:Clone()
        prepProjectile(clone)
        return clone
    end)

    prepProjectile(effect)
    deactivateVisualEffects(effect)
    setProjectileCFrame(effect, effectCFrame)
    effect.Parent = Workspace

    task.defer(function()
        emitHitEffect(effect)
    end)

    task.delay(2, function()
        recycleHitEffect(key, effect)
    end)
end

local function playExplosionBurst(position, explosionType, ownerUserId)
    if typeof(position) ~= "Vector3" then
        return
    end
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    local effectPart = Instance.new("Part")
    effectPart.Name = "LocalExplosionBurst"
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.CanQuery = false
    effectPart.CanTouch = false
    effectPart.Transparency = 1
    effectPart.Parent = Workspace

    if explosionType == "Row" then
        effectPart.Size = Vector3.new(6, 1, 100)
        effectPart.Position = position - Vector3.new(0, 1.5, 0)

        local particles = Instance.new("ParticleEmitter")
        particles.Texture = "rbxassetid://248625108"
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
        particles.Lifetime = NumberRange.new(0.05, 0.12)
        particles.LightEmission = 1
        particles.EmissionDirection = Enum.NormalId.Top
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 4),
            NumberSequenceKeypoint.new(1, 10),
        })
        particles.Rate = 2000
        particles.Speed = NumberRange.new(15, 30)
        particles.Parent = effectPart

        task.delay(0.5, function()
            if particles then
                particles.Enabled = false
            end
        end)
    else
        effectPart.Position = position

        local attachment = Instance.new("Attachment")
        attachment.Parent = effectPart

        local particles = Instance.new("ParticleEmitter")
        particles.Texture = "rbxassetid://243098098"
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0))
        particles.Size = NumberSequence.new(1, 15)
        particles.Rate = 500
        particles.Speed = NumberRange.new(10, 20)
        particles.Lifetime = NumberRange.new(0.2, 0.4)
        particles.SpreadAngle = Vector2.new(180, 180)
        particles.Parent = attachment

        task.delay(0.2, function()
            if particles then
                particles.Enabled = false
            end
        end)
    end

    Debris:AddItem(effectPart, 2)
end

local function playThrownPlantVisual(modelName, startPosition, targetPosition, height, duration, ownerUserId)
    if type(modelName) ~= "string" or modelName == "" then
        return
    end
    if typeof(startPosition) ~= "Vector3" or typeof(targetPosition) ~= "Vector3" then
        return
    end
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
    local template = itemModels and (itemModels:FindFirstChild(modelName .. "_Plant") or itemModels:FindFirstChild(modelName))
    if not template then
        warnProjectileOnce(modelName, "ItemModels thrown plant visual not found on client")
        return
    end

    local model = template:Clone()
    prepProjectile(model)
    setProjectileCFrame(model, CFrame.new(startPosition))
    model.Parent = Workspace

    task.spawn(function()
        height = tonumber(height) or 15
        duration = math.max(0.05, tonumber(duration) or 0.5)
        local startTime = os.clock()

        while model and model.Parent do
            local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
            local currentPos = startPosition:Lerp(targetPosition, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * height, 0)
            setProjectileCFrame(model, CFrame.new(currentPos) * CFrame.Angles(math.rad(alpha * 360), 0, 0))

            if alpha >= 1 then
                break
            end

            RunService.Heartbeat:Wait()
        end

        if model then
            visualCache[model] = nil
            model:Destroy()
        end
    end)
end

local function playHitVisual(targetZombieModel, damage, hitPos, hitEffectTexture, hitEffectColor, ownerUserId)
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    flashZombieRed(targetZombieModel)
    if (tonumber(damage) or 0) > 0 then
        showDamageText(targetZombieModel, damage)
    end
    playHitEffect(hitPos, hitEffectTexture, hitEffectColor)
end

local function playDamageTextVisual(targetZombieModel, damage, ownerUserId)
    if not areEffectsEnabled(tonumber(ownerUserId)) then
        return
    end

    flashZombieRed(targetZombieModel)
    showDamageText(targetZombieModel, damage)
end

local function playDamageTextBatch(entries)
    if type(entries) ~= "table" then
        return
    end

    for _, entry in ipairs(entries) do
        local targetZombieModel = entry.Target or entry[1]
        local damage = entry.Damage or entry[2]
        local ownerUserId = entry.OwnerUserId or entry[3]
        if areEffectsEnabled(tonumber(ownerUserId)) then
            showDamageText(targetZombieModel, damage)
        end
    end
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
        elseif action == "PlantVFX" then
            playPlantVFX(...)
        elseif action == "Projectile" then
            spawnProjectileVisual(...)
        elseif action == "Hit" then
            playHitVisual(...)
        elseif action == "DamageText" then
            playDamageTextVisual(...)
        elseif action == "DamageTextBatch" then
            playDamageTextBatch(...)
        elseif action == "GroundEffectStart" then
            startGroundEffectVisual(...)
        elseif action == "GroundEffectRefresh" then
            refreshGroundEffectVisual(...)
        elseif action == "GroundEffectStop" then
            stopGroundEffectVisual(...)
        elseif action == "ThrownPlantVisual" then
            playThrownPlantVisual(...)
        elseif action == "EffectBurst" then
            playEffectBurst(...)
        elseif action == "ExplosionBurst" then
            playExplosionBurst(...)
        end
    end)
end

return PlantAttackVisualController

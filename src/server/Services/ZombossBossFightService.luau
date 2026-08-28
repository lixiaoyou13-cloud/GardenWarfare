-- src/server/Services/ZombossBossFightService.luau
local ZombossBossFightService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local BossZombieConfig = require(sharedFolder:WaitForChild("BossZombieConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local CombatRegistry = require(script.Parent.CombatRegistry)

local REMOTE_NAME = "ZombossBossFightRE"
local TACO_DROP_REMOTE_NAME = "ZombossTacoDropRE"
local BOSS_ID = "ZomBoss1"
local BOSS_MAX_HP = 80000000
local HP_UPDATE_INTERVAL_SECONDS = 0.1
local SCRATCH_HEAD_INTERVAL_SECONDS = 20
local DEFAULT_DEATH_CLEANUP_SECONDS = 2.5
local DEATH_POST_ANIMATION_DESTROY_DELAY_SECONDS = 2
local DEATH_FINAL_POSE_HOLD_OFFSET_SECONDS = 0.05
local DEFAULT_BOSS_EFFECT_EMIT_COUNT = 1
local TIMED_BOSS_EFFECT_DURATION_SECONDS = 1.5
local UNKNOWN_ACTION_ANIMATION_TIMEOUT_SECONDS = 10
local ACTION_ANIMATION_TIMEOUT_PADDING_SECONDS = 1.5
local SHAKE_ANIMATION_MARKER_NAME = "shake"
local FIRE_START_MARKER_NAME = "huo"
local FIRE_END_MARKER_NAME = "huoend"
local JUMP_BOOM_MARKER_NAME = "boom"
local JUMP_BOOM_EFFECT_NAME = "boom"
local JUMP_BOOM_SHAKE_MAGNITUDE = 2.6
local BOSS_ACTION_LOCK_ATTRIBUTE = "ZombossActionLocked"
local BOSS_STOP_INTRO_WALK_ATTRIBUTE = "ZombossStopIntroWalk"
local DEATH_EXPLOSION_MARKER_NAMES = { "Explosion1", "Explosion2", "Explosion3" }
local TACO_DAMAGE_MILESTONE_FRACTION = 0.01
local MAX_TACO_DAMAGE_MILESTONES = 100
local TACO_DAMAGE_MILESTONE_REWARD = 1
local TACO_DEFEAT_REWARD_TOTAL = 120
local MAX_TACO_DEFEAT_VISUALS_PER_PLAYER = 120
local FIRE_MARKER_PLANT_DAMAGE = 1500
local FIRE_MARKER_MIN_PLANTS = 4
local FIRE_MARKER_MAX_PLANTS = 8
local BOOM_MARKER_PLANT_DAMAGE = 2500
local BOOM_MARKER_MIN_PLANTS = 5
local BOOM_MARKER_MAX_PLANTS = 7

local STATE_REMOTE_NAME = "GetZombossBossFightStateRF"
local remoteEvent = nil
local tacoDropRemoteEvent = nil
local stateRemoteFunction = nil
local activeFight = nil
local initialized = false
local startLocked = false
local warnedFireMarkerIssues = {}
local warnedDeathExplosionIssues = {}
local warnedJumpBoomIssues = {}
local buildDamageStats = nil
local cachedPlotService = nil
local warnedPlotServiceLoadFailure = false
local cachedCombatService = nil
local warnedCombatServiceLoadFailure = false

local function getPlotService()
    if cachedPlotService then
        return cachedPlotService
    end

    local ok, serviceOrErr = pcall(function()
        return require(script.Parent.PlotService)
    end)

    if ok then
        cachedPlotService = serviceOrErr
        return cachedPlotService
    end

    if not warnedPlotServiceLoadFailure then
        warnedPlotServiceLoadFailure = true
        warn("[ZombossBossFightService] Failed to load PlotService: " .. tostring(serviceOrErr))
    end
    return nil
end

local function getCombatService()
    if cachedCombatService then
        return cachedCombatService
    end

    local ok, serviceOrErr = pcall(function()
        return require(script.Parent.CombatService)
    end)

    if ok then
        cachedCombatService = serviceOrErr
        return cachedCombatService
    end

    if not warnedCombatServiceLoadFailure then
        warnedCombatServiceLoadFailure = true
        warn("[ZombossBossFightService] Failed to load CombatService: " .. tostring(serviceOrErr))
    end
    return nil
end

local function buildFailure(reason, detail)
    if detail == nil or detail == "" then
        return reason
    end

    return reason .. ": " .. tostring(detail)
end

local function getOrCreateRemoteEvent()
    local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if existing then
        if existing:IsA("RemoteEvent") then
            return existing
        end

        warn("[ZombossBossFightService] " .. REMOTE_NAME .. " exists but is not a RemoteEvent.")
        return nil
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
    return remote
end

local function getOrCreateTacoDropRemoteEvent()
    local existing = ReplicatedStorage:FindFirstChild(TACO_DROP_REMOTE_NAME)
    if existing then
        if existing:IsA("RemoteEvent") then
            return existing
        end

        warn("[ZombossBossFightService] " .. TACO_DROP_REMOTE_NAME .. " exists but is not a RemoteEvent.")
        return nil
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = TACO_DROP_REMOTE_NAME
    remote.Parent = ReplicatedStorage
    return remote
end

local function getOrCreateStateRemoteFunction()
    local existing = ReplicatedStorage:FindFirstChild(STATE_REMOTE_NAME)
    if existing then
        if existing:IsA("RemoteFunction") then
            return existing
        end

        warn("[ZombossBossFightService] " .. STATE_REMOTE_NAME .. " exists but is not a RemoteFunction.")
        return nil
    end

    local remote = Instance.new("RemoteFunction")
    remote.Name = STATE_REMOTE_NAME
    remote.Parent = ReplicatedStorage
    return remote
end

local function getBossRootPart(boss)
    if not boss then
        return nil
    end

    if boss:IsA("BasePart") then
        return boss
    end

    if boss:IsA("Model") then
        return boss:FindFirstChild("HumanoidRootPart", true)
            or boss.PrimaryPart
            or boss:FindFirstChildWhichIsA("BasePart", true)
    end

    return boss:FindFirstChildWhichIsA("BasePart", true)
end

local function getOrCreateHumanoid(boss)
    if not boss then
        return nil
    end

    local humanoid = boss:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid
    end

    if boss:IsA("Model") then
        humanoid = Instance.new("Humanoid")
        humanoid.Name = "Humanoid"
        humanoid.Parent = boss
        return humanoid
    end

    return nil
end

local function getAnimator(model)
    if not model then
        return nil
    end

    local controller = model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildOfClass("AnimationController")

    if not controller and model:IsA("Model") then
        controller = Instance.new("AnimationController")
        controller.Name = "ZombossBossFightAnimationController"
        controller.Parent = model
    end

    if not controller then
        return nil
    end

    local animator = controller:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = controller
    end

    return animator
end

local function stopBossAnimationTracks(boss, fadeTime)
    local animator = getAnimator(boss)
    if not animator then
        return
    end

    local ok, tracksOrErr = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok or type(tracksOrErr) ~= "table" then
        return
    end

    for _, track in ipairs(tracksOrErr) do
        pcall(function()
            track:Stop(fadeTime or 0.1)
        end)
    end
end

local function bindAnimationShakeMarker(track, sourceName, defaultMagnitude)
    if not track then
        return nil
    end

    local okSignal, signalOrErr = pcall(function()
        return track:GetMarkerReachedSignal(SHAKE_ANIMATION_MARKER_NAME)
    end)
    if not okSignal or not signalOrErr then
        return nil
    end

    return signalOrErr:Connect(function(parameter)
        local magnitude = tonumber(parameter) or defaultMagnitude or 1
        if remoteEvent then
            remoteEvent:FireAllClients("AnimationShake", {
                Source = sourceName or "BossAnimation",
                Magnitude = math.clamp(magnitude, 0.2, 3),
            })
        end
    end)
end

local function flashPlantRed(plantModel)
    local cachedParts = CombatRegistry.GetCachedParts(plantModel)
    for _, part in ipairs(cachedParts.BaseParts) do
        if part and part.Parent then
            if not part:GetAttribute("OriginalColor") then
                part:SetAttribute("OriginalColor", part.Color)
            end

            part.Color = Color3.fromRGB(255, 50, 50)
            task.delay(0.15, function()
                if part and part.Parent then
                    part.Color = part:GetAttribute("OriginalColor")
                end
            end)
        end
    end
end

local function collectAliveCombatPlants(plot, ownerUserId)
    local plants = {}
    local lawnFolder = plot and plot:FindFirstChild("Lawn")
    if not lawnFolder then
        return plants
    end

    for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
        for _, child in ipairs(lawnPart:GetChildren()) do
            if child:IsA("Model")
                and child:GetAttribute("IsCombatPlant") == true
                and child:GetAttribute("IsDead") ~= true
                and (tonumber(child:GetAttribute("Health")) or 0) > 0
                and (not ownerUserId or tonumber(child:GetAttribute("OwnerId")) == ownerUserId)
            then
                table.insert(plants, child)
            end
        end
    end

    return plants
end

local function isLivingCombatPlant(model)
    return model
        and model:IsA("Model")
        and model:GetAttribute("IsCombatPlant") == true
        and model:GetAttribute("IsDead") ~= true
        and (tonumber(model:GetAttribute("Health")) or 0) > 0
end

-- Boss 战中植物死亡会直接销毁，这里同步刷新格子占用状态。
local function refreshLawnOccupancy(lawnPart)
    if not (lawnPart and lawnPart:IsA("BasePart")) then
        return
    end

    local mainPlant = nil
    local pumpkinShield = nil
    for _, child in ipairs(lawnPart:GetChildren()) do
        if isLivingCombatPlant(child) then
            if child:GetAttribute("IsPumpkinShield") == true then
                pumpkinShield = pumpkinShield or child
            else
                mainPlant = mainPlant or child
            end
        end
    end

    if pumpkinShield then
        local shieldId = pumpkinShield:GetAttribute("PlantId") or pumpkinShield.Name
        lawnPart:SetAttribute("PumpkinShield", shieldId)
        pumpkinShield:SetAttribute("OccupiesEmptyGrid", mainPlant == nil)
    else
        lawnPart:SetAttribute("PumpkinShield", nil)
    end

    if mainPlant then
        lawnPart:SetAttribute("OccupiedBy", mainPlant:GetAttribute("PlantId") or mainPlant.Name)
    elseif pumpkinShield then
        lawnPart:SetAttribute("OccupiedBy", pumpkinShield:GetAttribute("PlantId") or pumpkinShield.Name)
    else
        lawnPart:SetAttribute("OccupiedBy", nil)
    end

    local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        prompt.Enabled = mainPlant == nil
    end
end

local function destroyDeadCombatPlant(plant)
    if not plant or not plant.Parent then
        return
    end

    local lawnPart = plant.Parent
    CombatRegistry.UnregisterPlant(plant)
    plant:Destroy()
    refreshLawnOccupancy(lawnPart)
end

local function reloadSavedPlantsForAllPlayers()
    local CombatService = getCombatService()
    if not (CombatService and type(CombatService.ReloadSavedPlants) == "function") then
        warn("[ZombossBossFightService] Cannot reload combat plants because CombatService is unavailable.")
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Parent then
            local ok, err = pcall(function()
                CombatService.ReloadSavedPlants(player)
            end)
            if not ok then
                warn("[ZombossBossFightService] Failed to reload combat plants for " .. tostring(player.Name) .. ": " .. tostring(err))
            end
        end
    end
end

local function shuffleArray(array)
    for index = #array, 2, -1 do
        local swapIndex = math.random(1, index)
        array[index], array[swapIndex] = array[swapIndex], array[index]
    end
end

local function damageCombatPlant(player, plant, damageAmount)
    if not player or not player.Parent or not plant or not plant.Parent then
        return false
    end
    if plant:GetAttribute("IsDead") == true then
        return false
    end

    local currentHP = tonumber(plant:GetAttribute("Health")) or 0
    if currentHP <= 0 then
        return false
    end

    local newHP = math.max(0, currentHP - math.max(0, tonumber(damageAmount) or 0))
    plant:SetAttribute("Health", newHP)

    local gridName = plant:GetAttribute("GridName")
    if gridName then
        PlayerDataManager.UpdateCombatPlantHP(player, gridName, newHP)
    end

    if newHP > 0 then
        flashPlantRed(plant)
        return true
    end

    plant:SetAttribute("IsDead", true)
    destroyDeadCombatPlant(plant)
    return true
end

local function damageRandomPlayerPlantsForAllPlayers(minPlants, maxPlants, damageAmount, reason)
    local damagedTotal = 0
    minPlants = math.max(0, math.floor(tonumber(minPlants) or 0))
    maxPlants = math.max(minPlants, math.floor(tonumber(maxPlants) or minPlants))

    local PlotService = getPlotService()
    if not PlotService or type(PlotService.GetPlayerPlot) ~= "function" then
        warn("[ZombossBossFightService] Zomboss " .. tostring(reason) .. " plant damage skipped because PlotService is unavailable.")
        return damagedTotal
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local plot = PlotService.GetPlayerPlot(player)
        local plants = collectAliveCombatPlants(plot, player.UserId)
        if #plants > 0 then
            shuffleArray(plants)
            local targetCount = math.random(minPlants, maxPlants)
            targetCount = math.clamp(targetCount, 1, #plants)

            for index = 1, targetCount do
                if damageCombatPlant(player, plants[index], damageAmount) then
                    damagedTotal += 1
                end
            end
        end
    end

    if damagedTotal <= 0 then
        warn("[ZombossBossFightService] Zomboss " .. tostring(reason) .. " plant damage found no alive combat plants.")
    end

    return damagedTotal
end

local function isFireBeamEffect(instance)
    return instance:IsA("ParticleEmitter")
        or instance:IsA("Beam")
        or instance:IsA("Trail")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("Highlight")
end

local function setFireBeamEffectsEnabled(boss, enabled)
    local fireBeam = boss and boss:FindFirstChild("FireBeam", true)
    if not fireBeam then
        return false
    end

    local changed = false
    for _, attachment in ipairs(fireBeam:GetDescendants()) do
        if attachment:IsA("Attachment") then
            for _, effect in ipairs(attachment:GetDescendants()) do
                if isFireBeamEffect(effect) then
                    effect.Enabled = enabled
                    changed = true
                    if not enabled and (effect:IsA("ParticleEmitter") or effect:IsA("Trail")) then
                        pcall(function()
                            effect:Clear()
                        end)
                    end
                end
            end
        end
    end

    return changed
end

local function isTimedExplosionEffect(instance)
    return instance:IsA("Beam")
        or instance:IsA("Trail")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("Highlight")
end

local function warnDeathExplosionOnce(bossId, markerName, reason)
    local key = tostring(bossId or BOSS_ID) .. ":" .. tostring(markerName) .. ":" .. tostring(reason)
    if warnedDeathExplosionIssues[key] then
        return
    end

    warnedDeathExplosionIssues[key] = true
    warn("[ZombossBossFightService] Death explosion " .. tostring(reason) .. ": " .. tostring(markerName))
end

local function warnJumpBoomOnce(bossId, reason)
    local key = tostring(bossId or BOSS_ID) .. ":" .. tostring(reason)
    if warnedJumpBoomIssues[key] then
        return
    end

    warnedJumpBoomIssues[key] = true
    local message = "[ZombossBossFightService] Jump boom " .. tostring(reason) .. "."
    if string.find(tostring(reason), "marker", 1, true) then
        message = message .. " The jump animation played, but the lowercase 'boom' Animation Marker did not fire."
    end
    warn(message)
end

local function getBossEffectEmitCount(emitter)
    local emitCount = tonumber(emitter:GetAttribute("EmitCount"))
    if emitCount and emitCount > 0 then
        return math.floor(emitCount)
    end

    return DEFAULT_BOSS_EFFECT_EMIT_COUNT
end

local function setBossEffectRootEnabled(effectRoot, enabled)
    if not effectRoot then
        return
    end

    local function setEffect(instance)
        if instance:IsA("ParticleEmitter") then
            instance.Enabled = enabled
            if not enabled then
                pcall(function()
                    instance:Clear()
                end)
            end
        elseif isTimedExplosionEffect(instance) then
            instance.Enabled = enabled
            if not enabled and instance:IsA("Trail") then
                pcall(function()
                    instance:Clear()
                end)
            end
        end
    end

    setEffect(effectRoot)
    for _, descendant in ipairs(effectRoot:GetDescendants()) do
        setEffect(descendant)
    end
end

local function setDeathExplosionEffectsEnabled(boss, enabled)
    if not boss then
        return
    end

    for _, markerName in ipairs(DEATH_EXPLOSION_MARKER_NAMES) do
        local effectRoot = boss:FindFirstChild(markerName, true)
        if effectRoot then
            setBossEffectRootEnabled(effectRoot, enabled)
        end
    end
end

local function triggerBossEffectRoot(effectRoot)
    local triggered = false
    local function triggerEffect(instance)
        if instance:IsA("ParticleEmitter") then
            triggered = true
            pcall(function()
                instance:Clear()
                instance:Emit(getBossEffectEmitCount(instance))
            end)
        elseif isTimedExplosionEffect(instance) then
            triggered = true
            instance.Enabled = true
            task.delay(TIMED_BOSS_EFFECT_DURATION_SECONDS, function()
                if instance and instance.Parent then
                    instance.Enabled = false
                    if instance:IsA("Trail") then
                        pcall(function()
                            instance:Clear()
                        end)
                    end
                end
            end)
        end
    end

    triggerEffect(effectRoot)
    for _, descendant in ipairs(effectRoot:GetDescendants()) do
        triggerEffect(descendant)
    end

    return triggered
end

local function triggerDeathExplosionEffects(boss, bossId, markerName)
    local effectRoot = boss and boss:FindFirstChild(markerName, true)
    if not effectRoot then
        warnDeathExplosionOnce(bossId, markerName, "effect node missing")
        return false
    end

    local triggered = triggerBossEffectRoot(effectRoot)
    if not triggered then
        warnDeathExplosionOnce(bossId, markerName, "has no supported effects")
    end

    return triggered
end

local function triggerJumpBoomEffects(boss, bossId)
    local effectRoot = boss and boss:FindFirstChild(JUMP_BOOM_EFFECT_NAME, true)
    if not effectRoot then
        warnJumpBoomOnce(bossId, "effect node missing")
        return false
    end

    local triggered = triggerBossEffectRoot(effectRoot)
    if not triggered then
        warnJumpBoomOnce(bossId, "has no supported effects")
    end

    return triggered
end

local function setJumpBoomEffectsEnabled(boss, enabled)
    local effectRoot = boss and boss:FindFirstChild(JUMP_BOOM_EFFECT_NAME, true)
    if effectRoot then
        setBossEffectRootEnabled(effectRoot, enabled)
    end
end

local function warnFireMarkerOnce(bossId, markerName)
    local key = tostring(bossId or BOSS_ID) .. ":" .. tostring(markerName)
    if warnedFireMarkerIssues[key] then
        return
    end
    warnedFireMarkerIssues[key] = true
    warn("[ZombossBossFightService] Fire animation marker was not reached: " .. tostring(markerName))
end

local function playBossActionAnimation(fight, animationId, sourceName, defaultMagnitude, useFireMarkers, useJumpBoomMarker)
    if not fight or fight.Ending or activeFight ~= fight then
        return false
    end

    local boss = fight.Boss
    if not boss or not boss.Parent then
        return false
    end

    if type(animationId) ~= "string" or animationId == "" then
        return false
    end

    local animator = getAnimator(boss)
    if not animator then
        return false
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    animation:Destroy()

    if not ok or not trackOrErr then
        warn("[ZombossBossFightService] Failed to load " .. tostring(sourceName) .. " animation: " .. tostring(trackOrErr))
        return false
    end

    local track = trackOrErr
    track.Looped = false
    track.Priority = Enum.AnimationPriority.Action
    local lockedPivot = boss:GetPivot()
    local pivotLockConnection = nil
    local stopped = false
    local timedOut = false
    local fireStartReached = false
    local fireEndReached = false
    local jumpBoomReached = false

    local markerConnection = bindAnimationShakeMarker(track, sourceName, defaultMagnitude)
    local stoppedConnection = track.Stopped:Connect(function()
        stopped = true
    end)
    local fireStartConnection = nil
    local fireEndConnection = nil
    local jumpBoomConnection = nil

    if useFireMarkers then
        local okStart, startSignal = pcall(function()
            return track:GetMarkerReachedSignal(FIRE_START_MARKER_NAME)
        end)
        if okStart and startSignal then
            fireStartConnection = startSignal:Connect(function()
                fireStartReached = true
                setFireBeamEffectsEnabled(boss, true)
                damageRandomPlayerPlantsForAllPlayers(
                    FIRE_MARKER_MIN_PLANTS,
                    FIRE_MARKER_MAX_PLANTS,
                    FIRE_MARKER_PLANT_DAMAGE,
                    FIRE_START_MARKER_NAME
                )
            end)
        end

        local okEnd, endSignal = pcall(function()
            return track:GetMarkerReachedSignal(FIRE_END_MARKER_NAME)
        end)
        if okEnd and endSignal then
            fireEndConnection = endSignal:Connect(function()
                fireEndReached = true
                setFireBeamEffectsEnabled(boss, false)
            end)
        end
    end

    if useJumpBoomMarker then
        local okBoom, boomSignal = pcall(function()
            return track:GetMarkerReachedSignal(JUMP_BOOM_MARKER_NAME)
        end)
        if okBoom and boomSignal then
            jumpBoomConnection = boomSignal:Connect(function()
                if jumpBoomReached then
                    return
                end
                jumpBoomReached = true
                if jumpBoomConnection then
                    jumpBoomConnection:Disconnect()
                    jumpBoomConnection = nil
                end
                if remoteEvent then
                    remoteEvent:FireAllClients("AnimationShake", {
                        Source = "JumpBoom",
                        Magnitude = JUMP_BOOM_SHAKE_MAGNITUDE,
                    })
                end
                triggerJumpBoomEffects(boss, fight.BossId)
                damageRandomPlayerPlantsForAllPlayers(
                    BOOM_MARKER_MIN_PLANTS,
                    BOOM_MARKER_MAX_PLANTS,
                    BOOM_MARKER_PLANT_DAMAGE,
                    JUMP_BOOM_MARKER_NAME
                )
            end)
        end
    end

    fight.ActionTrack = track
    track:Play(0.05)
    local startedAt = os.clock()
    local timeoutSeconds = UNKNOWN_ACTION_ANIMATION_TIMEOUT_SECONDS

    pivotLockConnection = RunService.Heartbeat:Connect(function()
        if activeFight == fight and not fight.Ending and boss.Parent and track.IsPlaying then
            boss:PivotTo(lockedPivot)
        end
    end)

    while activeFight == fight and not fight.Ending and boss.Parent and not stopped do
        local length = tonumber(track.Length) or 0
        if length > 0 then
            timeoutSeconds = length + ACTION_ANIMATION_TIMEOUT_PADDING_SECONDS
        end
        if os.clock() - startedAt >= timeoutSeconds then
            timedOut = true
            warn("[ZombossBossFightService] " .. tostring(sourceName) .. " animation timed out.")
            break
        end

        RunService.Heartbeat:Wait()
    end

    if timedOut or activeFight ~= fight or fight.Ending or not boss.Parent then
        pcall(function()
            if track.IsPlaying then
                track:Stop(0.05)
            end
        end)
    end

    if markerConnection then
        markerConnection:Disconnect()
    end
    if fireStartConnection then
        fireStartConnection:Disconnect()
    end
    if fireEndConnection then
        fireEndConnection:Disconnect()
    end
    if jumpBoomConnection then
        jumpBoomConnection:Disconnect()
    end
    if stoppedConnection then
        stoppedConnection:Disconnect()
    end
    if pivotLockConnection then
        pivotLockConnection:Disconnect()
    end

    if useFireMarkers then
        if activeFight == fight and not fight.Ending and boss.Parent then
            if not fireStartReached then
                warnFireMarkerOnce(fight.BossId, FIRE_START_MARKER_NAME)
            end
            if not fireEndReached then
                warnFireMarkerOnce(fight.BossId, FIRE_END_MARKER_NAME)
            end
        end
        setFireBeamEffectsEnabled(boss, false)
    end

    if useJumpBoomMarker and activeFight == fight and not fight.Ending and boss.Parent and not jumpBoomReached then
        warnJumpBoomOnce(fight.BossId, "marker was not reached; check asset rbxassetid://122118226905874")
    end

    if fight.ActionTrack == track then
        fight.ActionTrack = nil
    end
    pcall(function()
        track:Destroy()
    end)

    return not timedOut and stopped and activeFight == fight and not fight.Ending and boss.Parent ~= nil
end

local function playBossActionSequence(fight)
    if not fight or fight.Ending or activeFight ~= fight or fight.ActionSequenceRunning then
        return
    end

    local boss = fight.Boss
    if not boss or not boss.Parent then
        return
    end

    fight.ActionSequenceRunning = true
    boss:SetAttribute(BOSS_ACTION_LOCK_ATTRIBUTE, true)
    setFireBeamEffectsEnabled(boss, false)

    local bossConfig = BossZombieConfig[fight.BossId or BOSS_ID] or {}
    local anims = bossConfig.Anims or {}
    local scratchAnimationId = anims.ScratchHead or anims.Eat
    local sequence = {
        { AnimationId = scratchAnimationId, Source = "ScratchHead", Shake = 1 },
        { AnimationId = anims.Fire, Source = "Fire", Shake = 1.15, FireMarkers = true },
        { AnimationId = anims.Jump, Source = "Jump", Shake = 1.25, JumpBoomMarker = true },
        { AnimationId = scratchAnimationId, Source = "ScratchHead", Shake = 1 },
    }

    for _, step in ipairs(sequence) do
        if activeFight ~= fight or fight.Ending or not boss.Parent then
            break
        end

        playBossActionAnimation(fight, step.AnimationId, step.Source, step.Shake, step.FireMarkers, step.JumpBoomMarker)
    end

    setFireBeamEffectsEnabled(boss, false)
    if boss and boss.Parent then
        boss:SetAttribute(BOSS_ACTION_LOCK_ATTRIBUTE, nil)
    end
    fight.ActionSequenceRunning = false
end

local function playDeathAnimation(boss, animationId, bossId, onFinished)
    local function finishAfterFallbackDelay()
        task.delay(DEFAULT_DEATH_CLEANUP_SECONDS, function()
            if type(onFinished) == "function" then
                onFinished()
            end
        end)
    end

    if type(animationId) ~= "string" or animationId == "" or not boss then
        finishAfterFallbackDelay()
        return false
    end

    stopBossAnimationTracks(boss, 0.1)

    local animator = getAnimator(boss)
    if not animator then
        finishAfterFallbackDelay()
        return false
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    animation:Destroy()

    if not ok or not trackOrErr then
        warn("[ZombossBossFightService] Failed to load death animation: " .. tostring(trackOrErr))
        finishAfterFallbackDelay()
        return false
    end

    local track = trackOrErr
    track.Looped = false
    track.Priority = Enum.AnimationPriority.Action
    setDeathExplosionEffectsEnabled(boss, false)

    local reachedExplosionMarkers = {}
    local connections = {}

    local shakeConnection = bindAnimationShakeMarker(track, "Death", 1.25)
    if shakeConnection then
        table.insert(connections, shakeConnection)
    end

    for _, markerName in ipairs(DEATH_EXPLOSION_MARKER_NAMES) do
        reachedExplosionMarkers[markerName] = false
        local okSignal, signalOrErr = pcall(function()
            return track:GetMarkerReachedSignal(markerName)
        end)

        if okSignal and signalOrErr then
            local markerConnection = signalOrErr:Connect(function()
                reachedExplosionMarkers[markerName] = true
                triggerDeathExplosionEffects(boss, bossId, markerName)
            end)
            table.insert(connections, markerConnection)
        end
    end

    track:Play(0.05)
    local lengthReadStartedAt = os.clock()
    while boss and boss.Parent and track.Length <= 0 and os.clock() - lengthReadStartedAt < 1 do
        RunService.Heartbeat:Wait()
    end

    local length = tonumber(track.Length) or 0
    if length <= 0 then
        length = DEFAULT_DEATH_CLEANUP_SECONDS
    end

    local cleanupDelay = math.max(0.1, length)
    local finalized = false
    local stoppedConnection = nil
    local function holdDeathFinalPose()
        if not boss or not boss.Parent then
            return
        end

        pcall(function()
            if not track.IsPlaying then
                track:Play(0)
            end
            if track.Length > 0 then
                track.TimePosition = math.max(0, track.Length - DEATH_FINAL_POSE_HOLD_OFFSET_SECONDS)
            end
            track:AdjustSpeed(0)
        end)
    end

    local function finalizeDeathAnimation()
        if finalized then
            return
        end

        finalized = true
        if stoppedConnection then
            stoppedConnection:Disconnect()
            stoppedConnection = nil
        end

        for _, markerName in ipairs(DEATH_EXPLOSION_MARKER_NAMES) do
            if not reachedExplosionMarkers[markerName] then
                warnDeathExplosionOnce(bossId, markerName, "marker was not reached")
            end
        end

        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        table.clear(connections)

        if boss and boss.Parent then
            holdDeathFinalPose()
            setDeathExplosionEffectsEnabled(boss, false)
        end

        if type(onFinished) == "function" then
            onFinished()
        end
    end

    stoppedConnection = track.Stopped:Connect(function()
        finalizeDeathAnimation()
    end)

    task.delay(cleanupDelay, function()
        if finalized then
            return
        end

        finalizeDeathAnimation()
    end)

    return true
end

local function getCurrentHP(fight)
    local humanoid = fight and fight.Humanoid
    if not humanoid then
        return 0
    end

    return math.max(0, math.floor(humanoid.Health + 0.5))
end

function buildDamageStats(fight)
    local stats = {}
    local damageByUserId = fight and fight.DamageByUserId
    if type(damageByUserId) ~= "table" then
        return stats
    end

    for userId, damage in pairs(damageByUserId) do
        local numericUserId = tonumber(userId)
        local numericDamage = math.max(0, math.floor((tonumber(damage) or 0) + 0.5))
        if numericUserId and numericDamage > 0 then
            table.insert(stats, {
                UserId = numericUserId,
                Damage = numericDamage,
            })
        end
    end

    table.sort(stats, function(a, b)
        if a.Damage == b.Damage then
            return a.UserId < b.UserId
        end

        return a.Damage > b.Damage
    end)

    return stats
end

local function buildPayload(fight)
    local payload = {
        IsActive = fight ~= nil and not fight.Ending,
        CurrentHP = getCurrentHP(fight),
        MaxHP = fight and fight.MaxHP or 1,
        DamageStats = buildDamageStats(fight),
    }
    return payload
end

local function fireAll(action, payload)
    if remoteEvent then
        remoteEvent:FireAllClients(action, payload)
    end
end

local function fireClient(player, action, payload)
    if remoteEvent and player and player.Parent then
        remoteEvent:FireClient(player, action, payload)
    end
end

local function getFightEffectOrigin(fight)
    local rootPart = fight and fight.RootPart
    if rootPart and rootPart.Parent then
        return rootPart.Position
    end

    local boss = fight and fight.Boss
    if boss and boss.Parent then
        local ok, pivot = pcall(function()
            return boss:GetPivot()
        end)
        if ok and typeof(pivot) == "CFrame" then
            return pivot.Position
        end
    end

    return nil
end

local function fireTacoDrop(player, fight, amount, visualCount, reason)
    if not player or not player.Parent then
        return
    end

    tacoDropRemoteEvent = tacoDropRemoteEvent or getOrCreateTacoDropRemoteEvent()
    if not tacoDropRemoteEvent then
        return
    end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    visualCount = math.max(1, math.floor(tonumber(visualCount) or amount or 1))
    if amount <= 0 then
        return
    end

    tacoDropRemoteEvent:FireClient(player, {
        Amount = amount,
        VisualCount = visualCount,
        OriginPosition = getFightEffectOrigin(fight),
        Reason = reason,
    })
end

local function grantTacos(player, amount, context)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 or not player or not player.Parent then
        return false
    end

    local data = PlayerDataManager.GetPlayerData(player)
    if type(data) ~= "table" then
        warn("[ZombossBossFightService] Cannot grant Zomboss tacos; player data is missing for " .. tostring(player.Name))
        return false
    end

    data.Tacos = math.max(0, math.floor(tonumber(data.Tacos) or 0)) + amount
    PlayerDataManager.FireDataPatch(player, {
        Tacos = data.Tacos,
    })
    PlayerDataManager.RequestSave(player, context or "zomboss taco reward")
    return true
end

local function awardDamageMilestoneTacos(fight, ownerUserId)
    if not fight or fight.Ending then
        return
    end

    local damageByUserId = fight.DamageByUserId
    if type(damageByUserId) ~= "table" then
        return
    end

    ownerUserId = tonumber(ownerUserId)
    if not ownerUserId then
        return
    end

    local cumulativeDamage = math.max(0, tonumber(damageByUserId[ownerUserId]) or 0)
    if cumulativeDamage <= 0 then
        return
    end

    fight.TacoMilestonesByUserId = fight.TacoMilestonesByUserId or {}
    local previousMilestone = math.max(0, math.floor(tonumber(fight.TacoMilestonesByUserId[ownerUserId]) or 0))
    local reachedMilestone = previousMilestone
    local grantAmount = 0

    for milestoneIndex = previousMilestone + 1, MAX_TACO_DAMAGE_MILESTONES do
        local threshold = math.max(1, math.ceil((tonumber(fight.MaxHP) or 1) * TACO_DAMAGE_MILESTONE_FRACTION * milestoneIndex))
        if cumulativeDamage < threshold then
            break
        end

        reachedMilestone = milestoneIndex
        grantAmount += TACO_DAMAGE_MILESTONE_REWARD
    end

    if grantAmount <= 0 then
        return
    end

    local player = Players:GetPlayerByUserId(ownerUserId)
    if grantTacos(player, grantAmount, "zomboss damage taco milestone") then
        fight.TacoMilestonesByUserId[ownerUserId] = reachedMilestone
        fireTacoDrop(player, fight, grantAmount, grantAmount, "DamageMilestone")
    end
end

local function awardDefeatTacos(fight)
    if not fight or fight.DefeatTacosAwarded then
        return
    end

    fight.DefeatTacosAwarded = true
    local stats = buildDamageStats(fight)
    local eligiblePlayers = {}

    for _, stat in ipairs(stats) do
        local player = Players:GetPlayerByUserId(stat.UserId)
        if player and player.Parent then
            table.insert(eligiblePlayers, {
                Player = player,
                UserId = stat.UserId,
                Damage = stat.Damage,
            })
        end
    end

    local playerCount = #eligiblePlayers
    if playerCount <= 0 then
        warn("[ZombossBossFightService] Zomboss defeated, but no online damage dealers were eligible for taco split.")
        return
    end

    local baseReward = math.floor(TACO_DEFEAT_REWARD_TOTAL / playerCount)
    local remainder = TACO_DEFEAT_REWARD_TOTAL % playerCount

    for index, entry in ipairs(eligiblePlayers) do
        local rewardAmount = baseReward
        if index <= remainder then
            rewardAmount += 1
        end

        if rewardAmount > 0 and grantTacos(entry.Player, rewardAmount, "zomboss defeat taco split") then
            fireTacoDrop(
                entry.Player,
                fight,
                rewardAmount,
                math.clamp(rewardAmount, 1, MAX_TACO_DEFEAT_VISUALS_PER_PLAYER),
                "DefeatReward"
            )
        end
    end
end

local function broadcastStartState(fight)
    if activeFight ~= fight or not fight or fight.Ending then
        return
    end

    fireAll("Start", buildPayload(fight))
end

local function setFightAttributes(boss, maxHP)
    if not boss then
        return
    end

    boss:SetAttribute("IsEventZomboss", true)
    boss:SetAttribute("EventBossMaxHP", maxHP)
    boss:SetAttribute("EventBossStartedAt", os.time())
end

local function disconnectFight(fight)
    if not fight then
        return
    end

    if fight.HealthConnection then
        fight.HealthConnection:Disconnect()
        fight.HealthConnection = nil
    end
    if fight.DestroyingConnection then
        fight.DestroyingConnection:Disconnect()
        fight.DestroyingConnection = nil
    end
    if fight.ActionTrack then
        pcall(function()
            fight.ActionTrack:Stop(0.1)
        end)
        fight.ActionTrack = nil
    end
    if fight.ScratchHeadTrack then
        pcall(function()
            fight.ScratchHeadTrack:Stop(0.1)
        end)
        fight.ScratchHeadTrack = nil
    end
    fight.ActionSequenceRunning = false
    if fight.Boss and fight.Boss.Parent then
        setFireBeamEffectsEnabled(fight.Boss, false)
        setJumpBoomEffectsEnabled(fight.Boss, false)
        fight.Boss:SetAttribute(BOSS_ACTION_LOCK_ATTRIBUTE, nil)
    end
end

local function finishFight(wasDefeated)
    local fight = activeFight
    if not fight or fight.Ending then
        return
    end

    fight.Ending = true
    if wasDefeated then
        awardDefeatTacos(fight)
    end
    activeFight = nil
    startLocked = false
    disconnectFight(fight)

    local boss = fight.Boss
    if boss and boss.Parent then
        boss:SetAttribute(BOSS_STOP_INTRO_WALK_ATTRIBUTE, true)
        boss:SetAttribute("IsZombie", false)
        boss:SetAttribute("IsEventZomboss", false)
    end

    fireAll("End", buildPayload(fight))
    reloadSavedPlantsForAllPlayers()

    if wasDefeated and boss and boss.Parent then
        local bossConfig = BossZombieConfig[fight.BossId or BOSS_ID] or {}
        setDeathExplosionEffectsEnabled(boss, false)
        playDeathAnimation(boss, bossConfig.Anims and bossConfig.Anims.Death, fight.BossId, function()
            task.delay(DEATH_POST_ANIMATION_DESTROY_DELAY_SECONDS, function()
                if boss and boss.Parent then
                    setFireBeamEffectsEnabled(boss, false)
                    setJumpBoomEffectsEnabled(boss, false)
                    setDeathExplosionEffectsEnabled(boss, false)
                    boss:Destroy()
                end
            end)
        end)
    elseif boss and boss.Parent then
        setFireBeamEffectsEnabled(boss, false)
        setJumpBoomEffectsEnabled(boss, false)
        setDeathExplosionEffectsEnabled(boss, false)
        boss:Destroy()
    end
end

local function queueHPUpdate(fight)
    if not fight or fight.PendingHPUpdate then
        return
    end

    fight.PendingHPUpdate = true
    task.delay(HP_UPDATE_INTERVAL_SECONDS, function()
        if activeFight ~= fight or fight.Ending then
            return
        end

        fight.PendingHPUpdate = false
        fireAll("UpdateHP", buildPayload(fight))
    end)
end

local function prepareBossForFight(boss, bossId)
    local rootPart = getBossRootPart(boss)
    local humanoid = getOrCreateHumanoid(boss)

    if not rootPart or not humanoid then
        return nil, nil
    end

    if boss:IsA("Model") and not boss.PrimaryPart and rootPart:IsA("BasePart") then
        boss.PrimaryPart = rootPart
    end

    boss:SetAttribute("IsZombie", true)
    boss:SetAttribute("BossId", bossId)
    boss:SetAttribute("OwnerId", nil)

    for _, descendant in ipairs(boss:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = true
            descendant.CanTouch = true
            descendant.CanQuery = true
            descendant.Anchored = descendant == rootPart or descendant.Anchored
        end
    end
    rootPart.Anchored = true

    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    end)
    humanoid.WalkSpeed = 0

    return humanoid, rootPart
end

function ZombossBossFightService.IsActive()
    return activeFight ~= nil or startLocked
end

function ZombossBossFightService.IsFightActive()
    return activeFight ~= nil and activeFight.Ending ~= true
end

function ZombossBossFightService.SetStartLocked(isLocked)
    startLocked = isLocked == true
end

function ZombossBossFightService.GetActiveBossTargetForPlot(_plot)
    local fight = activeFight
    if not fight or fight.Ending then
        return nil, nil, nil
    end

    local boss = fight.Boss
    local humanoid = fight.Humanoid
    local rootPart = fight.RootPart
    if not boss or not boss.Parent or not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart.Parent then
        return nil, nil, nil
    end

    return boss, humanoid, rootPart
end

function ZombossBossFightService.RecordPlayerDamage(boss, ownerUserId, damage)
    local fight = activeFight
    if not fight or fight.Ending or fight.Boss ~= boss then
        return false
    end

    ownerUserId = tonumber(ownerUserId)
    damage = math.max(0, math.floor((tonumber(damage) or 0) + 0.5))
    if not ownerUserId or ownerUserId <= 0 or damage <= 0 then
        return false
    end

    fight.DamageByUserId = fight.DamageByUserId or {}
    fight.DamageByUserId[ownerUserId] = (tonumber(fight.DamageByUserId[ownerUserId]) or 0) + damage
    awardDamageMilestoneTacos(fight, ownerUserId)
    queueHPUpdate(fight)
    return true
end

function ZombossBossFightService.Start(boss, bossId)
    if activeFight then
        return false, "Zomboss boss fight is already active."
    end

    bossId = tostring(bossId or BOSS_ID)
    if typeof(boss) ~= "Instance" or not boss.Parent then
        return false, "Boss instance is missing or no longer parented."
    end

    remoteEvent = remoteEvent or getOrCreateRemoteEvent()
    if not remoteEvent then
        return false, "ZombossBossFightRE RemoteEvent is missing or invalid."
    end

    local prepareOk, humanoid, rootPart = pcall(function()
        return prepareBossForFight(boss, bossId)
    end)
    if not prepareOk then
        return false, buildFailure("Failed to prepare boss for fight", humanoid)
    end

    if not rootPart then
        return false, "Boss model is missing a BasePart or HumanoidRootPart."
    end

    if not humanoid then
        return false, "Boss model is missing a Humanoid and one could not be created."
    end

    local maxHP = BOSS_MAX_HP
    local healthSetOk, healthSetErr = pcall(function()
        humanoid.MaxHealth = maxHP
        humanoid.Health = maxHP
    end)
    if not healthSetOk then
        return false, buildFailure("Failed to set Zomboss Humanoid health", healthSetErr)
    end
    setFightAttributes(boss, maxHP)
    setFireBeamEffectsEnabled(boss, false)

    local fight = {
        Boss = boss,
        BossId = bossId,
        Humanoid = humanoid,
        RootPart = rootPart,
        MaxHP = maxHP,
        DamageByUserId = {},
        TacoMilestonesByUserId = {},
        PendingHPUpdate = false,
        ActionSequenceRunning = false,
        Ending = false,
    }
    activeFight = fight
    startLocked = false

    fight.HealthConnection = humanoid.HealthChanged:Connect(function(newHealth)
        if activeFight ~= fight or fight.Ending then
            return
        end

        if newHealth <= 0 then
            finishFight(true)
        else
            queueHPUpdate(fight)
        end
    end)

    fight.DestroyingConnection = boss.Destroying:Connect(function()
        if activeFight == fight and not fight.Ending then
            finishFight(false)
        end
    end)

    task.spawn(function()
        while activeFight == fight and not fight.Ending do
            task.wait(SCRATCH_HEAD_INTERVAL_SECONDS)
            if activeFight == fight and not fight.Ending then
                playBossActionSequence(fight)
            end
        end
    end)

    broadcastStartState(fight)
    task.delay(0.5, function()
        broadcastStartState(fight)
    end)
    task.delay(1.5, function()
        broadcastStartState(fight)
    end)
    task.delay(3, function()
        broadcastStartState(fight)
    end)

    return true, nil, {
        BossName = boss.Name,
        MaxHP = maxHP,
    }
end

function ZombossBossFightService.End()
    finishFight(false)
end

function ZombossBossFightService.Init()
    if initialized then
        return
    end
    initialized = true

    remoteEvent = getOrCreateRemoteEvent()
    tacoDropRemoteEvent = getOrCreateTacoDropRemoteEvent()
    stateRemoteFunction = getOrCreateStateRemoteFunction()
    if stateRemoteFunction then
        stateRemoteFunction.OnServerInvoke = function()
            return buildPayload(activeFight)
        end
    end

    Players.PlayerAdded:Connect(function(player)
        task.delay(2, function()
            if activeFight and player.Parent then
                fireClient(player, "Start", buildPayload(activeFight))
            end
        end)
    end)
end

return ZombossBossFightService

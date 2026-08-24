-- src/server/Services/ZombossIntroService.luau
local ZombossIntroService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlotService = require(script.Parent.PlotService)
local ZombieService = require(script.Parent.ZombieService)
local ZombossBossFightService = require(script.Parent.ZombossBossFightService)

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local BossZombieConfig = require(sharedFolder:WaitForChild("BossZombieConfig"))
local ZombossShopConfig = require(sharedFolder:WaitForChild("ZombossShopConfig"))

local REMOTE_NAME = "ZombossIntroRE"
local EFFECTS_FOLDER_NAME = "Dr. Zomboss special effects"
local PORTAL_NAME = "CosmicPortal"
local ARRIVAL_PORTAL_NAME = "CosmicPortal1"
local BOSS_START_NAME = "Pos1"
local BOSS_TARGET_NAME = "Pos2"
local BOSS_ID = "ZomBoss1"
local STUDIO_TEST_COMMAND = "!zomboss"

local WAIT_FOR_PLOT_SECONDS = 15
local CLIENT_READY_DELAY_SECONDS = 3
local CAMERA_FOCUS_SECONDS = 2
local BOSS_CLOSEUP_SECONDS = 1
local BOSS_CLOSEUP_EXIT_SECONDS = 0.25
local BLACKOUT_FADE_IN_SECONDS = 0
local BLACKOUT_HOLD_SECONDS = 2
local BLACKOUT_FADE_OUT_SECONDS = 1.25
local BOSS_TITLE_TO_FIGHT_DELAY_SECONDS = 1
local BOSS_FIGHT_START_DELAY_SECONDS = 0.1
local BOSS_ARRIVAL_DEFEAT_BLACKOUT_SECONDS = 2
local BOSS_ARRIVAL_DEFEAT_TEXT = "You are too weak."
local DEFAULT_PARTICLE_EMIT_COUNT = 1
local PORTAL_EFFECT_VISIBLE_SECONDS = 5
local FOOTSTEP_TARGET_INTERVAL_SECONDS = 0.8
local BOSS_WALK_SPEED_MULTIPLIER = 2
local SHAKE_ANIMATION_MARKER_NAME = "shake"
local BOSS_STOP_INTRO_WALK_ATTRIBUTE = "ZombossStopIntroWalk"

local lastStartedBossWindowId = nil
local remoteEvent = nil
local studioTestChatConnections = {}

-- 读取共享配置里的僵王事件总开关，方便临时关闭整套入场和 Boss 战。
local function isBossEventEnabled()
    if type(ZombossShopConfig.IsBossEventEnabled) == "function" then
        return ZombossShopConfig.IsBossEventEnabled()
    end

    return ZombossShopConfig.BossEventEnabled ~= false
end

local function getOrCreateRemoteEvent()
    local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if existing then
        if existing:IsA("RemoteEvent") then
            return existing
        end

        warn("[ZombossIntroService] " .. REMOTE_NAME .. " exists but is not a RemoteEvent.")
        return nil
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
    return remote
end

local function getObjectCFrame(instance)
    if not instance then
        return nil
    end

    if instance:IsA("Model") then
        return instance:GetPivot()
    end

    if instance:IsA("BasePart") then
        return instance.CFrame
    end

    if instance:IsA("Attachment") then
        return instance.WorldCFrame
    end

    local part = instance:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.CFrame
    end

    local attachment = instance:FindFirstChildWhichIsA("Attachment", true)
    return attachment and attachment.WorldCFrame or nil
end

local function buildLookAtCFrame(position, lookAtPosition, fallbackCFrame)
    local direction = lookAtPosition - position
    if direction.Magnitude < 0.01 then
        return fallbackCFrame or CFrame.new(position)
    end

    return CFrame.lookAt(position, lookAtPosition)
end

local function getIntroObjects()
    local effectsFolder = Workspace:FindFirstChild(EFFECTS_FOLDER_NAME)
    if not effectsFolder then
        warn("[ZombossIntroService] Missing Workspace." .. EFFECTS_FOLDER_NAME)
        return nil
    end

    local portal = effectsFolder:FindFirstChild(PORTAL_NAME)
    if not portal then
        warn("[ZombossIntroService] Missing " .. EFFECTS_FOLDER_NAME .. "." .. PORTAL_NAME)
        return nil
    end

    local arrivalPortal = effectsFolder:FindFirstChild(ARRIVAL_PORTAL_NAME)
    if not arrivalPortal then
        warn("[ZombossIntroService] Missing " .. EFFECTS_FOLDER_NAME .. "." .. ARRIVAL_PORTAL_NAME)
    end

    local startPoint = effectsFolder:FindFirstChild(BOSS_START_NAME)
    if not startPoint then
        warn("[ZombossIntroService] Missing " .. EFFECTS_FOLDER_NAME .. "." .. BOSS_START_NAME)
        return nil
    end

    local target = effectsFolder:FindFirstChild(BOSS_TARGET_NAME)
    if not target then
        warn("[ZombossIntroService] Missing " .. EFFECTS_FOLDER_NAME .. "." .. BOSS_TARGET_NAME)
        return nil
    end

    local startCFrame = getObjectCFrame(startPoint)
    local targetCFrame = getObjectCFrame(target)
    if not startCFrame or not targetCFrame then
        warn("[ZombossIntroService] Pos1 and Pos2 need a Model, BasePart, Attachment, or child pivot.")
        return nil
    end

    local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModels then
        warn("[ZombossIntroService] Missing ReplicatedStorage.ItemModels.")
        return nil
    end

    local bossConfig = BossZombieConfig[BOSS_ID]
    if not bossConfig then
        warn("[ZombossIntroService] Missing BossZombieConfig." .. BOSS_ID)
        return nil
    end

    local modelName = bossConfig.ModelName or bossConfig.Id or BOSS_ID
    local bossTemplate = itemModels:FindFirstChild(modelName)
    if not bossTemplate then
        warn("[ZombossIntroService] Missing ReplicatedStorage.ItemModels." .. tostring(modelName))
        return nil
    end

    return {
        Portal = portal,
        ArrivalPortal = arrivalPortal,
        StartPoint = startPoint,
        Target = target,
        BossConfig = bossConfig,
        BossTemplate = bossTemplate,
        StartCFrame = startCFrame,
        TargetCFrame = targetCFrame,
    }
end

local function isPortalEffect(instance)
    return instance:IsA("ParticleEmitter")
        or instance:IsA("Beam")
        or instance:IsA("Trail")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("Highlight")
        or instance:IsA("Fire")
        or instance:IsA("Smoke")
        or instance:IsA("Sparkles")
end

local function setPortalEffectsEnabled(portal, enabled)
    if not portal then
        return false
    end

    local changed = false
    local function setEffect(effect)
        if not isPortalEffect(effect) then
            return
        end

        effect.Enabled = enabled
        changed = true

        if enabled and effect:IsA("ParticleEmitter") then
            local emitCount = tonumber(effect:GetAttribute("EmitCount")) or DEFAULT_PARTICLE_EMIT_COUNT
            pcall(function()
                effect:Emit(emitCount)
            end)
        elseif not enabled and (effect:IsA("ParticleEmitter") or effect:IsA("Trail")) then
            pcall(function()
                effect:Clear()
            end)
        end
    end

    setEffect(portal)
    for _, descendant in ipairs(portal:GetDescendants()) do
        setEffect(descendant)
    end

    return changed
end

local function triggerTimedPortalEffects(portal, visibleSeconds)
    if not setPortalEffectsEnabled(portal, true) then
        return false
    end

    task.delay(math.max(0, tonumber(visibleSeconds) or PORTAL_EFFECT_VISIBLE_SECONDS), function()
        if portal and portal.Parent then
            setPortalEffectsEnabled(portal, false)
        end
    end)

    return true
end

local function getBossRootPart(boss)
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

local function prepareBossModel(boss, startCFrame)
    boss.Name = BOSS_ID
    boss:SetAttribute("IsZombossIntroBoss", true)
    boss:SetAttribute("BossId", BOSS_ID)

    local rootPart = getBossRootPart(boss)
    if rootPart then
        rootPart.Anchored = true
    end

    for _, descendant in ipairs(boss:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = true
            descendant.CanTouch = true
            descendant.CanQuery = true
            if not rootPart then
                descendant.Anchored = true
            end
        elseif descendant:IsA("Sound") then
            descendant:Destroy()
        end
    end

    boss:PivotTo(startCFrame)
end

local function getAnimator(model)
    local controller = model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildOfClass("AnimationController")

    if not controller then
        controller = Instance.new("AnimationController")
        controller.Name = "ZombossIntroAnimationController"
        controller.Parent = model
    end

    local animator = controller:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = controller
    end

    return animator
end

local function playWalkAnimation(boss, animationId)
    if type(animationId) ~= "string" or animationId == "" then
        return nil
    end

    local animator = getAnimator(boss)
    if not animator then
        return nil
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not ok or not trackOrErr then
        warn("[ZombossIntroService] Failed to load walk animation: " .. tostring(trackOrErr))
        animation:Destroy()
        return nil
    end

    local track = trackOrErr
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    track:Play(0.1)
    return track
end

local function stopAnimation(track)
    if not track then
        return
    end

    pcall(function()
        track:Stop(0.2)
    end)
end

local function bindAnimationShakeMarker(track, sourceName)
    if not track or not remoteEvent then
        return nil
    end

    local ok, signalOrErr = pcall(function()
        return track:GetMarkerReachedSignal(SHAKE_ANIMATION_MARKER_NAME)
    end)
    if not ok or not signalOrErr then
        warn("[ZombossIntroService] Failed to bind shake marker: " .. tostring(signalOrErr))
        return nil
    end

    return signalOrErr:Connect(function(parameter)
        local magnitude = tonumber(parameter) or 1
        remoteEvent:FireAllClients("AnimationShake", {
            Source = sourceName or "BossAnimation",
            Magnitude = math.clamp(magnitude, 0.2, 3),
        })
    end)
end

local function moveBossToTarget(boss, startCFrame, targetCFrame, duration)
    local distance = (targetCFrame.Position - startCFrame.Position).Magnitude
    if distance <= 0.05 then
        if boss.Parent then
            boss:PivotTo(targetCFrame)
        end
        return 0
    end

    local stepCount = math.max(1, math.floor(duration / FOOTSTEP_TARGET_INTERVAL_SECONDS + 0.5))
    local nextFootstepTime = 0
    local firedSteps = 0
    local elapsed = 0

    while elapsed < duration and boss.Parent do
        local dt = RunService.Heartbeat:Wait()
        if boss:GetAttribute(BOSS_STOP_INTRO_WALK_ATTRIBUTE) == true then
            return elapsed
        end

        if boss:GetAttribute("ZombossActionLocked") == true then
            continue
        end

        elapsed += dt

        local alpha = math.clamp(elapsed / duration, 0, 1)
        boss:PivotTo(startCFrame:Lerp(targetCFrame, alpha))

        if remoteEvent and elapsed >= nextFootstepTime then
            firedSteps += 1
            local normalizedProgress = math.clamp(elapsed / duration, 0, 1)
            local stepMagnitude = 0.65 + normalizedProgress * 0.55
            remoteEvent:FireAllClients("Footstep", {
                StepIndex = firedSteps,
                StepCount = stepCount,
                Magnitude = stepMagnitude,
                NormalizedProgress = normalizedProgress,
            })
            nextFootstepTime += FOOTSTEP_TARGET_INTERVAL_SECONDS
        end
    end

    if boss.Parent and boss:GetAttribute(BOSS_STOP_INTRO_WALK_ATTRIBUTE) ~= true then
        boss:PivotTo(targetCFrame)
    end

    return duration
end

local function resetPlayerBattle(player)
    local plot = PlotService.GetPlayerPlot(player)
    if not plot then
        return
    end

    plot:SetAttribute("BattleToken", (plot:GetAttribute("BattleToken") or 0) + 1)
    plot:SetAttribute("IsGameOver", true)
    plot:SetAttribute("IsLevelActive", false)
    plot:SetAttribute("ActiveZombies", 0)
    plot:SetAttribute("TotalZombies", 0)
    plot:SetAttribute("ZombiesDefeated", 0)

    ZombieService.CleanupPlayerBattle(player)
    local restoreOk, restoreErr = pcall(function()
        ZombieService.RestorePlotPlants(plot, player)
    end)
    if not restoreOk then
        warn("[ZombossIntroService] Failed to restore plants before Zomboss fight: " .. tostring(restoreErr))
    end

    local combatOk, CombatService = pcall(function()
        return require(script.Parent.CombatService)
    end)
    if combatOk and CombatService and type(CombatService.ReloadSavedPlants) == "function" then
        local reloadOk, reloadErr = pcall(function()
            CombatService.ReloadSavedPlants(player)
        end)
        if not reloadOk then
            warn("[ZombossIntroService] Failed to reload plants before Zomboss fight: " .. tostring(reloadErr))
        end
    elseif not combatOk then
        warn("[ZombossIntroService] Failed to load CombatService before Zomboss fight: " .. tostring(CombatService))
    end

    plot:SetAttribute("IsGameOver", false)

    local syncBattleUI = ReplicatedStorage:FindFirstChild("SyncBattleUI_RE")
    if syncBattleUI and syncBattleUI:IsA("RemoteEvent") then
        syncBattleUI:FireClient(player, false, plot:GetAttribute("CurrentLevel") or 1, 0, 0)
    end
end

local function waitForAnyReadyPlot()
    local deadline = os.clock() + WAIT_FOR_PLOT_SECONDS

    while os.clock() < deadline do
        for _, player in ipairs(Players:GetPlayers()) do
            if PlotService.GetPlayerPlot(player) then
                return true
            end
        end

        task.wait(0.5)
    end

    return false
end

local function runIntro(bossWindowId)
    if not isBossEventEnabled() then
        return
    end

    if bossWindowId ~= nil then
        if lastStartedBossWindowId == bossWindowId then
            return
        end
        lastStartedBossWindowId = bossWindowId
    end

    if ZombossBossFightService.IsActive() then
        warn("[ZombossIntroService] Zomboss spawn skipped because a fight is already active.")
        return
    end

    if not waitForAnyReadyPlot() then
        warn("[ZombossIntroService] No player plot was ready; intro skipped.")
        return
    end

    task.wait(CLIENT_READY_DELAY_SECONDS)

    local objects = getIntroObjects()
    if not objects then
        return
    end

    local startPosition = objects.StartCFrame.Position
    local targetPosition = objects.TargetCFrame.Position
    local startCFrame = buildLookAtCFrame(startPosition, targetPosition, objects.StartCFrame)
    local targetCFrame = buildLookAtCFrame(targetPosition, targetPosition + startCFrame.LookVector, objects.TargetCFrame)

    triggerTimedPortalEffects(objects.Portal, PORTAL_EFFECT_VISIBLE_SECONDS)

    local boss = objects.BossTemplate:Clone()
    prepareBossModel(boss, startCFrame)
    boss.Parent = Workspace

    for _, player in ipairs(Players:GetPlayers()) do
        resetPlayerBattle(player)
    end

    local speed = math.max(0.1, (tonumber(objects.BossConfig.Speed) or 1) * BOSS_WALK_SPEED_MULTIPLIER)
    local distance = (targetCFrame.Position - startCFrame.Position).Magnitude
    local moveDuration = math.max(0.1, distance / speed)
    local blackoutDuration = BLACKOUT_FADE_IN_SECONDS + BLACKOUT_HOLD_SECONDS + BLACKOUT_FADE_OUT_SECONDS
    local moveStartDelay = CAMERA_FOCUS_SECONDS + BOSS_CLOSEUP_SECONDS + BOSS_CLOSEUP_EXIT_SECONDS + blackoutDuration
    local fightIntroEndDelay = blackoutDuration + CAMERA_FOCUS_SECONDS + BOSS_TITLE_TO_FIGHT_DELAY_SECONDS

    ZombossBossFightService.SetStartLocked(true)

    if remoteEvent then
        remoteEvent:FireAllClients("Start", {
            Boss = boss,
            StartCFrame = startCFrame,
            TargetCFrame = targetCFrame,
            BlackoutText = "Here it comes.",
            CameraFocusSeconds = CAMERA_FOCUS_SECONDS,
            CloseupSeconds = BOSS_CLOSEUP_SECONDS,
            CloseupTitleText = "Dr. Zomboss!",
            FadeInSeconds = BLACKOUT_FADE_IN_SECONDS,
            HoldSeconds = BLACKOUT_HOLD_SECONDS,
            FadeOutSeconds = BLACKOUT_FADE_OUT_SECONDS,
            SnapBlackout = true,
            TitleToFightDelaySeconds = BOSS_TITLE_TO_FIGHT_DELAY_SECONDS,
            MoveStartDelaySeconds = moveStartDelay,
            MoveDurationSeconds = moveDuration,
            FootstepIntervalSeconds = FOOTSTEP_TARGET_INTERVAL_SECONDS,
        })
    end

    task.delay(fightIntroEndDelay, function()
        if not boss or not boss.Parent then
            ZombossBossFightService.SetStartLocked(false)
            return
        end

        if remoteEvent then
            remoteEvent:FireAllClients("End")
        end

        task.wait(BOSS_FIGHT_START_DELAY_SECONDS)
        if not boss or not boss.Parent then
            ZombossBossFightService.SetStartLocked(false)
            return
        end

        local callOk, ok, message, startInfo = pcall(function()
            return ZombossBossFightService.Start(boss, BOSS_ID)
        end)
        if not callOk then
            ZombossBossFightService.SetStartLocked(false)
            warn("[ZombossIntroService] Failed to start Zomboss boss fight: " .. tostring(ok))
            return
        end

        if not ok then
            ZombossBossFightService.SetStartLocked(false)
            warn("[ZombossIntroService] Failed to start Zomboss boss fight: " .. tostring(message))
            return
        end

        startInfo = type(startInfo) == "table" and startInfo or {}
        print(string.format(
            "[ZombossIntroService] Zomboss boss fight started. Boss=%s MaxHP=%s",
            tostring(startInfo.BossName or (boss and boss.Name) or BOSS_ID),
            tostring(startInfo.MaxHP or "?")
        ))
    end)

    task.wait(moveStartDelay)
    if not boss or not boss.Parent or boss:GetAttribute(BOSS_STOP_INTRO_WALK_ATTRIBUTE) == true then
        return
    end

    local walkTrack = playWalkAnimation(boss, objects.BossConfig.Anims and objects.BossConfig.Anims.Walk)
    local walkShakeConnection = bindAnimationShakeMarker(walkTrack, "Walk")
    local walkAnimationSpeed = math.clamp(distance / math.max(1, moveDuration) / speed, 0.85, 1.35)
    if walkTrack then
        walkTrack:AdjustSpeed(walkAnimationSpeed)
    end

    if remoteEvent then
        remoteEvent:FireAllClients("BossWalkStart", {
            Boss = boss,
            MoveDurationSeconds = moveDuration,
        })
    end

    moveBossToTarget(boss, startCFrame, targetCFrame, moveDuration)
    if boss and boss.Parent and boss:GetAttribute(BOSS_STOP_INTRO_WALK_ATTRIBUTE) == true then
        if walkShakeConnection then
            walkShakeConnection:Disconnect()
        end
        stopAnimation(walkTrack)
        return
    end
    triggerTimedPortalEffects(objects.ArrivalPortal, PORTAL_EFFECT_VISIBLE_SECONDS)

    if walkShakeConnection then
        walkShakeConnection:Disconnect()
    end
    stopAnimation(walkTrack)

    if not boss or not boss.Parent or not ZombossBossFightService.IsFightActive() then
        return
    end

    if remoteEvent then
        remoteEvent:FireAllClients("BossArrived", {
            Boss = boss,
            ShowBlackout = true,
            BlackoutText = BOSS_ARRIVAL_DEFEAT_TEXT,
            FadeInSeconds = 0,
            HoldSeconds = BOSS_ARRIVAL_DEFEAT_BLACKOUT_SECONDS,
            FadeOutSeconds = 0.2,
            SnapBlackout = true,
        })
    end

    task.wait(BOSS_ARRIVAL_DEFEAT_BLACKOUT_SECONDS)
    if boss and boss.Parent and ZombossBossFightService.IsFightActive() then
        ZombossBossFightService.End()
    end
end

local function bindStudioTestCommand(player)
    if not RunService:IsStudio() or studioTestChatConnections[player] then
        return
    end

    studioTestChatConnections[player] = player.Chatted:Connect(function(message)
        if string.lower(tostring(message or "")) ~= STUDIO_TEST_COMMAND then
            return
        end

        print("[ZombossIntroService] Studio test command received from " .. tostring(player.Name) .. ".")
        task.spawn(function()
            runIntro(nil)
        end)
    end)
end

local function unbindStudioTestCommand(player)
    local connection = studioTestChatConnections[player]
    if connection then
        connection:Disconnect()
        studioTestChatConnections[player] = nil
    end
end

function ZombossIntroService.Init()
    remoteEvent = getOrCreateRemoteEvent()
    if not isBossEventEnabled() then
        print("[ZombossIntroService] Zomboss boss event is disabled by config.")
        return
    end

    if RunService:IsStudio() then
        for _, player in ipairs(Players:GetPlayers()) do
            bindStudioTestCommand(player)
        end
        Players.PlayerAdded:Connect(bindStudioTestCommand)
        Players.PlayerRemoving:Connect(unbindStudioTestCommand)
    end

    task.spawn(function()
        while true do
            local now = os.time()
            local nextBossSpawnAt = ZombossShopConfig.GetNextBossSpawnAt(now)
            while true do
                local remaining = nextBossSpawnAt - os.time()
                if remaining <= 0 then
                    break
                end

                task.wait(math.clamp(remaining, 1, 60))
            end

            local bossWindowId = ZombossShopConfig.GetBossSpawnWindowId(os.time())
            runIntro(bossWindowId)
        end
    end)
end

return ZombossIntroService

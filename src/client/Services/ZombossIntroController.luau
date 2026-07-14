-- src/client/Services/ZombossIntroController.luau
local ZombossIntroController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ZombossUICleanup = require(script.Parent.Parent.Utils.ZombossUICleanup)

local localPlayer = Players.LocalPlayer
local REMOTE_NAME = "ZombossIntroRE"
local GUI_NAME = "ZombossIntroGui"
local BOSS_CAMERA_LOOK_HEIGHT = 28
local BOSS_CAMERA_HEIGHT = 70
local BOSS_CAMERA_DISTANCE = 48
local BOSS_CAMERA_DOWN_ANGLE_DEGREES = 15
local BOSS_CLOSEUP_LOOK_HEIGHT = 34
local BOSS_CLOSEUP_CAMERA_HEIGHT = 56
local BOSS_CLOSEUP_CAMERA_DISTANCE = 28
local BOSS_CLOSEUP_DOWN_ANGLE_DEGREES = 15
local BOSS_CLOSEUP_TITLE_TEXT = "Dr. Zomboss!"

local activeRunId = 0
local renderConnection = nil
local screenShakeConnection = nil
local restoreCameraState = nil
local hiddenGuiStates = nil
local hiddenGuiChildConnection = nil
local shakeEvents = {}
local recoilEvents = {}
local rng = Random.new()
local ensureScreenShakeLoop = nil

local function safeDisconnect(connection)
    if connection then
        connection:Disconnect()
    end
end

local function getCamera()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera
    end

    Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
    return Workspace.CurrentCamera
end

local function getOverlayGui()
    local playerGui = localPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        return nil
    end

    local gui = playerGui:FindFirstChild(GUI_NAME)
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 10000
        gui.Enabled = true
        gui.Parent = playerGui

        local mask = Instance.new("Frame")
        mask.Name = "BlackMask"
        mask.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        mask.BackgroundTransparency = 1
        mask.BorderSizePixel = 0
        mask.Size = UDim2.fromScale(1, 1)
        mask.Visible = false
        mask.Parent = gui

        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "IntroText"
        textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        textLabel.BackgroundTransparency = 1
        textLabel.Position = UDim2.fromScale(0.5, 0.5)
        textLabel.Size = UDim2.fromScale(0.85, 0.18)
        textLabel.Font = Enum.Font.GothamBlack
        textLabel.Text = ""
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        textLabel.TextScaled = true
        textLabel.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
        textLabel.TextStrokeTransparency = 1
        textLabel.TextTransparency = 1
        textLabel.Parent = mask

        local textScale = Instance.new("UIScale")
        textScale.Name = "IntroTextScale"
        textScale.Scale = 1
        textScale.Parent = textLabel

        local flash = Instance.new("Frame")
        flash.Name = "ImpactFlash"
        flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        flash.BackgroundTransparency = 1
        flash.BorderSizePixel = 0
        flash.Size = UDim2.fromScale(1, 1)
        flash.Visible = false
        flash.Parent = gui

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "BossTitle"
        titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Position = UDim2.fromScale(-0.35, 0.32)
        titleLabel.Size = UDim2.fromScale(0.9, 0.16)
        titleLabel.Font = Enum.Font.GothamBlack
        titleLabel.Text = ""
        titleLabel.TextColor3 = Color3.fromRGB(255, 235, 210)
        titleLabel.TextScaled = true
        titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        titleLabel.TextStrokeTransparency = 1
        titleLabel.TextTransparency = 1
        titleLabel.Visible = false
        titleLabel.ZIndex = 5
        titleLabel.Parent = gui

        local titleScale = Instance.new("UIScale")
        titleScale.Name = "BossTitleScale"
        titleScale.Scale = 1
        titleScale.Parent = titleLabel
    end

    return gui
end

local function shouldHideGui(gui)
    return gui:IsA("ScreenGui") and gui.Name ~= GUI_NAME
end

local function hideGuiForIntro(gui)
    if not shouldHideGui(gui) then
        return
    end

    hiddenGuiStates = hiddenGuiStates or {}
    if hiddenGuiStates[gui] == nil then
        hiddenGuiStates[gui] = gui.Enabled
    end
    gui.Enabled = false
end

local function hidePlayerGui(runId)
    if runId ~= activeRunId then
        return
    end

    local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        return
    end

    hiddenGuiStates = {}
    for _, child in ipairs(playerGui:GetDescendants()) do
        hideGuiForIntro(child)
    end

    safeDisconnect(hiddenGuiChildConnection)
    hiddenGuiChildConnection = playerGui.DescendantAdded:Connect(function(child)
        if runId ~= activeRunId then
            return
        end

        hideGuiForIntro(child)
    end)
end

local function restorePlayerGui(runId)
    if runId and runId ~= activeRunId then
        return
    end

    safeDisconnect(hiddenGuiChildConnection)
    hiddenGuiChildConnection = nil

    if hiddenGuiStates then
        for gui, wasEnabled in pairs(hiddenGuiStates) do
            if typeof(gui) == "Instance" and gui.Parent and gui:IsA("ScreenGui") then
                gui.Enabled = wasEnabled
            end
        end
    end

    hiddenGuiStates = nil
end

local function getBossCFrame(boss)
    if typeof(boss) ~= "Instance" or not boss.Parent then
        return nil
    end

    if boss:IsA("Model") then
        return boss:GetPivot()
    end

    if boss:IsA("BasePart") then
        return boss.CFrame
    end

    local part = boss:FindFirstChildWhichIsA("BasePart", true)
    return part and part.CFrame or nil
end

local function getFallbackBossPosition(payload, startClock)
    local startCFrame = payload.StartCFrame
    local targetCFrame = payload.TargetCFrame
    if typeof(startCFrame) ~= "CFrame" then
        return Vector3.zero
    end

    if typeof(targetCFrame) ~= "CFrame" then
        return startCFrame.Position
    end

    local moveStartDelay = tonumber(payload.MoveStartDelaySeconds) or 0
    local moveDuration = math.max(0.1, tonumber(payload.MoveDurationSeconds) or 0.1)
    local elapsed = os.clock() - startClock - moveStartDelay
    local alpha = math.clamp(elapsed / moveDuration, 0, 1)
    return startCFrame.Position:Lerp(targetCFrame.Position, alpha)
end

local function getCameraCFrame(bossCFrame, bossPosition, payload, cameraSettings)
    local startCFrame = payload.StartCFrame
    local targetCFrame = payload.TargetCFrame
    local frontDirection = nil

    if typeof(bossCFrame) == "CFrame" then
        local flatLook = Vector3.new(bossCFrame.LookVector.X, 0, bossCFrame.LookVector.Z)
        if flatLook.Magnitude > 0.01 then
            frontDirection = flatLook.Unit
        end
    end

    if not frontDirection and typeof(startCFrame) == "CFrame" and typeof(targetCFrame) == "CFrame" then
        local delta = targetCFrame.Position - startCFrame.Position
        local flatDelta = Vector3.new(delta.X, 0, delta.Z)
        if flatDelta.Magnitude > 0.01 then
            frontDirection = flatDelta.Unit
        end
    end
    frontDirection = frontDirection or Vector3.new(0, 0, -1)

    local lookHeight = cameraSettings and cameraSettings.LookHeight or BOSS_CAMERA_LOOK_HEIGHT
    local cameraHeight = cameraSettings and cameraSettings.CameraHeight or BOSS_CAMERA_HEIGHT
    local cameraDistance = cameraSettings and cameraSettings.CameraDistance or BOSS_CAMERA_DISTANCE
    local downAngleDegrees = cameraSettings and cameraSettings.DownAngleDegrees
    if downAngleDegrees then
        cameraHeight = lookHeight + math.tan(math.rad(downAngleDegrees)) * cameraDistance
    end

    local lookAtPosition = bossPosition + Vector3.new(0, lookHeight, 0)
    local cameraPosition = bossPosition + frontDirection * cameraDistance + Vector3.new(0, cameraHeight, 0)
    return CFrame.lookAt(cameraPosition, lookAtPosition)
end

local function addCameraShake(duration, magnitude, rotationMagnitude)
    duration = math.max(0.05, tonumber(duration) or 0.25)
    magnitude = math.max(0, tonumber(magnitude) or 0)
    rotationMagnitude = math.max(0, tonumber(rotationMagnitude) or 0)
    if magnitude <= 0 and rotationMagnitude <= 0 then
        return
    end

    table.insert(shakeEvents, {
        StartTime = os.clock(),
        Duration = duration,
        Magnitude = magnitude,
        RotationMagnitude = rotationMagnitude,
    })

    if ensureScreenShakeLoop then
        ensureScreenShakeLoop()
    end
end

local function getCameraShakeCFrame()
    local now = os.clock()
    local offset = Vector3.zero
    local rotation = Vector3.zero

    for index = #shakeEvents, 1, -1 do
        local event = shakeEvents[index]
        local progress = (now - event.StartTime) / event.Duration
        if progress >= 1 then
            table.remove(shakeEvents, index)
        else
            local strength = (1 - progress) * (1 - progress)
            local magnitude = event.Magnitude * strength
            local rotationMagnitude = event.RotationMagnitude * strength
            offset += Vector3.new(
                rng:NextNumber(-magnitude, magnitude),
                rng:NextNumber(-magnitude, magnitude),
                rng:NextNumber(-magnitude * 0.35, magnitude * 0.35)
            )
            rotation += Vector3.new(
                rng:NextNumber(-rotationMagnitude, rotationMagnitude),
                rng:NextNumber(-rotationMagnitude, rotationMagnitude),
                rng:NextNumber(-rotationMagnitude, rotationMagnitude)
            )
        end
    end

    return CFrame.new(offset) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
end

local function addCameraRecoil(duration, distance)
    duration = math.max(0.05, tonumber(duration) or 0.3)
    distance = math.max(0, tonumber(distance) or 0)
    if distance <= 0 then
        return
    end

    table.insert(recoilEvents, {
        StartTime = os.clock(),
        Duration = duration,
        Distance = distance,
    })

    if ensureScreenShakeLoop then
        ensureScreenShakeLoop()
    end
end

local function getCameraRecoilCFrame()
    local now = os.clock()
    local offsetZ = 0

    for index = #recoilEvents, 1, -1 do
        local event = recoilEvents[index]
        local progress = (now - event.StartTime) / event.Duration
        if progress >= 1 then
            table.remove(recoilEvents, index)
        else
            offsetZ += event.Distance * (1 - progress) * (1 - progress)
        end
    end

    return CFrame.new(0, 0, offsetZ)
end

ensureScreenShakeLoop = function()
    if screenShakeConnection then
        return
    end

    screenShakeConnection = RunService.RenderStepped:Connect(function()
        if renderConnection then
            return
        end

        if #shakeEvents == 0 and #recoilEvents == 0 then
            safeDisconnect(screenShakeConnection)
            screenShakeConnection = nil
            return
        end

        local camera = Workspace.CurrentCamera
        if camera then
            camera.CFrame = camera.CFrame * getCameraRecoilCFrame() * getCameraShakeCFrame()
        end
    end)
end

local function playImpactFlash(color, startTransparency, fadeSeconds)
    local gui = getOverlayGui()
    local flash = gui and gui:FindFirstChild("ImpactFlash")
    if not (flash and flash:IsA("Frame")) then
        return
    end

    flash.Visible = true
    flash.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
    flash.BackgroundTransparency = math.clamp(tonumber(startTransparency) or 0.35, 0, 1)
    local tween = TweenService:Create(
        flash,
        TweenInfo.new(math.max(0.05, tonumber(fadeSeconds) or 0.25), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 1 }
    )
    tween:Play()
    tween.Completed:Connect(function()
        if flash.BackgroundTransparency >= 0.99 then
            flash.Visible = false
        end
    end)
end

local function hideBossTitle()
    local gui = getOverlayGui()
    local titleLabel = gui and gui:FindFirstChild("BossTitle")
    if titleLabel and titleLabel:IsA("TextLabel") then
        titleLabel.Visible = false
        titleLabel.TextTransparency = 1
        titleLabel.TextStrokeTransparency = 1
        titleLabel.Position = UDim2.fromScale(-0.35, 0.32)
        titleLabel.Rotation = -6

        local titleScale = titleLabel:FindFirstChildOfClass("UIScale")
        if titleScale then
            titleScale.Scale = 1
        end
    end
end

local function playBossTitle(runId, titleText, holdSeconds)
    local gui = getOverlayGui()
    local titleLabel = gui and gui:FindFirstChild("BossTitle")
    if not (titleLabel and titleLabel:IsA("TextLabel")) then
        return
    end

    local titleScale = titleLabel:FindFirstChildOfClass("UIScale")
    if not titleScale then
        titleScale = Instance.new("UIScale")
        titleScale.Name = "BossTitleScale"
        titleScale.Parent = titleLabel
    end

    titleLabel.Visible = true
    titleLabel.Text = titleText
    titleLabel.Position = UDim2.fromScale(-0.35, 0.32)
    titleLabel.Rotation = -6
    titleLabel.TextTransparency = 1
    titleLabel.TextStrokeTransparency = 1
    titleScale.Scale = 0.88

    TweenService:Create(
        titleLabel,
        TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Position = UDim2.fromScale(0.5, 0.32),
            Rotation = 0,
            TextTransparency = 0,
            TextStrokeTransparency = 0,
        }
    ):Play()
    TweenService:Create(
        titleScale,
        TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1.08 }
    ):Play()

    playImpactFlash(Color3.fromRGB(255, 70, 55), 0.62, 0.25)
    addCameraShake(0.45, 0.45, 0.014)

    task.wait(math.max(0, holdSeconds))
    if runId ~= activeRunId then
        return
    end

    TweenService:Create(
        titleLabel,
        TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }
    ):Play()
    TweenService:Create(
        titleScale,
        TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Scale = 1.18 }
    ):Play()

    task.wait(0.25)
    if runId == activeRunId then
        hideBossTitle()
    end
end

local function restoreCamera(runId)
    if runId and runId ~= activeRunId then
        return
    end

    safeDisconnect(renderConnection)
    renderConnection = nil

    local camera = Workspace.CurrentCamera
    if camera and restoreCameraState then
        camera.CameraType = restoreCameraState.CameraType
        camera.CameraSubject = restoreCameraState.CameraSubject
        camera.CFrame = restoreCameraState.CFrame
        camera.FieldOfView = restoreCameraState.FieldOfView
    end

    restoreCameraState = nil
    table.clear(shakeEvents)
    table.clear(recoilEvents)
end

local function hideOverlay(runId)
    if runId ~= activeRunId then
        return
    end

    local gui = getOverlayGui()
    local mask = gui and gui:FindFirstChild("BlackMask")
    if mask then
        mask.Visible = false
        mask.BackgroundTransparency = 1
        local textLabel = mask:FindFirstChild("IntroText")
        if textLabel and textLabel:IsA("TextLabel") then
            textLabel.TextTransparency = 1
            textLabel.TextStrokeTransparency = 1
        end
    end
end

local function finishIntro(runId)
    if runId ~= activeRunId then
        return
    end

    hideBossTitle()
    hideOverlay(runId)
    ZombossUICleanup.ForceCloseBossBlockingUI()
    restoreCamera(runId)
    restorePlayerGui(runId)
    ZombossUICleanup.SetBossUILock("Intro", false)
end

local function playBlackout(runId, payload)
    local gui = getOverlayGui()
    local mask = gui and gui:FindFirstChild("BlackMask")
    if not (mask and mask:IsA("Frame")) then
        return
    end

    local textLabel = mask:FindFirstChild("IntroText")
    if not (textLabel and textLabel:IsA("TextLabel")) then
        return
    end
    local textScale = textLabel:FindFirstChildOfClass("UIScale")
    if not textScale then
        textScale = Instance.new("UIScale")
        textScale.Name = "IntroTextScale"
        textScale.Parent = textLabel
    end

    local fadeInSeconds = math.max(0, tonumber(payload.FadeInSeconds) or 0.35)
    local holdSeconds = math.max(0, tonumber(payload.HoldSeconds) or 1.5)
    local fadeOutSeconds = math.max(0, tonumber(payload.FadeOutSeconds) or 0.45)

    local snapBlackout = payload.SnapBlackout == true or fadeInSeconds <= 0

    mask.Visible = true
    mask.BackgroundTransparency = snapBlackout and 0 or 1
    textLabel.Text = tostring(payload.BlackoutText or "Here it comes.")
    textLabel.TextTransparency = snapBlackout and 0 or 1
    textLabel.TextStrokeTransparency = snapBlackout and 0.2 or 1
    textLabel.Position = UDim2.fromScale(0.5, 0.5)
    textScale.Scale = 1
    addCameraShake(holdSeconds, 0.12, 0.004)

    if not snapBlackout then
        TweenService:Create(mask, TweenInfo.new(fadeInSeconds), { BackgroundTransparency = 0 }):Play()
        TweenService:Create(textLabel, TweenInfo.new(fadeInSeconds), {
            TextTransparency = 0,
            TextStrokeTransparency = 0.2,
        }):Play()
    end

    TweenService:Create(textScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 }):Play()
    task.spawn(function()
        local trembleEnd = os.clock() + fadeInSeconds + holdSeconds
        while runId == activeRunId and os.clock() < trembleEnd do
            textLabel.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(rng:NextInteger(-3, 3), rng:NextInteger(-2, 2))
            task.wait(0.045)
        end
        if runId == activeRunId then
            textLabel.Position = UDim2.fromScale(0.5, 0.5)
        end
    end)

    task.wait(fadeInSeconds + holdSeconds)
    if runId ~= activeRunId then
        return
    end

    TweenService:Create(mask, TweenInfo.new(fadeOutSeconds), { BackgroundTransparency = 1 }):Play()
    TweenService:Create(textLabel, TweenInfo.new(fadeOutSeconds), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }):Play()
    TweenService:Create(textScale, TweenInfo.new(fadeOutSeconds), { Scale = 1.18 }):Play()

    task.wait(fadeOutSeconds)
    textScale.Scale = 1
    hideOverlay(runId)
end

local function startIntro(payload)
    if type(payload) ~= "table" then
        return
    end

    activeRunId += 1
    local runId = activeRunId

    ZombossUICleanup.SetBossUILock("Intro", true)
    restoreCamera()
    restorePlayerGui()
    ZombossUICleanup.ForceCloseBossBlockingUI()
    hideBossTitle()

    local camera = getCamera()
    if not camera then
        ZombossUICleanup.SetBossUILock("Intro", false)
        return
    end

    restoreCameraState = {
        CameraType = camera.CameraType,
        CameraSubject = camera.CameraSubject,
        CFrame = camera.CFrame,
        FieldOfView = camera.FieldOfView,
    }

    local cameraFocusSeconds = math.max(0, tonumber(payload.CameraFocusSeconds) or 1)
    local closeupSeconds = math.max(0, tonumber(payload.CloseupSeconds) or 2)
    local closeupTitleText = tostring(payload.CloseupTitleText or BOSS_CLOSEUP_TITLE_TEXT)
    local cameraSettings = {
        LookHeight = BOSS_CAMERA_LOOK_HEIGHT,
        CameraHeight = BOSS_CAMERA_HEIGHT,
        CameraDistance = BOSS_CAMERA_DISTANCE,
        DownAngleDegrees = BOSS_CAMERA_DOWN_ANGLE_DEGREES,
    }

    local function startCameraFocus(startClock)
        if runId ~= activeRunId then
            return
        end

        local focusCamera = getCamera()
        if not focusCamera then
            return
        end

        focusCamera.CameraType = Enum.CameraType.Scriptable
        focusCamera.FieldOfView = 50
        TweenService:Create(
            focusCamera,
            TweenInfo.new(math.max(0.1, cameraFocusSeconds), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            { FieldOfView = 62 }
        ):Play()
        addCameraShake(0.45, 0.28, 0.008)

        renderConnection = RunService.RenderStepped:Connect(function()
            if runId ~= activeRunId then
                return
            end

            local currentCamera = Workspace.CurrentCamera
            if not currentCamera then
                return
            end

            local bossCFrame = getBossCFrame(payload.Boss)
            local bossPosition = bossCFrame and bossCFrame.Position or getFallbackBossPosition(payload, startClock)
            currentCamera.CameraType = Enum.CameraType.Scriptable
            currentCamera.CFrame = getCameraCFrame(bossCFrame, bossPosition, payload, cameraSettings)
                * getCameraRecoilCFrame()
                * getCameraShakeCFrame()
        end)
    end

    task.spawn(function()
        local startClock = os.clock()
        playBlackout(runId, payload)

        if runId ~= activeRunId then
            return
        end

        ZombossUICleanup.ForceCloseBossBlockingUI()
        hidePlayerGui(runId)
        startCameraFocus(startClock)
        task.wait(cameraFocusSeconds)

        if runId ~= activeRunId then
            return
        end

        cameraSettings = {
            LookHeight = BOSS_CLOSEUP_LOOK_HEIGHT,
            CameraHeight = BOSS_CLOSEUP_CAMERA_HEIGHT,
            CameraDistance = BOSS_CLOSEUP_CAMERA_DISTANCE,
            DownAngleDegrees = BOSS_CLOSEUP_DOWN_ANGLE_DEGREES,
        }

        local closeupCamera = Workspace.CurrentCamera
        if closeupCamera then
            TweenService:Create(
                closeupCamera,
                TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { FieldOfView = 42 }
            ):Play()
        end
        addCameraRecoil(0.3, 0.9)
        playBossTitle(runId, closeupTitleText, closeupSeconds)

        if runId == activeRunId then
            cameraSettings = {
                LookHeight = BOSS_CAMERA_LOOK_HEIGHT,
                CameraHeight = BOSS_CAMERA_HEIGHT,
                CameraDistance = BOSS_CAMERA_DISTANCE,
                DownAngleDegrees = BOSS_CAMERA_DOWN_ANGLE_DEGREES,
            }

            local walkCamera = Workspace.CurrentCamera
            if walkCamera then
                TweenService:Create(
                    walkCamera,
                    TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                    { FieldOfView = 62 }
                ):Play()
            end
        end
    end)

    local totalDuration = (tonumber(payload.MoveStartDelaySeconds) or cameraFocusSeconds)
        + (tonumber(payload.MoveDurationSeconds) or 0)
        + 3
    task.delay(totalDuration, function()
        finishIntro(runId)
    end)
end

function ZombossIntroController.Init()
    task.spawn(function()
        local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)
        if not remote or not remote:IsA("RemoteEvent") then
            warn("[ZombossIntroController] " .. REMOTE_NAME .. " was not found.")
            return
        end

        remote.OnClientEvent:Connect(function(action, payload)
            if action == "Start" then
                startIntro(payload)
            elseif action == "BossWalkStart" then
                if renderConnection then
                    addCameraShake(0.55, 0.9, 0.025)
                    addCameraRecoil(0.35, 1.4)
                    playImpactFlash(Color3.fromRGB(255, 245, 220), 0.45, 0.28)
                end
            elseif action == "Footstep" then
                if renderConnection then
                    local magnitude = type(payload) == "table" and tonumber(payload.Magnitude) or 1
                    addCameraShake(0.42, (magnitude or 1) * 0.48, (magnitude or 1) * 0.014)
                    if payload and payload.StepIndex == 1 then
                        playImpactFlash(Color3.fromRGB(255, 80, 70), 0.58, 0.3)
                    end
                end
            elseif action == "BossArrived" then
                if renderConnection then
                    addCameraShake(0.85, 1.45, 0.035)
                    addCameraRecoil(0.65, 4.5)
                    playImpactFlash(Color3.fromRGB(255, 255, 255), 0.38, 0.4)
                end
                if type(payload) == "table" and payload.ShowBlackout == true then
                    task.spawn(function()
                        playBlackout(activeRunId, payload)
                    end)
                end
            elseif action == "AnimationShake" then
                local magnitude = type(payload) == "table" and tonumber(payload.Magnitude) or 1
                magnitude = magnitude or 1
                addCameraShake(0.34, magnitude * 0.55, magnitude * 0.018)
                addCameraRecoil(0.2, magnitude * 0.65)
            elseif action == "End" then
                finishIntro(activeRunId)
            end
        end)
    end)
end

return ZombossIntroController

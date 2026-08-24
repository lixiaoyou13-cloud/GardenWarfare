-- src/client/Services/ZombossBossFightController.luau
local ZombossBossFightController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NumberFormatUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormatUtil"))
local ZombossUICleanup = require(script.Parent.Parent.Utils.ZombossUICleanup)

local localPlayer = Players.LocalPlayer
local REMOTE_NAME = "ZombossBossFightRE"
local STATE_REMOTE_NAME = "GetZombossBossFightStateRF"
local BOSS_STATE_POLL_INTERVAL_SECONDS = 2

local hpGui = nil
local hpFill = nil
local hpText = nil
local baseFillSize = nil
local dpsGui = nil
local dpsTemplate = nil
local dpsRowsByUserId = {}
local avatarCacheByUserId = {}
local avatarLoadingByUserId = {}
local isActive = false
local shakeEvents = {}
local shakeConnection = nil
local rng = Random.new()
local warnedMissingHP = false
local warnedMissingHPFill = false
local warnedMissingHPText = false
local warnedMissingDPS = false
local warnedMissingDPSTemplate = false
local warnedStatePollFailure = false
local loggedFirstHPUpdate = false
local lastHPUpdateLogAt = 0
local hiddenControlStates = nil
local fightUiRevision = 0
local START_STATE_REAPPLY_DELAYS = { 0, 0.5, 1.5, 3 }
local BOSS_PLAY_PROPERTY_VISIBLE_NAMES = {
    HP = true,
    DPS = true,
}

local function isTextObject(instance)
    return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 10)
end

local function getBasicGui()
    local playerGui = getPlayerGui()
    return playerGui and playerGui:FindFirstChild("BasicGui")
end

local function getLevelSelectGui()
    local basicGui = getBasicGui()
    return basicGui and basicGui:FindFirstChild("LevelSelect")
end

local function getPlayProperty()
    local basicGui = getBasicGui()
    return basicGui and basicGui:FindFirstChild("PlayProperty")
end

local function resolveHPObjects()
    local playProperty = getPlayProperty()
    if not playProperty then
        return false
    end

    hpGui = playProperty:FindFirstChild("HP")
    if not hpGui then
        return false
    end

    hpFill = hpGui:FindFirstChild("ImageLabel")
    if not (hpFill and (hpFill:IsA("ImageLabel") or hpFill:IsA("ImageButton") or hpFill:IsA("Frame"))) then
        hpFill = nil
    end

    hpText = hpGui:FindFirstChild("TextLabel")
    if not isTextObject(hpText) then
        hpText = hpGui:FindFirstChildWhichIsA("TextLabel", true)
    end

    if hpFill and not baseFillSize then
        baseFillSize = hpFill.Size
    end

    return true
end

local function resolveDPSObjects()
    local playProperty = getPlayProperty()
    if not playProperty then
        return false
    end

    dpsGui = playProperty:FindFirstChild("DPS")
    if not dpsGui then
        return false
    end

    dpsTemplate = dpsGui:FindFirstChild("Frame")
    if not (dpsTemplate and dpsTemplate:IsA("GuiObject")) then
        dpsTemplate = nil
        return false
    end

    return true
end

local function setGuiVisible(instance, visible)
    if instance and instance:IsA("GuiObject") then
        instance.Visible = visible
    elseif instance and instance:IsA("ScreenGui") then
        instance.Enabled = visible
    end
end

local function ensurePlayPropertyVisible()
    local playProperty = getPlayProperty()
    if not playProperty then
        return
    end

    setGuiVisible(playProperty, true)
    if playProperty:IsA("ScreenGui") then
        playProperty.DisplayOrder = math.max(playProperty.DisplayOrder, 50)
    end
end

local function findTextObjectIn(instance)
    if isTextObject(instance) then
        return instance
    end

    return instance and instance:FindFirstChildWhichIsA("TextLabel", true)
end

local function ensureDPSLayout()
    if not dpsGui then
        return
    end

    local existingLayout = dpsGui:FindFirstChildWhichIsA("UIListLayout") or dpsGui:FindFirstChildWhichIsA("UIGridLayout")
    if existingLayout then
        existingLayout.SortOrder = Enum.SortOrder.LayoutOrder
        return
    end

    local layout = Instance.new("UIListLayout")
    layout.Name = "ZombossDPSListLayout"
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = dpsGui
end

local function clearDPSRows()
    for userId, row in pairs(dpsRowsByUserId) do
        if row and row.Parent then
            row:Destroy()
        end
        dpsRowsByUserId[userId] = nil
    end
end

local function setDPSVisible(visible)
    if resolveDPSObjects() then
        setGuiVisible(dpsGui, visible)
        if dpsTemplate then
            dpsTemplate.Visible = false
        end
    elseif visible and dpsGui and not warnedMissingDPSTemplate then
        warnedMissingDPSTemplate = true
        warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.DPS.Frame")
    elseif visible and not warnedMissingDPS then
        warnedMissingDPS = true
        warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.DPS")
    end
end

local function applyAvatar(imageLabel, userId)
    if not imageLabel or not imageLabel:IsA("ImageLabel") then
        return
    end

    local cached = avatarCacheByUserId[userId]
    if cached then
        imageLabel.Image = cached
        return
    end

    imageLabel.Image = ""
    if avatarLoadingByUserId[userId] then
        return
    end

    avatarLoadingByUserId[userId] = true
    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        end)
        avatarLoadingByUserId[userId] = nil

        if ok and type(image) == "string" then
            avatarCacheByUserId[userId] = image
            local row = dpsRowsByUserId[userId]
            local currentImageLabel = row and row:FindFirstChild("ImageLabel", true)
            if currentImageLabel and currentImageLabel:IsA("ImageLabel") then
                currentImageLabel.Image = image
            end
        end
    end)
end

local function updateDPS(damageStats)
    if type(damageStats) ~= "table" then
        damageStats = {}
    end

    if not resolveDPSObjects() then
        if dpsGui and not warnedMissingDPSTemplate then
            warnedMissingDPSTemplate = true
            warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.DPS.Frame")
        elseif not dpsGui and not warnedMissingDPS then
            warnedMissingDPS = true
            warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.DPS")
        end
        return
    end

    setGuiVisible(dpsGui, true)
    if dpsTemplate then
        dpsTemplate.Visible = false
    elseif not warnedMissingDPSTemplate then
        warnedMissingDPSTemplate = true
        warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.DPS.Frame")
        return
    end

    ensureDPSLayout()

    table.sort(damageStats, function(a, b)
        local damageA = tonumber(a and a.Damage) or 0
        local damageB = tonumber(b and b.Damage) or 0
        if damageA == damageB then
            return (tonumber(a and a.UserId) or 0) < (tonumber(b and b.UserId) or 0)
        end

        return damageA > damageB
    end)

    local seenUserIds = {}
    for index, entry in ipairs(damageStats) do
        local userId = tonumber(entry and entry.UserId)
        local damage = math.max(0, math.floor((tonumber(entry and entry.Damage) or 0) + 0.5))
        if userId and userId > 0 and damage > 0 then
            seenUserIds[userId] = true
            local row = dpsRowsByUserId[userId]
            if not (row and row.Parent) then
                row = dpsTemplate:Clone()
                row.Name = "Player_" .. tostring(userId)
                row:SetAttribute("ZombossDPSRow", true)
                row.Parent = dpsGui
                dpsRowsByUserId[userId] = row
            end

            row.LayoutOrder = index
            row.Visible = true

            local imageLabel = row:FindFirstChild("ImageLabel", true)
            applyAvatar(imageLabel, userId)

            local numberRoot = row:FindFirstChild("Number", true)
            local numberText = findTextObjectIn(numberRoot)
            if numberText then
                numberText.Text = NumberFormatUtil.FormatNumber(damage)
            end
        end
    end

    for userId, row in pairs(dpsRowsByUserId) do
        if not seenUserIds[userId] then
            if row and row.Parent then
                row:Destroy()
            end
            dpsRowsByUserId[userId] = nil
        end
    end
end

local function rememberGuiState(instance)
    if not instance then
        return
    end

    hiddenControlStates = hiddenControlStates or {}
    if hiddenControlStates[instance] ~= nil then
        return
    end

    if instance:IsA("GuiObject") then
        hiddenControlStates[instance] = instance.Visible
    elseif instance:IsA("ScreenGui") then
        hiddenControlStates[instance] = instance.Enabled
    end
end

local function restoreGuiStates()
    if not hiddenControlStates then
        return
    end

    for instance, wasVisible in pairs(hiddenControlStates) do
        if typeof(instance) == "Instance" and instance.Parent then
            setGuiVisible(instance, wasVisible)
        end
    end

    hiddenControlStates = nil
end

local function setBattleControlsHidden(hidden)
    if not hidden then
        restoreGuiStates()
        return
    end

    local playProperty = getPlayProperty()
    if playProperty then
        for _, child in ipairs(playProperty:GetChildren()) do
            if child:IsA("GuiObject") and not BOSS_PLAY_PROPERTY_VISIBLE_NAMES[child.Name] then
                rememberGuiState(child)
                setGuiVisible(child, false)
            end
        end
    end

    local basicGui = getBasicGui()
    if basicGui then
        for _, child in ipairs(basicGui:GetChildren()) do
            if child:IsA("ScreenGui") and child ~= playProperty then
                rememberGuiState(child)
                child.Enabled = false
            end
        end
    end
end

local function formatHP(value)
    return tostring(math.max(0, math.floor(tonumber(value) or 0)))
end

local function getShakeCFrame()
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

local function ensureShakeLoop()
    if shakeConnection then
        return
    end

    shakeConnection = RunService.RenderStepped:Connect(function()
        if #shakeEvents == 0 then
            shakeConnection:Disconnect()
            shakeConnection = nil
            return
        end

        local camera = Workspace.CurrentCamera
        if camera then
            camera.CFrame = camera.CFrame * getShakeCFrame()
        end
    end)
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
    ensureShakeLoop()
end

local function updateHP(currentHP, maxHP)
    if not resolveHPObjects() then
        if not warnedMissingHP then
            warnedMissingHP = true
            warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.HP")
        end
        return
    end

    currentHP = math.max(0, math.floor(tonumber(currentHP) or 0))
    maxHP = math.max(1, math.floor(tonumber(maxHP) or 1))
    local ratio = math.clamp(currentHP / maxHP, 0, 1)

    setGuiVisible(hpGui, true)

    if hpFill then
        local baseSize = baseFillSize or hpFill.Size
        hpFill.Size = UDim2.new(
            baseSize.X.Scale * ratio,
            math.floor(baseSize.X.Offset * ratio + 0.5),
            baseSize.Y.Scale,
            baseSize.Y.Offset
        )
        hpFill.Visible = true
    elseif not warnedMissingHPFill then
        warnedMissingHPFill = true
        warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.HP.ImageLabel")
    end

    if hpText and isTextObject(hpText) then
        hpText.Text = formatHP(currentHP) .. "/" .. formatHP(maxHP)
    elseif not warnedMissingHPText then
        warnedMissingHPText = true
        warn("[ZombossBossFightController] Missing BasicGui.PlayProperty.HP.TextLabel")
    end
end

local function applyFightUIState(payload)
    payload = type(payload) == "table" and payload or {}
    ZombossUICleanup.SetBossUILock("Fight", true)
    ZombossUICleanup.ForceCloseBossBlockingUI()
    ensurePlayPropertyVisible()
    setBattleControlsHidden(true)
    ensurePlayPropertyVisible()
    updateHP(payload.CurrentHP, payload.MaxHP)
    updateDPS(payload.DamageStats)
end

local function startFight(payload)
    ZombossUICleanup.SetBossUILock("Fight", true)
    ZombossUICleanup.ForceCloseBossBlockingUI()
    isActive = true
    payload = type(payload) == "table" and payload or {}
    fightUiRevision += 1
    local revision = fightUiRevision

    print(string.format(
        "[ZombossBossFightController] Start received. HP=%s/%s",
        tostring(payload.CurrentHP),
        tostring(payload.MaxHP)
    ))

    for _, delaySeconds in ipairs(START_STATE_REAPPLY_DELAYS) do
        task.delay(delaySeconds, function()
            if isActive and fightUiRevision == revision then
                applyFightUIState(payload)
            end
        end)
    end
end

local function endFight(payload)
    isActive = false
    fightUiRevision += 1
    payload = type(payload) == "table" and payload or {}
    print("[ZombossBossFightController] End received.")
    updateHP(payload.CurrentHP or 0, payload.MaxHP or 1)

    if hpGui then
        setGuiVisible(hpGui, false)
    end

    clearDPSRows()
    setDPSVisible(false)
    setBattleControlsHidden(false)
    ZombossUICleanup.SetBossUILock("Fight", false)
end

local function syncFightState(payload)
    if type(payload) ~= "table" then
        return
    end

    if payload.IsActive then
        if isActive then
            applyFightUIState(payload)
        else
            startFight(payload)
        end
    elseif isActive then
        endFight(payload)
    end
end

local function startStatePolling()
    task.spawn(function()
        local stateRemote = ReplicatedStorage:WaitForChild(STATE_REMOTE_NAME, 15)
        if not stateRemote then
            warn("[ZombossBossFightController] " .. STATE_REMOTE_NAME .. " was not found after 15 seconds; waiting without timeout.")
            stateRemote = ReplicatedStorage:WaitForChild(STATE_REMOTE_NAME)
        end
        if not stateRemote or not stateRemote:IsA("RemoteFunction") then
            warn("[ZombossBossFightController] " .. STATE_REMOTE_NAME .. " was not found.")
            return
        end

        while true do
            local ok, payload = pcall(function()
                return stateRemote:InvokeServer()
            end)
            if ok then
                syncFightState(payload)
            elseif not warnedStatePollFailure then
                warnedStatePollFailure = true
                warn("[ZombossBossFightController] Failed to poll boss fight state: " .. tostring(payload))
            end

            task.wait(BOSS_STATE_POLL_INTERVAL_SECONDS)
        end
    end)
end

function ZombossBossFightController.Init()
    task.spawn(function()
        resolveHPObjects()
        if hpGui then
            setGuiVisible(hpGui, false)
        end
        setDPSVisible(false)

        startStatePolling()

        local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 15)
        if not remote then
            warn("[ZombossBossFightController] " .. REMOTE_NAME .. " was not found after 15 seconds; waiting without timeout.")
            remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)
        end
        if not remote or not remote:IsA("RemoteEvent") then
            warn("[ZombossBossFightController] " .. REMOTE_NAME .. " was not found.")
            return
        end

        remote.OnClientEvent:Connect(function(action, payload)
            if action == "Start" then
                startFight(payload)
            elseif action == "UpdateHP" then
                if isActive then
                    payload = type(payload) == "table" and payload or {}
                    local now = os.clock()
                    if not loggedFirstHPUpdate or now - lastHPUpdateLogAt >= 5 then
                        loggedFirstHPUpdate = true
                        lastHPUpdateLogAt = now
                        print(string.format(
                            "[ZombossBossFightController] UpdateHP received. HP=%s/%s",
                            tostring(payload.CurrentHP),
                            tostring(payload.MaxHP)
                        ))
                    end
                    applyFightUIState(payload)
                end
            elseif action == "End" then
                endFight(payload)
            elseif action == "AnimationShake" then
                local magnitude = type(payload) == "table" and tonumber(payload.Magnitude) or 1
                magnitude = magnitude or 1
                addCameraShake(0.34, magnitude * 0.55, magnitude * 0.018)
            end
        end)
    end)
end

return ZombossBossFightController

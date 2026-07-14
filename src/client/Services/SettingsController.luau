local SettingsController = {}

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PlantAttackVisualController = require(script.Parent.PlantAttackVisualController)

local localPlayer = Players.LocalPlayer

local ON_COLOR = Color3.fromRGB(55, 170, 90)
local OFF_COLOR = Color3.fromRGB(190, 65, 65)
local ON_BUTTON_X_SCALE = 0.6
local OFF_BUTTON_X_SCALE = 0.1
local SETTINGS_INPUT_BLOCKER_NAME = "SettingsInputBlocker"
local SETTINGS_BLOCK_JUMP_ACTION = "GardenWarfareSettingsBlockJump"
local SETTINGS_DISPLAY_ORDER = 200
local DISTURB_REMOTE_NAME = "SetRejectInteractionRE"
local DIRECT_BOX_REMOTE_NAME = "SetZombieBoxDirectRewardRE"
local DEFAULT_MUSIC_VOLUME = 1
local BASE_SUNFLOWER_NAME = "BaseSunflower"
local BASE_SUNFLOWER_DEFAULT_SCALE = 1
local BASE_SUNFLOWER_MAX_SCALE = 50
local BASE_SUNFLOWER_SCALE_EPSILON = 0.01

local settings = {
    Music = true,
    MusicVolume = DEFAULT_MUSIC_VOLUME,
    EffectsSelf = true,
    EffectsOthers = true,
    PlantSelf = true,
    PlantOthers = true,
    Sunflower = true,
    Disturb = false,
    Box = false,
}

local started = false
local pausedTracks = setmetatable({}, { __mode = "k" })
local watchedAnimators = setmetatable({}, { __mode = "k" })
local watchedPlantModels = setmetatable({}, { __mode = "k" })
local watchedPlots = setmetatable({}, { __mode = "k" })
local watchedPlantFolders = setmetatable({}, { __mode = "k" })
local watchedLawnFolders = setmetatable({}, { __mode = "k" })
local watchedBaseSunflowers = setmetatable({}, { __mode = "k" })
local toggleButtonOnPositions = setmetatable({}, { __mode = "k" })
local toggleUis = {}
local musicSliderUi = nil
local isDraggingMusicSlider = false
local isSettingsInputBlocked = false

local TOGGLE_FRAME_NAMES = {
    Music = { "MusicFrame", "Music" },
    EffectsSelf = { "EffectsSelfFrame", "EffectsSelf" },
    EffectsOthers = { "EffectsOthersFrame", "EffectsOthers" },
    PlantSelf = { "PlantSelf", "PlantSelfFrame" },
    PlantOthers = { "PlantOthersFrame", "PlantOthers" },
    Sunflower = { "Sunflower", "SunflowerFrame" },
    Disturb = { "Disturb", "DisturbFrame" },
    Box = { "box", "Box", "BoxFrame" },
}

local EFFECT_CONTAINER_NAMES = {
    Glow = true,
    Lightning = true,
    HolyLight = true,
    VFX = true,
    vfx = true,
    Vfx = true,
}

local function isButton(instance)
    return instance and (instance:IsA("TextButton") or instance:IsA("ImageButton"))
end

local function blockJumpAction()
    return Enum.ContextActionResult.Sink
end

local function setSettingsInputBlocked(isBlocked)
    if isSettingsInputBlocked == isBlocked then
        return
    end

    isSettingsInputBlocked = isBlocked
    if isBlocked then
        ContextActionService:BindActionAtPriority(
            SETTINGS_BLOCK_JUMP_ACTION,
            blockJumpAction,
            false,
            3000,
            Enum.PlayerActions.CharacterJump
        )
    else
        ContextActionService:UnbindAction(SETTINGS_BLOCK_JUMP_ACTION)
    end
end

local function ensureSettingsInputBlocker(settingsGui, frame)
    if not settingsGui then
        return
    end

    if settingsGui:IsA("ScreenGui") then
        settingsGui.DisplayOrder = math.max(settingsGui.DisplayOrder, SETTINGS_DISPLAY_ORDER)
    end

    local blocker = settingsGui:FindFirstChild(SETTINGS_INPUT_BLOCKER_NAME)
    if not blocker then
        blocker = Instance.new("TextButton")
        blocker.Name = SETTINGS_INPUT_BLOCKER_NAME
        blocker.Size = UDim2.new(1, 0, 1, 0)
        blocker.Position = UDim2.new(0, 0, 0, 0)
        blocker.AnchorPoint = Vector2.new(0, 0)
        blocker.BackgroundTransparency = 1
        blocker.Text = ""
        blocker.AutoButtonColor = false
        blocker.BorderSizePixel = 0
        blocker.ZIndex = 0
        blocker.Parent = settingsGui
    end

    if blocker:IsA("GuiButton") then
        blocker.Active = true
        blocker.AutoButtonColor = false
        blocker.Modal = true
    end

    if frame and frame:IsA("GuiObject") then
        frame.ZIndex = math.max(frame.ZIndex, 1)
    end
end

local function findNamedControl(root, name)
    if not root then return nil end

    local direct = root:FindFirstChild(name, true)
    if isButton(direct) then
        return direct
    end

    if direct then
        local childButton = direct:FindFirstChildWhichIsA("GuiButton", true)
        if childButton then
            return childButton
        end
    end

    return nil
end

local function setButtonLabel(button, title, enabled)
    if not button then return end

    local text = title .. ": " .. (enabled and "ON" or "OFF")
    if button:IsA("TextButton") then
        button.Text = text
    end

    local label = button:FindFirstChildWhichIsA("TextLabel", true)
    if label then
        label.Text = text
    end

    button.BackgroundColor3 = enabled and ON_COLOR or OFF_COLOR
end

local function getOwnerUserId(instance)
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

local function shouldEnableEffects(ownerUserId)
    if isLocalOwner(ownerUserId) then
        return settings.EffectsSelf
    end

    return settings.EffectsOthers
end

local function shouldEnablePlantAnimation(ownerUserId)
    if isLocalOwner(ownerUserId) then
        return settings.PlantSelf
    end

    return settings.PlantOthers
end

local function isDefaultVisualSettings()
    return settings.EffectsSelf
        and settings.EffectsOthers
        and settings.PlantSelf
        and settings.PlantOthers
end

local function isPlantModel(model)
    if not model or not model:IsA("Model") or model:GetAttribute("IsZombie") then
        return false
    end

    return model:GetAttribute("IsCombatPlant")
        or model:GetAttribute("IsMature")
        or model:GetAttribute("PlantedOn") ~= nil
        or model:GetAttribute("YieldPlant") ~= nil
        or model.Name == BASE_SUNFLOWER_NAME
        or string.match(model.Name, "^BaseMerchant_") ~= nil
end

local function isBaseSunflower(model)
    return model and model:IsA("Model") and model.Name == BASE_SUNFLOWER_NAME
end

local function findPlantModelAncestor(instance)
    local current = instance
    while current and current ~= Workspace and current ~= game do
        if current:IsA("Model") and isPlantModel(current) then
            return current
        end

        current = current.Parent
    end

    return nil
end

local function hasEffectContainerAncestor(instance, model)
    local current = instance
    while current and current ~= model do
        if EFFECT_CONTAINER_NAMES[current.Name] then
            return true
        end

        current = current.Parent
    end

    return EFFECT_CONTAINER_NAMES[model.Name] == true
end

local function applyEffectEnabled(instance, enabled, model)
    if instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("Light")
        or instance:IsA("Highlight")
    then
        if enabled then
            local original = instance:GetAttribute("SettingsOriginalEnabled")
            if original ~= nil then
                instance.Enabled = original
                instance:SetAttribute("SettingsOriginalEnabled", nil)
            end
        else
            if instance:GetAttribute("SettingsOriginalEnabled") == nil then
                instance:SetAttribute("SettingsOriginalEnabled", instance.Enabled)
            end
            instance.Enabled = false
        end

        return
    end

    if instance:IsA("BasePart") and hasEffectContainerAncestor(instance, model) then
        if enabled then
            local original = instance:GetAttribute("SettingsOriginalTransparency")
            if original ~= nil then
                instance.Transparency = original
                instance:SetAttribute("SettingsOriginalTransparency", nil)
            end
        else
            if instance:GetAttribute("SettingsOriginalTransparency") == nil then
                instance:SetAttribute("SettingsOriginalTransparency", instance.Transparency)
            end
            instance.Transparency = 1
        end
    end
end

local function applyPlantEffects(model, enabled)
    for _, desc in ipairs(model:GetDescendants()) do
        applyEffectEnabled(desc, enabled, model)
    end
end

local function getAnimationTrackSpeed(track)
    local success, speed = pcall(function()
        return track.Speed
    end)

    if success and typeof(speed) == "number" then
        return speed
    end

    return 1
end

local function applyAnimationTrack(track, enabled)
    if not track then
        return
    end

    if enabled then
        local originalSpeed = pausedTracks[track]
        if originalSpeed ~= nil then
            if typeof(originalSpeed) ~= "number" then
                originalSpeed = 1
            end

            pcall(function()
                track:AdjustSpeed(originalSpeed)
            end)
            pausedTracks[track] = nil
        end
        return
    end

    if pausedTracks[track] == nil then
        pausedTracks[track] = getAnimationTrackSpeed(track)
    end

    pcall(function()
        track:AdjustSpeed(0)
    end)
end

local function applyAnimatorTracks(animator, enabled)
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        applyAnimationTrack(track, enabled)
    end
end

local function watchAnimator(model, animator)
    if not animator or watchedAnimators[animator] then
        return
    end
    watchedAnimators[animator] = true

    local function applyTrackForCurrentSettings(track)
        local plantModel = findPlantModelAncestor(animator)
        if not plantModel and model and model.Parent and isPlantModel(model) then
            plantModel = model
        end
        if not plantModel then
            return
        end

        local ownerUserId = getOwnerUserId(plantModel)
        applyAnimationTrack(track, shouldEnablePlantAnimation(ownerUserId))
    end

    animator.AnimationPlayed:Connect(function(track)
        applyTrackForCurrentSettings(track)
        task.defer(applyTrackForCurrentSettings, track)
    end)
end

local function watchPlantModel(model)
    if not isPlantModel(model) then
        return
    end

    if not watchedPlantModels[model] then
        watchedPlantModels[model] = true
        model.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Animator") then
                watchAnimator(model, descendant)
                applyAnimatorTracks(descendant, shouldEnablePlantAnimation(getOwnerUserId(model)))
            end
        end)
    end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Animator") then
            watchAnimator(model, desc)
        end
    end
end

local function applyPlantAnimations(model, enabled)
    watchPlantModel(model)

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Animator") then
            watchAnimator(model, desc)
            applyAnimatorTracks(desc, enabled)
        end
    end
end

local function applyPlantSettings(model)
    if not isPlantModel(model) then
        return
    end

    watchPlantModel(model)

    local ownerUserId = getOwnerUserId(model)
    applyPlantEffects(model, shouldEnableEffects(ownerUserId))
    applyPlantAnimations(model, shouldEnablePlantAnimation(ownerUserId))
end

local function deferApplyPlantSettings(model)
    if isDefaultVisualSettings() then
        return
    end

    task.defer(function()
        if model and model.Parent then
            applyPlantSettings(model)
        end
    end)
end

local function forEachExistingPlant(callback)
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then
        return
    end

    local seen = {}
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("Model") and isPlantModel(desc) and not seen[desc] then
                seen[desc] = true
                callback(desc)
            end
        end
    end
end

local function applyExistingPlantsOnce()
    PlantAttackVisualController.SetVisualSettings(settings)
    forEachExistingPlant(applyPlantSettings)
end

local function isMusicSound(sound)
    if not sound:IsA("Sound") then
        return false
    end

    local loweredName = string.lower(sound.Name)
    return sound.Looped
        or string.find(loweredName, "music", 1, true) ~= nil
        or string.find(loweredName, "bgm", 1, true) ~= nil
        or string.find(loweredName, "theme", 1, true) ~= nil
end

local function clamp01(value)
    return math.clamp(tonumber(value) or 0, 0, 1)
end

local function getEffectiveMusicVolume()
    if settings.Music == false then
        return 0
    end

    return clamp01(settings.MusicVolume == nil and DEFAULT_MUSIC_VOLUME or settings.MusicVolume)
end

local function getOriginalSoundVolume(sound)
    local original = sound:GetAttribute("SettingsOriginalVolume")
    if typeof(original) ~= "number" then
        original = sound.Volume
        sound:SetAttribute("SettingsOriginalVolume", original)
    end

    return original
end

local function applySoundVolume(sound)
    if not isMusicSound(sound) then
        return
    end

    sound.Volume = getOriginalSoundVolume(sound) * getEffectiveMusicVolume()
end

local function applyMusicSettings()
    for _, desc in ipairs(SoundService:GetDescendants()) do
        if desc:IsA("Sound") then
            applySoundVolume(desc)
        end
    end
end

local function applyDisturbSetting()
    local remote = ReplicatedStorage:FindFirstChild(DISTURB_REMOTE_NAME)
    if not remote or not remote:IsA("RemoteEvent") then
        warn("[SettingsController] " .. DISTURB_REMOTE_NAME .. " was not found.")
        return
    end

    remote:FireServer(settings.Disturb == true)
end

local function applyBoxSetting()
    local remote = ReplicatedStorage:FindFirstChild(DIRECT_BOX_REMOTE_NAME)
        or ReplicatedStorage:WaitForChild(DIRECT_BOX_REMOTE_NAME, 5)
    if not remote or not remote:IsA("RemoteEvent") then
        warn("[SettingsController] " .. DIRECT_BOX_REMOTE_NAME .. " was not found.")
        return
    end

    remote:FireServer(settings.Box == true)
end

local function sanitizeBaseSunflowerScale(value)
    local scale = tonumber(value)
    if not scale or scale ~= scale or scale == math.huge or scale == -math.huge then
        return BASE_SUNFLOWER_DEFAULT_SCALE
    end

    return math.clamp(scale, BASE_SUNFLOWER_DEFAULT_SCALE, BASE_SUNFLOWER_MAX_SCALE)
end

local function getBaseSunflowerTargetScale(sunflower)
    if settings.Sunflower == false then
        return BASE_SUNFLOWER_DEFAULT_SCALE
    end

    return sanitizeBaseSunflowerScale(sunflower:GetAttribute("LastSunflowerScale"))
end

local function applyBaseSunflowerScale(sunflower)
    if not isBaseSunflower(sunflower) or not sunflower.Parent then
        return
    end

    local targetScale = getBaseSunflowerTargetScale(sunflower)
    if not targetScale then
        return
    end

    local okGetScale, currentScale = pcall(function()
        return sunflower:GetScale()
    end)
    if okGetScale and typeof(currentScale) == "number" and math.abs(currentScale - targetScale) <= BASE_SUNFLOWER_SCALE_EPSILON then
        return
    end

    local ok, err = pcall(function()
        sunflower:ScaleTo(targetScale)
    end)
    if not ok then
        warn("[SettingsController] Failed to apply BaseSunflower scale: " .. tostring(err))
    end
end

local function watchBaseSunflower(sunflower)
    if not isBaseSunflower(sunflower) then
        return
    end

    if not watchedBaseSunflowers[sunflower] then
        watchedBaseSunflowers[sunflower] = true
        sunflower:GetAttributeChangedSignal("LastSunflowerScale"):Connect(function()
            task.defer(applyBaseSunflowerScale, sunflower)
        end)
    end

    task.defer(applyBaseSunflowerScale, sunflower)
end

local function forEachBaseSunflower(callback)
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then
        return
    end

    local seen = {}
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        for _, desc in ipairs(plot:GetDescendants()) do
            if isBaseSunflower(desc) and not seen[desc] then
                seen[desc] = true
                callback(desc)
            end
        end
    end
end

local function applyBaseSunflowerSettings()
    forEachBaseSunflower(function(sunflower)
        watchBaseSunflower(sunflower)
        applyBaseSunflowerScale(sunflower)
    end)
end

local function watchPlantsFolder(folder)
    if not folder or watchedPlantFolders[folder] then
        return
    end
    watchedPlantFolders[folder] = true

    folder.ChildAdded:Connect(function(child)
        if child:IsA("Model") then
            deferApplyPlantSettings(child)
        end
    end)
end

local function watchLawnFolder(folder)
    if not folder or watchedLawnFolders[folder] then
        return
    end
    watchedLawnFolders[folder] = true

    folder.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Model") and isPlantModel(descendant) then
            deferApplyPlantSettings(descendant)
        end
    end)
end

local function watchPlot(plot)
    if not plot or watchedPlots[plot] then
        return
    end
    watchedPlots[plot] = true

    watchPlantsFolder(plot:FindFirstChild("Plants"))
    watchLawnFolder(plot:FindFirstChild("Lawn"))

    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("Model") and isPlantModel(desc) then
            if isBaseSunflower(desc) then
                watchBaseSunflower(desc)
            end
            deferApplyPlantSettings(desc)
        elseif desc:IsA("Animator") then
            task.defer(function()
                local plantModel = findPlantModelAncestor(desc)
                if plantModel then
                    applyPlantSettings(plantModel)
                end
            end)
        end
    end

    plot.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Model") then
            if isBaseSunflower(descendant) then
                watchBaseSunflower(descendant)
            end
            deferApplyPlantSettings(descendant)
        elseif descendant:IsA("Animator") then
            task.defer(function()
                local plantModel = findPlantModelAncestor(descendant)
                if plantModel then
                    applyPlantSettings(plantModel)
                end
            end)
        end
    end)

    plot.ChildAdded:Connect(function(child)
        if child.Name == "Plants" then
            watchPlantsFolder(child)
        elseif child.Name == "Lawn" then
            watchLawnFolder(child)
        elseif child.Name == BASE_SUNFLOWER_NAME and child:IsA("Model") then
            watchBaseSunflower(child)
            deferApplyPlantSettings(child)
        elseif string.match(child.Name, "^BaseMerchant_") ~= nil and child:IsA("Model") then
            deferApplyPlantSettings(child)
        end
    end)
end

local function watchPlotFolders()
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then
        task.spawn(function()
            plotsFolder = Workspace:WaitForChild("Plots", 15)
            if not plotsFolder then
                return
            end

            for _, plot in ipairs(plotsFolder:GetChildren()) do
                watchPlot(plot)
            end

            plotsFolder.ChildAdded:Connect(watchPlot)
        end)
        return
    end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        watchPlot(plot)
    end

    plotsFolder.ChildAdded:Connect(watchPlot)
end

local function applySettingChange(key)
    if key == "Music" then
        applyMusicSettings()
    elseif key == "Disturb" then
        applyDisturbSetting()
    elseif key == "Box" then
        applyBoxSetting()
    elseif key == "Sunflower" then
        applyBaseSunflowerSettings()
    else
        applyExistingPlantsOnce()
    end
end

local function findToggleFrame(root, key)
    local names = TOGGLE_FRAME_NAMES[key]
    if not root or not names then
        return nil
    end

    for _, name in ipairs(names) do
        local found = root:FindFirstChild(name, true)
        if found and found:IsA("GuiObject") then
            return found
        end
    end

    return nil
end

local function findGradientsByName(root, name)
    local gradients = {}
    if not root then
        return gradients
    end

    local direct = root:FindFirstChild(name)
    if direct and direct:IsA("UIGradient") then
        table.insert(gradients, direct)
    end

    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("UIGradient") and desc.Name == name then
            table.insert(gradients, desc)
        end
    end

    return gradients
end

local function findFirstGradientByName(root, name)
    local gradients = findGradientsByName(root, name)
    return gradients[1]
end

local function findToggleStateLabel(button)
    if not button then
        return nil
    end

    local named = button:FindFirstChild("On/Off", true)
    if named and (named:IsA("TextLabel") or named:IsA("TextButton") or named:IsA("TextBox")) then
        return named
    end

    return button:FindFirstChildWhichIsA("TextLabel", true)
        or button:FindFirstChildWhichIsA("TextButton", true)
        or button:FindFirstChildWhichIsA("TextBox", true)
end

local function setGradientsEnabled(gradients, enabled)
    for _, gradient in ipairs(gradients or {}) do
        if gradient and gradient.Parent then
            gradient.Enabled = enabled
        end
    end
end

local function resolveToggleGradients(frame, button)
    local namedOnGradients = findGradientsByName(button, "On")
    local namedOffGradients = findGradientsByName(button, "Off")
    if #namedOnGradients > 0 or #namedOffGradients > 0 then
        return nil, nil, namedOnGradients, namedOffGradients, true
    end

    local onGradient = findFirstGradientByName(frame, "UIGradient")
    local offGradient = findFirstGradientByName(frame, "UIGradient1")

    local gradients = {}
    for _, desc in ipairs(frame:GetDescendants()) do
        if desc:IsA("UIGradient") then
            table.insert(gradients, desc)
        end
    end

    if not onGradient then
        for _, gradient in ipairs(gradients) do
            if gradient ~= offGradient then
                onGradient = gradient
                break
            end
        end
    end

    if not offGradient then
        for _, gradient in ipairs(gradients) do
            if gradient ~= onGradient then
                offGradient = gradient
                break
            end
        end
    end

    return onGradient, offGradient, {}, {}, false
end

local function resolveToggleUi(root, key)
    local toggleFrame = findToggleFrame(root, key)
    if not toggleFrame then
        return nil
    end

    local innerFrame = toggleFrame:FindFirstChild("Frame")
    if not innerFrame or not innerFrame:IsA("GuiObject") then
        innerFrame = toggleFrame
    end

    local buttonContainer = toggleFrame:FindFirstChild("Button", true)
    local button = buttonContainer and buttonContainer:FindFirstChild("On/Off")
    if not isButton(button) then
        button = innerFrame:FindFirstChild("Button")
    end
    if not isButton(button) then
        button = innerFrame:FindFirstChildWhichIsA("GuiButton", true)
    end

    if not isButton(button) then
        return nil
    end

    local onGradient, offGradient, onGradients, offGradients, usesNamedState = resolveToggleGradients(innerFrame, button)
    return {
        Button = button,
        Frame = innerFrame,
        OnGradient = onGradient,
        OffGradient = offGradient,
        OnGradients = onGradients,
        OffGradients = offGradients,
        StateLabel = findToggleStateLabel(button),
        UsesNamedState = usesNamedState,
    }
end

local function setToggleUi(key)
    local ui = toggleUis[key]
    if not ui then
        return
    end

    local enabled = settings[key] ~= false
    local button = ui.Button
    if ui.StateLabel then
        ui.StateLabel.Text = enabled and "On" or "Off"
    end

    setGradientsEnabled(ui.OnGradients, enabled)
    setGradientsEnabled(ui.OffGradients, not enabled)

    if button and not ui.UsesNamedState then
        local onPosition = toggleButtonOnPositions[button] or button.Position
        toggleButtonOnPositions[button] = onPosition

        if enabled then
            button.Position = UDim2.new(ON_BUTTON_X_SCALE, onPosition.X.Offset, onPosition.Y.Scale, onPosition.Y.Offset)
        else
            button.Position = UDim2.new(OFF_BUTTON_X_SCALE, onPosition.X.Offset, onPosition.Y.Scale, onPosition.Y.Offset)
        end
    end

    if ui.OnGradient then
        ui.OnGradient.Enabled = enabled
    end

    if ui.OffGradient then
        ui.OffGradient.Enabled = not enabled
    end
end

local function refreshToggleUis()
    for key in pairs(toggleUis) do
        setToggleUi(key)
    end
end

local function getMusicSliderRatio()
    return getEffectiveMusicVolume()
end

local function getSliderTrackBounds(ui)
    local bg = ui and ui.BG
    local button = ui and ui.Button
    if not (bg and button) then
        return nil, nil
    end

    local bgWidth = bg.AbsoluteSize.X
    local buttonWidth = button.AbsoluteSize.X
    if bgWidth <= 0 then
        return nil, nil
    end

    local minX = bg.AbsolutePosition.X + (buttonWidth * button.AnchorPoint.X)
    local maxX = bg.AbsolutePosition.X + bgWidth - (buttonWidth * (1 - button.AnchorPoint.X))
    if maxX < minX then
        local centerX = bg.AbsolutePosition.X + (bgWidth / 2)
        return centerX, centerX
    end

    return minX, maxX
end

local function setMusicSliderButtonPosition()
    local ui = musicSliderUi
    if not ui then
        return
    end

    local button = ui.Button
    local parent = button and button.Parent
    if not (button and parent and parent:IsA("GuiObject")) then
        return
    end

    local minX, maxX = getSliderTrackBounds(ui)
    if not minX or not maxX or parent.AbsoluteSize.X <= 0 then
        return
    end

    local ratio = getMusicSliderRatio()
    local targetX = minX + ((maxX - minX) * ratio)
    local xScale = (targetX - parent.AbsolutePosition.X) / parent.AbsoluteSize.X
    button.Position = UDim2.new(xScale, 0, button.Position.Y.Scale, button.Position.Y.Offset)
end

local function setMusicVolume(volume)
    settings.MusicVolume = clamp01(volume)
    settings.Music = settings.MusicVolume > 0
    setMusicSliderButtonPosition()
    applyMusicSettings()
end

local function getSliderRatioFromScreenX(ui, screenX)
    local minX, maxX = getSliderTrackBounds(ui)
    if not minX or not maxX then
        return getMusicSliderRatio()
    end

    if maxX == minX then
        return 0
    end

    return math.clamp((screenX - minX) / (maxX - minX), 0, 1)
end

local function updateMusicSliderFromInput(input)
    local ui = musicSliderUi
    if not ui or not input then
        return
    end

    setMusicVolume(getSliderRatioFromScreenX(ui, input.Position.X))
end

local function isSliderPointerInput(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isSliderMoveInput(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function resolveMusicSlider(root)
    local musicFrame = findToggleFrame(root, "Music")
    if not musicFrame then
        return nil
    end

    local slider = musicFrame:FindFirstChild("Slider", true)
    if not slider or not slider:IsA("GuiObject") then
        return nil
    end

    local bg = slider:FindFirstChild("BG")
    local button = slider:FindFirstChild("Button")
    if not (bg and bg:IsA("GuiObject") and isButton(button)) then
        return nil
    end

    return {
        Frame = musicFrame,
        Slider = slider,
        BG = bg,
        Button = button,
    }
end

local function bindMusicSlider(root)
    local ui = resolveMusicSlider(root)
    if not ui then
        return false
    end

    musicSliderUi = ui
    ui.Slider.Active = true
    ui.BG.Active = true
    ui.Button.Active = true
    setMusicSliderButtonPosition()
    task.defer(setMusicSliderButtonPosition)

    if ui.Button:GetAttribute("SettingsMusicSliderBound") then
        return true
    end
    ui.Button:SetAttribute("SettingsMusicSliderBound", true)

    local function beginDrag(input)
        if not isSliderPointerInput(input) then
            return
        end

        isDraggingMusicSlider = true
        updateMusicSliderFromInput(input)
    end

    ui.Button.InputBegan:Connect(beginDrag)
    ui.BG.InputBegan:Connect(beginDrag)
    ui.Slider.InputBegan:Connect(beginDrag)

    UserInputService.InputChanged:Connect(function(input)
        if isDraggingMusicSlider and isSliderMoveInput(input) then
            updateMusicSliderFromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if isDraggingMusicSlider and isSliderPointerInput(input) then
            isDraggingMusicSlider = false
            updateMusicSliderFromInput(input)
        end
    end)

    return true
end

local function bindToggle(root, key, title)
    local ui = resolveToggleUi(root, key)
    if ui then
        toggleUis[key] = ui
        setToggleUi(key)

        local button = ui.Button
        if not button:GetAttribute("SettingsBound") then
            button:SetAttribute("SettingsBound", true)
            button.Activated:Connect(function()
                settings[key] = not settings[key]
                setToggleUi(key)
                applySettingChange(key)
            end)
        end
        return
    end

    local legacyButton = findNamedControl(root, key)
    if not legacyButton then return end
    if legacyButton:GetAttribute("SettingsBound") then
        setButtonLabel(legacyButton, title, settings[key])
        return
    end

    legacyButton:SetAttribute("SettingsBound", true)
    setButtonLabel(legacyButton, title, settings[key])

    legacyButton.Activated:Connect(function()
        settings[key] = not settings[key]
        setButtonLabel(legacyButton, title, settings[key])
        applySettingChange(key)
    end)
end

local function bindSettingsGui()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 15)
    if not basicGui then
        warn("[SettingsController] BasicGui was not found")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", 15)
    local settingsGui = basicGui:WaitForChild("Settings", 15)
    if not playProperty or not settingsGui then
        warn("[SettingsController] PlayProperty or Settings was not found")
        return
    end

    settingsGui.Enabled = false
    setSettingsInputBlocked(false)

    local frame = settingsGui:FindFirstChild("Frame", true) or settingsGui

    local setupButton = findNamedControl(playProperty, "Setup")
    if setupButton and not setupButton:GetAttribute("SettingsOpenBound") then
        setupButton:SetAttribute("SettingsOpenBound", true)
        setupButton.Activated:Connect(function()
            ensureSettingsInputBlocker(settingsGui, frame)
            setSettingsInputBlocked(true)
            settingsGui.Enabled = true
            refreshToggleUis()
            setMusicSliderButtonPosition()
        end)
    end

    local closeButton = findNamedControl(frame, "Close")
    if closeButton and not closeButton:GetAttribute("SettingsCloseBound") then
        closeButton:SetAttribute("SettingsCloseBound", true)
        closeButton.Activated:Connect(function()
            settingsGui.Enabled = false
            setSettingsInputBlocked(false)
        end)
    end

    settingsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not settingsGui.Enabled then
            setSettingsInputBlocked(false)
        end
    end)

    if not bindMusicSlider(frame) then
        bindToggle(frame, "Music", "Music")
    end
    bindToggle(frame, "EffectsSelf", "Self Effects")
    bindToggle(frame, "EffectsOthers", "Other Effects")
    bindToggle(frame, "PlantSelf", "Self Plants")
    bindToggle(frame, "PlantOthers", "Other Plants")
    bindToggle(frame, "Sunflower", "Sunflower")
    bindToggle(frame, "Disturb", "Reject Interaction")
    bindToggle(frame, "Box", "Box")
    refreshToggleUis()
    setMusicSliderButtonPosition()
    applyDisturbSetting()
    applyBoxSetting()
end

function SettingsController.Init()
    if started then
        return
    end
    started = true

    task.spawn(bindSettingsGui)
    watchPlotFolders()

    SoundService.DescendantAdded:Connect(function(desc)
        if desc:IsA("Sound") then
            task.defer(applySoundVolume, desc)
        end
    end)
end

return SettingsController

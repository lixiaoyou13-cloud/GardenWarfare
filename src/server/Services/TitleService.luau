local TitleService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local TitleConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TitleConfig"))

local REMOTE_NAME = "ToggleTitleRE"
local BILLBOARD_NAME = "EquippedTitleBillboard"
local TRAIL_NAME = "EquippedTitleTrail"
local TRAIL_GENERATED_ATTRIBUTE = "TitleTrailGenerated"
local MAX_LEVEL_PLOT_BILLBOARD_NAME = "EquippedTitleMaxLevelBillboard"
local OWNER_PLOT_BILLBOARD_NAME = "EquippedTitleOwnerBillboard"
local MAX_LEVEL_PART_NAME = "PlayerMaxLevelPart"
local TITLE_BASE_WALK_SPEED_ATTRIBUTE = "TitleBaseWalkSpeed"
local TITLE_SPEED_BOOST_ATTRIBUTE = "TitleSpeedBoostPercent"
local TITLE_SPEED_APPLIED_ATTRIBUTE = "TitleSpeedBoostApplied"

local function getOrCreateRemoteEvent(name)
    local remote = ReplicatedStorage:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = ReplicatedStorage
    end

    return remote
end

local function clearTitleBillboard(character)
    if not character then
        return
    end

    local head = character:FindFirstChild("Head")
    local existing = head and head:FindFirstChild(BILLBOARD_NAME)
    if existing then
        existing:Destroy()
    end
end

local function clearTitleTrail(character)
    local existing = character and character:FindFirstChild(TRAIL_NAME)
    if existing then
        existing:Destroy()
    end

    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:GetAttribute(TRAIL_GENERATED_ATTRIBUTE) == true then
            descendant:Destroy()
        end
    end
end

local function getTitleTrailTemplate(title, titleId)
    local trailRoot = ReplicatedStorage:FindFirstChild("Trail")
    if not trailRoot then
        return nil
    end

    local trailConfigName = type(title) == "table" and title.Trail or nil
    local trailConfig = type(trailConfigName) == "string" and trailRoot:FindFirstChild(trailConfigName) or nil
    if not trailConfig and type(titleId) == "string" then
        trailConfig = trailRoot:FindFirstChild(titleId)
    end
    if not trailConfig then
        return nil
    end

    return trailConfig
end

local function prepareTrailPart(part)
    part:SetAttribute(TRAIL_GENERATED_ATTRIBUTE, true)
    part.Anchored = false
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
end

local function hasTrailBasePart(trailObject)
    if trailObject:IsA("BasePart") then
        return true
    end

    for _, descendant in ipairs(trailObject:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return true
        end
    end

    return false
end

local function weldTrailToRoot(trailObject, rootPart)
    if trailObject:IsA("BasePart") then
        prepareTrailPart(trailObject)
        trailObject.CFrame = rootPart.CFrame
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = trailObject
        weld.Parent = trailObject
        return
    end

    for _, descendant in ipairs(trailObject:GetDescendants()) do
        if descendant:IsA("BasePart") then
            prepareTrailPart(descendant)
            descendant.CFrame = rootPart.CFrame
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = rootPart
            weld.Part1 = descendant
            weld.Parent = descendant
        end
    end
end

local function getTitleMoveSpeedBoostPercent(title)
    local boostPercent = type(title) == "table" and tonumber(title.MoveSpeedBoostPercent) or nil
    if boostPercent == nil then
        boostPercent = tonumber(TitleConfig.EquippedMoveSpeedBoostPercent) or 0
    end

    return math.max(0, boostPercent)
end

local function clearTitleMoveSpeed(character)
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    local baseWalkSpeed = humanoid:GetAttribute(TITLE_BASE_WALK_SPEED_ATTRIBUTE)
    if humanoid:GetAttribute(TITLE_SPEED_APPLIED_ATTRIBUTE) == true and type(baseWalkSpeed) == "number" and baseWalkSpeed > 0 then
        humanoid.WalkSpeed = baseWalkSpeed
    end

    humanoid:SetAttribute(TITLE_BASE_WALK_SPEED_ATTRIBUTE, nil)
    humanoid:SetAttribute(TITLE_SPEED_BOOST_ATTRIBUTE, nil)
    humanoid:SetAttribute(TITLE_SPEED_APPLIED_ATTRIBUTE, nil)
end

local function applyTitleMoveSpeed(character, title)
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    if not humanoid then
        return
    end

    local boostPercent = getTitleMoveSpeedBoostPercent(title)
    if boostPercent <= 0 then
        return
    end

    local baseWalkSpeed = humanoid:GetAttribute(TITLE_BASE_WALK_SPEED_ATTRIBUTE)
    if humanoid:GetAttribute(TITLE_SPEED_APPLIED_ATTRIBUTE) ~= true or type(baseWalkSpeed) ~= "number" or baseWalkSpeed <= 0 then
        baseWalkSpeed = humanoid.WalkSpeed
    end

    humanoid:SetAttribute(TITLE_BASE_WALK_SPEED_ATTRIBUTE, baseWalkSpeed)
    humanoid:SetAttribute(TITLE_SPEED_BOOST_ATTRIBUTE, boostPercent)
    humanoid:SetAttribute(TITLE_SPEED_APPLIED_ATTRIBUTE, true)
    humanoid.WalkSpeed = baseWalkSpeed * (1 + boostPercent / 100)
end

local function isLooseTrailEffect(instance)
    return instance:IsA("Attachment")
        or instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("Highlight")
end

local function attachLooseTrailEffects(trailObject, rootPart)
    local effects = {}
    if isLooseTrailEffect(trailObject) then
        table.insert(effects, trailObject)
    end

    for _, descendant in ipairs(trailObject:GetDescendants()) do
        if isLooseTrailEffect(descendant) then
            table.insert(effects, descendant)
        end
    end

    for _, effect in ipairs(effects) do
        effect:SetAttribute(TRAIL_GENERATED_ATTRIBUTE, true)
        effect.Parent = rootPart
    end
end

local function applyTitleTrailToCharacter(character, title, titleId)
    if not character then
        return
    end

    clearTitleTrail(character)

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5) or character.PrimaryPart
    if not rootPart then
        return
    end

    local trailTemplate = getTitleTrailTemplate(title, titleId)
    if not trailTemplate then
        return
    end

    local trailObject = trailTemplate:Clone()
    trailObject.Name = TRAIL_NAME
    trailObject:SetAttribute(TRAIL_GENERATED_ATTRIBUTE, true)
    trailObject.Parent = character

    if hasTrailBasePart(trailObject) then
        if trailObject:IsA("Model") then
            trailObject:PivotTo(rootPart.CFrame)
        elseif trailObject:IsA("BasePart") then
            trailObject.CFrame = rootPart.CFrame
        end

        weldTrailToRoot(trailObject, rootPart)
    else
        attachLooseTrailEffects(trailObject, rootPart)
    end
end

local function getPlayerPlot(player)
    local ok, plotService = pcall(function()
        return require(script.Parent.PlotService)
    end)

    if ok and plotService and type(plotService.GetPlayerPlot) == "function" then
        return plotService.GetPlayerPlot(player)
    end

    return nil
end

local function getBasePart(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    end

    return instance:FindFirstChildWhichIsA("BasePart", true)
end

function TitleService.ClearPlotTitleDisplays(plot)
    if not plot then
        return
    end

    for _, descendant in ipairs(plot:GetDescendants()) do
        if descendant.Name == MAX_LEVEL_PLOT_BILLBOARD_NAME or descendant.Name == OWNER_PLOT_BILLBOARD_NAME then
            descendant:Destroy()
        end
    end
end

local function createPlotTitleBillboard(name, parent, adornee, imageId, size, studsOffset, maxDistance)
    if not parent or not adornee then
        return
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = name
    billboard.Size = size
    billboard.StudsOffset = studsOffset
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = maxDistance
    billboard.Adornee = adornee

    local image = Instance.new("ImageLabel")
    image.Name = "TitleImage"
    image.Size = UDim2.fromScale(1, 1)
    image.BackgroundTransparency = 1
    image.Image = imageId
    image.ImageColor3 = Color3.fromRGB(255, 255, 255)
    image.ScaleType = Enum.ScaleType.Fit
    image.Parent = billboard

    billboard.Parent = parent
end

local function findMaxLevelAdornee(plot)
    local maxLevelPart = plot and plot:FindFirstChild(MAX_LEVEL_PART_NAME, true)
    return getBasePart(maxLevelPart)
end

local function findOwnerBillboardAdornee(plot)
    if not plot then
        return nil
    end

    for _, descendant in ipairs(plot:GetDescendants()) do
        if descendant.Name == "OwnerBillboard" and descendant:IsA("BillboardGui") then
            return descendant.Adornee or getBasePart(descendant.Parent)
        end
    end

    return nil
end

function TitleService.UpdatePlotTitleDisplays(player)
    local plot = getPlayerPlot(player)
    if not plot then
        return
    end

    TitleService.ClearPlotTitleDisplays(plot)

    local titleId = PlayerDataManager.GetEquippedTitle(player)
    if titleId == "" then
        return
    end

    local title = TitleConfig.GetTitle(titleId)
    if not title or type(title.ImageId) ~= "string" or title.ImageId == "" then
        return
    end

    local maxLevelAdornee = findMaxLevelAdornee(plot)
    if maxLevelAdornee then
        createPlotTitleBillboard(
            MAX_LEVEL_PLOT_BILLBOARD_NAME,
            maxLevelAdornee,
            maxLevelAdornee,
            title.ImageId,
            UDim2.fromScale(18, 5.76),
            Vector3.new(0, 6.2, 0),
            250
        )
    end

    local ownerAdornee = findOwnerBillboardAdornee(plot)
    if ownerAdornee then
        createPlotTitleBillboard(
            OWNER_PLOT_BILLBOARD_NAME,
            ownerAdornee,
            ownerAdornee,
            title.ImageId,
            UDim2.fromScale(28.8, 9.36),
            Vector3.new(0, 27.8, 0),
            250
        )
    end
end

local function applyTitleToCharacter(player, character)
    if not player or not character then
        return
    end

    clearTitleBillboard(character)
    clearTitleTrail(character)
    clearTitleMoveSpeed(character)

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        return
    end

    local titleId = PlayerDataManager.GetEquippedTitle(player)
    if titleId == "" then
        return
    end

    local title = TitleConfig.GetTitle(titleId)
    if not title or type(title.ImageId) ~= "string" or title.ImageId == "" then
        return
    end

    applyTitleTrailToCharacter(character, title, titleId)
    applyTitleMoveSpeed(character, title)
end

local function applyAllTitleDisplays(player, character)
    applyTitleToCharacter(player, character)
    TitleService.UpdatePlotTitleDisplays(player)
end

local function bindPlayer(player)
    player.CharacterAdded:Connect(function(character)
        task.spawn(applyAllTitleDisplays, player, character)
    end)

    if player.Character then
        task.spawn(applyAllTitleDisplays, player, player.Character)
    end
end

function TitleService.Init()
    local toggleTitleRE = getOrCreateRemoteEvent(REMOTE_NAME)
    toggleTitleRE.OnServerEvent:Connect(function(player, titleId)
        if type(titleId) ~= "string" then
            return
        end

        local ok, _, message = PlayerDataManager.ToggleTitle(player, titleId)
        if ok then
            applyAllTitleDisplays(player, player.Character)
            return
        end

        local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
        if showTipRE and message then
            showTipRE:FireClient(player, message)
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayer(player)
    end
    Players.PlayerAdded:Connect(bindPlayer)

    print("Server: TitleService active.")
end

return TitleService

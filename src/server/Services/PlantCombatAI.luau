-- src/server/Services/PlantCombatAI.luau
local PlantCombatAI = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local plantAttackVisualRE = ReplicatedStorage:FindFirstChild("PlantAttackVisualRE")
if not plantAttackVisualRE then
    plantAttackVisualRE = Instance.new("RemoteEvent")
    plantAttackVisualRE.Name = "PlantAttackVisualRE"
    plantAttackVisualRE.Parent = ReplicatedStorage
end

local PROJECTILE_SPEED = 25
local VISUAL_EVENT_RADIUS = 220
local DEFAULT_PIERCING_RANGE = 100
local DEFAULT_PIERCING_WIDTH = 4
local DEFAULT_PIERCING_DAMAGE_SCALE = 0.6
local SHOOTER_TARGET_WIDTH = 6
local warnedProjectileIssues = {}
local warnedAnimationIssues = {}
local failedAnimationIds = {}
local animationLengthCache = {}
local activeGroundEffects = {}

local function warnProjectileOnce(projectileName, message)
    local key = tostring(projectileName) .. ":" .. message
    if warnedProjectileIssues[key] then return end
    warnedProjectileIssues[key] = true
    warn(("[PlantCombatAI] %s: %s"):format(tostring(projectileName), message))
end

local function warnAnimationOnce(animationId, message)
    local key = tostring(animationId) .. ":" .. message
    if warnedAnimationIssues[key] then return end
    warnedAnimationIssues[key] = true
    warn(("[PlantCombatAI] Animation %s: %s"):format(tostring(animationId), message))
end

local function loadPlantAnimation(animator, animationId, priority, looped)
    if not animator or animationId == nil then
        return nil
    end

    animationId = tostring(animationId)
    if animationId == "" then
        return nil
    end
    if failedAnimationIds[animationId] then
        return nil
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = animationId

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    anim:Destroy()

    if not ok or not trackOrErr then
        failedAnimationIds[animationId] = true
        warnAnimationOnce(animationId, "failed to load: " .. tostring(trackOrErr))
        return nil
    end

    trackOrErr.Priority = priority
    trackOrErr.Looped = looped == true
    return trackOrErr
end

local function GetSafeGameSpeed(plot)
    local speedMult = plot and tonumber(plot:GetAttribute("GameSpeed")) or 1
    if speedMult ~= 1 and speedMult ~= 2 and speedMult ~= 4 then
        return 1
    end
    return speedMult
end

local function addRecipient(recipients, recipientSet, player)
    if not player or recipientSet[player] then
        return
    end

    recipientSet[player] = true
    table.insert(recipients, player)
end

local function getCharacterRoot(player)
    local character = player.Character
    if not character then return nil end

    return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function getLawnRowFromGridName(gridName)
    if type(gridName) ~= "string" then
        return nil
    end

    return tonumber(string.match(gridName, "^Lawn(%d+)_"))
end

local function collectVisualRecipients(plot, originPosition)
    local recipients = {}
    local recipientSet = {}

    local ownerId = plot and plot:GetAttribute("OwnerId")
    if ownerId then
        addRecipient(recipients, recipientSet, Players:GetPlayerByUserId(ownerId))
    end

    if typeof(originPosition) == "Vector3" then
        for _, player in ipairs(Players:GetPlayers()) do
            local rootPart = getCharacterRoot(player)
            if rootPart and (rootPart.Position - originPosition).Magnitude <= VISUAL_EVENT_RADIUS then
                addRecipient(recipients, recipientSet, player)
            end
        end
    end

    return recipients
end

local function firePlantVisualEvent(plot, originPosition, ...)
    local recipients = collectVisualRecipients(plot, originPosition)
    if #recipients == 0 then
        return
    end

    for _, player in ipairs(recipients) do
        plantAttackVisualRE:FireClient(player, ...)
    end
end

local function findLawnForPosition(plot, position)
    if not plot or typeof(position) ~= "Vector3" then
        return nil
    end

    local lawnFolder = plot:FindFirstChild("Lawn")
    if not lawnFolder then
        return nil
    end

    local bestLawn = nil
    local bestScore = math.huge

    for _, lawnPart in ipairs(lawnFolder:GetDescendants()) do
        if lawnPart:IsA("BasePart") then
            local localPos = lawnPart.CFrame:PointToObjectSpace(position)
            local dx = math.max(math.abs(localPos.X) - lawnPart.Size.X * 0.5, 0)
            local dz = math.max(math.abs(localPos.Z) - lawnPart.Size.Z * 0.5, 0)
            local score = dx * dx + dz * dz
            if score < bestScore then
                bestScore = score
                bestLawn = lawnPart
            end
        end
    end

    return bestLawn
end

local function findContainingLawnForPosition(plot, position)
    if not plot or typeof(position) ~= "Vector3" then
        return nil
    end

    local lawnFolder = plot:FindFirstChild("Lawn")
    if not lawnFolder then
        return nil
    end

    for _, lawnPart in ipairs(lawnFolder:GetDescendants()) do
        if lawnPart:IsA("BasePart") then
            local localPos = lawnPart.CFrame:PointToObjectSpace(position)
            if math.abs(localPos.X) <= lawnPart.Size.X * 0.5
                and math.abs(localPos.Z) <= lawnPart.Size.Z * 0.5 then
                return lawnPart
            end
        end
    end

    return nil
end

local function getFlatUnit(direction, fallback)
    if typeof(direction) ~= "Vector3" then
        direction = fallback
    end

    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude > 0.001 then
        return flat.Unit
    end

    if typeof(fallback) == "Vector3" then
        local fallbackFlat = Vector3.new(fallback.X, 0, fallback.Z)
        if fallbackFlat.Magnitude > 0.001 then
            return fallbackFlat.Unit
        end
    end

    return Vector3.new(1, 0, 0)
end

local function getLawnStepDistance(lawnPart, direction)
    if not lawnPart then
        return 8
    end

    local localDirection = lawnPart.CFrame:VectorToObjectSpace(getFlatUnit(direction))
    if math.abs(localDirection.X) >= math.abs(localDirection.Z) then
        return math.max(1, lawnPart.Size.X)
    end

    return math.max(1, lawnPart.Size.Z)
end

local function getLawnSideWidth(lawnPart, direction)
    if not lawnPart then
        return 8
    end

    local localDirection = lawnPart.CFrame:VectorToObjectSpace(getFlatUnit(direction))
    if math.abs(localDirection.X) >= math.abs(localDirection.Z) then
        return math.max(1, lawnPart.Size.Z)
    end

    return math.max(1, lawnPart.Size.X)
end

local function isZombieOwnedByPlot(zombieModel, plot)
    local zombieOwnerId = zombieModel and zombieModel:GetAttribute("OwnerId")
    local plotOwnerId = plot and plot:GetAttribute("OwnerId")
    return not (zombieOwnerId and plotOwnerId and zombieOwnerId ~= plotOwnerId)
end

local function getLivingZombieParts(zombieModel)
    if not zombieModel or not zombieModel.Parent or not zombieModel:GetAttribute("IsZombie") then
        return nil, nil
    end

    local humanoid = zombieModel:FindFirstChildOfClass("Humanoid")
    local rootPart = zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart
    if not humanoid or humanoid.Health <= 0 or not rootPart then
        return nil, nil
    end

    return humanoid, rootPart
end

local function collectPiercingTargets(plant, firePosition, shotDirection, itemDetail, plot, primaryTarget)
    local range = math.max(1, tonumber(itemDetail.PiercingRange) or DEFAULT_PIERCING_RANGE)
    local width = math.max(1, tonumber(itemDetail.PiercingWidth) or DEFAULT_PIERCING_WIDTH)
    local height = math.max(2, tonumber(itemDetail.PiercingHeight) or 8)
    local flatDir = getFlatUnit(shotDirection, plant and plant:GetPivot().LookVector)
    local center = firePosition + flatDir * (range * 0.5)
    local checkCFrame = CFrame.lookAt(center, center + flatDir)
    local checkSize = Vector3.new(width, height, range)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = plant and { plant } or {}

    local targetMap = {}
    local targets = {}

    local function addTarget(zombieModel)
        if targetMap[zombieModel] or not isZombieOwnedByPlot(zombieModel, plot) then
            return
        end

        local humanoid, rootPart = getLivingZombieParts(zombieModel)
        if not humanoid or not rootPart then
            return
        end

        local offset = rootPart.Position - firePosition
        local forwardDistance = offset:Dot(flatDir)
        if forwardDistance < -1 or forwardDistance > range + 1 then
            return
        end

        targetMap[zombieModel] = true
        table.insert(targets, {
            Model = zombieModel,
            Humanoid = humanoid,
            RootPart = rootPart,
            Distance = forwardDistance,
        })
    end

    if primaryTarget then
        addTarget(primaryTarget)
    end

    for _, part in ipairs(Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)) do
        local zombieModel = part:FindFirstAncestorOfClass("Model")
        if zombieModel and zombieModel:GetAttribute("IsZombie") then
            addTarget(zombieModel)
        end
    end

    table.sort(targets, function(a, b)
        return a.Distance < b.Distance
    end)

    return targets
end

local function isFrontAreaAttack(itemDetail)
    return itemDetail and (itemDetail.AttackMode == "FrontArea" or type(itemDetail.FrontArea) == "table")
end

local function getPlantLawnPart(plant, plot)
    if plant and plant.Parent and plant.Parent:IsA("BasePart") then
        return plant.Parent
    end

    local rootPart = plant and (plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart"))
    if rootPart then
        return findLawnForPosition(plot, rootPart.Position)
    end

    return nil
end

local function collectFrontAreaTargets(plant, rootPart, itemDetail, plot)
    if not plant or not rootPart or not itemDetail then
        return {}
    end

    local config = type(itemDetail.FrontArea) == "table" and itemDetail.FrontArea or {}
    local lawnPart = getPlantLawnPart(plant, plot)
    local flatDir = getFlatUnit(rootPart.CFrame.LookVector, Vector3.new(1, 0, 0))
    local stepDistance = getLawnStepDistance(lawnPart, flatDir)
    local gridRange = math.max(0.1, tonumber(config.GridRange) or 1)
    local range = stepDistance * gridRange
    local centerOffset = stepDistance * (tonumber(config.CenterGridOffset) or gridRange)
    local center = rootPart.Position + flatDir * centerOffset
    local checkCFrame = CFrame.lookAt(center, center + flatDir)
    local width = math.max(1, tonumber(config.Width) or getLawnSideWidth(lawnPart, flatDir))
    local height = math.max(2, tonumber(config.Height) or 8)
    local checkSize = Vector3.new(width, height, range)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = { plant }

    local targetMap = {}
    local targets = {}
    local plantRowNum = getLawnRowFromGridName(plant:GetAttribute("GridName"))

    local function addTarget(zombieModel)
        if targetMap[zombieModel] or not isZombieOwnedByPlot(zombieModel, plot) then
            return
        end

        local zombieRowNum = tonumber(zombieModel:GetAttribute("LaneRow"))
        if plantRowNum and zombieRowNum and plantRowNum ~= zombieRowNum then
            return
        end

        local humanoid, zombieRoot = getLivingZombieParts(zombieModel)
        if not humanoid or not zombieRoot then
            return
        end

        local forwardDistance = (zombieRoot.Position - rootPart.Position):Dot(flatDir)
        targetMap[zombieModel] = true
        table.insert(targets, {
            Model = zombieModel,
            Humanoid = humanoid,
            RootPart = zombieRoot,
            Distance = forwardDistance,
        })
    end

    for _, part in ipairs(Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)) do
        if part.CollisionGroup == "Zombies" then
            local zombieModel = part:FindFirstAncestorOfClass("Model")
            if zombieModel then
                addTarget(zombieModel)
            end
        end
    end

    table.sort(targets, function(a, b)
        return a.Distance < b.Distance
    end)

    return targets, flatDir
end

local function applyKnockbackOnHit(zombieModel, rootPart, itemDetail, plot, shotDirection)
    local knockback = itemDetail and itemDetail.KnockbackOnHit
    if type(knockback) ~= "table" or not zombieModel or not zombieModel.Parent or not rootPart then
        return
    end

    local gridDistance = tonumber(knockback.GridDistance) or 0
    if gridDistance <= 0 then
        return
    end

    local lawnPart = findContainingLawnForPosition(plot, rootPart.Position)
    if knockback.OnlyWhenTargetOnLawn and not lawnPart then
        return
    end
    lawnPart = lawnPart or findLawnForPosition(plot, rootPart.Position)

    local flatDir = getFlatUnit(shotDirection, rootPart.CFrame.LookVector)
    local stepDistance = getLawnStepDistance(lawnPart, flatDir) * gridDistance
    local delta = flatDir * stepDistance

    zombieModel:PivotTo(zombieModel:GetPivot() + delta)

    if rootPart and rootPart.Parent then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function prepGroundEffect(effect)
    if not effect then
        return
    end

    local function prepPart(part)
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
    end

    if effect:IsA("BasePart") then
        prepPart(effect)
    end

    for _, desc in ipairs(effect:GetDescendants()) do
        if desc:IsA("BasePart") then
            prepPart(desc)
        elseif desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") then
            desc.Enabled = true
        elseif desc:IsA("Light") then
            desc.Enabled = true
        end
    end
end

local function positionGroundEffect(effect, lawnPart)
    if not effect or not lawnPart then
        return
    end

    local yOffset = lawnPart.Size.Y * 0.5
    if effect:IsA("BasePart") then
        effect.CFrame = lawnPart.CFrame * CFrame.new(0, yOffset + effect.Size.Y * 0.5, 0)
    elseif effect:IsA("Model") then
        local _, size = effect:GetBoundingBox()
        effect:PivotTo(lawnPart.CFrame * CFrame.new(0, yOffset + size.Y * 0.5, 0))
    end
end

local function showGroundDamageText(plot, zombieModel, damage)
    local rootPart = zombieModel and (zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart)
    if not rootPart then
        return
    end

    firePlantVisualEvent(
        plot,
        rootPart.Position,
        "DamageText",
        zombieModel,
        damage,
        plot and plot:GetAttribute("OwnerId")
    )
end

local function damageZombiesInLawn(lawnPart, plot, damage)
    if not lawnPart or not lawnPart.Parent or damage <= 0 then
        return
    end

    local boxCFrame = lawnPart.CFrame * CFrame.new(0, 4, 0)
    local boxSize = Vector3.new(lawnPart.Size.X, 8, lawnPart.Size.Z)
    local hitParts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize)
    local processedZombies = {}
    local plotOwnerId = plot and plot:GetAttribute("OwnerId")

    for _, part in ipairs(hitParts) do
        local targetModel = part:FindFirstAncestorOfClass("Model")
        if targetModel and targetModel:GetAttribute("IsZombie") and not processedZombies[targetModel] then
            local zombieOwnerId = targetModel:GetAttribute("OwnerId")
            if zombieOwnerId and plotOwnerId and zombieOwnerId ~= plotOwnerId then
                continue
            end

            processedZombies[targetModel] = true

            local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
            if targetHum and targetHum.Health > 0 then
                targetHum.Health = math.max(0, targetHum.Health - damage)
                showGroundDamageText(plot, targetModel, damage)
            end
        end
    end
end

local function spawnGroundEffect(plot, position, itemDetail, attackDamage)
    local groundEffect = itemDetail and itemDetail.GroundEffect
    if type(groundEffect) ~= "table" then
        return
    end

    local effectName = groundEffect.EffectName
    if type(effectName) ~= "string" or effectName == "" then
        return
    end

    local lawnPart = findLawnForPosition(plot, position)
    if not lawnPart then
        return
    end

    local duration = math.max(0.1, tonumber(groundEffect.Duration) or 2)
    local tickInterval = math.max(0.1, tonumber(groundEffect.TickInterval) or 1)
    local damagePerSecond = math.max(1, math.floor((tonumber(attackDamage) or 0) * (tonumber(groundEffect.DamagePerSecondScale) or 0.1)))
    local damagePerTick = math.max(1, math.floor(damagePerSecond * tickInterval))
    local now = os.clock()
    local active = activeGroundEffects[lawnPart]

    if groundEffect.MaxOnePerGrid and active and active.effect and active.effect.Parent then
        active.expiresAt = now + duration
        active.damagePerTick = math.max(active.damagePerTick or 0, damagePerTick)
        return
    end

    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local template = hitFolder and hitFolder:FindFirstChild(effectName)
    if not template then
        warnProjectileOnce(effectName, "ReplicatedStorage.Hit ground effect not found on server")
        return
    end

    local effect = template:Clone()
    prepGroundEffect(effect)
    positionGroundEffect(effect, lawnPart)
    effect.Name = effectName .. "_GroundEffect"
    effect.Parent = Workspace

    local state = {
        effect = effect,
        expiresAt = now + duration,
        tickInterval = tickInterval,
        damagePerTick = damagePerTick,
        plot = plot,
    }
    activeGroundEffects[lawnPart] = state

    task.spawn(function()
        while activeGroundEffects[lawnPart] == state and os.clock() < state.expiresAt do
            damageZombiesInLawn(lawnPart, state.plot, state.damagePerTick)
            task.wait(state.tickInterval)
        end

        if activeGroundEffects[lawnPart] == state then
            activeGroundEffects[lawnPart] = nil
        end

        if effect and effect.Parent then
            effect:Destroy()
        end
    end)
end

local function getPlantAnimator(plant)
    if not plant or not plant.Parent then
        return nil
    end

    local animController = plant:FindFirstChildOfClass("AnimationController") or plant:FindFirstChildOfClass("Humanoid")
    if not animController then
        animController = Instance.new("AnimationController")
        animController.Parent = plant
    end

    local animator = animController:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = animController
    end

    return animator
end

local function getAnimationLengthSeconds(plant, animationId, fallback)
    if type(animationId) ~= "string" or animationId == "" then
        return fallback
    end

    local cachedLength = animationLengthCache[animationId]
    if cachedLength then
        return cachedLength
    end

    local animator = getPlantAnimator(plant)
    local track = loadPlantAnimation(animator, animationId, Enum.AnimationPriority.Action, false)
    if track then
        local length = tonumber(track.Length) or 0
        track:Destroy()

        if length > 0 then
            animationLengthCache[animationId] = length
            return length
        end
    end

    return fallback
end

local function applySlowOnHit(zombieModel, humanoid, itemDetail, speedMult)
    local slowConfig = itemDetail.SlowOnHit
    if type(slowConfig) ~= "table" then
        return
    end
    if not zombieModel or not zombieModel.Parent or not humanoid or humanoid.Health <= 0 then
        return
    end

    local moveMultiplier = math.clamp(tonumber(slowConfig.MoveMultiplier) or 0.5, 0, 1)
    local duration = tonumber(slowConfig.Duration) or 2
    local adjustedDuration = duration / math.max(tonumber(speedMult) or 1, 0.01)
    local tintColor = slowConfig.Color or Color3.fromRGB(80, 180, 255)
    local token = (zombieModel:GetAttribute("IceSlowToken") or 0) + 1

    zombieModel:SetAttribute("IceSlowToken", token)
    zombieModel:SetAttribute("SlowMultiplier", moveMultiplier)

    for _, part in ipairs(zombieModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part:GetAttribute("IceSlowOriginalColor") == nil then
                part:SetAttribute("IceSlowOriginalColor", part.Color)
            end
            part.Color = tintColor
        end
    end

    if humanoid.WalkSpeed > 0 then
        humanoid.WalkSpeed *= moveMultiplier
    end

    task.delay(adjustedDuration, function()
        if not zombieModel or not zombieModel.Parent then
            return
        end
        if zombieModel:GetAttribute("IceSlowToken") ~= token then
            return
        end

        zombieModel:SetAttribute("SlowMultiplier", nil)
        zombieModel:SetAttribute("IceSlowToken", nil)

        local currentHumanoid = zombieModel:FindFirstChildOfClass("Humanoid")
        if not currentHumanoid or currentHumanoid.Health <= 0 or zombieModel:GetAttribute("IsCharred") then
            return
        end

        for _, part in ipairs(zombieModel:GetDescendants()) do
            if part:IsA("BasePart") then
                local originalColor = part:GetAttribute("IceSlowOriginalColor")
                if originalColor then
                    part.Color = originalColor
                end
                part:SetAttribute("IceSlowOriginalColor", nil)
            end
        end
    end)
end

-- 1. 伤害文字与受击特效通用函数
local function applySplashDamage(primaryZombieModel, centerPosition, itemDetail, attackDamage, plot, speedMult)
    local radius = tonumber(itemDetail and itemDetail.SplashRadius)
    local scale = tonumber(itemDetail and itemDetail.SplashDamageScale)
    if not radius or radius <= 0 or not scale or scale <= 0 then
        return
    end

    local splashDamage = math.max(1, math.floor((tonumber(attackDamage) or 0) * scale + 0.5))
    if splashDamage <= 0 then
        return
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = primaryZombieModel and { primaryZombieModel } or {}

    local hitParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, overlapParams)
    local processedZombies = {}
    if primaryZombieModel then
        processedZombies[primaryZombieModel] = true
    end

    for _, part in ipairs(hitParts) do
        local targetModel = part:FindFirstAncestorOfClass("Model")
        if targetModel and targetModel:GetAttribute("IsZombie") and not processedZombies[targetModel] then
            processedZombies[targetModel] = true

            if not isZombieOwnedByPlot(targetModel, plot) then
                continue
            end

            local targetHum, targetRoot = getLivingZombieParts(targetModel)
            if targetHum and targetRoot and (targetRoot.Position - centerPosition).Magnitude <= radius then
                targetHum.Health = math.max(0, targetHum.Health - splashDamage)
                showGroundDamageText(plot, targetModel, splashDamage)

                if itemDetail.SplashAppliesSlow then
                    applySlowOnHit(targetModel, targetHum, itemDetail, speedMult)
                end
            end
        end
    end
end

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

local function getReactiveEmitCount(node, fallback)
    if not node then
        return fallback
    end

    local emitCount = node:GetAttribute("EmitCount")
    if not emitCount then
        local countValueNode = node:FindFirstChild("EmitCount")
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

local function enableReactiveEffectDescendants(effect)
    if not effect then
        return
    end

    local rootEmitCount = getReactiveEmitCount(effect, 12)

    for _, desc in ipairs(effect:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            desc.Enabled = true
            local emitCount = getReactiveEmitCount(desc, rootEmitCount)
            desc:Emit(emitCount)
        elseif desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Light") then
            desc.Enabled = true
        elseif desc:IsA("BasePart") then
            desc.CanCollide = false
            desc.CanTouch = false
            desc.CanQuery = false
            desc.Massless = true
        end
    end

    if effect:IsA("ParticleEmitter") then
        effect.Enabled = true
        local emitCount = getReactiveEmitCount(effect, rootEmitCount)
        effect:Emit(emitCount)
    elseif effect:IsA("Beam") or effect:IsA("Trail") or effect:IsA("Light") then
        effect.Enabled = true
    elseif effect:IsA("BasePart") then
        effect.CanCollide = false
        effect.CanTouch = false
        effect.CanQuery = false
        effect.Massless = true
    end
end

local function attachReactiveEffectToPlant(plant, rootPart, reactiveConfig)
    local effectFolderName = tostring(reactiveConfig.EffectFolder or "Hit")
    local effectName = tostring(reactiveConfig.EffectName or "Lightning")
    if effectName == "" then
        return
    end

    local effectFolder = ReplicatedStorage:FindFirstChild(effectFolderName)
    local template = effectFolder and effectFolder:FindFirstChild(effectName)
    if not template then
        warnProjectileOnce(effectName, ("ReplicatedStorage.%s effect not found on server"):format(effectFolderName))
        return
    end

    local effect = template:Clone()
    effect.Name = effectName .. "_ReactiveEffect"
    effect.Parent = plant

    if effect:IsA("BasePart") then
        effect.CFrame = rootPart.CFrame
        effect.Anchored = false

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = effect
        weld.Parent = effect
    elseif effect:IsA("Model") then
        effect:PivotTo(rootPart.CFrame)
        for _, desc in ipairs(effect:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Anchored = false
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = rootPart
                weld.Part1 = desc
                weld.Parent = desc
            end
        end
    elseif effect:IsA("Attachment") then
        effect.Parent = rootPart
    end

    enableReactiveEffectDescendants(effect)
    Debris:AddItem(effect, math.max(0.1, tonumber(reactiveConfig.EffectLifetime) or 1.25))
end

function PlantCombatAI.TriggerDamagedReactiveAttack(plant, itemDetail, mutationLevel, plot)
    local reactiveConfig = itemDetail and itemDetail.ReactiveOnDamaged
    if type(reactiveConfig) ~= "table" then
        return
    end
    if not plant or not plant.Parent or plant:GetAttribute("IsDead") or (plant:GetAttribute("Health") or 0) <= 0 then
        return
    end

    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    if not rootPart then
        return
    end

    local speedMult = GetSafeGameSpeed(plot)
    local cooldown = math.max(0.05, tonumber(reactiveConfig.Cooldown) or tonumber(itemDetail.AttackInterval) or 2)
    local adjustedCooldown = cooldown / math.max(speedMult, 0.01)
    local now = os.clock()
    local lastAttackAt = tonumber(plant:GetAttribute("ReactiveOnDamagedLastAttackAt")) or 0
    if now - lastAttackAt < adjustedCooldown then
        return
    end
    plant:SetAttribute("ReactiveOnDamagedLastAttackAt", now)

    local attackAnimation = itemDetail.AttackAnimation
    if type(attackAnimation) == "string" and attackAnimation ~= "" then
        firePlantVisualEvent(plot, rootPart.Position, "Attack", plant, attackAnimation, speedMult, plot and plot:GetAttribute("OwnerId"))
    end

    local effectDelay = tonumber(reactiveConfig.EffectDelay)
    if effectDelay == nil then
        effectDelay = getAnimationLengthSeconds(plant, attackAnimation, 0.8)
    end
    effectDelay = math.max(0, effectDelay) / math.max(speedMult, 0.01)

    local function runReactiveImpact()
        if not plant or not plant.Parent or plant:GetAttribute("IsDead") or (plant:GetAttribute("Health") or 0) <= 0 then
            return
        end

        local currentRootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
        if not currentRootPart then
            return
        end

        attachReactiveEffectToPlant(plant, currentRootPart, reactiveConfig)

        local radius = math.max(0.1, tonumber(reactiveConfig.Radius) or 14)
        local damage = math.max(1, math.floor(tonumber(reactiveConfig.Damage) or tonumber(itemDetail.Attack) or 0))
        if damage <= 0 then
            return
        end

        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { plant }

        local damagedZombies = {}
        for _, part in ipairs(Workspace:GetPartBoundsInRadius(currentRootPart.Position, radius, overlapParams)) do
            local zombieModel = part:FindFirstAncestorOfClass("Model")
            if zombieModel and zombieModel:GetAttribute("IsZombie") and not damagedZombies[zombieModel] then
                damagedZombies[zombieModel] = true

                if not isZombieOwnedByPlot(zombieModel, plot) then
                    continue
                end

                local targetHum, targetRoot = getLivingZombieParts(zombieModel)
                if targetHum and targetRoot and (targetRoot.Position - currentRootPart.Position).Magnitude <= radius then
                    targetHum.Health = math.max(0, targetHum.Health - damage)
                    showGroundDamageText(plot, zombieModel, damage)
                end
            end
        end
    end

    if effectDelay > 0 then
        task.delay(effectDelay, runReactiveImpact)
    else
        runReactiveImpact()
    end
end

-- 2. 子弹开火与命中逻辑
local function applyProjectileHit(plant, zombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
    local targetHum, targetRoot = getLivingZombieParts(zombieModel)
    if not targetHum or not targetRoot then
        return false
    end

    targetHum.Health = targetHum.Health - attackDamage
    applySlowOnHit(zombieModel, targetHum, itemDetail, speedMult)

    local zombieChestPos = targetRoot.Position + Vector3.new(0, 1, 0)
    local currentRootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    local toPlantDir = currentRootPart and (currentRootPart.Position - targetRoot.Position) or Vector3.new(1, 0, 0)
    local flatDir = Vector3.new(toPlantDir.X, 0, toPlantDir.Z)
    if flatDir.Magnitude > 0.001 then flatDir = flatDir.Unit else flatDir = Vector3.new(1, 0, 0) end
    local hitPos = zombieChestPos + flatDir * 1.2

    firePlantVisualEvent(
        plot,
        hitPos,
        "Hit",
        zombieModel,
        attackDamage,
        hitPos,
        itemDetail.HitEffectTexture,
        itemDetail.HitEffectColor,
        ownerUserId
    )

    spawnGroundEffect(plot, targetRoot.Position, itemDetail, attackDamage)
    applySplashDamage(zombieModel, targetRoot.Position, itemDetail, attackDamage, plot, speedMult)
    applyKnockbackOnHit(zombieModel, targetRoot, itemDetail, plot, shotDirection)

    return true
end

local function FireFrontAreaAttack(plant, itemDetail, attackDamage, plot)
    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    if not rootPart then
        return
    end

    local speedMult = GetSafeGameSpeed(plot)
    local ownerUserId = plot and plot:GetAttribute("OwnerId")
    local targets, shotDirection = collectFrontAreaTargets(plant, rootPart, itemDetail, plot)

    for _, target in ipairs(targets) do
        applyProjectileHit(plant, target.Model, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
    end
end

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
    local ownerUserId = plot and plot:GetAttribute("OwnerId")
    local initialTargetPos = targetRoot.Position + Vector3.new(0, 1, 0)
    local initialDist = (initialTargetPos - fireCFrame.Position).Magnitude
    local flightTime = math.max(0.05, initialDist / (PROJECTILE_SPEED * speedMult))
    local arcHeight = itemDetail.ArcHeight or 0
    local shotDirection = getFlatUnit(initialTargetPos - fireCFrame.Position, rootPart.CFrame.LookVector)
    local projectileVisualConfig = nil
    if itemDetail.Piercing then
        local maxPosPart = plot and plot:FindFirstChild("MAXPos", true)
        projectileVisualConfig = {
            ContinuePastTarget = true,
            Direction = shotDirection,
            MaxDistance = math.max(
                initialDist,
                tonumber(itemDetail.ProjectileVisualRange) or tonumber(itemDetail.PiercingRange) or DEFAULT_PIERCING_RANGE
            ),
            DestroyBeyondPosition = maxPosPart and maxPosPart:IsA("BasePart") and maxPosPart.Position or nil,
        }
    end

    firePlantVisualEvent(
        plot,
        fireCFrame.Position,
        "Projectile",
        projName,
        fireCFrame,
        initialTargetPos,
        targetZombieModel,
        arcHeight,
        speedMult,
        ownerUserId,
        projectileVisualConfig
    )

    task.delay(flightTime, function()
        if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then return end

        if itemDetail.Piercing then
            local targets = collectPiercingTargets(plant, fireCFrame.Position, shotDirection, itemDetail, plot, targetZombieModel)
            for index, target in ipairs(targets) do
                local hitDamage = attackDamage
                if index > 1 then
                    local damageScale = tonumber(itemDetail.PiercingDamageScale) or DEFAULT_PIERCING_DAMAGE_SCALE
                    hitDamage = math.max(1, math.floor(attackDamage * damageScale + 0.5))
                end

                applyProjectileHit(plant, target.Model, itemDetail, hitDamage, plot, speedMult, ownerUserId, shotDirection)
            end

            return
        end

        if not targetZombieModel.Parent or not targetHum or not targetHum.Parent or targetHum.Health <= 0 then return end
        applyProjectileHit(plant, targetZombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
    end)
end

-- 3. 射手类植物 AI
function PlantCombatAI.StartIdleAnimation(plant, itemDetail)
    if plant:GetAttribute("PlantCombatIdleStarted") then
        return
    end
    plant:SetAttribute("PlantCombatIdleStarted", true)

    task.spawn(function()
        local idleAnimTrack = nil
        local animator = getPlantAnimator(plant)

        idleAnimTrack = loadPlantAnimation(animator, itemDetail.IdleAnimId, Enum.AnimationPriority.Idle, true)
        if idleAnimTrack then
            idleAnimTrack:Play(0.1)
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
        local plantRowNum = getLawnRowFromGridName(plant:GetAttribute("GridName"))
        local usesFrontAreaAttack = isFrontAreaAttack(itemDetail)

        local animator = getPlantAnimator(plant)

        local idleAnimTrack = nil
        idleAnimTrack = loadPlantAnimation(animator, itemDetail.IdleAnimId, Enum.AnimationPriority.Idle, true)
        if idleAnimTrack then
            idleAnimTrack:Play(0.1)
        end

        while plant.Parent do
            local hp = plant:GetAttribute("Health") or 0
            if hp <= 0 or plant:GetAttribute("IsDead") then task.wait(0.5); continue end

            local speedMult = GetSafeGameSpeed(plot)
            local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
            if not rootPart then task.wait(0.5); continue end

            local hitParts = {}
            if not usesFrontAreaAttack then
                local overlapParams = OverlapParams.new()
                overlapParams.FilterType = Enum.RaycastFilterType.Exclude
                overlapParams.FilterDescendantsInstances = {plant}

                local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -50)
                local checkSize = Vector3.new(SHOOTER_TARGET_WIDTH, 5, 100)
                hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
            end

            local targetZombieModel, targetHum = nil, nil
            local minDistance = math.huge

            if usesFrontAreaAttack then
                local frontTargets = collectFrontAreaTargets(plant, rootPart, itemDetail, plot)
                local firstTarget = frontTargets[1]
                if firstTarget then
                    targetZombieModel = firstTarget.Model
                    targetHum = firstTarget.Humanoid
                end
            else
            for _, part in ipairs(hitParts) do
                if part.CollisionGroup == "Zombies" then
                    local zModel = part:FindFirstAncestorOfClass("Model")
                    if zModel then
                        -- 1：对比僵尸和地块的主人 ID
                        local zombieOwnerId = zModel:GetAttribute("OwnerId")
                        local plotOwnerId = plot and plot:GetAttribute("OwnerId")

                        -- 如果僵尸有主人，地块也有主人，且两者不是同一个人，说明是别人家的僵尸！忽略
                        if zombieOwnerId and plotOwnerId and zombieOwnerId ~= plotOwnerId then
                            continue
                        end

                        local zombieRowNum = tonumber(zModel:GetAttribute("LaneRow"))
                        if plantRowNum and zombieRowNum and plantRowNum ~= zombieRowNum then
                            continue
                        end

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
            end

            if targetZombieModel and targetHum then
                if itemDetail.AttackAnimation and itemDetail.AttackAnimation ~= "" then
                    firePlantVisualEvent(plot, rootPart.Position, "Attack", plant, itemDetail.AttackAnimation, speedMult, plot and plot:GetAttribute("OwnerId"))
                end

                local windUpTime = math.min(0.3, attackInterval * 0.2) / speedMult
                task.wait(windUpTime)

                if plant.Parent and (plant:GetAttribute("Health") or 0) > 0 then
                    if usesFrontAreaAttack then
                        FireFrontAreaAttack(plant, itemDetail, attackDamage, plot)
                    else
                        FireProjectile(plant, targetZombieModel, targetHum, itemDetail, attackDamage, plot)
                    end
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

-- 4. 爆炸类植物 AI ( 已重构：纯起爆逻辑)
function PlantCombatAI.TriggerExplosion(plant, itemDetail, mutationLevel)
    -- 防多次数起爆锁
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

                    -- 瞬间变黑，不再调用 FlashZombieRed
                    zModel:SetAttribute("IsCharred", true)

                    for _, p in pairs(zModel:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Color = Color3.fromRGB(30, 30, 30)
                            p.Material = Enum.Material.Slate -- 变成粗糙的焦炭质感
                        end
                        if p:IsA("MeshPart") then
                            p.TextureID = "" -- 剥离模型自转带的彩色贴图片
                        end
                        if p:IsA("Decal") or p:IsA("Texture") then
                            p.Transparency = 1 -- 隐藏脸部/表面贴图片
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

-- src/server/Services/PlantCombatAI.luau
local PlantCombatAI = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local CombatRegistry = require(script.Parent.CombatRegistry)

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
local DEFAULT_PIERCING_MAX_TARGETS = 5
local DEFAULT_PIERCING_HIT_EFFECT_LIMIT = 3
local DEFAULT_CHAIN_PROJECTILE_RANGE = 100
local DEFAULT_CHAIN_PROJECTILE_EXTRA_TARGETS = 3
local DEFAULT_CHAIN_PROJECTILE_DAMAGE_SCALE = 1
local DEFAULT_CHAIN_PROJECTILE_SPEED_MULTIPLIER = 1
local SHOOTER_TARGET_WIDTH = 6
local NORMAL_PROJECTILE_TARGET_MIN_Y_OFFSET = 1.2
local NORMAL_PROJECTILE_TARGET_MAX_Y_OFFSET = 1.8
local EVENT_BOSS_PROJECTILE_MIN_HEIGHT_SCALE = 0.45
local EVENT_BOSS_PROJECTILE_MAX_HEIGHT_SCALE = 0.7
local EVENT_BOSS_PROJECTILE_XZ_JITTER_RADIUS = 1.75
local DAMAGE_TEXT_BATCH_WINDOW = 0.05
local SUNSHROOM_HEAL_VFX_DEBUG = false
local CARROT_CANNON_ATTACK_DEBUG = false -- 临时调试萝卜加农炮攻击动画事件。
local warnedProjectileIssues = {}
local warnedAnimationIssues = {}
local failedAnimationIds = {}
local animationLengthCache = {}
local activeGroundEffects = {}
local activeSlowRestores = setmetatable({}, { __mode = "k" })
local pendingDamageTextByPlayer = setmetatable({}, { __mode = "k" })
local nextGroundEffectId = 0
local zombossBossFightServiceLoaded = false
local zombossBossFightService = nil
local warnedZombossBossFightServiceLoadFailure = false

local function getZombossBossFightService()
    if not zombossBossFightServiceLoaded then
        local ok, serviceOrErr = pcall(function()
            return require(script.Parent.ZombossBossFightService)
        end)

        if ok then
            zombossBossFightService = serviceOrErr
            zombossBossFightServiceLoaded = true
        elseif not warnedZombossBossFightServiceLoadFailure then
            warnedZombossBossFightServiceLoadFailure = true
            warn("[PlantCombatAI] Failed to load ZombossBossFightService: " .. tostring(serviceOrErr))
        end
    end

    return zombossBossFightService
end

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

local function getLawnGridCoords(gridName)
    if type(gridName) ~= "string" then
        return nil, nil
    end

    local row, column = string.match(gridName, "^Lawn(%d+)_(%d+)$")
    return tonumber(row), tonumber(column)
end

local function getAuraDamageMultiplier(auraConfig, mutationLevel)
    if type(auraConfig) ~= "table" then
        return 1
    end

    local baseDamageBonus = tonumber(auraConfig.BaseDamageBonus)
    if baseDamageBonus and baseDamageBonus > 0 then
        local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
        local auraBuffMul = tonumber(stats and stats.AuraBuffMul) or 1
        return 1 + baseDamageBonus * auraBuffMul
    end

    local multiplier = tonumber(auraConfig.DamageMultiplier)
    if multiplier and multiplier > 0 then
        return multiplier
    end

    local bonus = tonumber(auraConfig.DamageBonus)
    if bonus and bonus > 0 then
        return 1 + bonus
    end

    return 1
end

local function getPlantConfigForModel(plantModel)
    if not plantModel then
        return nil
    end

    local plantId = plantModel:GetAttribute("PlantId")
        or plantModel:GetAttribute("YieldPlant")
        or plantModel.Name
    return ItemConfig.Plants[plantId]
end

local function getAttackBuffAuraMultiplier(plant, plot)
    if not plant or not plot then
        return 1
    end

    local plantRow, plantColumn = getLawnGridCoords(plant:GetAttribute("GridName"))
    if not plantRow or not plantColumn then
        return 1
    end

    local lawnFolder = plot:FindFirstChild("Lawn")
    if not lawnFolder then
        return 1
    end

    local bestMultiplier = 1
    for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
        if not lawnPart:IsA("BasePart") then
            continue
        end

        local auraRow, auraColumn = getLawnGridCoords(lawnPart.Name)
        if not auraRow or not auraColumn then
            continue
        end

        for _, auraPlant in ipairs(lawnPart:GetChildren()) do
            if auraPlant:GetAttribute("IsCombatPlant") ~= true
                or auraPlant:GetAttribute("IsDead") == true
                or (tonumber(auraPlant:GetAttribute("Health")) or 0) <= 0
            then
                continue
            end

            local auraDetail = getPlantConfigForModel(auraPlant)
            local auraConfig = auraDetail and auraDetail.AttackBuffAura
            if type(auraConfig) ~= "table" then
                continue
            end

            local gridRadius = math.max(0, math.floor(tonumber(auraConfig.GridRadius) or 1))
            if math.abs(auraRow - plantRow) > gridRadius or math.abs(auraColumn - plantColumn) > gridRadius then
                continue
            end

            local auraMutationLevel = tonumber(auraPlant:GetAttribute("MutationLevel")) or 1
            bestMultiplier = math.max(bestMultiplier, getAuraDamageMultiplier(auraConfig, auraMutationLevel))
        end
    end

    return bestMultiplier
end

local function applyAttackBuffAura(plant, plot, attackDamage)
    attackDamage = math.max(0, tonumber(attackDamage) or 0)
    local auraMultiplier = getAttackBuffAuraMultiplier(plant, plot)
    if auraMultiplier <= 1 then
        return attackDamage
    end

    return math.max(1, math.floor(attackDamage * auraMultiplier + 0.5))
end

local function collectVisualRecipients(plot, originPosition, ownerUserId)
    local recipients = {}
    local recipientSet = {}

    local ownerId = ownerUserId or (plot and plot:GetAttribute("OwnerId"))
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
        return 0
    end

    for _, player in ipairs(recipients) do
        plantAttackVisualRE:FireClient(player, ...)
    end

    return #recipients
end

local function flushDamageTextBatch(player, batch)
    if pendingDamageTextByPlayer[player] ~= batch then
        return
    end

    pendingDamageTextByPlayer[player] = nil
    if not player or not player.Parent then
        return
    end

    local entries = {}
    for zombieModel, entry in pairs(batch.Entries) do
        if zombieModel and zombieModel.Parent and (tonumber(entry.Damage) or 0) > 0 then
            table.insert(entries, {
                Target = zombieModel,
                Damage = entry.Damage,
                OwnerUserId = entry.OwnerUserId,
            })
        end
    end

    if #entries > 0 then
        plantAttackVisualRE:FireClient(player, "DamageTextBatch", entries)
    end
end

local function queueDamageTextForRecipients(recipients, zombieModel, damage, ownerUserId)
    damage = tonumber(damage) or 0
    if damage <= 0 or not zombieModel or not zombieModel.Parent then
        return
    end

    for _, player in ipairs(recipients) do
        if player and player.Parent then
            local batch = pendingDamageTextByPlayer[player]
            if not batch then
                batch = {
                    Entries = {},
                }
                pendingDamageTextByPlayer[player] = batch
                task.delay(DAMAGE_TEXT_BATCH_WINDOW, function()
                    flushDamageTextBatch(player, batch)
                end)
            end

            local entry = batch.Entries[zombieModel]
            if not entry then
                entry = {
                    Damage = 0,
                    OwnerUserId = ownerUserId,
                }
                batch.Entries[zombieModel] = entry
            end

            entry.Damage += damage
            entry.OwnerUserId = ownerUserId or entry.OwnerUserId
        end
    end
end

local function queueDamageText(plot, zombieModel, damage, ownerUserId)
    local rootPart = zombieModel and (zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart)
    if not rootPart then
        return
    end

    local resolvedOwnerId = ownerUserId or (plot and plot:GetAttribute("OwnerId")) or zombieModel:GetAttribute("OwnerId")
    local recipients = collectVisualRecipients(plot, rootPart.Position, resolvedOwnerId)
    queueDamageTextForRecipients(recipients, zombieModel, damage, resolvedOwnerId)
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

local function randomRange(minValue, maxValue)
    return minValue + (maxValue - minValue) * math.random()
end

local function getRandomXZOffset(radius)
    radius = math.max(0, tonumber(radius) or 0)
    if radius <= 0 then
        return Vector3.zero
    end

    local angle = math.random() * math.pi * 2
    local distance = math.random() * radius
    return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function getProjectileTargetPosition(zombieModel, rootPart)
    if not rootPart then
        return nil
    end

    if zombieModel
        and zombieModel:IsA("Model")
        and zombieModel:GetAttribute("IsEventZomboss") == true
    then
        local ok, boundingCFrame, boundingSize = pcall(function()
            return zombieModel:GetBoundingBox()
        end)

        if ok and typeof(boundingCFrame) == "CFrame" and typeof(boundingSize) == "Vector3" and boundingSize.Y > 0 then
            local bottomY = boundingCFrame.Position.Y - boundingSize.Y * 0.5
            local targetY = bottomY + boundingSize.Y * randomRange(
                EVENT_BOSS_PROJECTILE_MIN_HEIGHT_SCALE,
                EVENT_BOSS_PROJECTILE_MAX_HEIGHT_SCALE
            )
            return Vector3.new(rootPart.Position.X, targetY, rootPart.Position.Z)
                + getRandomXZOffset(EVENT_BOSS_PROJECTILE_XZ_JITTER_RADIUS)
        end
    end

    return rootPart.Position
        + Vector3.new(0, randomRange(NORMAL_PROJECTILE_TARGET_MIN_Y_OFFSET, NORMAL_PROJECTILE_TARGET_MAX_Y_OFFSET), 0)
end

local function getActiveEventBossTarget(plot)
    local service = getZombossBossFightService()
    if not service or type(service.GetActiveBossTargetForPlot) ~= "function" then
        return nil, nil, nil
    end

    local ok, bossModel, bossHumanoid, bossRoot = pcall(function()
        return service.GetActiveBossTargetForPlot(plot)
    end)

    if not ok then
        warn("[PlantCombatAI] Failed to read active Zomboss target: " .. tostring(bossModel))
        return nil, nil, nil
    end

    if bossModel and bossHumanoid and bossRoot then
        return bossModel, bossHumanoid, bossRoot
    end

    return nil, nil, nil
end

local function getPiercingMaxTargets(itemDetail)
    local maxTargets = math.floor(tonumber(itemDetail and itemDetail.PiercingMaxTargets) or DEFAULT_PIERCING_MAX_TARGETS)
    return math.max(1, maxTargets)
end

local function getPiercingHitEffectLimit(itemDetail)
    local effectLimit = math.floor(tonumber(itemDetail and itemDetail.PiercingHitEffectLimit) or DEFAULT_PIERCING_HIT_EFFECT_LIMIT)
    return math.max(0, effectLimit)
end

local function collectPiercingTargets(plant, firePosition, shotDirection, itemDetail, plot, primaryTarget, maxTargets)
    local range = math.max(1, tonumber(itemDetail.PiercingRange) or DEFAULT_PIERCING_RANGE)
    local width = math.max(1, tonumber(itemDetail.PiercingWidth) or DEFAULT_PIERCING_WIDTH)
    maxTargets = math.max(1, math.floor(tonumber(maxTargets) or DEFAULT_PIERCING_MAX_TARGETS))
    local flatDir = getFlatUnit(shotDirection, plant and plant:GetPivot().LookVector)

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

    for _, target in ipairs(CombatRegistry.CollectZombiesInBox(plot, nil, firePosition, flatDir, range, width, maxTargets)) do
        addTarget(target.Model)
    end

    table.sort(targets, function(a, b)
        return a.Distance < b.Distance
    end)

    while #targets > maxTargets do
        table.remove(targets)
    end

	return targets
end

local function getChainProjectileConfig(itemDetail)
	local config = itemDetail and itemDetail.ChainProjectile
	if type(config) ~= "table" then
		return nil
	end

	local extraTargets = math.max(0, math.floor(tonumber(config.ExtraTargets) or DEFAULT_CHAIN_PROJECTILE_EXTRA_TARGETS))
	if extraTargets <= 0 then
		return nil
	end

	return {
		ExtraTargets = extraTargets,
		Range = math.max(1, tonumber(config.Range) or DEFAULT_CHAIN_PROJECTILE_RANGE),
		DamageScale = math.max(0, tonumber(config.DamageScale) or DEFAULT_CHAIN_PROJECTILE_DAMAGE_SCALE),
		SpeedMultiplier = math.max(0.01, tonumber(config.SpeedMultiplier) or DEFAULT_CHAIN_PROJECTILE_SPEED_MULTIPLIER),
	}
end

local function findNextChainProjectileTarget(plot, fromPosition, hitTargets, range)
	if typeof(fromPosition) ~= "Vector3" then
		return nil
	end

	for _, target in ipairs(CombatRegistry.CollectZombiesInRadius(plot, fromPosition, range)) do
		local zombieModel = target.Model
		if zombieModel and not hitTargets[zombieModel] and isZombieOwnedByPlot(zombieModel, plot) then
			local humanoid, rootPart = getLivingZombieParts(zombieModel)
			if humanoid and rootPart then
				return {
					Model = zombieModel,
					Humanoid = humanoid,
					RootPart = rootPart,
				}
			end
		end
	end

	return nil
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

-- 查找植物面朝方向前方指定格数的草坪。
local function findFrontLawnPart(plant, plot, gridDistance)
    local sourceLawn = getPlantLawnPart(plant, plot)
    if not (sourceLawn and sourceLawn:IsA("BasePart")) then
        return nil
    end

    local rootPart = plant and (plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart"))
    if not rootPart then
        return nil
    end

    local flatDir = getFlatUnit(rootPart.CFrame.LookVector, sourceLawn.CFrame.LookVector)
    local stepDistance = getLawnStepDistance(sourceLawn, flatDir) * math.max(1, tonumber(gridDistance) or 1)
    local targetPosition = sourceLawn.Position + flatDir * stepDistance
    local containingLawn = findContainingLawnForPosition(plot, targetPosition)
    if containingLawn and containingLawn ~= sourceLawn then
        return containingLawn
    end

    local lawnFolder = plot and plot:FindFirstChild("Lawn")
    if not lawnFolder then
        return nil
    end

    local sideWidth = getLawnSideWidth(sourceLawn, flatDir)
    local bestLawn = nil
    local bestScore = math.huge
    for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
        if not lawnPart:IsA("BasePart") or lawnPart == sourceLawn then
            continue
        end

        local delta = lawnPart.Position - sourceLawn.Position
        local flatDelta = Vector3.new(delta.X, 0, delta.Z)
        local forward = flatDelta:Dot(flatDir)
        local lateral = (flatDelta - flatDir * forward).Magnitude
        if forward >= stepDistance * 0.45
            and forward <= stepDistance * 1.55
            and lateral <= sideWidth * 0.6
        then
            local score = math.abs(forward - stepDistance) + lateral
            if score < bestScore then
                bestScore = score
                bestLawn = lawnPart
            end
        end
    end

    return bestLawn
end

-- 收集目标格子里所有需要治疗的战斗植物。
local function collectDamagedCombatPlants(lawnPart)
    if not lawnPart then
        return {}
    end

    local targets = {}
    for _, child in ipairs(lawnPart:GetChildren()) do
        if not child:IsA("Model")
            or child:GetAttribute("IsCombatPlant") ~= true
            or child:GetAttribute("IsDead") == true
        then
            continue
        end

        local currentHP = tonumber(child:GetAttribute("Health")) or 0
        local maxHP = tonumber(child:GetAttribute("MaxHealth")) or 0
        if currentHP <= 0 or maxHP <= 0 or currentHP >= maxHP then
            continue
        end

        table.insert(targets, child)
    end

    return targets
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
    local width = math.max(1, tonumber(config.Width) or getLawnSideWidth(lawnPart, flatDir))
    local queryOrigin = center - flatDir * (range * 0.5)

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

    for _, target in ipairs(CombatRegistry.CollectZombiesInBox(plot, plantRowNum, queryOrigin, flatDir, range, width)) do
        addTarget(target.Model)
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
    if zombieModel:GetAttribute("IsEventZomboss") == true then
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

local function showGroundDamageText(plot, zombieModel, damage, ownerUserId)
    queueDamageText(plot, zombieModel, damage, ownerUserId)
end

local function damageZombiesInLawn(lawnPart, plot, damage)
    if not lawnPart or not lawnPart.Parent or damage <= 0 then
        return
    end

    local rowNum = getLawnRowFromGridName(lawnPart.Name)
    local flatDir = getFlatUnit(lawnPart.CFrame.LookVector, Vector3.new(0, 0, -1))
    local range = math.max(0.1, lawnPart.Size.Z)
    local width = math.max(0.1, lawnPart.Size.X)
    local origin = lawnPart.Position - flatDir * (range * 0.5)

    for _, target in ipairs(CombatRegistry.CollectZombiesInBox(plot, rowNum, origin, flatDir, range, width)) do
        local targetHum = target.Humanoid
        local targetModel = target.Model
        if targetHum and targetHum.Health > 0 then
            targetHum.Health = math.max(0, targetHum.Health - damage)
            showGroundDamageText(plot, targetModel, damage)
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

    if groundEffect.MaxOnePerGrid and active then
        active.expiresAt = now + duration
        active.damagePerTick = math.max(active.damagePerTick or 0, damagePerTick)
        firePlantVisualEvent(plot, lawnPart.Position, "GroundEffectRefresh", active.visualId, duration)
        return
    end

    nextGroundEffectId += 1
    local visualId = tostring(os.clock()) .. "_" .. tostring(nextGroundEffectId)

    local state = {
        visualId = visualId,
        expiresAt = now + duration,
        tickInterval = tickInterval,
        damagePerTick = damagePerTick,
        plot = plot,
        lawnPart = lawnPart,
    }
    activeGroundEffects[lawnPart] = state

    firePlantVisualEvent(
        plot,
        lawnPart.Position,
        "GroundEffectStart",
        visualId,
        effectName,
        lawnPart.CFrame,
        lawnPart.Size,
        duration,
        plot and plot:GetAttribute("OwnerId")
    )

    task.spawn(function()
        while activeGroundEffects[lawnPart] == state and os.clock() < state.expiresAt do
            damageZombiesInLawn(lawnPart, state.plot, state.damagePerTick)
            task.wait(state.tickInterval)
        end

        if activeGroundEffects[lawnPart] == state then
            activeGroundEffects[lawnPart] = nil
        end

        firePlantVisualEvent(state.plot, lawnPart.Position, "GroundEffectStop", state.visualId)
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
    if zombieModel:GetAttribute("IsEventZomboss") == true then
        return
    end

    local moveMultiplier = math.clamp(tonumber(slowConfig.MoveMultiplier) or 0.5, 0, 1)
    local duration = tonumber(slowConfig.Duration) or 2
    local adjustedDuration = duration / math.max(tonumber(speedMult) or 1, 0.01)
    local tintColor = slowConfig.Color or Color3.fromRGB(80, 180, 255)
    local now = os.clock()
    local expiresAt = now + adjustedDuration
    local state = activeSlowRestores[zombieModel]
    local currentMultiplier = tonumber(zombieModel:GetAttribute("SlowMultiplier")) or 1
    local effectiveMultiplier = math.min(currentMultiplier, moveMultiplier)

    zombieModel:SetAttribute("SlowMultiplier", effectiveMultiplier)
    zombieModel:SetAttribute("IceSlowExpiresAt", math.max(tonumber(zombieModel:GetAttribute("IceSlowExpiresAt")) or 0, expiresAt))

    if state then
        state.expiresAt = math.max(state.expiresAt or 0, expiresAt)
        return
    end

    local originalColors = {}
    local cachedParts = CombatRegistry.GetCachedParts(zombieModel)
    for _, part in ipairs(cachedParts.BaseParts) do
        if part:IsA("BasePart") then
            originalColors[part] = part.Color
            if not zombieModel:GetAttribute("IsCharred") then
                part.Color = tintColor
            end
        end
    end

    if humanoid.WalkSpeed > 0 then
        humanoid.WalkSpeed *= effectiveMultiplier
    end

    state = {
        expiresAt = expiresAt,
        originalColors = originalColors,
    }
    activeSlowRestores[zombieModel] = state

    task.spawn(function()
        while zombieModel and zombieModel.Parent and activeSlowRestores[zombieModel] == state do
            local remaining = (tonumber(zombieModel:GetAttribute("IceSlowExpiresAt")) or state.expiresAt or 0) - os.clock()
            if remaining <= 0 then
                break
            end
            task.wait(math.min(remaining, 0.25))
        end

        if not zombieModel or not zombieModel.Parent or activeSlowRestores[zombieModel] ~= state then
            return
        end

        activeSlowRestores[zombieModel] = nil
        zombieModel:SetAttribute("SlowMultiplier", nil)
        zombieModel:SetAttribute("IceSlowExpiresAt", nil)

        local currentHumanoid = zombieModel:FindFirstChildOfClass("Humanoid")
        if not currentHumanoid or currentHumanoid.Health <= 0 or zombieModel:GetAttribute("IsCharred") then
            return
        end

        for part, originalColor in pairs(state.originalColors) do
            if part and part.Parent then
                part.Color = originalColor
                if part:GetAttribute("IceSlowOriginalColor") ~= nil then
                    part:SetAttribute("IceSlowOriginalColor", nil)
                end
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

    for _, target in ipairs(CombatRegistry.CollectZombiesInRadius(plot, centerPosition, radius, primaryZombieModel)) do
        local targetModel = target.Model
        local targetHum = target.Humanoid
        if targetHum and targetHum.Health > 0 then
            targetHum.Health = math.max(0, targetHum.Health - splashDamage)
            showGroundDamageText(plot, targetModel, splashDamage)

            if itemDetail.SplashAppliesSlow then
                applySlowOnHit(targetModel, targetHum, itemDetail, speedMult)
            end
        end
    end
end

function PlantCombatAI.ShowDamageText(zombieModel, damage)
    if not zombieModel or not zombieModel.Parent then
        return
    end

    queueDamageText(nil, zombieModel, damage, zombieModel:GetAttribute("OwnerId"))
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

local function destroyExistingReactiveEffects(plant, effectInstanceName)
    if not plant or type(effectInstanceName) ~= "string" or effectInstanceName == "" then
        return
    end

    for _, desc in ipairs(plant:GetDescendants()) do
        if desc.Name == effectInstanceName then
            desc:Destroy()
        end
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

    local effectInstanceName = effectName .. "_ReactiveEffect"
    destroyExistingReactiveEffects(plant, effectInstanceName)

    local effect = template:Clone()
    effect.Name = effectInstanceName
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

        for _, target in ipairs(CombatRegistry.CollectZombiesInRadius(plot, currentRootPart.Position, radius)) do
            local zombieModel = target.Model
            local targetHum = target.Humanoid
            if targetHum and targetHum.Health > 0 then
                targetHum.Health = math.max(0, targetHum.Health - damage)
                showGroundDamageText(plot, zombieModel, damage)
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
local function applyProjectileHit(plant, zombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection, visualAction)
    local targetHum, targetRoot = getLivingZombieParts(zombieModel)
    if not targetHum or not targetRoot then
        return false
    end

    local healthBefore = targetHum.Health
    local newHealth = math.max(0, healthBefore - attackDamage)
    local actualDamage = math.max(0, healthBefore - newHealth)
    if actualDamage > 0 and zombieModel:GetAttribute("IsEventZomboss") == true then
        local service = getZombossBossFightService()
        if service and type(service.RecordPlayerDamage) == "function" then
            service.RecordPlayerDamage(zombieModel, ownerUserId, actualDamage)
        end
    end
    targetHum.Health = newHealth
    applySlowOnHit(zombieModel, targetHum, itemDetail, speedMult)

    if visualAction == "DamageText" then
        showGroundDamageText(plot, zombieModel, attackDamage, ownerUserId)
    elseif visualAction ~= "None" then
        showGroundDamageText(plot, zombieModel, attackDamage, ownerUserId)
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
            nil,
            hitPos,
            itemDetail.HitEffectTexture,
            itemDetail.HitEffectColor,
            ownerUserId
        )
    end

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

local function fireProjectileVisualSegment(plot, projectileName, fireCFrame, targetPosition, targetZombieModel, arcHeight, speedMult, ownerUserId, projectileVisualConfig)
	firePlantVisualEvent(
		plot,
		fireCFrame.Position,
		"Projectile",
		projectileName,
		fireCFrame,
		targetPosition,
		targetZombieModel,
		arcHeight,
		speedMult,
		ownerUserId,
		projectileVisualConfig
	)
end

local function runChainProjectile(plant, itemDetail, attackDamage, plot, speedMult, ownerUserId, projectileName, arcHeight, hitTargets, startPosition)
	local chainConfig = getChainProjectileConfig(itemDetail)
	if not chainConfig then
		return
	end

	local currentPosition = startPosition
	local chainDamage = math.max(1, math.floor((tonumber(attackDamage) or 0) * chainConfig.DamageScale + 0.5))
	local chainSpeedMult = math.max(0.01, speedMult * chainConfig.SpeedMultiplier)

	for _ = 1, chainConfig.ExtraTargets do
		if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then
			return
		end

		local nextTarget = findNextChainProjectileTarget(plot, currentPosition, hitTargets, chainConfig.Range)
		if not nextTarget then
			return
		end

		local targetPosition = getProjectileTargetPosition(nextTarget.Model, nextTarget.RootPart)
		local offset = targetPosition - currentPosition
		local fireCFrame = offset.Magnitude > 0.001 and CFrame.lookAt(currentPosition, targetPosition) or CFrame.new(currentPosition)
		local flightTime = math.max(0.05, offset.Magnitude / (PROJECTILE_SPEED * chainSpeedMult))

		hitTargets[nextTarget.Model] = true
		fireProjectileVisualSegment(plot, projectileName, fireCFrame, targetPosition, nextTarget.Model, arcHeight, chainSpeedMult, ownerUserId)
		task.wait(flightTime)

		if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then
			return
		end

		local currentHumanoid, currentRoot = getLivingZombieParts(nextTarget.Model)
		if not currentHumanoid or not currentRoot then
			return
		end

		local shotDirection = getFlatUnit(targetPosition - currentPosition, currentRoot.CFrame.LookVector)
		local didHit = applyProjectileHit(plant, nextTarget.Model, itemDetail, chainDamage, plot, speedMult, ownerUserId, shotDirection)
		if not didHit then
			return
		end

		currentPosition = getProjectileTargetPosition(nextTarget.Model, currentRoot)
	end
end

local function FireProjectile(plant, targetZombieModel, _targetHum, itemDetail, attackDamage, plot)
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
    local initialTargetPos = getProjectileTargetPosition(targetZombieModel, targetRoot)
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

	fireProjectileVisualSegment(plot, projName, fireCFrame, initialTargetPos, targetZombieModel, arcHeight, speedMult, ownerUserId, projectileVisualConfig)

    task.delay(flightTime, function()
        if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then return end

        if itemDetail.Piercing then
            local maxTargets = getPiercingMaxTargets(itemDetail)
            local hitEffectLimit = getPiercingHitEffectLimit(itemDetail)
            local targets = collectPiercingTargets(plant, fireCFrame.Position, shotDirection, itemDetail, plot, targetZombieModel, maxTargets)
            for index, target in ipairs(targets) do
                local hitDamage = attackDamage
                if index > 1 then
                    local damageScale = tonumber(itemDetail.PiercingDamageScale) or DEFAULT_PIERCING_DAMAGE_SCALE
                    hitDamage = math.max(1, math.floor(attackDamage * damageScale + 0.5))
                end

                local visualAction = index > hitEffectLimit and "DamageText" or "Hit"
                applyProjectileHit(plant, target.Model, itemDetail, hitDamage, plot, speedMult, ownerUserId, shotDirection, visualAction)
            end

            return
        end

		local currentTargetHum, currentTargetRoot = getLivingZombieParts(targetZombieModel)
		if not currentTargetHum or not currentTargetRoot then return end

		local hitPosition = getProjectileTargetPosition(targetZombieModel, currentTargetRoot)
		local didHit = applyProjectileHit(plant, targetZombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
		if not didHit then return end

		local hitTargets = { [targetZombieModel] = true }
		runChainProjectile(plant, itemDetail, attackDamage, plot, speedMult, ownerUserId, projName, arcHeight, hitTargets, hitPosition)
	end)
end

-- 3. 射手类植物 AI
local function FireEventBossAttack(plant, targetZombieModel, targetHum, itemDetail, attackDamage, plot)
    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    local targetRoot = targetZombieModel and (targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart)
    if not rootPart or not targetRoot then
        return
    end

    local speedMult = GetSafeGameSpeed(plot)
    local ownerUserId = plot and plot:GetAttribute("OwnerId")
    local targetPosition = getProjectileTargetPosition(targetZombieModel, targetRoot)
    local shotDirection = getFlatUnit(targetPosition - rootPart.Position, rootPart.CFrame.LookVector)
    local projectileName = itemDetail.ProjectileName

    if type(projectileName) == "string" and projectileName ~= "" then
        local fireCFrame = rootPart.CFrame * CFrame.new(0, 1.5, -1.5)
        local posNode = plant:FindFirstChild("pos", true) or plant:FindFirstChild("Pos", true)
        if posNode then
            if posNode:IsA("Attachment") then
                fireCFrame = posNode.WorldCFrame
            elseif posNode:IsA("BasePart") then
                fireCFrame = posNode.CFrame
            end
        end

        local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo")
        if ammoFolder and ammoFolder:FindFirstChild(projectileName) then
            local arcHeight = itemDetail.ArcHeight or 0
            local distance = (targetPosition - fireCFrame.Position).Magnitude
            local flightTime = math.max(0.05, distance / (PROJECTILE_SPEED * speedMult))
            fireProjectileVisualSegment(plot, projectileName, fireCFrame, targetPosition, targetZombieModel, arcHeight, speedMult, ownerUserId)

            task.delay(flightTime, function()
                if not plant.Parent or (plant:GetAttribute("Health") or 0) <= 0 or plant:GetAttribute("IsDead") then
                    return
                end

                applyProjectileHit(plant, targetZombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
            end)
            return
        end

        warnProjectileOnce(projectileName, "ReplicatedStorage.Ammo template not found on server")
    end

    applyProjectileHit(plant, targetZombieModel, itemDetail, attackDamage, plot, speedMult, ownerUserId, shotDirection)
end

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

function PlantCombatAI.StartFrontHealAI(plant, itemDetail, mutationLevel, plot)
    local healConfig = itemDetail and itemDetail.FrontHeal
    if type(healConfig) ~= "table" or plant:GetAttribute("FrontHealAIStarted") then
        return
    end

    plant:SetAttribute("FrontHealAIStarted", true)

    task.spawn(function()
        local interval = math.max(0.1, tonumber(healConfig.Interval) or 5)
        local baseHealAmount = math.max(1, math.floor(tonumber(healConfig.Amount) or 1))
        local gridDistance = math.max(1, tonumber(healConfig.GridDistance) or 1)

        while plant.Parent and (tonumber(plant:GetAttribute("Health")) or 0) > 0 and plant:GetAttribute("IsDead") ~= true do
            local speedMult = GetSafeGameSpeed(plot)
            task.wait(interval / speedMult)

            if not plant.Parent or (tonumber(plant:GetAttribute("Health")) or 0) <= 0 or plant:GetAttribute("IsDead") == true then
                break
            end

            local frontLawn = findFrontLawnPart(plant, plot, gridDistance)
            local targetPlants = collectDamagedCombatPlants(frontLawn)
            if #targetPlants > 0 then
                -- 按当前变异等级计算治疗倍率，支持后续战斗中动态变异。
                local currentMutationLevel = tonumber(plant:GetAttribute("MutationLevel")) or mutationLevel or 1
                local stats = ItemConfig.MutationStats[currentMutationLevel] or ItemConfig.MutationStats[1]
                local healMul = tonumber(stats and stats.HealMul) or 1
                local healAmount = math.max(1, math.floor(baseHealAmount * healMul + 0.5))
                local healedCount = 0
                local debugTargetName = nil
                local debugOldHP = nil
                local debugNewHP = nil

                for _, targetPlant in ipairs(targetPlants) do
                    local currentHP = math.max(0, tonumber(targetPlant:GetAttribute("Health")) or 0)
                    local maxHP = math.max(1, tonumber(targetPlant:GetAttribute("MaxHealth")) or currentHP)
                    local newHP = math.min(maxHP, currentHP + healAmount)
                    if newHP <= currentHP then
                        continue
                    end

                    targetPlant:SetAttribute("Health", newHP)
                    targetPlant:SetAttribute("LastHealedAt", os.clock())
                    healedCount += 1

                    if not debugTargetName then
                        debugTargetName = targetPlant.Name
                        debugOldHP = currentHP
                        debugNewHP = newHP
                    end
                end

                if healedCount > 0 then

                    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
                    local recipients = firePlantVisualEvent(
                        plot,
                        rootPart and rootPart.Position,
                        "PlantVFX",
                        plant,
                        plot and plot:GetAttribute("OwnerId")
                    )

                    if SUNSHROOM_HEAL_VFX_DEBUG then
                        print(("[SunShroomHealVFX][Server] healed targets=%d first=%s hp=%s->%s amount=%s recipients=%d root=%s"):format(
                            healedCount,
                            tostring(debugTargetName),
                            tostring(debugOldHP),
                            tostring(debugNewHP),
                            tostring(healAmount),
                            tonumber(recipients) or 0,
                            rootPart and rootPart:GetFullName() or "nil"
                        ))
                    end
                end
            end
        end

        if plant then
            plant:SetAttribute("FrontHealAIStarted", nil)
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

            local targetZombieModel, targetHum = nil, nil
            local isEventBossTarget = false

            local eventBossModel, eventBossHum, eventBossRoot = getActiveEventBossTarget(plot)
            if eventBossModel and eventBossHum and eventBossRoot then
                targetZombieModel = eventBossModel
                targetHum = eventBossHum
                isEventBossTarget = true
            elseif usesFrontAreaAttack then
                local frontTargets = collectFrontAreaTargets(plant, rootPart, itemDetail, plot)
                local firstTarget = frontTargets[1]
                if firstTarget then
                    targetZombieModel = firstTarget.Model
                    targetHum = firstTarget.Humanoid
                end
            else
                local targetRoot
                targetZombieModel, targetHum, targetRoot = CombatRegistry.FindNearestZombieInLane(
                    plot,
                    plantRowNum,
                    rootPart.Position,
                    rootPart.CFrame.LookVector,
                    100,
                    SHOOTER_TARGET_WIDTH
                )
                if not targetRoot then
                    targetZombieModel = nil
                    targetHum = nil
                end

            end

            if targetZombieModel and targetHum then
                if itemDetail.AttackAnimation and itemDetail.AttackAnimation ~= "" then
                    local recipientCount = firePlantVisualEvent(plot, rootPart.Position, "Attack", plant, itemDetail.AttackAnimation, speedMult, plot and plot:GetAttribute("OwnerId"))
                    if CARROT_CANNON_ATTACK_DEBUG and itemDetail.Id == "CarrotCannon" then
                        print(("[CarrotCannonAttackDebug][Server] attack event plant=%s target=%s animation=%s recipients=%d speed=%.2f"):format(
                            tostring(plant and plant:GetFullName() or nil),
                            tostring(targetZombieModel and targetZombieModel.Name or nil),
                            tostring(itemDetail.AttackAnimation),
                            recipientCount,
                            speedMult
                        ))
                    end
                end

                local windUpTime = math.min(0.3, attackInterval * 0.2) / speedMult
                task.wait(windUpTime)

	                if plant.Parent and (plant:GetAttribute("Health") or 0) > 0 then
	                    local currentMutationLevel = tonumber(plant:GetAttribute("MutationLevel")) or mutationLevel or 1
	                    local stats = ItemConfig.MutationStats[currentMutationLevel] or ItemConfig.MutationStats[1]
	                    local attackDamage = math.floor(baseAttackDamage * stats.DamageMul)
	                    local buffedAttackDamage = applyAttackBuffAura(plant, plot, attackDamage)
	                    if isEventBossTarget then
	                        FireEventBossAttack(plant, targetZombieModel, targetHum, itemDetail, buffedAttackDamage, plot)
	                    elseif usesFrontAreaAttack then
	                        FireFrontAreaAttack(plant, itemDetail, buffedAttackDamage, plot)
	                    else
	                        FireProjectile(plant, targetZombieModel, targetHum, itemDetail, buffedAttackDamage, plot)
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
local function charZombieModel(zombieModel)
    if not zombieModel or not zombieModel.Parent then
        return
    end

    zombieModel:SetAttribute("IsCharred", true)
    local cachedParts = CombatRegistry.GetCachedParts(zombieModel)

    for _, part in ipairs(cachedParts.BaseParts) do
        if part and part.Parent then
            part.Color = Color3.fromRGB(30, 30, 30)
            part.Material = Enum.Material.Slate
        end
    end

    for _, meshPart in ipairs(cachedParts.MeshParts) do
        if meshPart and meshPart.Parent then
            meshPart.TextureID = ""
        end
    end

    for _, surface in ipairs(cachedParts.SurfaceDetails) do
        if surface and surface.Parent then
            surface.Transparency = 1
        end
    end

    for _, item in ipairs(cachedParts.DestroyOnChar) do
        if item and item.Parent then
            item:Destroy()
        end
    end
end

function PlantCombatAI.TriggerExplosion(plant, itemDetail, mutationLevel)
    if plant:GetAttribute("Exploded") then return end
    -- 防多次数起爆锁
    if plant:GetAttribute("Exploded") then return end
    plant:SetAttribute("Exploded", true)

    local rootPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
    if not rootPart then return end

    local myPlot = plant.Parent and plant.Parent.Parent and plant.Parent.Parent.Parent
    local flatDir = getFlatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
    local queryRow = nil
    local queryWidth = 14
    local queryRange = 14
    local queryOrigin = rootPart.Position - flatDir * (queryRange * 0.5)
    if itemDetail.ExplosionType == "Row" then
        queryRow = getLawnRowFromGridName(plant:GetAttribute("GridName"))
        queryWidth = 4
        queryRange = 100
        queryOrigin = rootPart.Position - flatDir * (queryRange * 0.5)
    end

    local registryTargets = CombatRegistry.CollectZombiesInBox(myPlot, queryRow, queryOrigin, flatDir, queryRange, queryWidth)
    local damagedZombies = {}

    for _, target in ipairs(registryTargets) do
        local zModel = target.Model
        local zHum = target.Humanoid
        if zModel and zHum and zHum.Health > 0 and not damagedZombies[zModel] then
            damagedZombies[zModel] = true

            local baseExplosionDamage = itemDetail.ExplosionDamage or 1800
            local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
            local explosionDamage = math.floor(baseExplosionDamage * stats.DamageMul)

            zHum.Health = zHum.Health - explosionDamage
            showGroundDamageText(myPlot, zModel, explosionDamage)
            charZombieModel(zModel)
        end
    end

    firePlantVisualEvent(
        myPlot,
        rootPart.Position,
        "ExplosionBurst",
        rootPart.Position,
        itemDetail.ExplosionType,
        myPlot and myPlot:GetAttribute("OwnerId")
    )

    local cachedPlantParts = CombatRegistry.GetCachedParts(plant)
    for _, p in ipairs(cachedPlantParts.BaseParts) do
        if p and p.Parent then
            p.Transparency = 1
        end
    end
    for _, p in ipairs(cachedPlantParts.VisualEffects) do
        if p and p.Parent then
            p.Enabled = false
        end
    end
    task.delay(1, function() if plant then plant:Destroy() end end)
end

return PlantCombatAI

-- src/server/Services/CombatRegistry.luau
local CombatRegistry = {}

local registryByPlot = setmetatable({}, { __mode = "k" })
local recordByModel = setmetatable({}, { __mode = "k" })
local cachedPartsByModel = setmetatable({}, { __mode = "k" })

local function getRowKey(rowNum)
    local normalized = tonumber(rowNum)
    if normalized then
        return normalized
    end

    return tostring(rowNum or "_")
end

local function getPlotState(plot)
    if not plot then
        return nil
    end

    local state = registryByPlot[plot]
    if not state then
        state = {
            Plants = {},
            Zombies = {},
            PlantsByRow = {},
            ZombiesByRow = {},
        }
        registryByPlot[plot] = state
    end

    return state
end

local function getFlatVector(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function getFlatUnit(vector, fallback)
    if typeof(vector) == "Vector3" then
        local flat = getFlatVector(vector)
        if flat.Magnitude > 0.001 then
            return flat.Unit
        end
    end

    if typeof(fallback) == "Vector3" then
        local flatFallback = getFlatVector(fallback)
        if flatFallback.Magnitude > 0.001 then
            return flatFallback.Unit
        end
    end

    return Vector3.new(0, 0, -1)
end

local function cacheModelParts(model)
    local cached = {
        BaseParts = {},
        MeshParts = {},
        VisualEffects = {},
        SurfaceDetails = {},
        DestroyOnChar = {},
        Joints = {},
        Sounds = {},
    }

    if not model then
        return cached
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(cached.BaseParts, descendant)
            if descendant:IsA("MeshPart") then
                table.insert(cached.MeshParts, descendant)
            end
        elseif descendant:IsA("ParticleEmitter")
            or descendant:IsA("Light")
            or descendant:IsA("Beam")
            or descendant:IsA("Highlight")
            or descendant:IsA("Trail")
        then
            table.insert(cached.VisualEffects, descendant)
        elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
            table.insert(cached.SurfaceDetails, descendant)
        elseif descendant:IsA("Clothing")
            or descendant:IsA("Shirt")
            or descendant:IsA("Pants")
            or descendant:IsA("ShirtGraphic")
            or descendant:IsA("CharacterMesh")
        then
            table.insert(cached.DestroyOnChar, descendant)
        elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
            table.insert(cached.Joints, descendant)
        elseif descendant:IsA("Sound") then
            table.insert(cached.Sounds, descendant)
        end
    end

    return cached
end

function CombatRegistry.GetCachedParts(model)
    if not model then
        return cacheModelParts(nil)
    end

    local cached = cachedPartsByModel[model]
    if not cached then
        cached = cacheModelParts(model)
        cachedPartsByModel[model] = cached
    end

    return cached
end

function CombatRegistry.RefreshCachedParts(model)
    if not model then
        return cacheModelParts(nil)
    end

    local cached = cacheModelParts(model)
    cachedPartsByModel[model] = cached

    local record = recordByModel[model]
    if record then
        record.CachedParts = cached
    end

    return cached
end

local function removeRecord(record)
    if not record then
        return
    end

    local state = registryByPlot[record.Plot]
    if state then
        local allBucket = record.Kind == "Zombie" and state.Zombies or state.Plants
        allBucket[record.Model] = nil

        local rowBuckets = record.Kind == "Zombie" and state.ZombiesByRow or state.PlantsByRow
        local rowBucket = rowBuckets[record.RowKey]
        if rowBucket then
            rowBucket[record.Model] = nil
            if next(rowBucket) == nil then
                rowBuckets[record.RowKey] = nil
            end
        end
    end

    if record.Model then
        recordByModel[record.Model] = nil
    end
end

local function registerModel(kind, plot, model, rowNum, humanoid, rootPart)
    if not plot or not model or not model.Parent then
        return nil
    end

    rootPart = rootPart or model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
    if not rootPart then
        return nil
    end

    if kind == "Zombie" then
        humanoid = humanoid or model:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return nil
        end
    end

    removeRecord(recordByModel[model])

    local state = getPlotState(plot)
    local rowKey = getRowKey(rowNum)
    local record = {
        Kind = kind,
        Plot = plot,
        Model = model,
        Row = tonumber(rowNum),
        RowKey = rowKey,
        Humanoid = humanoid,
        RootPart = rootPart,
        CachedParts = CombatRegistry.GetCachedParts(model),
    }

    recordByModel[model] = record

    if kind == "Zombie" then
        state.Zombies[model] = record
        state.ZombiesByRow[rowKey] = state.ZombiesByRow[rowKey] or {}
        state.ZombiesByRow[rowKey][model] = record
    else
        state.Plants[model] = record
        state.PlantsByRow[rowKey] = state.PlantsByRow[rowKey] or {}
        state.PlantsByRow[rowKey][model] = record
    end

    return record
end

function CombatRegistry.RegisterPlant(plot, plant, rowNum, rootPart)
    return registerModel("Plant", plot, plant, rowNum, nil, rootPart)
end

function CombatRegistry.UnregisterPlant(plant)
    removeRecord(recordByModel[plant])
end

function CombatRegistry.RegisterZombie(plot, zombie, rowNum, humanoid, rootPart)
    return registerModel("Zombie", plot, zombie, rowNum, humanoid, rootPart)
end

function CombatRegistry.UnregisterZombie(zombie)
    removeRecord(recordByModel[zombie])
end

function CombatRegistry.UpdateZombieRow(zombie, rowNum, rootPart)
    local record = recordByModel[zombie]
    if not record or record.Kind ~= "Zombie" then
        return nil
    end

    local state = registryByPlot[record.Plot]
    if not state then
        return nil
    end

    local oldBucket = state.ZombiesByRow[record.RowKey]
    if oldBucket then
        oldBucket[record.Model] = nil
        if next(oldBucket) == nil then
            state.ZombiesByRow[record.RowKey] = nil
        end
    end

    local rowKey = getRowKey(rowNum)
    record.Row = tonumber(rowNum)
    record.RowKey = rowKey
    if rootPart then
        record.RootPart = rootPart
    end

    state.ZombiesByRow[rowKey] = state.ZombiesByRow[rowKey] or {}
    state.ZombiesByRow[rowKey][record.Model] = record

    return record
end

local function isRecordAlive(record, expectedKind)
    if not record or record.Kind ~= expectedKind then
        return false
    end

    local model = record.Model
    local rootPart = record.RootPart
    if not model or not model.Parent or not rootPart or not rootPart.Parent then
        return false
    end

    if expectedKind == "Zombie" then
        local humanoid = record.Humanoid
        return humanoid and humanoid.Parent and humanoid.Health > 0 and model:GetAttribute("IsZombie") == true
    end

    return model:GetAttribute("IsCombatPlant") == true
        and model:GetAttribute("IsDead") ~= true
        and (tonumber(model:GetAttribute("Health")) or 0) > 0
end

local function getCandidateRecords(state, kind, rowNum)
    if not state then
        return nil
    end

    if kind == "Zombie" then
        if rowNum ~= nil then
            return state.ZombiesByRow[getRowKey(rowNum)] or {}
        end

        return state.Zombies
    end

    if rowNum ~= nil then
        return state.PlantsByRow[getRowKey(rowNum)] or {}
    end

    return state.Plants
end

local function getRootRadius(rootPart)
    local size = rootPart and rootPart.Size
    if typeof(size) ~= "Vector3" then
        return 0
    end

    return math.max(size.X, size.Z) * 0.5
end

local function recordInForwardBox(record, origin, direction, range, width)
    local rootPart = record.RootPart
    if not rootPart or not rootPart.Parent then
        return nil
    end

    local flatOffset = getFlatVector(rootPart.Position - origin)
    local forwardDistance = flatOffset:Dot(direction)
    local radius = getRootRadius(rootPart)
    if forwardDistance < -radius or forwardDistance > range + radius then
        return nil
    end

    local lateralOffset = flatOffset - direction * forwardDistance
    if lateralOffset.Magnitude > (width * 0.5) + radius then
        return nil
    end

    return forwardDistance
end

function CombatRegistry.CollectZombiesInBox(plot, rowNumOrNil, origin, direction, range, width, maxTargets)
    if not plot or typeof(origin) ~= "Vector3" then
        return {}
    end

    range = math.max(0.1, tonumber(range) or 0)
    width = math.max(0.1, tonumber(width) or 0)
    maxTargets = maxTargets and math.max(1, math.floor(tonumber(maxTargets) or 1)) or nil

    local state = registryByPlot[plot]
    local candidates = getCandidateRecords(state, "Zombie", rowNumOrNil)
    if not candidates then
        return {}
    end

    local flatDirection = getFlatUnit(direction, Vector3.new(0, 0, -1))
    local targets = {}

    for _, record in pairs(candidates) do
        if isRecordAlive(record, "Zombie") then
            local distance = recordInForwardBox(record, origin, flatDirection, range, width)
            if distance then
                table.insert(targets, {
                    Model = record.Model,
                    Humanoid = record.Humanoid,
                    RootPart = record.RootPart,
                    Distance = distance,
                })
            end
        else
            removeRecord(record)
        end
    end

    table.sort(targets, function(a, b)
        return a.Distance < b.Distance
    end)

    if maxTargets then
        while #targets > maxTargets do
            table.remove(targets)
        end
    end

    return targets
end

function CombatRegistry.FindNearestZombieInLane(plot, rowNum, origin, direction, range, width)
    local targets = CombatRegistry.CollectZombiesInBox(plot, rowNum, origin, direction, range, width, 1)
    local target = targets[1]
    if not target then
        return nil, nil, nil, nil
    end

    return target.Model, target.Humanoid, target.RootPart, target.Distance
end

function CombatRegistry.CollectZombiesInRadius(plot, center, radius, excludeModel)
    if not plot or typeof(center) ~= "Vector3" then
        return {}
    end

    radius = math.max(0.1, tonumber(radius) or 0)

    local state = registryByPlot[plot]
    local candidates = state and state.Zombies
    if not candidates then
        return {}
    end

    local targets = {}
    for model, record in pairs(candidates) do
        if model ~= excludeModel then
            if isRecordAlive(record, "Zombie") then
                local rootPart = record.RootPart
                local flatDistance = getFlatVector(rootPart.Position - center).Magnitude
                if flatDistance <= radius + getRootRadius(rootPart) then
                    table.insert(targets, {
                        Model = record.Model,
                        Humanoid = record.Humanoid,
                        RootPart = record.RootPart,
                        Distance = flatDistance,
                    })
                end
            else
                removeRecord(record)
            end
        end
    end

    table.sort(targets, function(a, b)
        return a.Distance < b.Distance
    end)

    return targets
end

function CombatRegistry.FindBlockingPlantInFront(plot, rowNum, origin, direction, range, width)
    if not plot or typeof(origin) ~= "Vector3" then
        return nil
    end

    range = math.max(0.1, tonumber(range) or 0)
    width = math.max(0.1, tonumber(width) or 0)

    local state = registryByPlot[plot]
    local candidates = getCandidateRecords(state, "Plant", rowNum)
    if not candidates then
        return nil
    end

    local flatDirection = getFlatUnit(direction, Vector3.new(0, 0, -1))
    local nearestRecord = nil
    local nearestDistance = math.huge

    for _, record in pairs(candidates) do
        if isRecordAlive(record, "Plant") then
            local distance = recordInForwardBox(record, origin, flatDirection, range, width)
            if distance and distance < nearestDistance then
                nearestRecord = record
                nearestDistance = distance
            end
        else
            removeRecord(record)
        end
    end

    return nearestRecord and nearestRecord.Model or nil
end

return CombatRegistry

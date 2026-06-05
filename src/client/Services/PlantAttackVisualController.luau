-- src/client/Services/PlantAttackVisualController.luau
local PlantAttackVisualController = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))

local PROJECTILE_SPEED = 25
local attackTracks = setmetatable({}, { __mode = "k" })
local flashingZombies = setmetatable({}, { __mode = "k" })
local warnedProjectileIssues = {}

local function warnProjectileOnce(projectileName, message)
    local key = tostring(projectileName) .. ":" .. message
    if warnedProjectileIssues[key] then return end
    warnedProjectileIssues[key] = true
    warn(("[PlantAttackVisual] %s: %s"):format(tostring(projectileName), message))
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

local function playAttackAnimation(plant, animationId, speedMult)
    if not plant or not plant.Parent then return end
    if type(animationId) ~= "string" or animationId == "" then return end

    speedMult = tonumber(speedMult) or 1

    local cached = attackTracks[plant]
    if not cached or cached.animationId ~= animationId or cached.animator ~= getAnimator(plant) then
        cleanupAttackTrack(plant)

        local animator = getAnimator(plant)
        if not animator then return end

        local anim = Instance.new("Animation")
        anim.AnimationId = animationId

        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        anim:Destroy()

        if not ok or not track then return end

        track.Priority = Enum.AnimationPriority.Action
        track.Looped = false

        cached = {
            animationId = animationId,
            animator = animator,
            track = track,
        }

        cached.markerConnection = track:GetMarkerReachedSignal("VFX"):Connect(function()
            if plant and plant.Parent then
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

    track:Stop(0)
    track:Play(0.05)
    track:AdjustSpeed(speedMult)
end

local function getProjectileParts(projectile)
    local parts = {}

    if projectile:IsA("BasePart") then
        table.insert(parts, projectile)
    end

    for _, desc in ipairs(projectile:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
        end
    end

    return parts
end

local function prepProjectile(projectile)
    if projectile:IsA("BasePart") then
        projectile.Anchored = true
        projectile.CanCollide = false
        projectile.CanTouch = false
        projectile.CanQuery = false

        for _, desc in ipairs(projectile:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
            end
        end

        return
    end

    for _, part in ipairs(getProjectileParts(projectile)) do
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
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

local function activateProjectileEffects(projectile, projectileName)
    local hasVisiblePart = false
    local hasEffect = false

    for _, part in ipairs(getProjectileParts(projectile)) do
        if part.Transparency < 1 and part.Size.Magnitude > 0 then
            hasVisiblePart = true
        end
    end

    for _, desc in ipairs(projectile:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            hasEffect = true
            desc.Enabled = true

            local emitCount = desc:GetAttribute("EmitCount")
            if not emitCount then
                local countValueNode = desc:FindFirstChild("EmitCount")
                if countValueNode and (countValueNode:IsA("IntValue") or countValueNode:IsA("NumberValue")) then
                    emitCount = countValueNode.Value
                end
            end

            emitCount = tonumber(emitCount)
            if emitCount and emitCount > 0 then
                desc:Emit(emitCount)
            end
        elseif desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") then
            hasEffect = true
            desc.Enabled = true
        end
    end

    if not hasVisiblePart and not hasEffect then
        warnProjectileOnce(projectileName, "template has no visible BasePart and no enabled effect")
    end
end

local function getTargetRoot(targetZombieModel)
    if not targetZombieModel or not targetZombieModel.Parent then return nil end
    return targetZombieModel:FindFirstChild("HumanoidRootPart") or targetZombieModel.PrimaryPart
end

local function getTargetHumanoid(targetZombieModel)
    if not targetZombieModel or not targetZombieModel.Parent then return nil end
    return targetZombieModel:FindFirstChildOfClass("Humanoid")
end

local function spawnProjectileVisual(projectileName, fireCFrame, initialTargetPos, targetZombieModel, arcHeight, speedMult)
    if type(projectileName) ~= "string" or projectileName == "" then return end
    if typeof(fireCFrame) ~= "CFrame" then return end
    if typeof(initialTargetPos) ~= "Vector3" then return end

    local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo") or ReplicatedStorage:WaitForChild("Ammo", 1)
    local template = ammoFolder and (ammoFolder:FindFirstChild(projectileName) or ammoFolder:WaitForChild(projectileName, 1))
    if not template then
        warnProjectileOnce(projectileName, "ReplicatedStorage.Ammo template not found on client")
        return
    end

    local projectile = createProjectileVisual(template, projectileName)
    prepProjectile(projectile)
    setProjectileCFrame(projectile, fireCFrame)
    projectile.Parent = Workspace
    activateProjectileEffects(projectile, projectileName)
    Debris:AddItem(projectile, 10)

    task.spawn(function()
        speedMult = tonumber(speedMult) or 1
        arcHeight = tonumber(arcHeight) or 0

        local startPos = fireCFrame.Position
        local targetRoot = getTargetRoot(targetZombieModel)

        local initialDist = (initialTargetPos - startPos).Magnitude
        local flightTime = math.max(0.05, initialDist / (PROJECTILE_SPEED * speedMult))
        local elapsedTime = 0

        while projectile and projectile.Parent do
            local humanoid = getTargetHumanoid(targetZombieModel)
            targetRoot = getTargetRoot(targetZombieModel)
            if humanoid and humanoid.Health <= 0 then
                projectile:Destroy()
                break
            end

            local dt = RunService.Heartbeat:Wait()
            local targetPos = targetRoot and (targetRoot.Position + Vector3.new(0, 1, 0)) or initialTargetPos

            if arcHeight > 0 then
                elapsedTime += dt
                local t = math.clamp(elapsedTime / flightTime, 0, 1)
                local p0 = startPos
                local p2 = targetPos
                local p1 = p0:Lerp(p2, 0.5) + Vector3.new(0, arcHeight, 0)
                local currentPos = (1 - t) ^ 2 * p0 + 2 * (1 - t) * t * p1 + t ^ 2 * p2
                local nextT = math.clamp(t + 0.05, 0, 1)
                local nextPos = (1 - nextT) ^ 2 * p0 + 2 * (1 - nextT) * nextT * p1 + nextT ^ 2 * p2

                if (nextPos - currentPos).Magnitude > 0.001 then
                    setProjectileCFrame(projectile, CFrame.lookAt(currentPos, nextPos))
                else
                    setProjectileCFrame(projectile, CFrame.new(currentPos))
                end

                if t >= 1 then
                    projectile:Destroy()
                    break
                end
            else
                local currentPos = getProjectilePosition(projectile)
                if not currentPos then
                    projectile:Destroy()
                    break
                end

                local direction = targetPos - currentPos
                local dist = direction.Magnitude
                local moveStep = PROJECTILE_SPEED * speedMult * dt

                if dist <= moveStep or dist <= 0.001 then
                    projectile:Destroy()
                    break
                end

                local nextPos = currentPos + direction.Unit * moveStep
                setProjectileCFrame(projectile, CFrame.lookAt(nextPos, targetPos))
            end
        end
    end)
end

local function flashZombieRed(zombieModel)
    if not zombieModel or not zombieModel.Parent then return end
    if flashingZombies[zombieModel] then return end
    flashingZombies[zombieModel] = true

    local originalColors = {}
    for _, p in ipairs(zombieModel:GetDescendants()) do
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

local function showDamageText(zombieModel, damage)
    if not zombieModel or not zombieModel.Parent then return end

    local rootPart = zombieModel:FindFirstChild("HumanoidRootPart") or zombieModel.PrimaryPart
    local head = zombieModel:FindFirstChild("Head") or rootPart
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DamageText"
    billboard.Size = UDim2.new(0, 60, 0, 25)
    billboard.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 1.5 + math.random(5, 15) / 10, math.random(-10, 10) / 10)
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
    TweenService:Create(billboard, tweenInfo, { StudsOffset = billboard.StudsOffset + Vector3.new(0, 1.5, 0) }):Play()
    TweenService:Create(textLabel, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
    Debris:AddItem(billboard, 1.0)
end

local function playHitEffect(hitPos, hitEffectTexture, hitEffectColor)
    if typeof(hitPos) ~= "Vector3" then return end

    local effectPart = Instance.new("Part")
    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
    effectPart.Transparency = 1
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.CanQuery = false
    effectPart.Position = hitPos
    effectPart.Parent = Workspace

    local hitFolder = ReplicatedStorage:FindFirstChild("Hit")
    local hitEffectPrefab = nil

    if typeof(hitEffectTexture) == "string" and hitEffectTexture ~= "" and hitFolder then
        local template = hitFolder:FindFirstChild(hitEffectTexture)
        if template and template:IsA("BasePart") then
            hitEffectPrefab = template
        end
    end

    if hitEffectPrefab then
        local clone = hitEffectPrefab:Clone()
        clone.Anchored = true
        clone.CanCollide = false
        clone.CFrame = CFrame.new(hitPos)
        clone.Parent = Workspace

        task.wait(0.05)

        for _, child in ipairs(clone:GetDescendants()) do
            if child:IsA("ParticleEmitter") then
                local emitCount = child:GetAttribute("EmitCount")
                if not emitCount then
                    local countValueNode = child:FindFirstChild("EmitCount")
                    if countValueNode and (countValueNode:IsA("IntValue") or countValueNode:IsA("NumberValue")) then
                        emitCount = countValueNode.Value
                    end
                end

                emitCount = tonumber(emitCount)
                if not emitCount or emitCount <= 0 then emitCount = 15 end

                child.Enabled = true
                child:Emit(emitCount)
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

        Debris:AddItem(clone, 1.5)
    else
        local attachment = Instance.new("Attachment", effectPart)
        local particles = Instance.new("ParticleEmitter", attachment)
        particles.Texture = hitEffectTexture or "rbxassetid://243098098"
        particles.Color = ColorSequence.new(hitEffectColor or Color3.fromRGB(255, 215, 0))
        particles.Size = NumberSequence.new(1, 0)
        particles.Rate = 0
        particles.Speed = NumberRange.new(5, 10)
        particles.Lifetime = NumberRange.new(0.1, 0.3)
        particles:Emit(15)
    end

    Debris:AddItem(effectPart, 1.5)
end

local function playHitVisual(targetZombieModel, damage, hitPos, hitEffectTexture, hitEffectColor)
    flashZombieRed(targetZombieModel)
    showDamageText(targetZombieModel, damage)
    task.spawn(playHitEffect, hitPos, hitEffectTexture, hitEffectColor)
end

function PlantAttackVisualController.Init()
    task.spawn(function()
        local visualRE = ReplicatedStorage:WaitForChild("PlantAttackVisualRE")

        visualRE.OnClientEvent:Connect(function(action, ...)
            if action == "Attack" then
                playAttackAnimation(...)
            elseif action == "Projectile" then
                spawnProjectileVisual(...)
            elseif action == "Hit" then
                playHitVisual(...)
            end
        end)
    end)
end

return PlantAttackVisualController

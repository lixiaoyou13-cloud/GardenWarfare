-- src/client/Services/ZombieBoxController.luau
local ZombieBoxController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local itemModels = ReplicatedStorage:WaitForChild("ItemModels")
local zombieBoxRE = ReplicatedStorage:WaitForChild("ZombieBoxRE")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- 用于假抽奖滚动动画的模型库
local fakeItemPool = {}
local OWNED_BOX_HIGHLIGHT_NAME = "OwnedZombieBoxHighlight"
local watchedRewardBoxes = setmetatable({}, { __mode = "k" })
local originalLocalTransparencyModifiers = setmetatable({}, { __mode = "k" })
local originalEffectEnabled = setmetatable({}, { __mode = "k" })

local function setVisualPartsAnchored(instance)
    if instance:IsA("BasePart") then
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
    end

    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored = true
            desc.CanCollide = false
            desc.CanTouch = false
            desc.CanQuery = false
        end
    end
end

local function pivotVisual(instance, cframe)
    if instance:IsA("Model") then
        if not instance.PrimaryPart then
            instance.PrimaryPart = instance:FindFirstChildWhichIsA("BasePart", true)
        end
        instance:PivotTo(cframe)
    elseif instance:IsA("BasePart") then
        instance.CFrame = cframe
    end
end

local function getVisualPosition(instance)
    if instance:IsA("Model") then
        return instance:GetPivot().Position
    elseif instance:IsA("BasePart") then
        return instance.Position
    end

    return Vector3.zero
end

local function refreshOwnedBoxHighlight(box)
    if not box or not box.Parent then return end
    if not (box:IsA("Model") or box:IsA("BasePart")) then return end

    local highlight = box:FindFirstChild(OWNED_BOX_HIGHLIGHT_NAME)
    local isOwnedZombieBox = box:GetAttribute("IsZombieRewardBox") == true
        and box:GetAttribute("OwnerId") == localPlayer.UserId

    if not isOwnedZombieBox then
        if highlight then highlight:Destroy() end
        return
    end

    if highlight then return end

    highlight = Instance.new("Highlight")
    highlight.Name = OWNED_BOX_HIGHLIGHT_NAME
    highlight.Adornee = box
    highlight.FillColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.82
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = box
end

local function isPotentialRewardBox(box)
    return box
        and (box:IsA("Model") or box:IsA("BasePart"))
        and (box:GetAttribute("IsZombieRewardBox") == true or string.find(box.Name, "ZombieRewardBox") ~= nil)
end

local function isOwnedRewardBox(box)
    return isPotentialRewardBox(box) and box:GetAttribute("OwnerId") == localPlayer.UserId
end

local function setLocalEffectVisible(effect, isVisible)
    if effect:IsA("BasePart") then
        if originalLocalTransparencyModifiers[effect] == nil then
            originalLocalTransparencyModifiers[effect] = effect.LocalTransparencyModifier
        end
        effect.LocalTransparencyModifier = isVisible and originalLocalTransparencyModifiers[effect] or 1
    elseif effect:IsA("ParticleEmitter")
        or effect:IsA("Light")
        or effect:IsA("Beam")
        or effect:IsA("Trail")
        or effect:IsA("Highlight")
    then
        if originalEffectEnabled[effect] == nil then
            originalEffectEnabled[effect] = effect.Enabled
        end
        effect.Enabled = isVisible and originalEffectEnabled[effect] or false
    end
end

local function applyRewardBoxVisibility(box)
    if not isPotentialRewardBox(box) then
        return
    end

    local isVisible = isOwnedRewardBox(box)
    setLocalEffectVisible(box, isVisible)
    for _, descendant in ipairs(box:GetDescendants()) do
        setLocalEffectVisible(descendant, isVisible)
    end

    refreshOwnedBoxHighlight(box)
end

local function watchPotentialRewardBox(box)
    if not isPotentialRewardBox(box) then return end

    applyRewardBoxVisibility(box)
    if watchedRewardBoxes[box] then
        return
    end
    watchedRewardBoxes[box] = true

    box.DescendantAdded:Connect(function()
        task.defer(applyRewardBoxVisibility, box)
    end)

    box:GetAttributeChangedSignal("OwnerId"):Connect(function()
        applyRewardBoxVisibility(box)
    end)

    box:GetAttributeChangedSignal("IsZombieRewardBox"):Connect(function()
        applyRewardBoxVisibility(box)
    end)
end

local function getSeedModelName(seedId)
    local seedModelName = tostring(seedId) .. "_Seed"
    if itemModels:FindFirstChild(seedModelName) then
        return seedModelName
    end
    if itemModels:FindFirstChild("Seed") then
        return "Seed"
    end
    return nil
end

local function getPlantModelName(plantId)
    local plantModelName = tostring(plantId) .. "_Plant"
    if itemModels:FindFirstChild(plantModelName) then
        return plantModelName
    end
    if itemModels:FindFirstChild(tostring(plantId)) then
        return tostring(plantId)
    end
    return nil
end

local function addFakeItemPoolEntry(itemType, itemId, modelName)
    if not modelName then return end
    table.insert(fakeItemPool, {
        type = itemType,
        id = itemId,
        modelName = modelName,
    })
end

local function rebuildFakeItemPool()
    table.clear(fakeItemPool)

    for seedId, seedDetail in pairs(ItemConfig.Seeds or {}) do
        if not seedDetail.ExcludeFromRandomSeedRewards then
            addFakeItemPoolEntry("Seed", seedId, getSeedModelName(seedId))
        end
    end

    for plantId, plantDetail in pairs(ItemConfig.Plants or {}) do
        if not plantDetail.ExcludeFromRandomPlantRewards then
            addFakeItemPoolEntry("Plant", plantId, getPlantModelName(plantId))
        end
    end
end

local function getDisplayTemplateForReward(item)
    if type(item) == "table" then
        if item.type == "Plant" then
            local plantModelName = getPlantModelName(item.id)
            if plantModelName then
                return itemModels:FindFirstChild(plantModelName)
            end
        elseif item.type == "Seed" then
            local seedModelName = getSeedModelName(item.id)
            if seedModelName then
                return itemModels:FindFirstChild(seedModelName)
            end
        end
    end

    return itemModels:FindFirstChild("Seed")
end

function ZombieBoxController.Init()
    rebuildFakeItemPool()

    -- 监听服务端要求生成盲盒的指令
    zombieBoxRE.OnClientEvent:Connect(function(action, dropPos, finalItem)
        if action == "SpawnBox" then
            ZombieBoxController.SpawnLocalBox(dropPos, finalItem)
        elseif action == "LevelChestReward" then
            ZombieBoxController.SpawnLevelChestReward(dropPos, finalItem)
        end
    end)

    for _, child in ipairs(Workspace:GetChildren()) do
        watchPotentialRewardBox(child)
    end

    Workspace.ChildAdded:Connect(watchPotentialRewardBox)
end

function ZombieBoxController.SpawnLevelChestReward(dropPos, chestId)
    local chestFolder = ReplicatedStorage:FindFirstChild("Chest")
    local chestTemplate = chestFolder and chestFolder:FindFirstChild(tostring(chestId))
    if not chestTemplate then
        warn("[ZombieBoxController] Missing chest visual: " .. tostring(chestId))
        return
    end

    local chestVisual = chestTemplate:Clone()
    setVisualPartsAnchored(chestVisual)

    local startPos = typeof(dropPos) == "Vector3" and dropPos or Vector3.zero
    pivotVisual(chestVisual, CFrame.new(startPos + Vector3.new(0, 3, 0)))
    chestVisual.Parent = Workspace

    local glow = Instance.new("Highlight")
    glow.FillColor = Color3.fromRGB(255, 230, 120)
    glow.FillTransparency = 0.55
    glow.OutlineColor = Color3.fromRGB(255, 255, 255)
    glow.OutlineTransparency = 0
    glow.Parent = chestVisual

    local flightTime = 0.75
    local startTime = os.clock()
    local visualStartPos = getVisualPosition(chestVisual)

    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not chestVisual or not chestVisual.Parent then
            if connection then connection:Disconnect() end
            return
        end

        local elapsedTime = os.clock() - startTime
        local t = math.clamp(elapsedTime / flightTime, 0, 1)
        local targetChar = localPlayer.Character
        local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        local endPos = targetHRP and targetHRP.Position + Vector3.new(0, 1.2, 0) or visualStartPos

        if t >= 1 then
            connection:Disconnect()
            chestVisual:Destroy()
            return
        end

        local controlPos = visualStartPos:Lerp(endPos, 0.5) + Vector3.new(0, 14, 0)
        local currentPos = ((1 - t) ^ 2 * visualStartPos) + (2 * (1 - t) * t * controlPos) + (t ^ 2 * endPos)
        pivotVisual(chestVisual, CFrame.new(currentPos))
    end)
end

function ZombieBoxController.SpawnLocalBox(dropPos, finalItem)
    local luckyTemplate = itemModels:FindFirstChild("Box")
    if not luckyTemplate then return end

    local box = luckyTemplate:Clone()

    box:PivotTo(CFrame.new(dropPos))

    for _, part in pairs(box:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
        end
    end

    box.Parent = Workspace

    -- 2. 开箱动画
    task.spawn(function()
        for _, p in pairs(box:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Color = Color3.fromRGB(255, 255, 255)
                p.Material = Enum.Material.Neon
            elseif p:IsA("ParticleEmitter") or p:IsA("Light") then
                p.Enabled = true
            end
        end

        task.wait(0.3)

        local boxPos = box:GetPivot().Position
        box:Destroy()

        local displayModel
        local iterations = 15
        for i = 1, iterations do
            if displayModel then displayModel:Destroy() end

            local randomEntry = #fakeItemPool > 0 and fakeItemPool[math.random(1, #fakeItemPool)] or nil
            local template = randomEntry and itemModels:FindFirstChild(randomEntry.modelName) or itemModels:FindFirstChild("Seed")

            if template then
                displayModel = template:Clone()
                for _, p in pairs(displayModel:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Color = Color3.new(0, 0, 0)
                        p.Material = Enum.Material.SmoothPlastic
                        p.Anchored = true
                        p.CanCollide = false
                    end
                end
                displayModel:PivotTo(CFrame.new(boxPos + Vector3.new(0, 3, 0)))
                displayModel.Parent = Workspace
            end
            task.wait(0.12)
        end
        if displayModel then displayModel:Destroy() end

        local finalTemplate = getDisplayTemplateForReward(finalItem)

        if finalTemplate then
            local finalModel = finalTemplate:Clone()
            for _, p in pairs(finalModel:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = true
                    p.CanCollide = false
                end
            end
            finalModel:PivotTo(CFrame.new(boxPos + Vector3.new(0, 3, 0)))
            finalModel.Parent = Workspace

            local glow = Instance.new("Highlight")
            glow.FillColor = Color3.fromRGB(255, 215, 0)
            glow.Parent = finalModel

            task.wait(0.5)

            local flightTime = 0.6
            local startTime = os.clock()
            local startPos = finalModel:GetPivot().Position

            local connection
            connection = RunService.Heartbeat:Connect(function()
                local elapsedTime = os.clock() - startTime
                local t = math.clamp(elapsedTime / flightTime, 0, 1)

                if t >= 1 then
                    connection:Disconnect()
                    finalModel:Destroy()

                    zombieBoxRE:FireServer("GiveReward", finalItem)
                else
                    local targetChar = localPlayer.Character
                    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                    local endPos = targetHRP and targetHRP.Position or startPos

                    local p0 = startPos
                    local p2 = endPos
                    local p1 = p0:Lerp(p2, 0.5) + Vector3.new(0, 15, 0)

                    local currentPos = ((1 - t)^2 * p0) + (2 * (1 - t) * t * p1) + (t^2 * p2)
                    finalModel:PivotTo(CFrame.new(currentPos))
                end
            end)
        end
    end)
end

return ZombieBoxController

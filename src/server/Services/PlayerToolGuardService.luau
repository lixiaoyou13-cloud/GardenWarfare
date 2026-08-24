local PlayerToolGuardService = {}

local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local watchedContainers = setmetatable({}, { __mode = "k" })

local function startsWith(value, prefix)
    return string.sub(value, 1, #prefix) == prefix
end

local function isExecutable(instance)
    return instance:IsA("Script") or instance:IsA("LocalScript")
end

local function isBackpackItem(instance)
    local ok, result = pcall(function()
        return instance:IsA("BackpackItem")
    end)

    local hopperOk, isHopperBin = pcall(function()
        return instance:IsA("HopperBin")
    end)

    return (ok and result) or instance:IsA("Tool") or (hopperOk and isHopperBin)
end

local function destroyBlockedInstance(instance, reason)
    if not instance or not instance.Parent then
        return
    end

    warn("[PlayerToolGuard] Removed " .. instance:GetFullName() .. " (" .. reason .. ")")
    instance:Destroy()
end

local function neutralizeExplosion(instance)
    if not instance:IsA("Explosion") then
        return
    end

    instance.BlastPressure = 0
    instance.DestroyJointRadiusPercent = 0
end

local function cleanToolContainer(container)
    for _, child in ipairs(container:GetDescendants()) do
        if isBackpackItem(child) then
            destroyBlockedInstance(child, "external backpack item")
        elseif isExecutable(child) and (container == StarterPack or container.Name == "Backpack" or container.Name == "StarterGear") then
            destroyBlockedInstance(child, "script inside player item container")
        elseif child:IsA("Explosion") then
            neutralizeExplosion(child)
        end
    end
end

local function watchToolContainer(container)
    if not container or watchedContainers[container] then
        return
    end

    watchedContainers[container] = true
    cleanToolContainer(container)

    container.DescendantAdded:Connect(function(descendant)
        task.defer(function()
            if not descendant or not descendant.Parent then
                return
            end

            if isBackpackItem(descendant) then
                destroyBlockedInstance(descendant, "external backpack item")
            elseif isExecutable(descendant) and (container == StarterPack or container.Name == "Backpack" or container.Name == "StarterGear") then
                destroyBlockedInstance(descendant, "script inside player item container")
            elseif descendant:IsA("Explosion") then
                neutralizeExplosion(descendant)
            end
        end)
    end)
end

local function getGeneratedModelOwner(modelName)
    local loweredName = string.lower(modelName)

    for _, player in ipairs(Players:GetPlayers()) do
        local namePrefix = string.lower(player.Name) .. "'s"
        local displayPrefix = string.lower(player.DisplayName or "") .. "'s"

        if startsWith(loweredName, namePrefix) or (displayPrefix ~= "'s" and startsWith(loweredName, displayPrefix)) then
            return player
        end
    end

    return nil
end

local function modelHasExecutable(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if isExecutable(descendant) then
            return true
        end
    end

    return false
end

local function isSuspiciousRuntimeModel(model)
    if not model:IsA("Model") then
        return false
    end

    if Players:GetPlayerFromCharacter(model) then
        return false
    end

    if getGeneratedModelOwner(model.Name) then
        return true
    end

    local loweredName = string.lower(model.Name)
    if (string.find(loweredName, "robot", 1, true) or string.find(loweredName, "godzilla", 1, true)) and modelHasExecutable(model) then
        return true
    end

    return false
end

local function cleanWorkspaceInstance(instance)
    if instance:IsA("Explosion") then
        neutralizeExplosion(instance)
        return
    end

    if isSuspiciousRuntimeModel(instance) then
        destroyBlockedInstance(instance, "player-generated scripted model")
    end
end

local function watchCharacter(character)
    watchToolContainer(character)
end

local function watchPlayer(player)
    task.spawn(function()
        local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
        watchToolContainer(backpack)

        local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 10)
        watchToolContainer(starterGear)
    end)

    player.ChildAdded:Connect(function(child)
        if child.Name == "Backpack" or child.Name == "StarterGear" then
            watchToolContainer(child)
        end
    end)

    if player.Character then
        watchCharacter(player.Character)
    end

    player.CharacterAdded:Connect(watchCharacter)
end

function PlayerToolGuardService.Init()
    watchToolContainer(StarterPack)

    for _, player in ipairs(Players:GetPlayers()) do
        watchPlayer(player)
    end

    Players.PlayerAdded:Connect(watchPlayer)

    for _, instance in ipairs(Workspace:GetDescendants()) do
        cleanWorkspaceInstance(instance)
    end

    Workspace.DescendantAdded:Connect(function(instance)
        task.defer(function()
            if instance and instance.Parent then
                cleanWorkspaceInstance(instance)
            end
        end)
    end)

    print("Server: PlayerToolGuardService active; external Roblox tools and scripted gear models are blocked.")
end

return PlayerToolGuardService

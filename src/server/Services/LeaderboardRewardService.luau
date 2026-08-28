local LeaderboardRewardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LeaderboardRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LeaderboardRewardConfig"))

local touchDebounce = {}
local boundTouchParts = {}
local boundTouchModels = {}

--[[ 创建或复用打开页面事件。 ]]
local function getOrCreateOpenRemote()
    local remoteNames = LeaderboardRewardConfig.RemoteNames or {}
    local remoteName = remoteNames.Open or "OpenLeaderboardRewardRE"
    local remote = ReplicatedStorage:FindFirstChild(remoteName)
    if remote and not remote:IsA("RemoteEvent") then
        warn("[LeaderboardRewardService] " .. tostring(remoteName) .. " exists but is not a RemoteEvent.")
        return nil
    end

    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = remoteName
        remote.Parent = ReplicatedStorage
    end

    return remote
end

--[[ 从触碰零件反查玩家。 ]]
local function getPlayerFromHit(hit)
    if not hit then
        return nil
    end

    local current = hit.Parent
    while current and current ~= Workspace do
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
            return Players:GetPlayerFromCharacter(current)
        end
        current = current.Parent
    end

    return nil
end

--[[ 通知客户端打开排行榜奖励展示页。 ]]
local function openRewardUi(player)
    local openRE = getOrCreateOpenRemote()
    if not openRE or not player or not player.Parent then
        return
    end

    openRE:FireClient(player)
end

--[[ 绑定单个触碰零件。 ]]
local function bindTouchPart(part)
    if not (part and part:IsA("BasePart")) then
        return
    end
    if boundTouchParts[part] then
        return
    end

    boundTouchParts[part] = true
    part.CanTouch = true
    part.Touched:Connect(function(hit)
        local player = getPlayerFromHit(hit)
        if not player then
            return
        end

        local now = os.clock()
        local debounceSeconds = math.max(0.25, tonumber(LeaderboardRewardConfig.TouchDebounceSeconds) or 2)
        if now - (touchDebounce[player.UserId] or 0) < debounceSeconds then
            return
        end

        touchDebounce[player.UserId] = now
        openRewardUi(player)
    end)
end

--[[ 绑定一个入口模型下的所有可触碰零件。 ]]
local function bindTouchModel(model)
    if not model or boundTouchModels[model] then
        return
    end

    boundTouchModels[model] = true
    if model:IsA("BasePart") then
        bindTouchPart(model)
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        bindTouchPart(descendant)
    end

    model.DescendantAdded:Connect(bindTouchPart)
end

--[[ 根据 Workspace 相对路径查找入口模型。 ]]
local function findWorkspacePath(pathText)
    local current = Workspace
    for _, segment in ipairs(string.split(tostring(pathText or ""), ".")) do
        if segment ~= "" then
            current = current and current:FindFirstChild(segment)
            if not current then
                return nil
            end
        end
    end

    return current
end

--[[ 绑定配置中的所有入口模型。 ]]
local function bindConfiguredTouchModels()
    local paths = LeaderboardRewardConfig.TouchModelPaths
    if type(paths) == "table" then
        for _, pathText in ipairs(paths) do
            bindTouchModel(findWorkspacePath(pathText))
        end
    end

    local fallbackName = LeaderboardRewardConfig.TouchModelName
    if type(fallbackName) == "string" and fallbackName ~= "" then
        bindTouchModel(Workspace:FindFirstChild(fallbackName))
    end
end

function LeaderboardRewardService.Init()
    getOrCreateOpenRemote()
    bindConfiguredTouchModels()

    Workspace.DescendantAdded:Connect(function()
        task.defer(bindConfiguredTouchModels)
    end)

    Players.PlayerRemoving:Connect(function(player)
        touchDebounce[player.UserId] = nil
    end)

    print("Server: LeaderboardRewardService active.")
end

return LeaderboardRewardService

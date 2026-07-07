-- src/server/Services/BaseSunflowerService.luau
local BaseSunflowerService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- 专门用来追踪所有玩家的基地向日葵，方便实时更新
local activeSunflowers = {}

-- 算法 计算缩放并更新悬浮 UI
local function UpdateSunflowerScale(sunflower, totalSun)
    if not sunflower or not sunflower:IsA("Model") then return end
    local minScale = 1
    local maxScale = 50
    local threshold = 1000000

    -- 太阳数量为0时间，自转动缩回1倍
    local scale = minScale + (math.min(totalSun, threshold) / threshold) * (maxScale - minScale)

    local lastScale = sunflower:GetAttribute("LastSunflowerScale")
    if sunflower.PrimaryPart and (typeof(lastScale) ~= "number" or math.abs(lastScale - scale) > 0.01) then
        sunflower:ScaleTo(scale)
        sunflower:SetAttribute("LastSunflowerScale", scale)
    end

    -- 去我们创建的虚拟独立 UI 锚点方块上寻找 UI
    local plot = sunflower.Parent
    if not plot then return end

    local collectSunPart = nil
    local elementBtn = plot:FindFirstChild("ElementButton", true)
    if elementBtn then collectSunPart = elementBtn:FindFirstChild("CollectSun") end

    if not collectSunPart then
        collectSunPart = plot:FindFirstChild("CollectSun")
    end

    if collectSunPart then
        local guiAnchor = collectSunPart:FindFirstChild("SunGuiAnchor")
        if guiAnchor then
            -- 遍历前后两面的 SurfaceGui 同步更新数值
            for _, gui in ipairs(guiAnchor:GetChildren()) do
                if gui:IsA("SurfaceGui") and gui.Name == "SunCounterGui" then
                    local container = gui:FindFirstChild("Container")
                    local textLabel = container and container:FindFirstChild("SunText")
                    if textLabel then
                        local displaySun = totalSun
                        -- 大数值转换 (K, M)
                        if totalSun >= 1000000 then
                            displaySun = string.format("%.1fM", totalSun / 1000000)
                        elseif totalSun >= 1000 then
                            displaySun = string.format("%.1fK", totalSun / 1000)
                        end
                        local displayText = tostring(displaySun)
                        if textLabel.Text ~= displayText then
                            textLabel.Text = displayText
                        end
                    end
                end
            end
        end
    end
end

-- 杀毒软件 强行隐藏特效外壳
local function HideAllMutations(model)
    local effectNames = { "Glow", "Lightning", "HolyLight" }
    for _, fxName in ipairs(effectNames) do
        for _, node in ipairs(model:GetDescendants()) do
            if node.Name == fxName then
                if node:IsA("BasePart") then node.Transparency = 1
                elseif node:IsA("ParticleEmitter") or node:IsA("Light") or node:IsA("Beam") or node:IsA("Highlight") or node:IsA("Trail") then node.Enabled = false end
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("BasePart") then child.Transparency = 1
                    elseif child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then child.Enabled = false end
                end
            end
        end
    end
end

-- 主入口 生成基地向日葵
function BaseSunflowerService.SpawnSunflower(player, plot)
    local collectSunPart = nil
    local elementBtn = plot:FindFirstChild("ElementButton", true)
    if elementBtn then collectSunPart = elementBtn:FindFirstChild("CollectSun") end

    if not collectSunPart then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc.Name == "CollectSun" and desc:IsA("BasePart") then collectSunPart = desc; break end
        end
    end

    if collectSunPart then
        collectSunPart.Anchored = true

        local sunflowerConfig = ItemConfig.Plants and ItemConfig.Plants["Sunflower"]
        local itemModels = ReplicatedStorage:WaitForChild("ItemModels")
        local modelTemplate = itemModels:FindFirstChild("Sunflower_Plant") or itemModels:FindFirstChild("Sunflower")

        if modelTemplate then
            local sunflower = modelTemplate:Clone()
            sunflower.Name = "BaseSunflower"
            sunflower:SetAttribute("OwnerId", player.UserId)

            if not sunflower.PrimaryPart then sunflower.PrimaryPart = sunflower:FindFirstChildWhichIsA("BasePart", true) end

            local hasAnim = sunflowerConfig and sunflowerConfig.IdleAnimId and sunflowerConfig.IdleAnimId ~= ""

            -- 打钢筋 防掉落与动画适配
            for _, part in ipairs(sunflower:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                    if hasAnim and sunflower.PrimaryPart and part == sunflower.PrimaryPart then
                        part.Anchored = true
                    else
                        part.Anchored = not hasAnim
                    end
                end
            end

            HideAllMutations(sunflower)
            if sunflower.PrimaryPart then sunflower.PrimaryPart.Transparency = 1 end

            local targetCFrame = collectSunPart.CFrame * CFrame.new(0, 1.5, 0)
            sunflower:PivotTo(targetCFrame)
            sunflower.Parent = plot

            -- 创建悬浮UI ( 静止挂载中枢：悬空+防遮挡+双面显示)
            if collectSunPart then
                -- 1. 销毁可能存在的旧独立锚点
                local oldAnchor = collectSunPart:FindFirstChild("SunGuiAnchor")
                if oldAnchor then oldAnchor:Destroy() end

                -- 2. 创建一个绝对静止、透明的不碰撞看板部件
                local guiAnchor = Instance.new("Part")
                guiAnchor.Name = "SunGuiAnchor"
                guiAnchor.Size = Vector3.new(4, 1.5, 0.05)
                guiAnchor.Transparency = 1 -- 隐形
                guiAnchor.Anchored = true -- 静止不动
                guiAnchor.CanCollide = false -- 无碰撞
                guiAnchor.CanQuery = false -- 防鼠标点击拦截
                guiAnchor.CanTouch = false

                -- 3. 悬浮在 CollectSun 上方固定 5 格高空（可根据视线随意微调高度）
                guiAnchor.CFrame = collectSunPart.CFrame * CFrame.new(0, 5, 0)
                guiAnchor.Parent = collectSunPart

                -- 4. 双面渲染渲染逻辑：同时间渲染正面和背面，防止转镜头时间转到反面看不见
                local renderFaces = { Enum.NormalId.Front, Enum.NormalId.Back }

                for _, faceDirection in ipairs(renderFaces) do
                    local sGui = Instance.new("SurfaceGui")
                    sGui.Name = "SunCounterGui"
                    sGui.Face = faceDirection
                    sGui.LightInfluence = 0 -- 纯亮发光字，不受全地图阴影影响

                    -- 开启 AlwaysOnTop
                    -- 这样即便向日葵模型膨胀把这个锚点Part整个吞进肚子里，UI 依然会雷打不动地穿透渲染在最前面
                    sGui.AlwaysOnTop = true
                    sGui.CanvasSize = Vector2.new(400, 150)

                    local container = Instance.new("Frame")
                    container.Name = "Container"
                    container.Size = UDim2.new(1, 0, 1, 0)
                    container.BackgroundTransparency = 1
                    container.Parent = sGui

                    local icon = Instance.new("ImageLabel")
                    icon.Name = "SunIcon"
                    icon.Size = UDim2.new(0, 100, 0, 100)
                    icon.Position = UDim2.new(0, 30, 0.5, -50)
                    icon.BackgroundTransparency = 1
                    icon.Image = "rbxassetid://102426033120992"
                    icon.ScaleType = Enum.ScaleType.Fit
                    icon.Parent = container

                    local textLabel = Instance.new("TextLabel")
                    textLabel.Name = "SunText"
                    textLabel.Size = UDim2.new(1, -150, 1, 0)
                    textLabel.Position = UDim2.new(0, 140, 0, 0)
                    textLabel.BackgroundTransparency = 1
                    textLabel.Text = "0"
                    textLabel.TextColor3 = Color3.fromRGB(255, 230, 50)
                    textLabel.TextStrokeTransparency = 0
                    textLabel.Font = Enum.Font.GothamBold
                    textLabel.TextScaled = true
                    textLabel.TextXAlignment = Enum.TextXAlignment.Left
                    textLabel.Parent = container

                    sGui.Parent = guiAnchor
                end
            end

            -- 自转动靠近底座方块收割
            local oldPrompt = collectSunPart:FindFirstChild("HarvestPrompt")
            if oldPrompt then oldPrompt:Destroy() end

            task.spawn(function()
                local isHarvesting = false
                local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
                local harvestRE = ReplicatedStorage:FindFirstChild("HarvestSunRE")

                while collectSunPart and collectSunPart.Parent and sunflower and sunflower.Parent do
                    task.wait(0.3)

                    if isHarvesting then continue end

                    local character = player.Character
                    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                    if not rootPart then continue end

                    local distance = (rootPart.Position - collectSunPart.Position).Magnitude

                    if distance <= 15 then
                        local pData = PlayerDataManager.GetPlayerData(player)

                        if pData and (pData.TotalSun or 0) > 0 then
                            isHarvesting = true
                            local amount = pData.TotalSun
                            pData.TotalSun = 0
                            local boostedAmount = PlayerDataManager.ApplyFriendSunBoost(player, amount)

                            local finalReward = PlayerDataManager.GiveCoins(player, boostedAmount) or boostedAmount
                            local isX2Sun = finalReward == boostedAmount * 2

                            if harvestRE then
                                harvestRE:FireClient(player, boostedAmount, collectSunPart.Position, isX2Sun)
                            end

                            local AnalyticsService = game:GetService("AnalyticsService")
                            pcall(function()
                                AnalyticsService:LogEconomyEvent(
                                    player,
                                    Enum.AnalyticsEconomyFlowType.Source,
                                    "Coins",
                                    finalReward,
                                    pData.Coins,
                                    Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
                                    "Sunflower_Collect"
                                )
                            end)

                            task.wait(0.75)
                            isHarvesting = false
                        end
                    end
                end
            end)

            -- 装载动画
            if hasAnim then
                local animController = sunflower:FindFirstChildOfClass("AnimationController") or sunflower:FindFirstChildOfClass("Humanoid")
                if not animController then animController = Instance.new("AnimationController"); animController.Parent = sunflower end

                local animator = animController:FindFirstChildOfClass("Animator")
                if not animator then animator = Instance.new("Animator"); animator.Parent = animController end

                local anim = Instance.new("Animation")
                anim.AnimationId = sunflowerConfig.IdleAnimId
                local track = animator:LoadAnimation(anim)
                track.Looped = true;
                track:Play()
            end

            local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
            local pData = PlayerDataManager.GetPlayerData(player)
            UpdateSunflowerScale(sunflower, pData and pData.TotalSun or 0)

            -- 加入追踪列表
            activeSunflowers[player.UserId] = sunflower
            print("[BaseSunflower] Spawn successful; auto-harvest enabled.")
        end
    end
end

function BaseSunflowerService.Init()
    if not ReplicatedStorage:FindFirstChild("HarvestSunRE") then
        local re = Instance.new("RemoteEvent")
        re.Name = "HarvestSunRE"
        re.Parent = ReplicatedStorage
    end

    task.spawn(function()
        local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
        while true do
            task.wait(1)
            for userId, sunflower in pairs(activeSunflowers) do
                local player = Players:GetPlayerByUserId(userId)
                if player and sunflower and sunflower.Parent then
                    local pData = PlayerDataManager.GetPlayerData(player)
                    if pData then
                        UpdateSunflowerScale(sunflower, pData.TotalSun or 0)
                    end
                else
                    activeSunflowers[userId] = nil
                end
            end
        end
    end)
    print("Server: BaseSunflowerService module loaded.")
end

return BaseSunflowerService

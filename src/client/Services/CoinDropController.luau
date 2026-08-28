-- src/client/Services/CoinDropController.luau
local CoinDropController = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local COIN_IMAGE_ID = "rbxassetid://102426033120992"
local TACO_IMAGE_ID = "rbxassetid://119494958086601"
local EXPLOSION_IMAGE_ID = "rbxassetid://123456"
local SUN_PICKUP_SOUND_ID = "rbxassetid://116731565409481"
local X2_SUN_GAME_PASS_ID = 1856661235
local ownsX2SunCache = false
local MAX_HARVEST_SUN_VISUALS = 6
local MAX_ZOMBOSS_TACO_VISUALS = 120
local ZOMBOSS_TACO_FLY_DELAY_SECONDS = 1
local HARVEST_SUN_POOL_LIMIT = 18
local harvestSunPool = {}

local function ownsX2SunPass()
    if ownsX2SunCache then
        return true
    end

    local player = Players.LocalPlayer
    local success, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, X2_SUN_GAME_PASS_ID)
    end)

    if success and result == true then
        ownsX2SunCache = true
        return true
    end

    return false
end

local function getSunPickupDisplayText(amount, isX2)
    if isX2 then
        return "+" .. UIEffectUtil.FormatNumber(amount) .. "x2"
    end
    return nil
end

local function playSunPickupSound()
    -- 直接用音效 AssetId 创建本地 Sound，避免 SoundService 中对象名/路径不一致导致找不到或不响
    local pickupSound = Instance.new("Sound")
    pickupSound.Name = "LocalSunPickupSound"
    pickupSound.SoundId = SUN_PICKUP_SOUND_ID
    pickupSound.Volume = 1
    pickupSound.Parent = SoundService
    SoundService:PlayLocalSound(pickupSound)
    Debris:AddItem(pickupSound, 3)
end

local function getLocalRoot()
    local char = Players.LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHarvestSunVisualCount(amountNumber)
    if amountNumber >= 200000 then
        return 6
    elseif amountNumber >= 50000 then
        return 5
    elseif amountNumber >= 10000 then
        return 4
    elseif amountNumber >= 2000 then
        return 3
    elseif amountNumber >= 500 then
        return 2
    end

    return 1
end

local function createLocalSunIcon(position, imageId, partName)
    local sunPart = table.remove(harvestSunPool)
    local gui = sunPart and sunPart:FindFirstChildOfClass("BillboardGui")
    local img = gui and gui:FindFirstChildOfClass("ImageLabel")
    local iconImageId = imageId or COIN_IMAGE_ID

    if not sunPart then
        sunPart = Instance.new("Part")
        sunPart.Size = Vector3.new(1.3, 1.3, 1.3)
        sunPart.Shape = Enum.PartType.Ball
        sunPart.Transparency = 1

        gui = Instance.new("BillboardGui")
        gui.Size = UDim2.new(2.5, 0, 2.5, 0)
        gui.AlwaysOnTop = true
        gui.Parent = sunPart

        img = Instance.new("ImageLabel")
        img.Size = UDim2.new(1, 0, 1, 0)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = gui
    end

    sunPart.Name = partName or "LocalHarvestSun"
    sunPart.Anchored = true
    sunPart.CanCollide = false
    sunPart.CanQuery = false
    sunPart.CanTouch = false
    sunPart.AssemblyLinearVelocity = Vector3.zero
    sunPart.AssemblyAngularVelocity = Vector3.zero
    sunPart.Position = position
    sunPart:SetAttribute("InHarvestSunPool", false)
    if gui then gui.Enabled = true end
    if img then
        img.Image = iconImageId
        img.ImageTransparency = 0
    end
    sunPart.Parent = workspace

    return sunPart, gui, img
end

local function releaseLocalSunIcon(sunPart)
    if not sunPart then return end
    if sunPart:GetAttribute("InHarvestSunPool") then return end

    local gui = sunPart:FindFirstChildOfClass("BillboardGui")
    local img = gui and gui:FindFirstChildOfClass("ImageLabel")
    if gui then gui.Enabled = false end
    if img then img.ImageTransparency = 0 end

    sunPart:SetAttribute("InHarvestSunPool", true)
    sunPart.Parent = nil

    if #harvestSunPool >= HARVEST_SUN_POOL_LIMIT then
        sunPart:Destroy()
        return
    end

    table.insert(harvestSunPool, sunPart)
end

local function playTacoCollectPopup(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return
    end

    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = playerGui:FindFirstChild("TacoCollectGui") or Instance.new("ScreenGui")
    screenGui.ResetOnSpawn = false
    screenGui.Name = "TacoCollectGui"
    screenGui.DisplayOrder = 101
    screenGui.Parent = playerGui

    local startX = math.random(35, 65) / 100
    local startY = math.random(22, 48) / 100
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Position = UDim2.new(startX, 0, startY, 0)
    container.Size = UDim2.new(0, 180, 0, 60)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Parent = screenGui

    local icon = Instance.new("ImageLabel")
    icon.BackgroundTransparency = 1
    icon.Image = TACO_IMAGE_ID
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Size = UDim2.new(0, 60, 0, 60)
    icon.Position = UDim2.new(0, 0, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.Parent = container

    local textLabel = Instance.new("TextLabel")
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "+" .. UIEffectUtil.FormatNumber(amount)
    textLabel.TextColor3 = Color3.fromRGB(255, 235, 140)
    textLabel.TextStrokeColor3 = Color3.fromRGB(120, 65, 15)
    textLabel.TextStrokeTransparency = 0
    textLabel.Font = Enum.Font.GothamBlack
    textLabel.TextScaled = true
    textLabel.Size = UDim2.new(0, 110, 0, 50)
    textLabel.Position = UDim2.new(0, 66, 0.5, 0)
    textLabel.AnchorPoint = Vector2.new(0, 0.5)
    textLabel.Parent = container

    local popScale = Instance.new("UIScale")
    popScale.Scale = 0
    popScale.Parent = container
    TweenService:Create(popScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
    TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(startX + math.random(-4, 4) / 100, 0, startY - 0.04, 0),
    }):Play()

    task.delay(0.9, function()
        if not container or not container.Parent then
            return
        end

        TweenService:Create(container, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(container.Position.X.Scale, container.Position.X.Offset, container.Position.Y.Scale - 0.08, container.Position.Y.Offset),
        }):Play()
        TweenService:Create(icon, TweenInfo.new(0.35), {ImageTransparency = 1}):Play()
        TweenService:Create(textLabel, TweenInfo.new(0.35), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }):Play()
        Debris:AddItem(container, 0.45)
    end)
end

local function finishZombossTacoCollect(amount)
    playSunPickupSound()
    playTacoCollectPopup(amount)
end

local function playZombossTacoDrop(payload)
    if type(payload) ~= "table" then
        return
    end

    local amount = math.max(0, math.floor(tonumber(payload.Amount) or 0))
    if amount <= 0 then
        return
    end

    local visualCount = math.max(1, math.floor(tonumber(payload.VisualCount) or amount))
    visualCount = math.clamp(visualCount, 1, MAX_ZOMBOSS_TACO_VISUALS)

    local origin = nil
    if typeof(payload.OriginPosition) == "Vector3" then
        origin = payload.OriginPosition
    else
        local root = getLocalRoot()
        origin = root and root.Position
    end

    if not origin then
        finishZombossTacoCollect(amount)
        return
    end

    origin += Vector3.new(0, 3, 0)
    local tacoParts = {}

    for i = 1, visualCount do
        local tacoPart, _, img = createLocalSunIcon(origin, TACO_IMAGE_ID, "LocalZombossTaco")
        local angle = (i / visualCount) * math.pi * 2 + (math.random() - 0.5) * 0.55
        local radius = 1.8 + math.random() * 4.2
        local burstPos = origin + Vector3.new(
            math.cos(angle) * radius,
            1.2 + math.random() * 3.8,
            math.sin(angle) * radius
        )

        table.insert(tacoParts, {
            Part = tacoPart,
            Image = img,
        })

        TweenService:Create(
            tacoPart,
            TweenInfo.new(0.24 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = burstPos}
        ):Play()
    end

    task.delay(ZOMBOSS_TACO_FLY_DELAY_SECONDS, function()
        local root = getLocalRoot()
        if not root then
            for _, tacoInfo in ipairs(tacoParts) do
                releaseLocalSunIcon(tacoInfo.Part)
            end
            finishZombossTacoCollect(amount)
            return
        end

        local remaining = 0
        local didFinish = false
        local function finishOnce()
            if didFinish then
                return
            end
            didFinish = true
            finishZombossTacoCollect(amount)
        end

        for _, tacoInfo in ipairs(tacoParts) do
            local tacoPart = tacoInfo.Part
            if tacoPart and tacoPart.Parent then
                remaining += 1
                local targetPos = root.Position + Vector3.new(
                    (math.random() - 0.5) * 1.2,
                    1 + math.random() * 1.2,
                    (math.random() - 0.5) * 1.2
                )
                local flyTween = TweenService:Create(
                    tacoPart,
                    TweenInfo.new(0.32 + math.random() * 0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
                    {Position = targetPos}
                )
                if tacoInfo.Image then
                    TweenService:Create(tacoInfo.Image, TweenInfo.new(0.35), {ImageTransparency = 1}):Play()
                end

                flyTween:Play()
                flyTween.Completed:Connect(function()
                    releaseLocalSunIcon(tacoPart)
                    remaining -= 1
                    if remaining <= 0 then
                        finishOnce()
                    end
                end)
            end
        end

        if remaining <= 0 then
            finishOnce()
            return
        end

        task.delay(1.4, function()
            if didFinish then
                return
            end

            for _, tacoInfo in ipairs(tacoParts) do
                if tacoInfo.Part and tacoInfo.Part.Parent then
                    releaseLocalSunIcon(tacoInfo.Part)
                end
            end
            finishOnce()
        end)
    end)
end

function CoinDropController.Init()
    local playDropRE = ReplicatedStorage:WaitForChild("PlayCoinDropRE")
    local pickupRE = ReplicatedStorage:WaitForChild("PickupCoinRE")

    local harvestRE = ReplicatedStorage:FindFirstChild("HarvestSunRE")
    if harvestRE then
        harvestRE.OnClientEvent:Connect(function(amount, startPos, isX2Sun)
            local amountNumber = math.floor(tonumber(amount) or 0)
            local displayAmount = amountNumber > 0 and amountNumber or 0
            local displayText = getSunPickupDisplayText(displayAmount, isX2Sun == true)

            if startPos and getLocalRoot() and amountNumber > 0 then
                local origin = startPos + Vector3.new(0, 3, 0)
                local sunCount = math.clamp(getHarvestSunVisualCount(amountNumber), 1, MAX_HARVEST_SUN_VISUALS)
                local sunParts = {}

                for i = 1, sunCount do
                    local sunPart, gui, img = createLocalSunIcon(origin)
                    local angle = (i / sunCount) * math.pi * 2 + (math.random() - 0.5) * 0.4
                    local radius = 1.5 + math.random() * 2.5
                    local burstPos = origin + Vector3.new(
                        math.cos(angle) * radius,
                        1.5 + math.random() * 2.5,
                        math.sin(angle) * radius
                    )

                    table.insert(sunParts, {
                        Part = sunPart,
                        Gui = gui,
                        Image = img,
                    })

                    TweenService:Create(
                        sunPart,
                        TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {Position = burstPos}
                    ):Play()

                    task.wait(0.025)
                end

                task.wait(0.55)

                local root = getLocalRoot()
                if not root then
                    for _, sunInfo in ipairs(sunParts) do
                        releaseLocalSunIcon(sunInfo.Part)
                    end
                    UIEffectUtil.Play2DCollectEffect(amountNumber, nil, displayText)
                    return
                end

                local remaining = #sunParts
                local didFinish = false

                local function finishHarvestCollect()
                    if didFinish then return end
                    didFinish = true
                    playSunPickupSound()
                    UIEffectUtil.Play2DCollectEffect(amountNumber, nil, displayText)
                end

                for _, sunInfo in ipairs(sunParts) do
                    local sunPart = sunInfo.Part
                    if sunPart and sunPart.Parent then
                        local flyTween = TweenService:Create(
                            sunPart,
                            TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
                            {Position = root.Position}
                        )
                        flyTween:Play()
                        flyTween.Completed:Connect(function()
                            releaseLocalSunIcon(sunPart)
                            remaining -= 1
                            if remaining <= 0 then
                                finishHarvestCollect()
                            end
                        end)
                    else
                        remaining -= 1
                        if remaining <= 0 then
                            finishHarvestCollect()
                        end
                    end
                end

                task.delay(1.2, function()
                    if didFinish then return end
                    for _, sunInfo in ipairs(sunParts) do
                        if sunInfo.Part and sunInfo.Part.Parent then
                            releaseLocalSunIcon(sunInfo.Part)
                        end
                    end
                    finishHarvestCollect()
                end)
                return
            end
            -- 如果没有获取到位置，作为兜底直接播放 UI 动画
            UIEffectUtil.Play2DCollectEffect(displayAmount, nil, displayText)
        end)
    end

    local tacoDropRE = ReplicatedStorage:WaitForChild("ZombossTacoDropRE", 10)
    if tacoDropRE then
        tacoDropRE.OnClientEvent:Connect(playZombossTacoDrop)
    end

    playDropRE.OnClientEvent:Connect(function(dropPosition, coinCount, totalValue)
        coinCount = math.max(1, math.floor(tonumber(coinCount) or 1))
        totalValue = math.max(1, math.floor(tonumber(totalValue) or 1))
        local valuePerCoin = math.floor(totalValue / coinCount)
        if valuePerCoin < 1 then valuePerCoin = 1 end

        local explosionPart = Instance.new("Part")
        explosionPart.Anchored = true; explosionPart.CanCollide = false; explosionPart.Transparency = 1; explosionPart.Position = dropPosition; explosionPart.Parent = workspace
        local emitter = Instance.new("ParticleEmitter")
        emitter.Texture = EXPLOSION_IMAGE_ID; emitter.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0)); emitter.LightEmission = 1; emitter.ZOffset = 1
        emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 3), NumberSequenceKeypoint.new(1, 0)})
        emitter.Speed = NumberRange.new(20, 50); emitter.Lifetime = NumberRange.new(0.3, 0.6); emitter.SpreadAngle = Vector2.new(180, 180); emitter.Drag = 5; emitter.Parent = explosionPart
        emitter:Emit(30); Debris:AddItem(explosionPart, 2)

        for i = 1, coinCount do
            local coin = Instance.new("Part")
            coin.Name = "LocalDroppedCoin"; coin.Size = Vector3.new(1.2, 1.2, 1.2); coin.Shape = Enum.PartType.Ball; coin.Transparency = 1; coin.CanCollide = true
            local offsetX = (math.random() - 0.5) * 3; local offsetY = math.random() * 2; local offsetZ = (math.random() - 0.5) * 3
            coin.Position = dropPosition + Vector3.new(offsetX, offsetY, offsetZ)
            coin.CustomPhysicalProperties = PhysicalProperties.new(1, 0.6, 0.5, 100, 100)

            local gui = Instance.new("BillboardGui")
            gui.Size = UDim2.new(2.5, 0, 2.5, 0); gui.AlwaysOnTop = false; gui.Parent = coin
            local img = Instance.new("ImageLabel")
            img.Size = UDim2.new(1, 0, 1, 0); img.BackgroundTransparency = 1; img.Image = COIN_IMAGE_ID; img.Parent = gui

            local att0 = Instance.new("Attachment", coin); att0.Position = Vector3.new(0, 0.5, 0)
            local att1 = Instance.new("Attachment", coin); att1.Position = Vector3.new(0, -0.5, 0)
            local trail = Instance.new("Trail"); trail.Attachment0 = att0; trail.Attachment1 = att1
            trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80)); trail.Lifetime = 0.3; trail.LightEmission = 1
            trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }); trail.Parent = coin

            local sensor = Instance.new("Part")
            sensor.Name = "PickupSensor"; sensor.Shape = Enum.PartType.Ball; sensor.Size = Vector3.new(24, 24, 24)
            sensor.Transparency = 1; sensor.CanCollide = false; sensor.CanQuery = false; sensor.Massless = true
            local weld = Instance.new("WeldConstraint"); weld.Part0 = coin; weld.Part1 = sensor; weld.Parent = coin
            sensor.CFrame = coin.CFrame; sensor.Parent = coin

            coin.Parent = workspace
            coin.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20), math.random(15, 35), math.random(-20, 20))

            task.delay(1, function()
                if trail then trail.Enabled = false end
                if coin and coin.Parent then coin.Anchored = true; coin.CanCollide = false end
            end)

            local canPickup = false; local isCollected = false
            task.delay(0.8, function() canPickup = true end)

           local connection
            connection = sensor.Touched:Connect(function(hit)
                if not canPickup or isCollected then return end
                local localPlayer = Players.LocalPlayer

                local character = localPlayer.Character
                if hit:IsDescendantOf(character) then
                    local humanoid = character:FindFirstChild("Humanoid")
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if humanoid and humanoid.Health > 0 and rootPart then
                        isCollected = true; canPickup = false; connection:Disconnect()

                        -- 让阳光/金币飞向玩家身体
                        coin.Anchored = true
                        if trail then trail.Enabled = true end -- 开启拖尾让飞行更新好看

                        -- 目标位置设定在玩家胸口处 (RootPart 稍微偏上一点击)
                        local targetPos = rootPart.Position + Vector3.new(0, 1, 0)

                        -- 创建一个 0.3 秒的快速飞行 Tween (吸入身体的感觉)
                        local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
                        local tween = TweenService:Create(coin, tweenInfo, {Position = targetPos})

                        -- 让图片在飞行的同时间逐渐变透明
                        if img then TweenService:Create(img, TweenInfo.new(0.3), {ImageTransparency = 1}):Play() end

                        tween:Play()

                        -- 等待飞行接触到玩家身体后，再弹出 UI 动画
                        tween.Completed:Connect(function()
                            playSunPickupSound()
                            coin.Transparency = 1
                            if gui then gui.Enabled = false end
                            if trail then trail.Enabled = false end

                            -- 呼出屏幕上的 UI 增加动画，并通知服务端真正加钱
                            local displayText = getSunPickupDisplayText(valuePerCoin, ownsX2SunPass())
                            UIEffectUtil.Play2DCollectEffect(valuePerCoin, function()
                                pickupRE:FireServer(valuePerCoin, false)
                                coin:Destroy()
                            end, displayText)
                        end)
                    end
                end
            end)

            task.delay(5, function()
                if isCollected or not coin or not coin.Parent then return end
                local localPlayer = Players.LocalPlayer; local targetSunflower = nil
                local plotsFolder = workspace:FindFirstChild("Plots")
                if plotsFolder then
                    for _, plot in ipairs(plotsFolder:GetChildren()) do
                        local baseSun = plot:FindFirstChild("BaseSunflower")
                        if baseSun and baseSun:GetAttribute("OwnerId") == localPlayer.UserId then targetSunflower = baseSun; break end
                    end
                end

                if targetSunflower then
                    isCollected = true; canPickup = false; if connection then connection:Disconnect() end
                    coin.Anchored = true; if trail then trail.Enabled = true end

                    -- 彻底移除了向日葵的张嘴动画逻辑
                    -- 动画引擎太脆弱了，我们不播动画了，直接让金币飞过去即可
                    -- 向日葵本身就在播放待机动画，金币吸入效果不受影响

                    local targetPos = targetSunflower:GetPivot().Position
                    local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In)
                    local tween = TweenService:Create(coin, tweenInfo, {Position = targetPos})
                    if img then TweenService:Create(img, TweenInfo.new(0.8), {ImageTransparency = 1}):Play() end
                    tween:Play()
                    tween.Completed:Connect(function()
                        pickupRE:FireServer(valuePerCoin, true)
                        coin:Destroy()
                    end)
                end
            end)
            Debris:AddItem(coin, 300)
        end
    end)
    print("Client: CoinDropController streamlined version loaded; sunflower animation calls disabled.")
end

return CoinDropController

-- src/client/Services/CoinDropController.luau
local CoinDropController = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil) 

local COIN_IMAGE_ID = "rbxassetid://102426033120992"
local EXPLOSION_IMAGE_ID = "rbxassetid://123456" 
local SUN_PICKUP_SOUND_ID = "rbxassetid://116731565409481"

local function playSunPickupSound()
    -- 直接用音效 AssetId 创建本地 Sound，避免 SoundService 中对象名/路径不一致导致找不到或不响。
    local pickupSound = Instance.new("Sound")
    pickupSound.Name = "LocalSunPickupSound"
    pickupSound.SoundId = SUN_PICKUP_SOUND_ID
    pickupSound.Volume = 1
    pickupSound.Parent = SoundService
    SoundService:PlayLocalSound(pickupSound)
    Debris:AddItem(pickupSound, 3)
end

function CoinDropController.Init()
    local playDropRE = ReplicatedStorage:WaitForChild("PlayCoinDropRE")
    local pickupRE = ReplicatedStorage:WaitForChild("PickupCoinRE")

    local harvestRE = ReplicatedStorage:FindFirstChild("HarvestSunRE")
    if harvestRE then
        harvestRE.OnClientEvent:Connect(function(amount, startPos)
            -- 如果服务端传来了起点坐标，就播放 3D 飞行特效
            if startPos then
                local char = Players.LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                
                if root then
                    -- 1. 创建一个用于飞行的视觉阳光
                    local sunPart = Instance.new("Part")
                    sunPart.Anchored = true
                    sunPart.CanCollide = false
                    sunPart.Transparency = 1
                    -- 让阳光从底座稍微偏上的位置冒出来
                    sunPart.Position = startPos + Vector3.new(0, 4, 0) 
                    
                    local gui = Instance.new("BillboardGui")
                    gui.Size = UDim2.new(3, 0, 3, 0)
                    gui.AlwaysOnTop = true
                    gui.Parent = sunPart
                    
                    local img = Instance.new("ImageLabel")
                    img.Size = UDim2.new(1, 0, 1, 0)
                    img.BackgroundTransparency = 1
                    img.Image = COIN_IMAGE_ID -- 使用模块顶部的统一阳光/金币图标
                    img.Parent = gui
                    
                    sunPart.Parent = workspace
                    
                    -- 2. 让阳光飞向玩家的身体
                    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In)
                    local tween = TweenService:Create(sunPart, tweenInfo, {Position = root.Position})
                    tween:Play()
                    
                    -- 3. 飞行结束（击中玩家）后销毁实体，再呼出 UI 动画
                    tween.Completed:Connect(function()
                        playSunPickupSound()
                        sunPart:Destroy()
                        UIEffectUtil.Play2DCollectEffect(amount) 
                    end)
                    return
                end
            end
            
            -- 如果没有获取到位置，作为兜底直接播放 UI 动画
            UIEffectUtil.Play2DCollectEffect(amount) 
        end)
    end

    playDropRE.OnClientEvent:Connect(function(dropPosition, coinCount, totalValue)
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
                        
                        -- [🌟 新增：让阳光/金币飞向玩家身体]
                        coin.Anchored = true 
                        if trail then trail.Enabled = true end -- 开启拖尾让飞行更好看
                        
                        -- 目标位置设定在玩家胸口处 (RootPart 稍微偏上一点)
                        local targetPos = rootPart.Position + Vector3.new(0, 1, 0)
                        
                        -- 创建一个 0.3 秒的快速飞行 Tween (吸入身体的感觉)
                        local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
                        local tween = TweenService:Create(coin, tweenInfo, {Position = targetPos})
                        
                        -- 让图片在飞行的同时逐渐变透明
                        if img then TweenService:Create(img, TweenInfo.new(0.3), {ImageTransparency = 1}):Play() end
                        
                        tween:Play()
                        
                        -- [🌟 重点：等待飞行结束接触到玩家身体后，再弹出 UI 动画]
                        tween.Completed:Connect(function()
                            playSunPickupSound()
                            coin.Transparency = 1
                            if gui then gui.Enabled = false end
                            if trail then trail.Enabled = false end
                            
                            -- 呼出屏幕上的 UI 增加动画，并通知服务端真正加钱
                            UIEffectUtil.Play2DCollectEffect(valuePerCoin, function() 
                                pickupRE:FireServer(valuePerCoin, false)
                                coin:Destroy()
                            end)
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

                    -- ==========================================
                    -- [🌟 修复：彻底移除了向日葵的张嘴动画逻辑]
                    -- 动画引擎太脆弱了，我们不播动画了，直接让金币飞过去即可。
                    -- 向日葵本身就在播放待机动画，金币吸入效果不受影响！
                    -- ==========================================

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
    print("客户端：CoinDropController 精简版已实装，不再调用向日葵动画！")
end

return CoinDropController
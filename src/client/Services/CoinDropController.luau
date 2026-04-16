-- src/client/CoinDropController.luau
local CoinDropController = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local COIN_IMAGE_ID = "rbxassetid://102426033120992"
local EXPLOSION_IMAGE_ID = "rbxassetid://123456"

function CoinDropController.Init()
    local playDropRE = ReplicatedStorage:WaitForChild("PlayCoinDropRE")
    local pickupRE = ReplicatedStorage:WaitForChild("PickupCoinRE")

    -- 接收服务器的爆金币指令
    playDropRE.OnClientEvent:Connect(function(dropPosition, coinCount, totalValue)
        local valuePerCoin = math.floor(totalValue / coinCount)
        if valuePerCoin < 1 then valuePerCoin = 1 end

        -- 【1. 生成爆炸火花特效 (本地渲染，0延迟)】
        local explosionPart = Instance.new("Part")
        explosionPart.Anchored = true; explosionPart.CanCollide = false
        explosionPart.Transparency = 1; explosionPart.Position = dropPosition
        explosionPart.Parent = workspace

        local emitter = Instance.new("ParticleEmitter")
        emitter.Texture = EXPLOSION_IMAGE_ID
        emitter.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0)) 
        emitter.LightEmission = 1; emitter.ZOffset = 1         
        emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 3), NumberSequenceKeypoint.new(1, 0)})
        emitter.Speed = NumberRange.new(20, 50); emitter.Lifetime = NumberRange.new(0.3, 0.6)
        emitter.SpreadAngle = Vector2.new(180, 180); emitter.Drag = 5 
        emitter.Parent = explosionPart
        
        emitter:Emit(30) 
        Debris:AddItem(explosionPart, 2) 

        -- 【2. 生成金币 (纯客户端物理，极度丝滑)】
        for i = 1, coinCount do
            local coin = Instance.new("Part")
            coin.Name = "LocalDroppedCoin"
            coin.Size = Vector3.new(1.2, 1.2, 1.2); coin.Shape = Enum.PartType.Ball
            coin.Transparency = 1; coin.CanCollide = true
            
            local offsetX = (math.random() - 0.5) * 3
            local offsetY = math.random() * 2          
            local offsetZ = (math.random() - 0.5) * 3
            coin.Position = dropPosition + Vector3.new(offsetX, offsetY, offsetZ)
            coin.CustomPhysicalProperties = PhysicalProperties.new(1, 0.6, 0.5, 100, 100)

            local gui = Instance.new("BillboardGui")
            gui.Size = UDim2.new(2.5, 0, 2.5, 0); gui.AlwaysOnTop = false; gui.Parent = coin

            local img = Instance.new("ImageLabel")
            img.Size = UDim2.new(1, 0, 1, 0); img.BackgroundTransparency = 1
            img.Image = COIN_IMAGE_ID; img.Parent = gui

            local att0 = Instance.new("Attachment", coin); att0.Position = Vector3.new(0, 0.5, 0)
            local att1 = Instance.new("Attachment", coin); att1.Position = Vector3.new(0, -0.5, 0)
            local trail = Instance.new("Trail")
            trail.Attachment0 = att0; trail.Attachment1 = att1
            trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80))
            trail.Lifetime = 0.3; trail.LightEmission = 1 
            trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
            trail.Parent = coin

            local sensor = Instance.new("Part")
            sensor.Name = "PickupSensor"
            sensor.Shape = Enum.PartType.Ball; sensor.Size = Vector3.new(24, 24, 24)
            sensor.Transparency = 1; sensor.CanCollide = false 
            sensor.CanQuery = false; sensor.Massless = true     
            
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = coin; weld.Part1 = sensor; weld.Parent = coin
            sensor.CFrame = coin.CFrame; sensor.Parent = coin

            -- 既然是本地生成的，根本不需要 SetNetworkOwner！直接进 workspace 就飞！
            coin.Parent = workspace
            
            local velocityX = math.random(-20, 20)
            local velocityY = math.random(15, 35) 
            local velocityZ = math.random(-20, 20)
            coin.AssemblyLinearVelocity = Vector3.new(velocityX, velocityY, velocityZ)

            task.delay(1, function() 
                if trail then trail.Enabled = false end 
                if coin and coin.Parent then
                    coin.Anchored = true; coin.CanCollide = false 
                end
            end)

            local canPickup = false
            task.delay(0.8, function() canPickup = true end) 

            local connection
            connection = sensor.Touched:Connect(function(hit)
                if not canPickup then return end
                
                -- 因为这是在客户端运行的，所以我们只认本地玩家的身体！
                local localPlayer = Players.LocalPlayer
                local character = localPlayer.Character
                
                -- 如果碰到金币的人不是我自己的身体，直接忽略！(防止别人帮你吸金币)
                if hit:IsDescendantOf(character) then
                    local humanoid = character:FindFirstChild("Humanoid")
                    local rootPart = character:FindFirstChild("HumanoidRootPart") 
                    
                    if humanoid and humanoid.Health > 0 and rootPart then
                        canPickup = false; connection:Disconnect() 
                        coin.Anchored = true 
                        if trail then trail.Enabled = true end 
                        
                        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                        local tween = TweenService:Create(coin, tweenInfo, {Position = rootPart.Position})
                        tween:Play()
                        
                        tween.Completed:Connect(function()
                            -- [🌟 最重要的一步] 动画播完了，打电报让服务器给钱！
                            pickupRE:FireServer(valuePerCoin)
                            coin:Destroy()
                        end)
                    end
                end
            end)
            Debris:AddItem(coin, 300) 
        end
    end)

    print("客户端：CoinDropController 加载完毕！纯本地渲染版，极致流畅！")
end

return CoinDropController
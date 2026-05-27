-- src/server/Services/BaseSunflowerService.luau
local BaseSunflowerService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- 专门用来追踪所有玩家的基地向日葵，方便实时更新
local activeSunflowers = {}

-- ==========================================
-- [核心算法] 计算缩放并更新悬浮 UI
-- ==========================================
local function UpdateSunflowerScale(sunflower, totalSun)
    if not sunflower or not sunflower:IsA("Model") then return end
    local minScale = 1
    local maxScale = 50
    local threshold = 1000000
    
    -- 太阳数量为0时，自动缩回1倍
    local scale = minScale + (math.min(totalSun, threshold) / threshold) * (maxScale - minScale)
    
    if sunflower.PrimaryPart then
        sunflower:ScaleTo(scale)
    end

    -- 🌟 修复：去我们创建的虚拟独立 UI 锚点方块上寻找 UI
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
            -- 🌟 遍历前后两面的 SurfaceGui 同步更新数值
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
                        textLabel.Text = tostring(displaySun)
                    end
                end
            end
        end
    end
end

-- ==========================================
-- [杀毒软件] 强行隐藏特效外壳
-- ==========================================
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

-- ==========================================
-- [主入口] 生成基地向日葵
-- ==========================================
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
            
            -- [打钢筋] 防掉落与动画适配
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
            
            -- ==========================================
            -- [创建悬浮UI (🌟 完美静止挂载中枢：悬空+防遮挡+双面显示)]
            -- ==========================================
            if collectSunPart then
                -- 1. 销毁可能存在的旧独立锚点
                local oldAnchor = collectSunPart:FindFirstChild("SunGuiAnchor")
                if oldAnchor then oldAnchor:Destroy() end

                -- 2. 创建一个绝对静止、透明的不碰撞看板部件
                local guiAnchor = Instance.new("Part")
                guiAnchor.Name = "SunGuiAnchor"
                guiAnchor.Size = Vector3.new(4, 1.5, 0.05) 
                guiAnchor.Transparency = 1       -- 隐形
                guiAnchor.Anchored = true        -- 静止不动
                guiAnchor.CanCollide = false     -- 无碰撞
                guiAnchor.CanQuery = false       -- 防鼠标点击拦截
                guiAnchor.CanTouch = false

                -- 3. 悬浮在 CollectSun 上方固定 5 格高空（可根据视线随意微调高度）
                guiAnchor.CFrame = collectSunPart.CFrame * CFrame.new(0, 5, 0)
                guiAnchor.Parent = collectSunPart

                -- 4. 🌟 双面渲染渲染逻辑：同时渲染正面和背面，防止转镜头时转到反面看不见
                local renderFaces = { Enum.NormalId.Front, Enum.NormalId.Back }
                
                for _, faceDirection in ipairs(renderFaces) do
                    local sGui = Instance.new("SurfaceGui")
                    sGui.Name = "SunCounterGui"
                    sGui.Face = faceDirection
                    sGui.LightInfluence = 0          -- 纯亮发光字，不受全地图阴影影响
                    
                    -- 🌟 核心修复：开启 AlwaysOnTop！
                    -- 这样即便向日葵模型膨胀把这个锚点Part整个吞进肚子里，UI 依然会雷打不动地穿透渲染在最前面！
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

            -- ==========================================
            -- [🌟 修改核心：自动靠近底座方块收割]
            -- ==========================================
            local oldPrompt = collectSunPart:FindFirstChild("HarvestPrompt")
            if oldPrompt then oldPrompt:Destroy() end

            task.spawn(function()
                local isHarvesting = false
                local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
                local TweenService = game:GetService("TweenService")
                local Debris = game:GetService("Debris")
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
                        
                        -- 如果累积了阳光，开启由浅入深的丰收演出
                        if pData and (pData.TotalSun or 0) > 0 then
                            isHarvesting = true
                            local amount = pData.TotalSun
                            
                            -- 1. 立即清空基地的暂存阳光，让向日葵头顶的 3D 看板计数器立刻归零
                            pData.TotalSun = 0
                            local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
                            if updateInventoryRE then updateInventoryRE:FireClient(player, pData) end
                            
                            -- 2. 计算阳光切片数量 (最少切成 5 个，最多 20 个)
                            local numSuns = math.clamp(math.floor(amount / 50), 5, 20) 
                            local rewardPerSun = math.floor(amount / numSuns) -- 每一个球代表的实际面值
                            local remainder = amount % numSuns -- 无法整除的余数留给最后一个球
                            
                            local sunParts = {}
                            
                            for i = 1, numSuns do
                                -- 创建隐形的物理外壳，用来承载碰撞和弹跳效果
                                local sunPart = Instance.new("Part")
                                sunPart.Size = Vector3.new(1.3, 1.3, 1.3)
                                sunPart.Shape = Enum.PartType.Ball
                                sunPart.Transparency = 1 -- 🌟 【核心修改】：完全隐藏原本丑陋的黄球外壳
                                sunPart.CanCollide = true -- 允许在地上由于重力自然弹跳
                                sunPart.Position = collectSunPart.Position + Vector3.new(0, 3, 0)
                                
                                -- 🌟 【核心修改】：挂载 BillboardGui，渲染你提供的专属 2D 阳光图片
                                local billboard = Instance.new("BillboardGui")
                                billboard.Size = UDim2.new(2.5, 0, 2.5, 0) -- 在 3D 世界中的渲染大小
                                billboard.AlwaysOnTop = true -- 穿透植物和方块，防止被埋进地里
                                billboard.Parent = sunPart
                                
                                local imageLabel = Instance.new("ImageLabel")
                                imageLabel.Size = UDim2.new(1, 0, 1, 0)
                                imageLabel.BackgroundTransparency = 1
                                imageLabel.Image = "rbxassetid://102426033120992" -- 🌟 使用你提供的阳光材质图片
                                imageLabel.Parent = billboard
                                
                                -- 给阳光赋予一个向上和向四周喷涌开来的 Velocity 物理爆发力
                                local rx = (math.random() - 0.5) * 35
                                local ry = math.random(25, 55)
                                local rz = (math.random() - 0.5) * 35
                                sunPart.Velocity = Vector3.new(rx, ry, rz)
                                
                                sunPart.Parent = Workspace
                                table.insert(sunParts, sunPart)
                                Debris:AddItem(sunPart, 7) -- 防残留垃圾清理锁
                                
                                -- 产生一个极短的间隔，做出源源不断往外“吐”阳光的喷泉喷发感
                                task.wait(0.06) 
                            end
                            
                            -- 3. 让这一地金灿灿的 2D 阳光在地上自然散落并逗留 2 秒钟
                            task.wait(2)
                            
                            -- 4. 🌟【核心修改】：让阳光像小蛇一样排成一列，逐一吸附到玩家身上，并分批加钱！
                            for i, sun in ipairs(sunParts) do
                                if sun and sun.Parent then
                                    local charNow = player.Character
                                    local rootNow = charNow and charNow:FindFirstChild("HumanoidRootPart")
                                    
                                    if rootNow then
                                        sun.CanCollide = false -- 关闭物理碰撞，准备凌空飞行
                                        sun.Anchored = true 
                                        
                                        -- 精确计算当前这颗阳光到身体时要加的额度
                                        local currentReward = rewardPerSun
                                        if i == numSuns then
                                            currentReward = rewardPerSun + remainder -- 最后一颗补齐余数，确保一分不差
                                        end
                                        
                                        -- 播放飞向玩家胸口的丝滑动画
                                        local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
                                        local tween = TweenService:Create(sun, tweenInfo, {Position = rootNow.Position})
                                        tween:Play()
                                        
                                        -- 重点：当该颗阳光“触碰”到玩家身体的瞬间，立刻结算这一部分的金币
                                        tween.Completed:Connect(function()
                                            sun:Destroy()
                                            if player and player.Parent then
                                                -- 🌟【核心重构】：逐个递增金币，而不是一次性给完！屏幕上的数字会疯狂跳动！
                                                local finalReward = PlayerDataManager.GiveCoins(player, currentReward)
                                                local isX2Sun = finalReward == currentReward * 2
                                                
                                                -- 通知客户端播放单次加钱的飘字音效和动效
                                                if harvestRE then 
                                                    harvestRE:FireClient(player, currentReward, rootNow.Position, isX2Sun) 
                                                end
                                            end
                                        end)
                                        
                                        -- 🌟 每颗阳光出发飞行的间隔时间。这个时间能产生“流水般吸入身体”的连贯节奏
                                        task.wait(0.08) 
                                    else
                                        sun:Destroy()
                                    end
                                end
                            end
                            
                            -- 5. 等待最后一颗阳光也安全到账，并记录一次总的后台埋点
                            task.wait(0.4)
                            local AnalyticsService = game:GetService("AnalyticsService")
                            AnalyticsService:LogEconomyEvent(
                                player, 
                                Enum.AnalyticsEconomyFlowType.Source, 
                                "Coins", 
                                amount, 
                                pData.Coins,
                                Enum.AnalyticsEconomyTransactionType.Gameplay.Name, 
                                "Sunflower_Collect" 
                            )
                            
                            isHarvesting = false
                        end
                    end
                end
            end)

            -- ==========================================
            -- [装载动画]
            -- ==========================================
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
            print("【向日葵系统】✅ 生成成功！自动收割功能已实装！")
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
    print("服务端：BaseSunflowerService 独立模块加载完毕！")
end

return BaseSunflowerService
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

    local rootPart = sunflower.PrimaryPart or sunflower:FindFirstChildWhichIsA("BasePart")
    if rootPart then
        local gui = rootPart:FindFirstChild("SunCounterGui")
        if gui and gui:FindFirstChild("Container") and gui.Container:FindFirstChild("SunText") then
            local displaySun = totalSun
            -- 大数值转换 (K, M)
            if totalSun >= 1000000 then
                displaySun = string.format("%.1fM", totalSun / 1000000)
            elseif totalSun >= 1000 then
                displaySun = string.format("%.1fK", totalSun / 1000)
            end
            gui.Container.SunText.Text = tostring(displaySun)
            gui.ExtentsOffset = Vector3.new(0, 3 + (scale * 1.5), 0)
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
            -- [创建悬浮UI]
            -- ==========================================
            local rootPart = sunflower.PrimaryPart or sunflower:FindFirstChildWhichIsA("BasePart")
            if rootPart then
                local bgGui = Instance.new("BillboardGui")
                bgGui.Name = "SunCounterGui"; bgGui.Size = UDim2.new(4, 0, 1.5, 0)
                bgGui.ExtentsOffset = Vector3.new(0, 3, 0); bgGui.AlwaysOnTop = true; bgGui.MaxDistance = 150
                
                local container = Instance.new("Frame")
                container.Name = "Container"; container.Size = UDim2.new(1, 0, 1, 0)
                container.BackgroundTransparency = 1; container.Parent = bgGui
                
                local icon = Instance.new("ImageLabel")
                icon.Name = "SunIcon"; icon.Size = UDim2.new(0.3, 0, 0.8, 0); icon.Position = UDim2.new(0, 0, 0.1, 0)
                icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://102426033120992"
                icon.ScaleType = Enum.ScaleType.Fit; icon.Parent = container
                
                local textLabel = Instance.new("TextLabel")
                textLabel.Name = "SunText"; textLabel.Size = UDim2.new(0.65, 0, 0.8, 0); textLabel.Position = UDim2.new(0.35, 0, 0.1, 0)
                textLabel.BackgroundTransparency = 1; textLabel.Text = "0"
                textLabel.TextColor3 = Color3.fromRGB(255, 230, 50); textLabel.TextStrokeTransparency = 0
                textLabel.Font = Enum.Font.GothamBold; textLabel.TextScaled = true; textLabel.Parent = container
                
                bgGui.Parent = rootPart
            end

            -- ==========================================
            -- [🌟 新增核心：一键收割感应区]
            -- ==========================================
           -- 清除该地块上可能残留的旧提示（防止重复生成）
            local oldPrompt = collectSunPart:FindFirstChild("HarvestPrompt")
            if oldPrompt then oldPrompt:Destroy() end

            -- 在收集地块（CollectSun）上创建交互提示，而不是向日葵身上
            local prompt = Instance.new("ProximityPrompt")
            prompt.Name = "HarvestPrompt"
            prompt.ActionText = "收集阳光"
            prompt.ObjectText = "基地地块" -- 文本改成地块相关
            prompt.KeyboardKeyCode = Enum.KeyCode.F
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 15 -- 稍微加大一点距离，让踩上去更容易触发
            prompt.HoldDuration = 0.2
            prompt.Parent = collectSunPart -- 【🌟核心修改】：绑定到地块零件上

            local isHarvesting = false
            prompt.Triggered:Connect(function(triggeringPlayer)
                if isHarvesting then return end
                
                -- 只有基地的所有者才能按 F 收集
                if triggeringPlayer.UserId == player.UserId then
                    local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
                    
                    -- 检查玩家是否有阳光
                    local pData = PlayerDataManager.GetPlayerData(triggeringPlayer)
                    if not pData or (pData.TotalSun or 0) <= 0 then return end
                    
                    local amount = PlayerDataManager.CollectAllSun(triggeringPlayer)
                    
                    if amount > 0 then
                        isHarvesting = true
                        
                        -- 触发客户端飞行金币特效
                        local harvestRE = ReplicatedStorage:FindFirstChild("HarvestSunRE")
                        if harvestRE then harvestRE:FireClient(triggeringPlayer, amount) end
                        
                        -- 1秒防抖冷却
                        task.wait(1)
                        isHarvesting = false
                    end
                else
                    -- 非主人警告
                    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                    if showNotifRE then 
                        showNotifRE:FireClient(triggeringPlayer, "⚠️ 无法操作", "这不是你的基地！") 
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
                track.Looped = true; track:Play()
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
    -- 注册客户端 UI 特效通讯通道
    if not ReplicatedStorage:FindFirstChild("HarvestSunRE") then
        local re = Instance.new("RemoteEvent")
        re.Name = "HarvestSunRE"
        re.Parent = ReplicatedStorage
    end

    -- 体型与UI实时同步器
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
                    -- 玩家退出或向日葵被毁，清理缓存
                    activeSunflowers[userId] = nil
                end
            end
        end
    end)
    print("服务端：BaseSunflowerService 独立模块加载完毕！")
end

return BaseSunflowerService
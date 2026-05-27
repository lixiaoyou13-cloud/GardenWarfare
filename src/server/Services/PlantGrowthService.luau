-- src/server/Services/PlantGrowthService.luau
-- 职责：纯粹负责植物的模型生成、生长表现、变异特效、成熟逻辑
local PlantGrowthService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local NumberFormatUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormatUtil"))
local PlotService = require(script.Parent.PlotService)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local CoinDropService = require(script.Parent.CoinDropService)

-- [终极特效控制系统：支持 Attachment 容器穿透]
function PlantGrowthService.ApplyMutationEffects(model, mutationLevel)
    mutationLevel = mutationLevel or 1
    local effectMap = { [2] = "Glow", [3] = "Lightning", [4] = "HolyLight" }
    
    for lvl, fxName in pairs(effectMap) do
        local shouldEnable = (mutationLevel == lvl)
        for _, node in ipairs(model:GetDescendants()) do
            if node.Name == fxName then
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                        child.Enabled = shouldEnable
                    end
                end
            end
        end
    end
end

-- [生成成熟植物]
function PlantGrowthService.SpawnMaturePlant(soil, itemDetail, plot, plantsFolder, savedMutation)
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local matureModelName = itemDetail.YieldPlant .. "_Plant"
    local matureModel = itemModelsFolder:FindFirstChild(matureModelName) or itemModelsFolder:FindFirstChild(itemDetail.YieldPlant)
    if not matureModel then return nil end
    
    local plotNum = tonumber(string.match(plot.Name, "%d+")) or 1
    local yRotation = (plotNum <= 4) and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, math.rad(90), 0)
    
    local grownPlant = matureModel:Clone()
    grownPlant.Name = itemDetail.YieldPlant
    grownPlant:SetAttribute("IsMature", true)
    grownPlant:SetAttribute("PlantedOn", soil.Name)
    
    local maxYield = itemDetail.YieldCount or 1
    grownPlant:SetAttribute("MaxYield", maxYield)
    grownPlant:SetAttribute("YieldCount", maxYield)
    
    local mutationLevel = savedMutation or 1
    grownPlant:SetAttribute("MutationLevel", mutationLevel)
    local ownerId = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if PlotService.GetPlayerPlot(p) == plot then ownerId = p.UserId; break end
    end
    grownPlant:SetAttribute("OwnerId", ownerId)
    
    if grownPlant:IsA("Model") and grownPlant.PrimaryPart then
        grownPlant:PivotTo(soil.CFrame * CFrame.new(0, soil.Size.Y/2 + grownPlant.PrimaryPart.Size.Y/2, 0) * yRotation)
    elseif grownPlant:IsA("BasePart") then
        grownPlant.CFrame = soil.CFrame * CFrame.new(0, soil.Size.Y/2 + grownPlant.Size.Y/2, 0) * yRotation
    end
    
    local plantConfig = ItemConfig.Plants[itemDetail.YieldPlant]
    local targetAnimId = plantConfig and plantConfig.IdleAnimId
    for _, part in pairs(grownPlant:GetDescendants()) do
        if part:IsA("BasePart") then 
            part.CanCollide = false
            if targetAnimId and grownPlant.PrimaryPart and part == grownPlant.PrimaryPart then
                part.Anchored = true
            elseif part.Name == "Glow" or part.Name == "HolyLight" or part.Name == "Lightning" then
                part.Anchored = true
            else
                part.Anchored = not targetAnimId 
            end
        end
    end
    
    if targetAnimId then
        local animController = grownPlant:FindFirstChildOfClass("AnimationController") or grownPlant:FindFirstChildOfClass("Humanoid")
        if not animController then animController = Instance.new("AnimationController"); animController.Parent = grownPlant end
        local animator = animController:FindFirstChildOfClass("Animator")
        if not animator then animator = Instance.new("Animator"); animator.Parent = animController end
        local anim = Instance.new("Animation"); anim.AnimationId = targetAnimId
        local track = animator:LoadAnimation(anim); track.Priority = Enum.AnimationPriority.Idle; track.Looped = true; track:Play()
    end

    PlantGrowthService.ApplyMutationEffects(grownPlant, mutationLevel)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "MatureUI"
    billboard.Size = UDim2.new(0, 160, 0, 55)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 50
    
    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 1, 0)
    bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bgFrame.BackgroundTransparency = 0.4
    local bgCorner = Instance.new("UICorner"); bgCorner.CornerRadius = UDim.new(0, 8); bgCorner.Parent = bgFrame
    bgFrame.Parent = billboard

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0.45, 0)
    statusLabel.Position = UDim2.new(0, 0, 0.05, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.FredokaOne
    
    local mutName = ItemConfig.MutationName and ItemConfig.MutationName[mutationLevel] or ""
    statusLabel.Text = (mutationLevel > 1) and ("⭐" .. mutName) or "Loading..."
    statusLabel.Parent = bgFrame

    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.Size = UDim2.new(0.9, 0, 0.35, 0)
    barBg.Position = UDim2.new(0.05, 0, 0.55, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    barBg.BackgroundTransparency = 0.5
    local barCorner = Instance.new("UICorner"); barCorner.CornerRadius = UDim.new(0, 4); barCorner.Parent = barBg
    barBg.Parent = bgFrame

    local barFill = Instance.new("Frame")
    barFill.Name = "BarFill"
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0) 
    local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(0, 4); fillCorner.Parent = barFill
    barFill.Parent = barBg

    local progressText = Instance.new("TextLabel")
    progressText.Name = "ProgressText"
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.TextStrokeTransparency = 0.2
    progressText.TextScaled = true
    progressText.Font = Enum.Font.SourceSansBold
    progressText.ZIndex = 2
    progressText.Text = maxYield .. " / " .. maxYield
    progressText.Parent = barBg

    grownPlant:GetAttributeChangedSignal("YieldCount"):Connect(function()
        local current = grownPlant:GetAttribute("YieldCount") or 0
        local max = grownPlant:GetAttribute("MaxYield") or 1
        local ratio = math.clamp(current / max, 0, 1)
        TweenService:Create(barFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
        progressText.Text = current .. " / " .. max
    end)
    
    local rootPart = grownPlant:IsA("Model") and grownPlant.PrimaryPart or grownPlant
    billboard.Parent = rootPart
    grownPlant.Parent = plantsFolder
    if plantConfig and plantConfig.Quality and plantConfig.Quality >= 5 then
        -- 1. 获取地块主人的名字用于广播
        local ownerName = "Unknown"
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == ownerId then
                ownerName = p.Name
                break
            end
        end
        -- 【核心修复】：改用 ShowTipRE 触发全服 UIEffectUtil.ShowTip
        -- ==========================================
        local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
        if showTipRE then
            local msg = "[" .. ownerName .. "]'s 5-Star rare plant [" .. plantConfig.Name .. "] has matured!"
            showTipRE:FireAllClients(msg) -- 触发全服广播
        end
        -- 3. 在 3D 场景中创建一个如同实体模型般的“Legendary”悬浮文字
        local legendaryBillboard = Instance.new("BillboardGui")
        legendaryBillboard.Name = "LegendaryTagUI"
        
        -- 【核心修复】：使用 Scale 也就是 3D 物理单位(Studs)，而不是像素。
        -- 这里的 4.5 和 1.2 代表它在场景中的实际物理宽高。它将和模型一样近大远小。
        legendaryBillboard.Size = UDim2.new(4.5, 0, 1.2, 0) 
        
        legendaryBillboard.StudsOffset = Vector3.new(0, 5.2, 0) 
        
        -- 【核心修复】：关闭 AlwaysOnTop，开启 LightInfluence，让它完全融入 3D 世界
        legendaryBillboard.AlwaysOnTop = false -- 开启真实空间遮挡，不再穿透模型
        legendaryBillboard.LightInfluence = 1 -- 接受场景的光照影响，就像真实模型一样
        legendaryBillboard.MaxDistance = 150 

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = "Legendary"
        textLabel.TextColor3 = Color3.fromRGB(255, 170, 0) 
        textLabel.Font = Enum.Font.FredokaOne 
        textLabel.TextScaled = true 
        
        textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        textLabel.TextStrokeTransparency = 0

        textLabel.Parent = legendaryBillboard
        legendaryBillboard.Parent = rootPart
    end

    return grownPlant -- [保留原有的这行返回]
end

-- [生成幼苗]
function PlantGrowthService.CreateSeedling(seedId, soil, itemDetail, plantedTime, plot, plantsFolder)
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local seedModelName = itemDetail.SeedId or "PlantSeed"
    local realModel = itemModelsFolder:FindFirstChild(seedModelName)

    if not realModel then return nil end

    local plotNum = tonumber(string.match(plot.Name, "%d+")) or 1
    local yRotation = (plotNum <= 4) and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, math.rad(-90), 0)

    local newPlant = realModel:Clone()
    newPlant.Name = seedId
    newPlant:SetAttribute("YieldPlant", itemDetail.YieldPlant)
    newPlant:SetAttribute("GrowthTime", itemDetail.GrowthTime)
    newPlant:SetAttribute("PlantedOn", soil.Name) 
    newPlant:SetAttribute("PlantedTime", plantedTime)

    if newPlant:IsA("Model") and newPlant.PrimaryPart then
        newPlant:PivotTo(soil.CFrame * CFrame.new(0, soil.Size.Y/2 + newPlant.PrimaryPart.Size.Y/2, 0) * yRotation)
    elseif newPlant:IsA("BasePart") then
        newPlant.CFrame = soil.CFrame * CFrame.new(0, soil.Size.Y/2 + newPlant.Size.Y/2, 0) * yRotation
    end

    for _, part in pairs(newPlant:GetDescendants()) do
        if part:IsA("BasePart") then part.Anchored = true; part.CanCollide = true end
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "GrowthUI"
    billboard.Size = UDim2.new(0, 180, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 50
    
    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 1, 0)
    bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bgFrame.BackgroundTransparency = 0.4
    local bgCorner = Instance.new("UICorner"); bgCorner.CornerRadius = UDim.new(0, 8); bgCorner.Parent = bgFrame
    bgFrame.Parent = billboard

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.05, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.Text = itemDetail.Name
    nameLabel.Parent = bgFrame

    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.Size = UDim2.new(0.9, 0, 0.35, 0)
    barBg.Position = UDim2.new(0.05, 0, 0.55, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    barBg.BackgroundTransparency = 0.5
    local barCorner = Instance.new("UICorner"); barCorner.CornerRadius = UDim.new(0, 4); barCorner.Parent = barBg
    barBg.Parent = bgFrame

    local barFill = Instance.new("Frame")
    barFill.Name = "BarFill"
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(85, 255, 127) 
    local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(0, 4); fillCorner.Parent = barFill
    barFill.Parent = barBg

    local progressText = Instance.new("TextLabel")
    progressText.Name = "ProgressText"
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.TextStrokeTransparency = 0.2
    progressText.TextScaled = true
    progressText.Font = Enum.Font.SourceSansBold
    progressText.ZIndex = 2
    progressText.Text = "⏳ --s"
    progressText.Parent = barBg
    
    local rootPart = newPlant:IsA("Model") and newPlant.PrimaryPart or newPlant
    billboard.Parent = rootPart
    newPlant.Parent = plantsFolder
    return newPlant
end

-- [开始植物生长循环]
function PlantGrowthService.StartPlantGrowth(player, plot, soil, itemDetail, newPlant, prompt, plantsFolder)
    task.spawn(function()
        local growthTime = itemDetail.GrowthTime
        -- 👇 1. 获取该植物种子的购买原价（保底100）
        local buyPrice = itemDetail.BuyPrice or 100 

        while newPlant and newPlant.Parent do
            local elapsed = os.time() - (newPlant:GetAttribute("PlantedTime") or os.time())
            local remaining = math.max(0, growthTime - elapsed)
           
            -- 用于植物头顶进度条的比例
            local progressRatio = math.clamp(elapsed / growthTime, 0, 1)
            
            local currentCost = buyPrice * 2

            local billboard = newPlant:FindFirstChild("GrowthUI", true)
            if remaining > 0 then
                if billboard then 
                    billboard.Enabled = true 
                    local barFill = billboard:FindFirstChild("BarFill", true)
                    local progressText = billboard:FindFirstChild("ProgressText", true)
                    
                    if barFill then barFill.Size = UDim2.new(progressRatio, 0, 1, 0) end
                    -- 头顶UI继续显示倒计时秒数
                    if progressText then progressText.Text = "⏳ " .. remaining .. "s" end
                end

                -- 👇 3. 🌟 核心修复：把原先显示的秒数，替换为真实阳光花费！
                if prompt and prompt.Parent then 
                    -- 你可以把 Coins 改成 ☀️ 或者 阳光，只要你喜欢
                    prompt.ActionText = "Speed up (" .. NumberFormatUtil.FormatNumber(currentCost) .. " Coins)" 
                end
            else
                -- ==========================================
                -- 以下为植物成熟的代码，保持原样不动
                -- ==========================================
                local seedId = newPlant.Name 
                local finalItemDetail = itemDetail
                local finalPlantId = seedId

                if seedId == "RandomSeed" then
                    local data = PlayerDataManager.GetPlayerData(player)
                    local maxLevel = data and data.UnlockedLevel or 1
                    local maxPossibleId = math.clamp(maxLevel + 1, 1, #ItemConfig.IdToSeedKey)
                    
                    local randomNum = math.random(1, maxPossibleId)
                    finalPlantId = ItemConfig.IdToSeedKey[randomNum]
                    finalItemDetail = ItemConfig.Seeds[finalPlantId]

                    if data and not data.UnlockedSeeds[finalPlantId] then
                        PlayerDataManager.UnlockSeed(player, finalPlantId)
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then
                           showNotifRE:FireClient(player, "📖 Collection Unlocked!", "The seed grew into [" .. finalItemDetail.Name .. "]!\nAvailable in Shop!")
                        end
                    end
                    
                    PlayerDataManager.UpdatePlantedPlant(player, soil.Name, finalPlantId, os.time() - growthTime)
                end

                if billboard then billboard.Enabled = false end
                if prompt then prompt.Enabled = false end

                local seedParts = {}
                for _, part in pairs(newPlant:GetDescendants()) do
                    if part:IsA("BasePart") and part.Transparency < 1 then table.insert(seedParts, part) end
                end

                if #seedParts > 0 then
                    local pulseInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
                    local lastTween = nil
                    for _, part in ipairs(seedParts) do
                        local tween = TweenService:Create(part, pulseInfo, { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.5 })
                        tween:Play()
                        lastTween = tween 
                    end
                    if lastTween then lastTween.Completed:Wait() end
                end

                if player and player.Parent then
                    local dropPos = soil.Position + Vector3.new(0, 3, 0)
                    local totalCoinValue = finalItemDetail.Output or 20 
                    CoinDropService.DropCoins(player, dropPos, 5, totalCoinValue)
                end

                PlayerDataManager.MarkPlantAsDropped(player, soil.Name)

                if newPlant:IsA("Model") and newPlant.PrimaryPart then newPlant:ScaleTo(3) end
                for _, part in pairs(newPlant:GetDescendants()) do
                    if part:IsA("BasePart") then part.Transparency = 1 end 
                end

                task.wait(0.2) 

                local pData = PlayerDataManager.GetPlayerData(player)
                local savedMutation = pData and pData.PlantedPlants[soil.Name] and pData.PlantedPlants[soil.Name].Mutation or 1
                PlantGrowthService.SpawnMaturePlant(soil, finalItemDetail, plot, plantsFolder, savedMutation)
                newPlant:Destroy() 
                  
                if prompt then 
                    prompt.ActionText = "Harvest"
                    prompt.HoldDuration = 15 -- 成熟后变15秒长按
                    prompt.Enabled = true 
                end
                break 
            end
            task.wait(0.2)
        end
    end)
end

return PlantGrowthService
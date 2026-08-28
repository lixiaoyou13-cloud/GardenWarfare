-- src/client/UI/PlantHoverController.luau
local PlantHoverController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local NumberFormatUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormatUtil"))

local HOVER_REFRESH_INTERVAL = 0.25

-- 悬浮面板数值统一做缩写，避免治疗量等大数挤出文本框。
local function formatStatNumber(value)
    return NumberFormatUtil.FormatNumber(math.max(0, math.floor((tonumber(value) or 0) + 0.5)))
end

local function getLawnGridCoords(gridName)
    if type(gridName) ~= "string" then
        return nil, nil
    end

    local row, column = string.match(gridName, "^Lawn(%d+)_(%d+)$")
    return tonumber(row), tonumber(column)
end

local function getAuraDamageMultiplier(auraConfig, mutationLevel)
    if type(auraConfig) ~= "table" then
        return 1
    end

    local baseDamageBonus = tonumber(auraConfig.BaseDamageBonus)
    if baseDamageBonus and baseDamageBonus > 0 then
        local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
        local auraBuffMul = tonumber(stats and stats.AuraBuffMul) or 1
        return 1 + baseDamageBonus * auraBuffMul
    end

    local multiplierByMutation = auraConfig.DamageMultiplierByMutation
    if type(multiplierByMutation) == "table" then
        local multiplier = tonumber(multiplierByMutation[mutationLevel]) or tonumber(multiplierByMutation[1])
        if multiplier and multiplier > 0 then
            return multiplier
        end
    end

    local bonusByMutation = auraConfig.DamageBonusByMutation
    if type(bonusByMutation) == "table" then
        local bonus = tonumber(bonusByMutation[mutationLevel]) or tonumber(bonusByMutation[1])
        if bonus and bonus > 0 then
            return 1 + bonus
        end
    end

    local multiplier = tonumber(auraConfig.DamageMultiplier)
    if multiplier and multiplier > 0 then
        return multiplier
    end

    local bonus = tonumber(auraConfig.DamageBonus)
    if bonus and bonus > 0 then
        return 1 + bonus
    end

    return 1
end

local function getPlantConfigForModel(plantModel)
    if not plantModel then
        return nil
    end

    local plantId = plantModel:GetAttribute("PlantId")
        or plantModel:GetAttribute("YieldPlant")
        or plantModel.Name
    return ItemConfig.Plants[plantId]
end

local function getAttackBuffAuraMultiplier(plant)
    if not plant then
        return 1
    end

    local lawnPart = plant.Parent
    local lawnFolder = lawnPart and lawnPart.Parent
    if not (lawnPart and lawnPart:IsA("BasePart") and lawnFolder and lawnFolder.Name == "Lawn") then
        return 1
    end

    local plantRow, plantColumn = getLawnGridCoords(plant:GetAttribute("GridName") or lawnPart.Name)
    if not plantRow or not plantColumn then
        return 1
    end

    local bestMultiplier = 1
    for _, auraLawnPart in ipairs(lawnFolder:GetChildren()) do
        if not auraLawnPart:IsA("BasePart") then
            continue
        end

        local auraRow, auraColumn = getLawnGridCoords(auraLawnPart.Name)
        if not auraRow or not auraColumn then
            continue
        end

        for _, auraPlant in ipairs(auraLawnPart:GetChildren()) do
            if not auraPlant:IsA("Model")
                or auraPlant:GetAttribute("IsCombatPlant") ~= true
                or auraPlant:GetAttribute("IsDead") == true
                or (tonumber(auraPlant:GetAttribute("Health")) or 0) <= 0
            then
                continue
            end

            local auraDetail = getPlantConfigForModel(auraPlant)
            local auraConfig = auraDetail and auraDetail.AttackBuffAura
            if type(auraConfig) ~= "table" then
                continue
            end

            local gridRadius = math.max(0, math.floor(tonumber(auraConfig.GridRadius) or 1))
            if math.abs(auraRow - plantRow) > gridRadius or math.abs(auraColumn - plantColumn) > gridRadius then
                continue
            end

            local auraMutationLevel = tonumber(auraPlant:GetAttribute("MutationLevel")) or 1
            bestMultiplier = math.max(bestMultiplier, getAuraDamageMultiplier(auraConfig, auraMutationLevel))
        end
    end

    return bestMultiplier
end

-- 计算治疗植物的单次治疗量，跟服务端使用同一套变异治疗倍率。
local function getFrontHealAmount(plantConfig, mutationLevel)
    local healConfig = plantConfig and plantConfig.FrontHeal
    if type(healConfig) ~= "table" then
        return nil
    end

    local baseHeal = tonumber(healConfig.Amount)
    if not baseHeal or baseHeal <= 0 then
        return nil
    end

    local level = tonumber(mutationLevel) or 1
    local stats = ItemConfig.MutationStats[level] or ItemConfig.MutationStats[1]
    local healMul = tonumber(stats and stats.HealMul) or 1
    return math.max(1, math.floor(baseHeal * healMul + 0.5))
end

-- 直接读取全局僵尸易伤光环配置，UI 不重复维护战斗数值。
local function getGlobalZombieDamageTakenBonusText(plantConfig, mutationLevel)
    local auraConfig = plantConfig and plantConfig.GlobalZombieDamageTakenAura
    local bonusByMutation = auraConfig and auraConfig.BonusByMutation
    if type(bonusByMutation) ~= "table" then
        return nil
    end

    local level = tonumber(mutationLevel) or 1
    local bonus = tonumber(bonusByMutation[level])
    if not bonus then
        return nil
    end

    local percentText = string.format("%.2f", math.max(0, bonus) * 100)
    percentText = percentText:gsub("0+$", ""):gsub("%.$", "")
    return percentText
end

function PlantHoverController.Init()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local playerGui = player:WaitForChild("PlayerGui")

    -- UI 容器 - 1.5倍整体放大
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlantHoverUI"
    billboard.Size = UDim2.new(0, 195, 0, 130)
    billboard.StudsOffset = Vector3.new(0, 6, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 50
    billboard.Enabled = false

    -- 1. 变异图片标签：移除描边防止“黑框”干扰，直接显示图片内容
    local mutIcon = Instance.new("ImageLabel")
    mutIcon.Name = "MutationIcon"
    mutIcon.Size = UDim2.new(0, 45, 0, 45)
    mutIcon.Position = UDim2.new(0.5, -22, 0, 0) -- 位于容器最顶部
    mutIcon.BackgroundTransparency = 1
    mutIcon.Visible = false
    mutIcon.ScaleType = Enum.ScaleType.Fit
    mutIcon.ZIndex = 10
    mutIcon.Parent = billboard

    -- 2. 名称/血条底板
    local bgFrame = Instance.new("Frame")
    bgFrame.Name = "MainPanel"
    bgFrame.Size = UDim2.new(1, 0, 0, 83)
    bgFrame.Position = UDim2.new(0, 0, 1, -83) -- 底部对齐
    bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bgFrame.BackgroundTransparency = 0.5
    Instance.new("UICorner", bgFrame).CornerRadius = UDim.new(0, 8)
    bgFrame.Parent = billboard

    -- DPS 显示标签
    local dpsLabel = Instance.new("TextLabel")
    dpsLabel.Name = "DPSLabel"
    dpsLabel.Size = UDim2.new(1, 0, 0.25, 0)
    dpsLabel.Position = UDim2.new(0, 0, 0.08, 0)
    dpsLabel.BackgroundTransparency = 1
    -- 1：必须设为白色，渐变色 UIGradient 才能正确显示
    dpsLabel.TextColor3 = Color3.new(1, 1, 1)
    dpsLabel.TextScaled = true
    dpsLabel.Font = Enum.Font.SourceSansBold
    dpsLabel.Parent = bgFrame

    local dpsGradient = Instance.new("UIGradient")
    dpsGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(134, 255, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(37, 205, 9))
    })
    dpsGradient.Rotation = 90
    dpsGradient.Parent = dpsLabel

    local dpsStroke = Instance.new("UIStroke")
    dpsStroke.Thickness = 1.5
    dpsStroke.Color = Color3.fromRGB(0, 0, 0)
    dpsStroke.Parent = dpsLabel

    -- 植物名称
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.35, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.Parent = bgFrame

    local nameStroke = Instance.new("UIStroke")
    nameStroke.Thickness = 1.5
    nameStroke.Color = Color3.fromRGB(0, 0, 0)
    nameStroke.Parent = nameLabel

    -- 血条区域
    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(0.85, 0, 0.15, 0)
    barBg.Position = UDim2.new(0.075, 0, 0.75, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    barBg.BackgroundTransparency = 0.5
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)
    barBg.Parent = bgFrame

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(85, 255, 127)
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 6)
    barFill.Parent = barBg

    -- 生命值数值文本
    local hpText = Instance.new("TextLabel")
    hpText.Name = "HPText"

    -- 将 Y 轴的 Scale 调大到 1.8，让文本框高度达到血条的 1.8 倍
    hpText.Size = UDim2.new(1, 0, 1.8, 0)
    -- 因为高度变大了，为了让文字依然在血条中间，往上偏移 -0.4
    hpText.Position = UDim2.new(0, 0, -0.4, 0)
    hpText.BackgroundTransparency = 1
    hpText.TextColor3 = Color3.fromRGB(255, 255, 255) -- 白色文字
    hpText.TextStrokeTransparency = 0.2 -- 添加微微的黑边，防止文字和绿色进度条融为一体
    hpText.TextScaled = true
    hpText.Font = Enum.Font.SourceSansBold
    hpText.ZIndex = 2 -- 确保显示在血条的最上层
    hpText.Parent = barBg

    billboard.Parent = playerGui

    -- 图片素材配置
    local MUTATION_ICONS = {
        [2] = "rbxassetid://89526577666854", -- 闪耀
        [3] = "rbxassetid://101706251051471", -- 雷电
        [4] = "rbxassetid://14507112520", -- 圣光
    }

    -- 动态逻辑处理
    local currentTarget = nil
    local hpConnection = nil
    local mutationConnection = nil
    local lastHoverUpdate = 0

    local function updateUI()
        if not currentTarget or not currentTarget.Parent then return end

        local currentHP = currentTarget:GetAttribute("Health") or 0
        local maxHP = currentTarget:GetAttribute("MaxHealth") or 1
        local mutationLevel = currentTarget:GetAttribute("MutationLevel") or 1
        local ratio = math.clamp(currentHP / maxHP, 0, 1)

        TweenService:Create(barFill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

        -- 更新生命值文本显示 (向下取整以防出现小数)
        hpText.Text = math.floor(currentHP) .. " / " .. math.floor(maxHP)

        local plantConfig = getPlantConfigForModel(currentTarget)
        local plantId = currentTarget:GetAttribute("PlantId")
            or currentTarget:GetAttribute("YieldPlant")
            or currentTarget.Name
        nameLabel.Text = plantConfig and plantConfig.Name or plantId

        -- 更新图片标签：如果图片 ID 正确，现在会正常显示
        local iconId = MUTATION_ICONS[mutationLevel]
        if iconId then
            -- 获取品质颜色
            local mutColor =  Color3.fromRGB(255, 255, 255)
            mutIcon.Image = iconId
            -- 2：如果图片标签本身带颜色，建议先将 ImageColor3 设为白色观察效果
            mutIcon.ImageColor3 = mutColor
            mutIcon.Visible = true
        else
            mutIcon.Visible = false
        end

        -- 布局自转适应判定
        local healAmount = getFrontHealAmount(plantConfig, mutationLevel)
        local canAttack = plantConfig and plantConfig.CanAttack and plantConfig.Attack and plantConfig.AttackInterval

        if healAmount then
            -- 治疗植物显示单次治疗量，不再显示攻击力/DPS。
            dpsLabel.Text = "Heal: " .. formatStatNumber(healAmount)
            dpsLabel.Visible = true

            bgFrame.Size = UDim2.new(1, 0, 0, 83)
            bgFrame.Position = UDim2.new(0, 0, 1, -83)
            nameLabel.Position = UDim2.new(0, 0, 0.35, 0)
            barBg.Position = UDim2.new(0.075, 0, 0.75, 0)
        elseif canAttack then
            -- 有攻击力：显示 DPS，维持面板原高度 (83)

            -- 严格读取 ItemConfig 中的变异攻击乘区
            local stats = ItemConfig.MutationStats[mutationLevel] or ItemConfig.MutationStats[1]
            local finalAttack = math.floor(plantConfig.Attack * stats.DamageMul)
            local auraMultiplier = getAttackBuffAuraMultiplier(currentTarget)
            if auraMultiplier > 1 then
                finalAttack = math.max(1, math.floor(finalAttack * auraMultiplier + 0.5))
            end
            local dpsValue = finalAttack / plantConfig.AttackInterval

            dpsLabel.Text = string.format("DPS: %.1f", dpsValue)
            dpsLabel.Visible = true

            -- 恢复默认高度与布局
            bgFrame.Size = UDim2.new(1, 0, 0, 83)
            bgFrame.Position = UDim2.new(0, 0, 1, -83)
            nameLabel.Position = UDim2.new(0, 0, 0.35, 0)
            barBg.Position = UDim2.new(0.075, 0, 0.75, 0)
        else
            -- 无普通攻击时按支持能力决定是否复用顶部属性行。
            local globalDamageBonusText = plantId == "Clover"
                and getGlobalZombieDamageTakenBonusText(plantConfig, mutationLevel)
                or nil
            local ownAuraConfig = plantConfig and plantConfig.AttackBuffAura
            if globalDamageBonusText then
                dpsLabel.Text = "Damage Boost: " .. globalDamageBonusText .. "%"
                dpsLabel.Visible = true
            elseif type(ownAuraConfig) == "table" then
                local auraMultiplier = getAuraDamageMultiplier(ownAuraConfig, mutationLevel)
                local bonusPercent = math.max(0, math.floor((auraMultiplier - 1) * 100 + 0.5))
                dpsLabel.Text = "Buff: +" .. tostring(bonusPercent) .. "%"
                dpsLabel.Visible = true
            else
                dpsLabel.Visible = false
            end

            -- 动态面板大小与位置，消除空白
            local showsSupportStat = globalDamageBonusText ~= nil or type(ownAuraConfig) == "table"
            local compactHeight = showsSupportStat and 83 or 58
            bgFrame.Size = UDim2.new(1, 0, 0, compactHeight)
            bgFrame.Position = UDim2.new(0, 0, 1, -58) -- 面板整体上移

            -- 内部组件向上微调，保持紧凑
            nameLabel.Position = UDim2.new(0, 0, 0.15, 0)
            barBg.Position = UDim2.new(0.075, 0, 0.62, 0)
            bgFrame.Position = UDim2.new(0, 0, 1, -compactHeight)
            if showsSupportStat then
                nameLabel.Position = UDim2.new(0, 0, 0.35, 0)
                barBg.Position = UDim2.new(0.075, 0, 0.75, 0)
            end
        end
    end

    -- 雷达扫描
    RunService.RenderStepped:Connect(function()
        local targetPart = mouse.Target
        local foundPlant = nil
        if targetPart then
            local currentObj = targetPart
            while currentObj and currentObj ~= Workspace do
                if currentObj:IsA("Model") and currentObj:GetAttribute("IsCombatPlant") then
                    foundPlant = currentObj
                    break
                end
                currentObj = currentObj.Parent
            end
        end

        if foundPlant then
            if currentTarget ~= foundPlant then
                currentTarget = foundPlant
                billboard.Adornee = foundPlant.PrimaryPart or foundPlant:FindFirstChildWhichIsA("BasePart") or foundPlant
                billboard.Enabled = true
                if hpConnection then hpConnection:Disconnect() end
                if mutationConnection then mutationConnection:Disconnect() end
                hpConnection = currentTarget:GetAttributeChangedSignal("Health"):Connect(updateUI)
                mutationConnection = currentTarget:GetAttributeChangedSignal("MutationLevel"):Connect(updateUI)
                updateUI()
                lastHoverUpdate = os.clock()
            elseif os.clock() - lastHoverUpdate >= HOVER_REFRESH_INTERVAL then
                updateUI()
                lastHoverUpdate = os.clock()
            end
        else
            if currentTarget then
                currentTarget = nil
                billboard.Enabled = false
                billboard.Adornee = nil
                if hpConnection then hpConnection:Disconnect(); hpConnection = nil end
                if mutationConnection then mutationConnection:Disconnect(); mutationConnection = nil end
            end
        end
    end)
end

return PlantHoverController

-- src/client/UI/EncyclopediaController.luau
local EncyclopediaController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local BaseItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BaseItemConfig"))
local NumberFormatUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormatUtil"))

local SPECIAL_CODEX_TAB = 5
local WAIT_TIMEOUT = 10

local QUALITY_FALLBACK_NAMES = {
    [1] = "Common",
    [2] = "Special",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Mutant",
}

local function warnMissing(path)
    warn("[EncyclopediaController] Missing UI object: " .. path)
end

local function waitChild(parent, childName, path)
    if not parent then
        warnMissing(path)
        return nil
    end

    local child = parent:WaitForChild(childName, WAIT_TIMEOUT)
    if not child then
        warnMissing(path)
    end
    return child
end

local function getQualityName(qualityId)
    local qualityConfig = BaseItemConfig.Item and BaseItemConfig.Item[qualityId]
    return (qualityConfig and qualityConfig.Name) or QUALITY_FALLBACK_NAMES[qualityId] or ("Quality " .. tostring(qualityId))
end

local function getQualityColor(qualityId)
    return (ItemConfig.QualityColor and ItemConfig.QualityColor[qualityId]) or Color3.fromRGB(255, 255, 255)
end

local function getQualityGradientIndex(qualityId)
    qualityId = tonumber(qualityId) or 1
    if qualityId < 1 then
        return 1
    end
    if qualityId > 6 then
        return 6
    end
    return qualityId
end

local function connectPress(guiObject, callback)
    if not guiObject then
        return
    end

    if guiObject:IsA("GuiButton") then
        guiObject.Activated:Connect(callback)
    else
        guiObject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                callback()
            end
        end)
    end
end

-- 图鉴属性数值统一走缩写格式，避免大数挤出 UI。
local function formatStatNumber(value)
    return NumberFormatUtil.FormatNumber(math.max(0, math.floor((tonumber(value) or 0) + 0.5)))
end

-- 图鉴直接读取 Clover 光环配置，避免与实际战斗增幅出现两套数值。
local function getGlobalZombieDamageTakenBonusText(plantDetail, mutationLevel)
    local auraConfig = plantDetail and plantDetail.GlobalZombieDamageTakenAura
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

local function isMutationUnlocked(unlockedMutations, plantId, mutationLevel)
    local mutationMap = type(unlockedMutations) == "table" and unlockedMutations[plantId]
    if type(mutationMap) ~= "table" then
        return false
    end

    local level = tonumber(mutationLevel) or 1
    return mutationMap[level] == true or mutationMap[tostring(level)] == true
end

local function getCodexMutationLevel(tabIndex, plantDetail)
    if tabIndex == SPECIAL_CODEX_TAB then
        return tonumber(plantDetail and plantDetail.CodexMutationLevel) or 1
    end

    return tonumber(tabIndex) or 1
end

local function getCodexMutationIconId(tabIndex, plantDetail, mutationLevel)
    local mutationIcons = ItemConfig.MutationIconIds
    if type(mutationIcons) ~= "table" then
        return nil
    end

    if tabIndex == SPECIAL_CODEX_TAB then
        if plantDetail and plantDetail.CodexLabel == "Mutant" then
            return mutationIcons.Mutant or mutationIcons[1]
        end

        return nil
    end

    local level = tonumber(mutationLevel) or 1
    if level <= 1 then
        return nil
    end

    return mutationIcons[level]
end

local function shouldShowPlantInTab(tabIndex, plantDetail)
    if tabIndex == SPECIAL_CODEX_TAB then
        return plantDetail and plantDetail.CodexCategory == SPECIAL_CODEX_TAB
    end

    if not plantDetail
        or plantDetail.HideFromStandardCodex == true
        or plantDetail.CodexCategory ~= nil then
        return false
    end

    local mutationLevel = getCodexMutationLevel(tabIndex, plantDetail)
    if plantDetail.NoMutation == true and mutationLevel > 1 then
        return false
    end

    return true
end

local function getSortedPlantsForTab(tabIndex)
    local sortedPlants = {}

    for plantId, plantDetail in pairs(ItemConfig.Plants) do
        if shouldShowPlantInTab(tabIndex, plantDetail) then
            local numericId = (ItemConfig.Seeds[plantId] and ItemConfig.Seeds[plantId].Id)
                or plantDetail.CodexOrder
                or 9999

            table.insert(sortedPlants, {
                plantId = plantId,
                plantDetail = plantDetail,
                quality = tonumber(plantDetail.Quality) or 1,
                numericId = numericId,
            })
        end
    end

    table.sort(sortedPlants, function(a, b)
        if a.quality == b.quality then
            return a.numericId < b.numericId
        end
        return a.quality < b.quality
    end)

    return sortedPlants
end

function EncyclopediaController.Init()
    local currentCodexLoadTicket = 0
    local activeTabIndex = 1

    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = waitChild(basicGui, "PlayProperty", "BasicGui.PlayProperty")
    local openCodexBtn = waitChild(playProperty, "Codex", "BasicGui.PlayProperty.Codex")
    local codexGui = waitChild(basicGui, "Codex", "BasicGui.Codex")
    local indexFrame = waitChild(codexGui, "Index", "BasicGui.Codex.Index")

    if not (openCodexBtn and codexGui and indexFrame) then
        return
    end

    local listFrame = waitChild(indexFrame, "List", "BasicGui.Codex.Index.List")
    local categoryScroll = listFrame and waitChild(listFrame, "ScrollingFrame", "BasicGui.Codex.Index.List.ScrollingFrame")
    local listHolder = waitChild(indexFrame, "ListHolder", "BasicGui.Codex.Index.ListHolder")
    local eggList = listHolder and waitChild(listHolder, "EggList", "BasicGui.Codex.Index.ListHolder.EggList")
    local infoHolder = waitChild(indexFrame, "InfoHolder", "BasicGui.Codex.Index.InfoHolder")
    local achievementsInfo = infoHolder and waitChild(infoHolder, "AchievementsInfo", "BasicGui.Codex.Index.InfoHolder.AchievementsInfo")
    local banner = waitChild(indexFrame, "Banner", "BasicGui.Codex.Index.Banner")
    local closeBtn = banner and waitChild(banner, "Close", "BasicGui.Codex.Index.Banner.Close")

    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates", WAIT_TIMEOUT)
    local liteTemplate = uiTemplates and uiTemplates:WaitForChild("Lite", WAIT_TIMEOUT)
    if not liteTemplate then
        warnMissing("ReplicatedStorage.UITemplates.Lite")
        return
    end

    local categoryBtns = {}
    local scrollingFrames = {}
    for i = 1, SPECIAL_CODEX_TAB do
        categoryBtns[i] = categoryScroll and categoryScroll:FindFirstChild("Category" .. i)
        scrollingFrames[i] = eggList and eggList:FindFirstChild("List" .. i)

        if not categoryBtns[i] then
            warnMissing("BasicGui.Codex.Index.List.ScrollingFrame.Category" .. i)
        end
        if not scrollingFrames[i] then
            warnMissing("BasicGui.Codex.Index.ListHolder.EggList.List" .. i)
        end
    end

    local detailNameText = achievementsInfo and achievementsInfo:FindFirstChild("Name")
    local detailQualityText = achievementsInfo and achievementsInfo:FindFirstChild("Title")
    local rewardFrame = achievementsInfo and achievementsInfo:FindFirstChild("RewardFrame")
    local detailHpText = rewardFrame and rewardFrame:FindFirstChild("Title1")
    local detailDpsText = rewardFrame and rewardFrame:FindFirstChild("Title2")
    local detailDescriptionText = rewardFrame and rewardFrame:FindFirstChild("Description")
    local detailIconFrame = achievementsInfo and achievementsInfo:FindFirstChild("PlayerIcon")
    local detailIconBackground = detailIconFrame and detailIconFrame:FindFirstChild("BackgroundFrame")
    local detailIcon = detailIconBackground and detailIconBackground:FindFirstChild("PlayerIcon")

    local detailObjectsReady = detailNameText
        and detailQualityText
        and detailHpText
        and detailDpsText
        and detailDescriptionText
        and detailIcon

    if not detailObjectsReady then
        warn("[EncyclopediaController] One or more AchievementsInfo detail objects are missing.")
    end

    if listHolder then
        for _, child in ipairs(listHolder:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Visible = (child == eggList)
            end
        end
    end

    if infoHolder then
        for _, child in ipairs(infoHolder:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Visible = (child == achievementsInfo)
            end
        end
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 5)

    local function fetchUnlockedMutations()
        if not getPlayerDataRF then
            return {}
        end

        local success, playerData = pcall(function()
            return getPlayerDataRF:InvokeServer()
        end)

        if not success or type(playerData) ~= "table" then
            warn("[EncyclopediaController] Failed to fetch player data for codex unlock state.")
            return {}
        end

        return playerData.UnlockedMutations or {}
    end

    local function applyQualityGradient(root, qualityId)
        if not root then
            return false
        end

        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("UIGradient") and child.Name:match("^UIGradient%d+$") then
                child.Enabled = false
            end
        end

        local runtimeGradient = root:FindFirstChild("CodexQualityGradient")
        if runtimeGradient and runtimeGradient:IsA("UIGradient") then
            runtimeGradient.Enabled = false
        end

        local gradientName = "UIGradient" .. tostring(getQualityGradientIndex(qualityId))
        local gradient = root:FindFirstChild(gradientName)
        if gradient and gradient:IsA("UIGradient") then
            gradient.Enabled = true
            return true
        end

        return false
    end

    local function buildQualityColorSequence(qualityId)
        local qualityColor = getQualityColor(qualityId)
        local lightColor = qualityColor:Lerp(Color3.fromRGB(255, 255, 255), 0.45)
        local darkColor = qualityColor:Lerp(Color3.fromRGB(0, 0, 0), 0.25)

        return ColorSequence.new({
            ColorSequenceKeypoint.new(0, lightColor),
            ColorSequenceKeypoint.new(1, darkColor),
        })
    end

    local function applyStrokeQualityColor(root, qualityId)
        if not root then
            return
        end

        local qualityColor = getQualityColor(qualityId)
        local qualityGradient = buildQualityColorSequence(qualityId)

        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("UIStroke") and (child.Name == "UIStroke" or child.Name == "InnerStroke") then
                child.Color = qualityColor

                local strokeGradient = child:FindFirstChildOfClass("UIGradient")
                if strokeGradient then
                    strokeGradient.Color = qualityGradient
                end
            end
        end
    end

    local function clearDetail()
        if detailNameText and detailNameText:IsA("TextLabel") then
            detailNameText.Text = ""
        end
        if detailQualityText and detailQualityText:IsA("TextLabel") then
            detailQualityText.Text = ""
        end
        if detailHpText and detailHpText:IsA("TextLabel") then
            detailHpText.Text = "HP: --"
        end
        if detailDpsText and detailDpsText:IsA("TextLabel") then
            detailDpsText.Text = "Attack/sec: --"
        end
        if detailDescriptionText and detailDescriptionText:IsA("TextLabel") then
            detailDescriptionText.Text = ""
        end
        if detailIcon and (detailIcon:IsA("ImageLabel") or detailIcon:IsA("ImageButton")) then
            detailIcon.Image = ""
            detailIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
        end
        applyQualityGradient(detailIconFrame, 1)
    end

    local function setDetail(plantId, plantDetail, tabIndex, isOwned)
        local qualityId = tonumber(plantDetail.Quality) or 1
        local mutationLevel = getCodexMutationLevel(tabIndex, plantDetail)
        local mutationStats = (ItemConfig.MutationStats and ItemConfig.MutationStats[mutationLevel]) or {
            DamageMul = 1,
            HealthMul = 1,
            HealMul = 1,
        }

        local finalHp = math.floor((tonumber(plantDetail.HP) or 0) * (tonumber(mutationStats.HealthMul) or 1))
        local baseAttack = tonumber(plantDetail.Attack)
        local intervalValue = tonumber(plantDetail.AttackInterval)
        local finalAttack = baseAttack and math.floor(baseAttack * (tonumber(mutationStats.DamageMul) or 1)) or nil
        local healConfig = type(plantDetail.FrontHeal) == "table" and plantDetail.FrontHeal or nil
        local baseHeal = healConfig and tonumber(healConfig.Amount) or nil
        local finalHeal = baseHeal and math.floor(baseHeal * (tonumber(mutationStats.HealMul) or 1) + 0.5) or nil

        if detailNameText and detailNameText:IsA("TextLabel") then
            detailNameText.Text = plantDetail.Name or plantId
        end
        if detailQualityText and detailQualityText:IsA("TextLabel") then
            detailQualityText.Text = getQualityName(qualityId)
            detailQualityText.TextColor3 = getQualityColor(qualityId)
        end
        if detailHpText and detailHpText:IsA("TextLabel") then
            detailHpText.Text = "HP: " .. tostring(finalHp)
        end
        if detailDpsText and detailDpsText:IsA("TextLabel") then
            local globalDamageBonusText = plantId == "Clover"
                and getGlobalZombieDamageTakenBonusText(plantDetail, mutationLevel)
                or nil
            if globalDamageBonusText then
                detailDpsText.Text = "伤害增幅: " .. globalDamageBonusText .. "%"
            elseif finalHeal then
                detailDpsText.Text = "Heal: " .. formatStatNumber(finalHeal)
            elseif finalAttack then
                if intervalValue and intervalValue > 0 then
                    local attackPerSecond = math.floor((finalAttack / intervalValue) + 0.5)
                    detailDpsText.Text = "Attack/sec: " .. tostring(attackPerSecond)
                else
                    detailDpsText.Text = "Attack: " .. tostring(finalAttack)
                end
            else
                detailDpsText.Text = "Attack/sec: --"
            end
        end
        if detailDescriptionText and detailDescriptionText:IsA("TextLabel") then
            detailDescriptionText.Text = plantDetail.Description or "No description available."
            detailDescriptionText.TextWrapped = true
            detailDescriptionText.TextXAlignment = Enum.TextXAlignment.Left
            detailDescriptionText.TextYAlignment = Enum.TextYAlignment.Top
        end
        if detailIcon and (detailIcon:IsA("ImageLabel") or detailIcon:IsA("ImageButton")) then
            detailIcon.Image = plantDetail.IconId or ""
            detailIcon.ImageColor3 = isOwned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
        end
        applyQualityGradient(detailIconFrame, qualityId)
    end

    local function applySlotQualityGradient(slot, qualityId)
        local hasTemplateGradient = applyQualityGradient(slot, qualityId)
        if not hasTemplateGradient then
            local gradient = slot:FindFirstChild("CodexQualityGradient")
            if not gradient or not gradient:IsA("UIGradient") then
                gradient = Instance.new("UIGradient")
                gradient.Name = "CodexQualityGradient"
                gradient.Parent = slot
            end

            gradient.Enabled = true
            gradient.Rotation = 90
            gradient.Color = buildQualityColorSequence(qualityId)
        end

        applyStrokeQualityColor(slot, qualityId)
    end

    local function configureSlot(slot, plantId, plantDetail, tabIndex, index, isOwned)
        local qualityId = tonumber(plantDetail.Quality) or 1
        slot.Name = plantId
        slot.Visible = true
        slot.LayoutOrder = index
        slot:SetAttribute("CodexGeneratedItem", true)

        local icon = slot:FindFirstChild("Icon")
        if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
            icon.Image = plantDetail.IconId or ""
            icon.ImageColor3 = isOwned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
        end

        local title = slot:FindFirstChild("InfoHolder")
            and slot.InfoHolder:FindFirstChild("Frame")
            and slot.InfoHolder.Frame:FindFirstChild("Title")
        if title and title:IsA("TextLabel") then
            title.Text = plantDetail.Name or plantId
        end

        local exclusive = slot:FindFirstChild("Exclusive")
        if exclusive then
            local mutationLevel = getCodexMutationLevel(tabIndex, plantDetail)
            local mutationIconId = getCodexMutationIconId(tabIndex, plantDetail, mutationLevel)
            if exclusive:IsA("ImageLabel") or exclusive:IsA("ImageButton") then
                exclusive.Image = mutationIconId or ""
                exclusive.ImageColor3 = Color3.fromRGB(255, 255, 255)
                exclusive.Visible = mutationIconId ~= nil and mutationIconId ~= ""
            elseif exclusive:IsA("GuiObject") then
                exclusive.Visible = false
            end
        end

        local claimFrame = slot:FindFirstChild("ClaimFrame")
        if claimFrame and claimFrame:IsA("GuiObject") then
            claimFrame.Visible = false
        end

        applySlotQualityGradient(slot, qualityId)
        connectPress(slot, function()
            setDetail(plantId, plantDetail, tabIndex, isOwned)
        end)
    end

    local function clearGeneratedSlots(scrollingFrame)
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child:GetAttribute("CodexGeneratedItem") == true or child:IsA("GuiButton") then
                child:Destroy()
            end
        end
    end

    local function loadCodexItems(tabIndex, selectFirstItem)
        local currentScroll = scrollingFrames[tabIndex]
        if not currentScroll then
            return
        end

        currentCodexLoadTicket += 1
        local myTicket = currentCodexLoadTicket
        local unlockedMutations = fetchUnlockedMutations()

        if myTicket ~= currentCodexLoadTicket then
            return
        end

        clearGeneratedSlots(currentScroll)

        local sortedPlants = getSortedPlantsForTab(tabIndex)
        local firstPlantId = nil
        local firstPlantDetail = nil
        local firstIsOwned = false

        for index, data in ipairs(sortedPlants) do
            local plantId = data.plantId
            local plantDetail = data.plantDetail
            local mutationLevel = getCodexMutationLevel(tabIndex, plantDetail)
            local isOwned = isMutationUnlocked(unlockedMutations, plantId, mutationLevel)
            local slot = liteTemplate:Clone()

            if index == 1 then
                firstPlantId = plantId
                firstPlantDetail = plantDetail
                firstIsOwned = isOwned
            end

            configureSlot(slot, plantId, plantDetail, tabIndex, index, isOwned)
            slot.Parent = currentScroll
        end

        if selectFirstItem and firstPlantId and firstPlantDetail then
            setDetail(firstPlantId, firstPlantDetail, tabIndex, firstIsOwned)
        end
    end

    local function setCategorySelected(tabIndex)
        for i = 1, SPECIAL_CODEX_TAB do
            local list = scrollingFrames[i]
            if list and list:IsA("GuiObject") then
                list.Visible = (i == tabIndex)
            end

            local button = categoryBtns[i]
            if button then
                local stroke = button:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = (i == tabIndex) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                end

                local darken = button:FindFirstChild("Darken")
                if darken and darken:IsA("GuiObject") then
                    darken.Visible = (i ~= tabIndex)
                end
            end
        end
    end

    local function switchTab(tabIndex)
        activeTabIndex = tabIndex
        clearDetail()
        setCategorySelected(tabIndex)
        loadCodexItems(tabIndex, true)
    end

    for i = 1, SPECIAL_CODEX_TAB do
        connectPress(categoryBtns[i], function()
            switchTab(i)
        end)
    end

    local function handleOpenCodex()
        codexGui.Enabled = true
        indexFrame.Visible = true
        switchTab(1)
    end

    local function handleCloseCodex()
        codexGui.Enabled = false
        clearDetail()
    end

    connectPress(openCodexBtn, handleOpenCodex)
    connectPress(closeBtn, handleCloseCodex)

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 5)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function()
            if codexGui.Enabled then
                loadCodexItems(activeTabIndex, false)
            end
        end)
    end

    clearDetail()
    setCategorySelected(activeTabIndex)
end

return EncyclopediaController

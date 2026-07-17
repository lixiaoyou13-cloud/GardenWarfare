-- src/client/UI/InventoryController.luau
local InventoryController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local WAIT_TIMEOUT = 10
local INVENTORY_QUALITY_GRADIENT_NAME = "InventoryQualityGradient"
local EQUIPPED_TITLE_EXCLUSIVE_ICON = "rbxassetid://84609421456230"

local PAGE_BY_TAB = {
    SeedTabBtn = "SeedPage",
    PlantTabBtn = "PlantPage",
    ChestTabBtn = "ChestPage",
    ItemTabBtn = "ItemPage",
    titleTabBtn = "TitlePage",
}

local TAB_BY_PAGE = {
    SeedPage = "SeedTabBtn",
    PlantPage = "PlantTabBtn",
    ChestPage = "ChestTabBtn",
    ItemPage = "ItemTabBtn",
    TitlePage = "titleTabBtn",
}

local FILTER_ALL = 1
local FILTER_NORMAL = 2
local FILTER_SHINY = 3
local FILTER_THUNDER = 4
local FILTER_DIVINE = 5
local FILTER_SPECIAL = 6

local FILTERABLE_PAGES = {
    SeedPage = true,
    PlantPage = true,
}

local function warnMissing(path)
    warn("[InventoryController] Missing UI object: " .. tostring(path))
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

local function isTextObject(instance)
    return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function findTextObject(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local direct = root:FindFirstChild(name, true)
        if isTextObject(direct) then
            return direct
        end
    end

    return nil
end

local function findImageObject(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local direct = root:FindFirstChild(name, true)
        if direct and (direct:IsA("ImageLabel") or direct:IsA("ImageButton") or direct:IsA("ViewportFrame")) then
            return direct
        end
    end

    return nil
end

local function findTitleText(slot)
    local infoHolder = slot:FindFirstChild("InfoHolder")
    local frame = infoHolder and infoHolder:FindFirstChild("Frame")
    local title = frame and frame:FindFirstChild("Title")
    if title and (title:IsA("TextLabel") or title:IsA("TextButton")) then
        return title
    end

    return findTextObject(slot, { "Title", "ItemName", "Name" })
end

local function findQuantityDisplay(slot)
    if not slot then
        return nil, nil
    end

    local numberRoot = slot:FindFirstChild("Number", true)
    if numberRoot then
        if isTextObject(numberRoot) then
            return numberRoot, numberRoot
        end

        if numberRoot:IsA("GuiObject") then
            local numberText = findTextObject(numberRoot, { "Text", "Label", "Value", "Number", "Quantity", "Amount", "Count" })
            if not numberText then
                for _, desc in ipairs(numberRoot:GetDescendants()) do
                    if isTextObject(desc) then
                        numberText = desc
                        break
                    end
                end
            end

            return numberRoot, numberText
        end
    end

    local legacyText = findTextObject(slot, { "Quantity", "Amount", "Count" })
    return legacyText, legacyText
end

local function setSlotTitleAndQuantity(slot, displayName, quantity)
    local title = findTitleText(slot)
    local quantityRoot, quantityText = findQuantityDisplay(slot)

    if quantity == nil then
        if quantityRoot and quantityRoot:IsA("GuiObject") then
            quantityRoot.Visible = false
        end
        if quantityText then
            quantityText.Visible = false
        end
        if title then
            title.Text = displayName
        end
    else
        local amountText = "x" .. tostring(quantity or 1)
        if quantityText then
            quantityText.Text = amountText
            quantityText.Visible = true
        end
        if quantityRoot and quantityRoot:IsA("GuiObject") then
            quantityRoot.Visible = true
        end

        if title then
            if quantityText then
                title.Text = displayName
            else
                title.Text = displayName .. " " .. amountText
            end
        end
    end

    if title and title:IsA("TextLabel") then
        title.TextWrapped = true
        title.TextScaled = true
    end
end

local function setSlotIcon(slot, itemId, itemType, iconId, mutationLevel)
    local icon = findImageObject(slot, { "Icon", "Icom" })
    if not icon then
        return
    end

    local itemImage = slot:FindFirstChild("ItemIconImage", true)
    if itemType == "Item" and iconId and iconId ~= "" then
        if icon:IsA("ViewportFrame") then
            icon.Visible = false
            if not itemImage or not itemImage:IsA("ImageLabel") then
                itemImage = Instance.new("ImageLabel")
                itemImage.Name = "ItemIconImage"
                itemImage.BackgroundTransparency = 1
                itemImage.ScaleType = Enum.ScaleType.Fit
                itemImage.Active = false
                itemImage.Parent = icon.Parent or slot
            end

            itemImage.Size = icon.Size
            itemImage.Position = icon.Position
            itemImage.AnchorPoint = icon.AnchorPoint
            itemImage.ZIndex = icon.ZIndex
            itemImage.Image = iconId
            itemImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
            itemImage.Visible = true
        else
            icon.Image = iconId
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            icon.Visible = true
            if itemImage and itemImage:IsA("GuiObject") then
                itemImage.Visible = false
            end
        end
    elseif icon:IsA("ViewportFrame") then
        if itemImage and itemImage:IsA("GuiObject") then
            itemImage.Visible = false
        end
        icon.Visible = true
        UIEffectUtil.RenderToViewport(icon, itemId, itemType, mutationLevel)
    else
        if itemImage and itemImage:IsA("GuiObject") then
            itemImage.Visible = false
        end
        icon.Visible = true
        icon.Image = iconId or ""
        icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end
end

local function setSlotMutationIcon(slot, itemConfig, itemType, mutationLevel)
    local exclusive = slot:FindFirstChild("Exclusive", true)
    if not exclusive then
        return
    end

    local iconId = nil
    local mutationIcons = itemConfig.MutationIconIds
    local level = tonumber(mutationLevel) or 1
    if itemType == "Plant" and type(mutationIcons) == "table" and level > 1 then
        iconId = mutationIcons[level]
    end

    if exclusive:IsA("ImageLabel") or exclusive:IsA("ImageButton") then
        exclusive.Image = iconId or ""
        exclusive.ImageColor3 = Color3.fromRGB(255, 255, 255)
        exclusive.Visible = iconId ~= nil and iconId ~= ""
    elseif exclusive:IsA("GuiObject") then
        exclusive.Visible = false
    end
end

local function getQualityGradientIndex(qualityId)
    return math.clamp(math.floor(tonumber(qualityId) or 1), 1, 6)
end

local function getQualityColor(itemConfig, qualityId)
    local qualityIndex = tonumber(qualityId) or 1
    return (itemConfig.QualityColor and itemConfig.QualityColor[qualityIndex]) or Color3.fromRGB(255, 255, 255)
end

local function buildQualityColorSequence(itemConfig, qualityId)
    local qualityColor = getQualityColor(itemConfig, qualityId)
    local lightColor = qualityColor:Lerp(Color3.fromRGB(255, 255, 255), 0.45)
    local darkColor = qualityColor:Lerp(Color3.fromRGB(0, 0, 0), 0.25)

    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, lightColor),
        ColorSequenceKeypoint.new(1, darkColor),
    })
end

local function applyTemplateQualityGradient(slot, qualityId)
    if not slot then
        return false
    end

    local gradientIndex = getQualityGradientIndex(qualityId)
    for _, child in ipairs(slot:GetChildren()) do
        if child:IsA("UIGradient") and child.Name:match("^UIGradient%d+$") then
            child.Enabled = false
        end
    end

    local runtimeGradient = slot:FindFirstChild(INVENTORY_QUALITY_GRADIENT_NAME)
    if runtimeGradient and runtimeGradient:IsA("UIGradient") then
        runtimeGradient.Enabled = false
    end

    local gradient = slot:FindFirstChild("UIGradient" .. tostring(gradientIndex))
    if gradient and gradient:IsA("UIGradient") then
        gradient.Enabled = true
        return true
    end

    return false
end

local function applyStrokeQualityColor(slot, itemConfig, qualityId)
    if not slot then
        return
    end

    local qualityColor = getQualityColor(itemConfig, qualityId)
    local qualityGradient = buildQualityColorSequence(itemConfig, qualityId)

    for _, child in ipairs(slot:GetChildren()) do
        if child:IsA("UIStroke") and (child.Name == "UIStroke" or child.Name == "InnerStroke") then
            child.Color = qualityColor

            local strokeGradient = child:FindFirstChildOfClass("UIGradient")
            if strokeGradient then
                strokeGradient.Color = qualityGradient
            end
        end
    end
end

local function applyQualityGradient(slot, itemConfig, qualityId)
    local hasTemplateGradient = applyTemplateQualityGradient(slot, qualityId)
    if not hasTemplateGradient then
        local gradient = slot:FindFirstChild(INVENTORY_QUALITY_GRADIENT_NAME)
        if not gradient or not gradient:IsA("UIGradient") then
            gradient = Instance.new("UIGradient")
            gradient.Name = INVENTORY_QUALITY_GRADIENT_NAME
            gradient.Parent = slot
        end

        gradient.Enabled = true
        gradient.Rotation = 90
        gradient.Color = buildQualityColorSequence(itemConfig, qualityId)
    end

    applyStrokeQualityColor(slot, itemConfig, qualityId)
end

local function createExplosionBadge(slot)
    if slot:FindFirstChild("ExplosionIcon") then
        return
    end

    local expIcon = Instance.new("ImageLabel")
    expIcon.Name = "ExplosionIcon"
    expIcon.Size = UDim2.new(0, 24, 0, 24)
    expIcon.Position = UDim2.new(0, 4, 0, 4)
    expIcon.BackgroundTransparency = 1
    expIcon.Image = "rbxassetid://5652766180"
    expIcon.ZIndex = 10
    expIcon.Parent = slot
end

local function getSeedIconId(itemConfig, seedId, seedDetail)
    if seedDetail and seedDetail.IconId then
        return seedDetail.IconId
    end

    local yieldPlantId = seedDetail and seedDetail.YieldPlant or seedId
    local plantDetail = itemConfig.Plants and itemConfig.Plants[yieldPlantId]
    return plantDetail and plantDetail.IconId or ""
end

local function getSeedPlantDetail(itemConfig, seedId, seedDetail)
    local yieldPlantId = seedDetail and seedDetail.YieldPlant or seedId
    return itemConfig.Plants and itemConfig.Plants[yieldPlantId]
end

local function getInventoryQuality(itemConfig, itemId, itemType, itemDetail)
    if itemType == "Seed" then
        local plantDetail = getSeedPlantDetail(itemConfig, itemId, itemDetail)
        return tonumber((plantDetail and plantDetail.Quality) or (itemDetail and itemDetail.Quality)) or 1
    end

    return tonumber(itemDetail and itemDetail.Quality) or 1
end

local function getInventoryOrder(itemConfig, itemId, itemType, itemDetail)
    if itemDetail then
        local detailId = tonumber(itemDetail.Id)
        if detailId then
            return detailId
        end
        if tonumber(itemDetail.CodexOrder) then
            return tonumber(itemDetail.CodexOrder)
        end
    end

    if itemType == "Plant" and itemConfig.IdToSeedKey then
        for index, seedKey in ipairs(itemConfig.IdToSeedKey) do
            if seedKey == itemId then
                return index
            end
        end
    end

    return 9999
end

local function getInventoryFilterCategory(itemType, itemDetail, qualityId, mutationLevel)
    local quality = tonumber(qualityId) or 1
    if quality >= 6
        or (itemDetail and itemDetail.CodexLabel == "Mutant")
        or (itemDetail and itemDetail.Source == "Special")
        or (itemDetail and itemDetail.CodexCategory == 5) then
        return FILTER_SPECIAL
    end

    if itemType == "Plant" then
        local level = tonumber(mutationLevel) or 1
        if level == 2 then
            return FILTER_SHINY
        elseif level == 3 then
            return FILTER_THUNDER
        elseif level == 4 then
            return FILTER_DIVINE
        end
    end

    return FILTER_NORMAL
end

local function sortInventoryEntries(a, b)
    if a.quality ~= b.quality then
        return a.quality > b.quality
    end
    if a.filterCategory ~= b.filterCategory then
        return a.filterCategory > b.filterCategory
    end
    if a.order ~= b.order then
        return a.order < b.order
    end
    return tostring(a.displayName) < tostring(b.displayName)
end

local function normalizeSearchText(text)
    return tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function buildSearchText(parts)
    local textParts = {}
    for _, value in ipairs(parts) do
        if value ~= nil and value ~= "" then
            table.insert(textParts, tostring(value))
        end
    end

    return normalizeSearchText(table.concat(textParts, " "))
end

local function removeMissingSlots(page, currentItems)
    if not page then
        return
    end

    for _, slot in ipairs(page:GetChildren()) do
        if slot:GetAttribute("InventoryGeneratedItem") == true and not currentItems[slot.Name] then
            slot:Destroy()
        end
    end
end

function InventoryController.Init()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
    local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChestConfig"))
    local TitleConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TitleConfig"))

    local basicGui = playerGui:WaitForChild("BasicGui")
    local inventoryGui = basicGui:WaitForChild("InventoryGui")
    local mainFrame = waitChild(inventoryGui, "MainFrame", "BasicGui.InventoryGui.MainFrame")
    if not mainFrame then
        return
    end

    local openButton = inventoryGui:FindFirstChild("OpenButton")
    local banner = waitChild(mainFrame, "Banner", "BasicGui.InventoryGui.MainFrame.Banner")
    local closeButton = banner and waitChild(banner, "Close", "BasicGui.InventoryGui.MainFrame.Banner.Close")
    local tabButtons = waitChild(mainFrame, "table", "BasicGui.InventoryGui.MainFrame.table")
    local pages = waitChild(mainFrame, "MainFrame", "BasicGui.InventoryGui.MainFrame.MainFrame")
    if not (closeButton and tabButtons and pages) then
        return
    end
    local sortFrame = mainFrame:FindFirstChild("Sort")
    local sortList = sortFrame and sortFrame:FindFirstChild("List")
    if not sortFrame then
        warnMissing("BasicGui.InventoryGui.MainFrame.Sort")
    elseif not sortList then
        warnMissing("BasicGui.InventoryGui.MainFrame.Sort.List")
    end
    local actionList = pages:FindFirstChild("ActionList")
    local searchBoxFrame = actionList and actionList:FindFirstChild("SearchBoxFrame")
    local searchBox = searchBoxFrame and searchBoxFrame:FindFirstChild("SearchBox")
    if not actionList then
        warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame.ActionList")
    elseif not searchBoxFrame then
        warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame.ActionList.SearchBoxFrame")
    elseif not searchBox then
        warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame.ActionList.SearchBoxFrame.SearchBox")
    end

    local playProperty = basicGui:FindFirstChild("PlayProperty")
    local coinLabel = playProperty and playProperty:FindFirstChild("CoinLabel")

    local uiTemplatesFolder = ReplicatedStorage:WaitForChild("UITemplates")
    local itemTemplate = waitChild(uiTemplatesFolder, "Lite", "ReplicatedStorage.UITemplates.Lite")
    if not itemTemplate then
        return
    end

    local seedPage = waitChild(pages, "SeedPage", "BasicGui.InventoryGui.MainFrame.MainFrame.SeedPage")
    local plantPage = waitChild(pages, "PlantPage", "BasicGui.InventoryGui.MainFrame.MainFrame.PlantPage")
    local chestPage = pages:FindFirstChild("ChestPage")
    local itemPage = pages:FindFirstChild("ItemPage")
    local titlePage = pages:FindFirstChild("TitlePage")
    if not itemPage then
        warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame.ItemPage")
    end
    if not titlePage then
        warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame.TitlePage")
    end
    if not (seedPage and plantPage) then
        return
    end

    mainFrame.Visible = true
    mainFrame.Active = true
    local rootGui = mainFrame:FindFirstAncestorOfClass("ScreenGui")
    if rootGui then
        rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        rootGui.DisplayOrder = 100
    end

    mainFrame.ZIndex += 10000
    for _, uiElement in ipairs(mainFrame:GetDescendants()) do
        if uiElement:IsA("GuiObject") then
            uiElement.ZIndex += 10000
        end
    end

    local currentPageName = "SeedPage"
    local currentFilter = FILTER_ALL
    local currentSearchText = ""
    if searchBox and searchBox:IsA("TextBox") then
        currentSearchText = normalizeSearchText(searchBox.Text)
    end

    local function isSlotVisibleForFilter(slot)
        if currentFilter == FILTER_ALL then
            if currentSearchText == "" then
                return true
            end
        elseif tonumber(slot:GetAttribute("InventoryFilterCategory")) ~= currentFilter then
            return false
        end

        if currentSearchText == "" then
            return true
        end

        local searchText = slot:GetAttribute("InventorySearchText")
        return type(searchText) == "string" and string.find(searchText, currentSearchText, 1, true) ~= nil
    end

    local function applyFilterToPage(page)
        if not page then
            return
        end

        for _, slot in ipairs(page:GetChildren()) do
            if slot:GetAttribute("InventoryGeneratedItem") == true and slot:IsA("GuiObject") then
                slot.Visible = isSlotVisibleForFilter(slot)
            end
        end
    end

    local function applyCurrentFilter()
        applyFilterToPage(seedPage)
        applyFilterToPage(plantPage)
    end

    local function updateSortVisibility()
        if sortFrame and sortFrame:IsA("GuiObject") then
            sortFrame.Visible = FILTERABLE_PAGES[currentPageName] == true
        end
    end

    local function updateSortButtonState()
        if not sortList then
            return
        end

        for index = FILTER_ALL, FILTER_SPECIAL do
            local button = sortList:FindFirstChild("Button" .. tostring(index))
            if button and button:IsA("GuiObject") then
                local isSelected = index == currentFilter
                local stroke = button:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                end

                local darken = button:FindFirstChild("Darken")
                if darken and darken:IsA("GuiObject") then
                    darken.Visible = not isSelected
                end

                local selected = button:FindFirstChild("Selected")
                if selected and selected:IsA("GuiObject") then
                    selected.Visible = isSelected
                end

                local notSelected = button:FindFirstChild("NotSelected")
                if notSelected and notSelected:IsA("GuiObject") then
                    notSelected.Visible = not isSelected
                end
            end
        end
    end

    local function resetFilterToAll()
        currentFilter = FILTER_ALL
        updateSortButtonState()
        applyCurrentFilter()
    end

    local function bindEquip(slot, equipKey)
        if slot:GetAttribute("InventoryEquipBoundKey") == equipKey then
            return
        end
        slot:SetAttribute("InventoryEquipBoundKey", equipKey)

        local lastClickTick = 0
        local function equip()
            if os.clock() - lastClickTick < 0.1 then
                return
            end
            lastClickTick = os.clock()
            ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer(equipKey)
        end

        connectPress(slot, equip)

        local icon = findImageObject(slot, { "Icon", "Icom" })
        if icon and icon ~= slot then
            connectPress(icon, equip)
        end
    end

    local function bindTitleToggle(slot, titleId)
        if slot:GetAttribute("InventoryTitleBoundKey") == titleId then
            return
        end
        slot:SetAttribute("InventoryTitleBoundKey", titleId)

        local lastClickTick = 0
        local function toggleTitle()
            if os.clock() - lastClickTick < 0.45 then
                return
            end
            lastClickTick = os.clock()
            ReplicatedStorage:WaitForChild("ToggleTitleRE"):FireServer(titleId)
        end

        local function connectRelease(guiObject)
            if not guiObject then
                return
            end

            if guiObject:IsA("GuiButton") then
                guiObject.Activated:Connect(toggleTitle)
            else
                guiObject.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        toggleTitle()
                    end
                end)
            end
        end

        connectRelease(slot)

        local icon = findImageObject(slot, { "Icon", "Icom" })
        if icon and icon ~= slot then
            connectRelease(icon)
        end
    end

    local function setTitleEquippedState(slot, isEquipped)
        local exclusive = slot:FindFirstChild("Exclusive", true)
        if exclusive and (exclusive:IsA("ImageLabel") or exclusive:IsA("ImageButton")) then
            exclusive.Image = isEquipped and EQUIPPED_TITLE_EXCLUSIVE_ICON or ""
            exclusive.ImageColor3 = Color3.fromRGB(255, 255, 255)
            exclusive.Visible = isEquipped
        elseif exclusive and exclusive:IsA("GuiObject") then
            exclusive.Visible = isEquipped
        end
    end

    local function configureSlot(slot, slotId, displayName, quantity, itemId, itemType, iconId, qualityId, equipKey, mutationLevel, itemDetail, filterCategory, layoutOrder, searchText)
        slot.Name = slotId
        slot.Visible = true
        slot.LayoutOrder = layoutOrder or 0
        slot:SetAttribute("InventoryGeneratedItem", true)
        slot:SetAttribute("InventoryQuality", tonumber(qualityId) or 1)
        slot:SetAttribute("InventoryFilterCategory", filterCategory or FILTER_NORMAL)
        slot:SetAttribute("InventorySearchText", searchText or "")

        setSlotTitleAndQuantity(slot, displayName, quantity)
        setSlotIcon(slot, itemId, itemType, iconId, mutationLevel)
        setSlotMutationIcon(slot, ItemConfig, itemType, mutationLevel)
        applyQualityGradient(slot, ItemConfig, qualityId)

        local claimFrame = slot:FindFirstChild("ClaimFrame", true)
        if claimFrame and claimFrame:IsA("GuiObject") then
            claimFrame.Visible = false
        end

        if itemDetail and itemDetail.IsThrowable then
            createExplosionBadge(slot)
        end

        if equipKey then
            bindEquip(slot, equipKey)
        end
    end

    local function refreshOrCreateSlot(page, slotId, configure)
        local existingSlot = page:FindFirstChild(slotId)
        if existingSlot then
            configure(existingSlot)
            return
        end

        local newSlot = itemTemplate:Clone()
        configure(newSlot)
        newSlot.Parent = page
    end

    local function RefreshInventory(newData)
        if not newData or not newData.Inventory then
            return
        end

        if coinLabel and (coinLabel:IsA("TextLabel") or coinLabel:IsA("TextButton")) then
            UIEffectUtil.RollNumber(coinLabel, newData.Coins, "")
        end

        local currentSeedItems, currentPlantItems, currentChestItems, currentItemItems, currentTitleItems = {}, {}, {}, {}, {}

        if newData.Inventory.Seeds then
            local seedEntries = {}
            for _, seedData in ipairs(newData.Inventory.Seeds) do
                local seedId = seedData.ID
                local seedDetail = ItemConfig.Seeds[seedId]
                if seedDetail then
                    currentSeedItems[seedId] = true
                    local quality = getInventoryQuality(ItemConfig, seedId, "Seed", seedDetail)
                    local yieldPlantId = seedDetail.YieldPlant or seedId
                    local yieldPlantDetail = getSeedPlantDetail(ItemConfig, seedId, seedDetail)
                    table.insert(seedEntries, {
                        data = seedData,
                        detail = seedDetail,
                        displayName = seedDetail.Name or seedId,
                        filterCategory = getInventoryFilterCategory("Seed", seedDetail, quality, 1),
                        iconId = getSeedIconId(ItemConfig, seedId, seedDetail),
                        id = seedId,
                        order = getInventoryOrder(ItemConfig, seedId, "Seed", seedDetail),
                        quality = quality,
                        searchText = buildSearchText({
                            seedDetail.Name,
                            seedId,
                            yieldPlantDetail and yieldPlantDetail.Name,
                            yieldPlantId,
                        }),
                    })
                end
            end

            table.sort(seedEntries, sortInventoryEntries)
            for layoutOrder, entry in ipairs(seedEntries) do
                refreshOrCreateSlot(seedPage, entry.id, function(slot)
                    configureSlot(
                        slot,
                        entry.id,
                        entry.displayName,
                        entry.data.Quantity,
                        entry.id,
                        "Seed",
                        entry.iconId,
                        entry.quality,
                        "Seed_" .. entry.id,
                        1,
                        entry.detail,
                        entry.filterCategory,
                        layoutOrder,
                        entry.searchText
                    )
                end)
            end
        end

        if newData.Inventory.Plants then
            local plantEntries = {}
            for _, plantData in ipairs(newData.Inventory.Plants) do
                local plantId = plantData.ID
                local mutLevel = plantData.Mutation or 1
                local slotId = plantId .. "_" .. tostring(mutLevel)
                currentPlantItems[slotId] = true

                local plantDetail = ItemConfig.Plants[plantId]
                if plantDetail then
                    local mutName = ItemConfig.MutationName and ItemConfig.MutationName[mutLevel] or "Unknown"
                    local displayName = mutLevel > 1 and ("[" .. mutName .. "] " .. (plantDetail.Name or plantId))
                        or (plantDetail.Name or plantId)
                    local quality = getInventoryQuality(ItemConfig, plantId, "Plant", plantDetail)

                    table.insert(plantEntries, {
                        data = plantData,
                        detail = plantDetail,
                        displayName = displayName,
                        filterCategory = getInventoryFilterCategory("Plant", plantDetail, quality, mutLevel),
                        iconId = plantDetail.IconId,
                        id = plantId,
                        mutationLevel = mutLevel,
                        order = getInventoryOrder(ItemConfig, plantId, "Plant", plantDetail),
                        quality = quality,
                        searchText = buildSearchText({
                            displayName,
                            plantDetail.Name,
                            plantId,
                            mutName,
                        }),
                        slotId = slotId,
                    })
                end
            end

            table.sort(plantEntries, sortInventoryEntries)
            for layoutOrder, entry in ipairs(plantEntries) do
                refreshOrCreateSlot(plantPage, entry.slotId, function(slot)
                    configureSlot(
                        slot,
                        entry.slotId,
                        entry.displayName,
                        entry.data.Quantity,
                        entry.id,
                        "Plant",
                        entry.iconId,
                        entry.quality,
                        "Plant_" .. entry.id .. "_" .. tostring(entry.mutationLevel),
                        entry.mutationLevel,
                        entry.detail,
                        entry.filterCategory,
                        layoutOrder,
                        entry.searchText
                    )
                end)
            end
        end

        if chestPage and newData.Inventory.Chests then
            for _, chestData in ipairs(newData.Inventory.Chests) do
                local chestId = chestData.ID
                currentChestItems[chestId] = true

                local chestDetail = ItemConfig.Chests and ItemConfig.Chests[chestId]
                if chestDetail then
                    local chestConfig = ChestConfig.GetChest(chestId)
                    local chestIconId = (chestConfig and chestConfig.ImageId) or chestDetail.IconId
                    refreshOrCreateSlot(chestPage, chestId, function(slot)
                        configureSlot(
                            slot,
                            chestId,
                            chestDetail.Name or chestId,
                            chestData.Quantity,
                            chestId,
                            "Chest",
                            chestIconId,
                            chestDetail.Quality,
                            "Chest_" .. chestId,
                            1,
                            chestDetail
                        )
                    end)
                end
            end
        end

        if itemPage and newData.Inventory.Items then
            local itemEntries = {}
            for _, itemData in ipairs(newData.Inventory.Items) do
                local itemId = itemData.ID
                local itemDetail = ItemConfig.Items and ItemConfig.Items[itemId]
                if itemDetail then
                    currentItemItems[itemId] = true
                    local quality = getInventoryQuality(ItemConfig, itemId, "Item", itemDetail)
                    table.insert(itemEntries, {
                        data = itemData,
                        detail = itemDetail,
                        displayName = itemDetail.Name or itemId,
                        iconId = itemDetail.IconId,
                        id = itemId,
                        order = getInventoryOrder(ItemConfig, itemId, "Item", itemDetail),
                        quality = quality,
                        searchText = buildSearchText({
                            itemDetail.Name,
                            itemId,
                            itemDetail.ItemType,
                        }),
                    })
                end
            end

            table.sort(itemEntries, sortInventoryEntries)
            for layoutOrder, entry in ipairs(itemEntries) do
                refreshOrCreateSlot(itemPage, entry.id, function(slot)
                    configureSlot(
                        slot,
                        entry.id,
                        entry.displayName,
                        entry.data.Quantity,
                        entry.id,
                        "Item",
                        entry.iconId,
                        entry.quality,
                        "Item_" .. entry.id,
                        1,
                        entry.detail,
                        FILTER_SPECIAL,
                        layoutOrder,
                        entry.searchText
                    )
                end)
            end
        end

        if titlePage and newData.Inventory.Titles then
            local ownedTitleMap = {}
            for _, titleData in ipairs(newData.Inventory.Titles) do
                local titleId = type(titleData) == "table" and titleData.ID or titleData
                local titleDetail = TitleConfig.GetTitle(titleId)
                if titleDetail then
                    ownedTitleMap[titleId] = titleDetail
                    currentTitleItems[titleId] = true
                end
            end

            local titleEntries = {}
            for _, titleDetail in ipairs(TitleConfig.GetSortedTitles()) do
                if ownedTitleMap[titleDetail.Id] then
                    table.insert(titleEntries, titleDetail)
                end
            end

            table.sort(titleEntries, function(a, b)
                local aOrder = tonumber(a.Order) or 9999
                local bOrder = tonumber(b.Order) or 9999
                if aOrder ~= bOrder then
                    return aOrder < bOrder
                end

                return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
            end)

            for layoutOrder, titleDetail in ipairs(titleEntries) do
                refreshOrCreateSlot(titlePage, titleDetail.Id, function(slot)
                    configureSlot(
                        slot,
                        titleDetail.Id,
                        titleDetail.Name or titleDetail.Id,
                        nil,
                        titleDetail.Id,
                        "Title",
                        titleDetail.ImageId,
                        titleDetail.Quality or 6,
                        nil,
                        1,
                        titleDetail,
                        FILTER_SPECIAL,
                        layoutOrder,
                        buildSearchText({ titleDetail.Name, titleDetail.Id })
                    )
                    setTitleEquippedState(slot, newData.EquippedTitle == titleDetail.Id)
                    bindTitleToggle(slot, titleDetail.Id)
                end)
            end
        end

        removeMissingSlots(seedPage, currentSeedItems)
        removeMissingSlots(plantPage, currentPlantItems)
        removeMissingSlots(chestPage, currentChestItems)
        removeMissingSlots(itemPage, currentItemItems)
        removeMissingSlots(titlePage, currentTitleItems)
        applyCurrentFilter()
    end

    local function switchTab(targetPageName)
        if not TAB_BY_PAGE[targetPageName] or not pages:FindFirstChild(targetPageName) then
            warnMissing("BasicGui.InventoryGui.MainFrame.MainFrame." .. tostring(targetPageName))
            targetPageName = currentPageName
        end

        currentPageName = targetPageName
        currentFilter = FILTER_ALL
        for _, page in ipairs(pages:GetChildren()) do
            if page:IsA("GuiObject") and TAB_BY_PAGE[page.Name] then
                page.Visible = page.Name == targetPageName
            end
        end

        local selectedTabName = TAB_BY_PAGE[targetPageName]
        for _, btn in ipairs(tabButtons:GetChildren()) do
            if btn:IsA("GuiObject") then
                local isSelected = btn.Name == selectedTabName
                local stroke = btn:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                end

                local darken = btn:FindFirstChild("Darken")
                if darken and darken:IsA("GuiObject") then
                    darken.Visible = not isSelected
                end
            end
        end

        updateSortVisibility()
        updateSortButtonState()
        applyCurrentFilter()
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshInventory(getPlayerDataRF:InvokeServer())
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(RefreshInventory)
    local playerDataPatchRE = ReplicatedStorage:WaitForChild("PlayerDataPatchRE", 10)
    if playerDataPatchRE then
        playerDataPatchRE.OnClientEvent:Connect(function(patch)
            if type(patch) ~= "table" then
                return
            end

            if patch.Coins ~= nil and coinLabel and (coinLabel:IsA("TextLabel") or coinLabel:IsA("TextButton")) then
                UIEffectUtil.RollNumber(coinLabel, patch.Coins, "")
            end
        end)
    end

    if sortList then
        for index = FILTER_ALL, FILTER_SPECIAL do
            local button = sortList:FindFirstChild("Button" .. tostring(index))
            if button then
                local filterIndex = index
                connectPress(button, function()
                    currentFilter = filterIndex
                    updateSortButtonState()
                    applyCurrentFilter()
                end)
            end
        end
    end
    updateSortButtonState()
    updateSortVisibility()

    if searchBox then
        if searchBox:IsA("TextBox") then
            currentSearchText = normalizeSearchText(searchBox.Text)
            searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                currentSearchText = normalizeSearchText(searchBox.Text)
                applyCurrentFilter()
            end)
        else
            warn("[InventoryController] SearchBox is not a TextBox: BasicGui.InventoryGui.MainFrame.MainFrame.ActionList.SearchBoxFrame.SearchBox")
        end
    end

    inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if inventoryGui.Enabled then
            resetFilterToAll()
        end
    end)

    if openButton then
        connectPress(openButton, function()
            inventoryGui.Enabled = true
        end)
    end
    connectPress(closeButton, function()
        inventoryGui.Enabled = false
    end)

    local openInvRE = ReplicatedStorage:WaitForChild("OpenInventoryRE", 5)
    if openInvRE then
        openInvRE.OnClientEvent:Connect(function(targetPageName)
            inventoryGui.Enabled = true
            local pageToOpen = targetPageName or "SeedPage"
            switchTab(pageToOpen)

            if pageToOpen == "SeedPage" or pageToOpen == "PlantPage" then
                local titleStr = (pageToOpen == "PlantPage") and "Deploy Notice" or "Plant Notice"
                local textStr = (pageToOpen == "PlantPage")
                    and "Please select a combat plant from your inventory to deploy!"
                    or "Please select a seed from your inventory to plant!"
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = titleStr,
                        Text = textStr,
                        Duration = 4,
                    })
                end)
            end
        end)
    end

    switchTab("SeedPage")
    for tabName, pageName in pairs(PAGE_BY_TAB) do
        local tabButton = tabButtons:FindFirstChild(tabName)
        if tabButton and pages:FindFirstChild(pageName) then
            connectPress(tabButton, function()
                switchTab(pageName)
            end)
        end
    end

    print("Client: InventoryController loaded with new Lite inventory UI.")
end

return InventoryController

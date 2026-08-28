-- src/client/UI/ChestController.luau
local ChestController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local ChestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChestConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local player = Players.LocalPlayer
local guiConnections = {}
local characterConnection = nil
local currentChestId = nil
local isOpeningChest = false
local suppressUnequipCloseUntilAnimationDone = false
local cachedPlayerData = nil
local pendingIAPChestId = nil
local pendingIAPPurchase = false

local DISPLAY_FRAME_NAME = "DisplayFrame"
local BOX_NAME = "Box"
local BOX_IMAGE_LABEL_NAME = "ImageLabel"
local BOX_LEVEL_TEXT_NAME = "TextLabel"
local VIEWPORT_FRAME_NAME = "ViewportFrame"
local VIEWPORT_LIGHT_NAME = "Light"
local IMAGE_SLIDE_START_POSITION = UDim2.fromScale(0.5, -0.25)
local IMAGE_FADE_SHRINK_SCALE = 0.18
local SLIDE_SECONDS = 0.5
local SHAKE_SECONDS = 2
local FADE_SHRINK_SECONDS = 0.5
local REWARD_VISIBLE_SECONDS = 3
local LIGHT_ROTATION_DEGREES_PER_SECOND = 10
local CHEST_OPEN_PRODUCT_ID = 3606175579

local function disconnectGuiConnections()
    for _, connection in ipairs(guiConnections) do
        connection:Disconnect()
    end
    table.clear(guiConnections)
end

local function findChestGui()
    local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
    local basicGui = playerGui:FindFirstChild("BasicGui") or playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        return nil
    end

    return basicGui:FindFirstChild("ChestGui") or basicGui:WaitForChild("ChestGui", 5)
end

local function setGuiOpen(chestGui, isOpen)
    if not chestGui then
        return
    end

    if chestGui:IsA("ScreenGui") then
        chestGui.Enabled = isOpen
    elseif chestGui:IsA("GuiObject") then
        chestGui.Visible = isOpen
    else
        pcall(function()
            chestGui.Enabled = isOpen
        end)
    end
end

local function getTextNode(root)
    if not root then
        return nil
    end

    if root:IsA("TextButton") or root:IsA("TextLabel") or root:IsA("TextBox") then
        return root
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("TextButton") or descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
            return descendant
        end
    end

    return nil
end

local function setText(root, text)
    local textNode = getTextNode(root)
    if textNode then
        textNode.Text = text
    end
end

local function setNamedText(root, names, text)
    for _, name in ipairs(names) do
        local node = root:FindFirstChild(name, true)
        if node then
            setText(node, text)
        end
    end
end

local function findButton(root, name)
    local node = root:FindFirstChild(name, true)
    if node then
        if node:IsA("GuiButton") then
            return node
        end

        for _, descendant in ipairs(node:GetDescendants()) do
            if descendant:IsA("GuiButton") then
                return descendant
            end
        end
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == name and descendant:IsA("GuiButton") then
            return descendant
        end
    end

    return nil
end

local function buildRewardText(chestConfig)
    local parts = {}
    for _, reward in ipairs(chestConfig.Rewards or {}) do
        local plantConfig = ItemConfig.Plants[reward.PlantId]
        local name = plantConfig and (plantConfig.Name or reward.PlantId) or reward.PlantId
        table.insert(parts, string.format("%s %d%%", name, reward.Weight or 0))
    end

    return table.concat(parts, " / ")
end

local function updateChestInfo(chestGui, chestId)
    local itemConfig = ItemConfig.Chests and ItemConfig.Chests[chestId]
    local chestConfig = ChestConfig.GetChest(chestId)
    if not chestConfig then
        return
    end

    local displayFrame = chestGui:FindFirstChild(DISPLAY_FRAME_NAME)
    local chestName = chestConfig.Name or (itemConfig and itemConfig.Name) or chestId
    local chestImageId = chestConfig.ImageId or (itemConfig and itemConfig.IconId) or ""
    local priceText = "Price: " .. UIEffectUtil.FormatNumber(chestConfig.Price or 0)

    local function setDirectText(parent, childName, text)
        local child = parent and parent:FindFirstChild(childName)
        if child then
            setText(child, text)
            return true
        end
        return false
    end

    local function setDirectImage(parent, childName, imageId)
        local child = parent and parent:FindFirstChild(childName)
        if child and (child:IsA("ImageLabel") or child:IsA("ImageButton")) then
            child.Image = imageId
            return true
        end
        return false
    end

    local function hideDirectText(parent, childName)
        local child = parent and parent:FindFirstChild(childName)
        if child then
            setText(child, "")
            if child:IsA("GuiObject") then
                child.Visible = false
            end
            return true
        end
        return false
    end

    if displayFrame then
        setDirectText(displayFrame, "ChestName", chestName)
        setDirectImage(displayFrame, "ChestImage", chestImageId)
        setDirectText(displayFrame, "PriceText", priceText)

        local rewardFrames = {}
        for _, child in ipairs(displayFrame:GetChildren()) do
            local index = tonumber(string.match(child.Name, "^Frame(%d+)$"))
            if index and child:IsA("GuiObject") then
                table.insert(rewardFrames, { Index = index, Frame = child })
            end
        end
        table.sort(rewardFrames, function(a, b)
            return a.Index < b.Index
        end)

        for _, frameInfo in ipairs(rewardFrames) do
            local reward = chestConfig.Rewards and chestConfig.Rewards[frameInfo.Index]
            local rewardFrame = frameInfo.Frame
            if reward then
                local plantConfig = ItemConfig.Plants[reward.PlantId]
                local plantName = plantConfig and (plantConfig.Name or reward.PlantId) or reward.PlantId
                setDirectText(rewardFrame, "Name", plantName)
                setDirectText(rewardFrame, "ProbabilityText", "Chance: " .. tostring(reward.Weight or 0) .. "%")
                hideDirectText(rewardFrame, "LevelText")
            else
                setDirectText(rewardFrame, "Name", "")
                setDirectText(rewardFrame, "ProbabilityText", "")
                hideDirectText(rewardFrame, "LevelText")
            end
        end
    end

    setNamedText(chestGui, { "ChestName", "Title", "NameLabel" }, chestName)
    setNamedText(chestGui, { "Price", "PriceLabel", "Cost", "CostLabel" }, priceText)
    setNamedText(chestGui, { "RewardText", "RewardsText", "RewardsLabel", "PlantList", "PlantsLabel", "Detail", "Details" }, buildRewardText(chestConfig))
end

local function getGuiObject(root, name)
    local node = root and (root:FindFirstChild(name) or root:FindFirstChild(name, true))
    if node and node:IsA("GuiObject") then
        return node
    end

    return nil
end

local function fetchPlayerData()
    local getPlayerDataRF = ReplicatedStorage:FindFirstChild("GetPlayerDataRF")
    if not getPlayerDataRF then
        return cachedPlayerData
    end

    local ok, data = pcall(function()
        return getPlayerDataRF:InvokeServer()
    end)
    if ok and type(data) == "table" then
        cachedPlayerData = data
    end

    return cachedPlayerData
end

local function updateIAPTextVisibility(chestGui, chestId)
    local iapText = getGuiObject(chestGui, "IAPText")
    if not iapText then
        return nil
    end

    local chestConfig = chestId and ChestConfig.GetChest(chestId)
    local playerData = fetchPlayerData()
    local currentSun = tonumber(playerData and playerData.Coins) or 0
    local price = tonumber(chestConfig and chestConfig.Price) or 0
    iapText.Visible = currentSun < price

    return iapText
end

local function getImageObject(root, name)
    local node = root and root:FindFirstChild(name)
    if node and (node:IsA("ImageLabel") or node:IsA("ImageButton")) then
        return node
    end

    return nil
end

local function getViewportFrame(root, name)
    local node = root and root:FindFirstChild(name)
    if node and node:IsA("ViewportFrame") then
        return node
    end

    return nil
end

local function clearViewportFrame(viewportFrame)
    if not viewportFrame then
        return
    end

    for _, child in ipairs(viewportFrame:GetChildren()) do
        child:Destroy()
    end
end

local function scaleUDim2(value, scale)
    return UDim2.new(
        value.X.Scale * scale,
        value.X.Offset * scale,
        value.Y.Scale * scale,
        value.Y.Offset * scale
    )
end

local function offsetUDim2(position, offsetX, offsetY)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset + offsetX,
        position.Y.Scale,
        position.Y.Offset + offsetY
    )
end

local function getScaledPositionKeepingCenter(position, size, anchorPoint, scale)
    local scaledSize = scaleUDim2(size, scale)
    local xCenterOffset = 0.5 - anchorPoint.X
    local yCenterOffset = 0.5 - anchorPoint.Y

    return UDim2.new(
        position.X.Scale + (size.X.Scale - scaledSize.X.Scale) * xCenterOffset,
        position.X.Offset + (size.X.Offset - scaledSize.X.Offset) * xCenterOffset,
        position.Y.Scale + (size.Y.Scale - scaledSize.Y.Scale) * yCenterOffset,
        position.Y.Offset + (size.Y.Offset - scaledSize.Y.Offset) * yCenterOffset
    )
end

local function getPositionAfterAnchorPointChange(position, size, oldAnchorPoint, newAnchorPoint)
    return UDim2.new(
        position.X.Scale + size.X.Scale * (newAnchorPoint.X - oldAnchorPoint.X),
        position.X.Offset + size.X.Offset * (newAnchorPoint.X - oldAnchorPoint.X),
        position.Y.Scale + size.Y.Scale * (newAnchorPoint.Y - oldAnchorPoint.Y),
        position.Y.Offset + size.Y.Offset * (newAnchorPoint.Y - oldAnchorPoint.Y)
    )
end

local function playTween(instance, tweenInfo, goal)
    local tween = TweenService:Create(instance, tweenInfo, goal)
    tween:Play()
    tween.Completed:Wait()
end

local function shakeBoxTwice(box, originalPosition, originalRotation, durationSeconds)
    local shakeSteps = {
        { OffsetX = -10, Rotation = -8 },
        { OffsetX = 10, Rotation = 8 },
        { OffsetX = -6, Rotation = -4 },
        { OffsetX = 6, Rotation = 4 },
        { OffsetX = 0, Rotation = 0 },
    }
    local totalSteps = #shakeSteps * 2
    local stepSeconds = math.max((tonumber(durationSeconds) or 0) / totalSteps, 0.01)

    for _ = 1, 2 do
        for _, step in ipairs(shakeSteps) do
            playTween(box, TweenInfo.new(stepSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = offsetUDim2(originalPosition, step.OffsetX, 0),
                Rotation = originalRotation + step.Rotation,
            })
        end
    end

    box.Position = originalPosition
    box.Rotation = originalRotation
end

local function startLightRotation(light, degreesPerSecond)
    if not light or not light.Parent then
        return function() end
    end

    local connection
    connection = RunService.RenderStepped:Connect(function(deltaTime)
        if not light.Parent then
            connection:Disconnect()
            return
        end

        light.Rotation = (light.Rotation + degreesPerSecond * deltaTime) % 360
    end)

    return function()
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
end

local function setBoxLevelText(box, result)
    local levelText = box and box:FindFirstChild(BOX_LEVEL_TEXT_NAME)
    if not levelText or not levelText:IsA("TextLabel") then
        return
    end

    levelText.Text = ""
    levelText.Visible = false
end

local function hideBoxLevelText(box)
    local levelText = box and box:FindFirstChild(BOX_LEVEL_TEXT_NAME)
    if levelText and levelText:IsA("TextLabel") then
        levelText.Text = ""
        levelText.Visible = false
    end
end

local function resetFishingStyleAnimationState(chestGui)
    local displayFrame = getGuiObject(chestGui, DISPLAY_FRAME_NAME)
    if displayFrame then
        displayFrame.Visible = true
    end

    local box = getGuiObject(chestGui, BOX_NAME)
    if not box then
        return
    end

    box.Visible = false
    hideBoxLevelText(box)

    local imageLabel = getImageObject(box, BOX_IMAGE_LABEL_NAME)
    if imageLabel then
        imageLabel.Visible = true
        imageLabel.ImageTransparency = 0
    end

    local light = getImageObject(box, VIEWPORT_LIGHT_NAME)
    if light then
        light.Visible = false
    end

    local viewportFrame = getViewportFrame(box, VIEWPORT_FRAME_NAME)
    if viewportFrame then
        clearViewportFrame(viewportFrame)
        viewportFrame.Visible = false
    end
end

local function playFishingStyleChestAnimation(chestGui, result)
    local displayFrame = getGuiObject(chestGui, DISPLAY_FRAME_NAME)
    local box = getGuiObject(chestGui, BOX_NAME)
    if not displayFrame or not box then
        return false
    end

    local imageLabel = getImageObject(box, BOX_IMAGE_LABEL_NAME)
    local viewportFrame = getViewportFrame(box, VIEWPORT_FRAME_NAME)
    if not imageLabel or not viewportFrame then
        return false
    end

    local light = getImageObject(box, VIEWPORT_LIGHT_NAME)
    local originalBoxPosition = box.Position
    local originalBoxRotation = box.Rotation
    local originalImage = imageLabel.Image
    local originalImageTransparency = imageLabel.ImageTransparency
    local originalImagePosition = imageLabel.Position
    local originalImageSize = imageLabel.Size
    local originalLightVisible = light and light.Visible or false
    local originalLightRotation = light and light.Rotation or 0
    local originalLightAnchorPoint = light and light.AnchorPoint or Vector2.new(0, 0)
    local originalLightPosition = light and light.Position or UDim2.new()

    setGuiOpen(chestGui, true)
    displayFrame.Visible = false
    box.Visible = true
    box.Position = IMAGE_SLIDE_START_POSITION
    box.Rotation = originalBoxRotation

    viewportFrame.Visible = false
    clearViewportFrame(viewportFrame)
    imageLabel.Visible = true
    imageLabel.ImageTransparency = 0
    imageLabel.Position = originalImagePosition
    imageLabel.Size = originalImageSize

    local chestId = result and result.ChestId
    local chestConfig = chestId and ChestConfig.GetChest(chestId)
    local chestDetail = chestId and ItemConfig.Chests and ItemConfig.Chests[chestId]
    local chestImageId = chestConfig and chestConfig.ImageId
    if type(chestImageId) ~= "string" or chestImageId == "" then
        chestImageId = chestDetail and chestDetail.IconId
    end
    if type(chestImageId) == "string" and chestImageId ~= "" then
        imageLabel.Image = chestImageId
    end

    playTween(box, TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = originalBoxPosition,
    })
    shakeBoxTwice(box, originalBoxPosition, originalBoxRotation, SHAKE_SECONDS)
    playTween(imageLabel, TweenInfo.new(FADE_SHRINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        ImageTransparency = 1,
        Position = getScaledPositionKeepingCenter(originalImagePosition, originalImageSize, imageLabel.AnchorPoint, IMAGE_FADE_SHRINK_SCALE),
        Size = scaleUDim2(originalImageSize, IMAGE_FADE_SHRINK_SCALE),
    })

    imageLabel.Visible = false
    viewportFrame.Visible = true
    if result and result.RewardPlantId then
        UIEffectUtil.RenderToViewport(viewportFrame, result.RewardPlantId, "Plant", tonumber(result.MutationLevel) or 1)
        setBoxLevelText(box, result)
    else
        clearViewportFrame(viewportFrame)
    end

    local stopLightRotation = function() end
    if light then
        light.Position = getPositionAfterAnchorPointChange(originalLightPosition, light.Size, originalLightAnchorPoint, Vector2.new(0.5, 0.5))
        light.AnchorPoint = Vector2.new(0.5, 0.5)
        light.Rotation = originalLightRotation
        light.Visible = true
        stopLightRotation = startLightRotation(light, LIGHT_ROTATION_DEGREES_PER_SECOND)
    end

    task.wait(REWARD_VISIBLE_SECONDS)
    stopLightRotation()

    clearViewportFrame(viewportFrame)
    viewportFrame.Visible = false
    hideBoxLevelText(box)
    imageLabel.Image = originalImage
    imageLabel.ImageTransparency = originalImageTransparency
    imageLabel.Position = originalImagePosition
    imageLabel.Size = originalImageSize
    imageLabel.Visible = true

    if light then
        light.Visible = originalLightVisible
        light.Rotation = originalLightRotation
        light.AnchorPoint = originalLightAnchorPoint
        light.Position = originalLightPosition
    end

    box.Position = originalBoxPosition
    box.Rotation = originalBoxRotation
    box.Visible = false
    displayFrame.Visible = true
    setGuiOpen(chestGui, false)

    return true
end

local function waitForDuration(value, fallbackSeconds)
    local seconds = tonumber(value) or fallbackSeconds
    if seconds and seconds > 0 then
        task.wait(seconds)
    end
end

local function playCopiedChestAnimation(chestGui, result)
    local payload = result or {}
    local entryNames = { "PlayOpenAnimation", "OpenAnimation", "ChestOpenAnimation" }

    chestGui:SetAttribute("ChestOpenRequest", (tonumber(chestGui:GetAttribute("ChestOpenRequest")) or 0) + 1)
    chestGui:SetAttribute("ChestRewardPlantId", payload.RewardPlantId or "")
    chestGui:SetAttribute("ChestRewardMutationLevel", tonumber(payload.MutationLevel) or 1)
    chestGui:SetAttribute("ChestId", payload.ChestId or currentChestId or "")

    for _, entryName in ipairs(entryNames) do
        local entry = chestGui:FindFirstChild(entryName, true)
        if entry then
            if entry:IsA("BindableFunction") then
                local ok, duration = pcall(function()
                    return entry:Invoke(payload)
                end)
                if ok then
                    waitForDuration(duration, 0)
                    return
                end
            elseif entry:IsA("BindableEvent") then
                local ok = pcall(function()
                    entry:Fire(payload)
                end)
                if ok then
                    task.wait(1.5)
                    return
                end
            elseif entry:IsA("ModuleScript") then
                local ok, module = pcall(require, entry)
                if ok then
                    local fn = type(module) == "table" and (module.Play or module.PlayOpenAnimation or module.OpenAnimation) or module
                    if type(fn) == "function" then
                        local playOk, duration
                        if type(module) == "table" then
                            playOk, duration = pcall(fn, module, payload)
                            if not playOk then
                                playOk, duration = pcall(fn, payload)
                            end
                        else
                            playOk, duration = pcall(fn, payload)
                        end
                        if playOk then
                            waitForDuration(duration, 1.5)
                            return
                        end
                    end
                end
            end
        end
    end

    if playFishingStyleChestAnimation(chestGui, payload) then
        return
    end

    task.wait(1.5)
end

local function playRewardAnimation(result)
    if not result or not result.RewardPlantId then
        return
    end

    local plantConfig = ItemConfig.Plants[result.RewardPlantId]
    if not plantConfig then
        return
    end

    local plantName = plantConfig.Name or result.RewardPlantId
    local playFullEffect = (tonumber(plantConfig.Quality) or 0) >= 4
    UIEffectUtil.PlayObtainEffect("Gain: 1x " .. plantName, playFullEffect)
end

local function playChestOpenResult(chestGui, result)
    local animationOk, animationErr = pcall(function()
        playCopiedChestAnimation(chestGui, result)
    end)

    suppressUnequipCloseUntilAnimationDone = false
    currentChestId = nil
    setGuiOpen(chestGui, false)

    if not animationOk then
        warn("[ChestController] Chest animation failed: " .. tostring(animationErr))
        UIEffectUtil.ShowTip("Reward added to inventory.")
    else
        playRewardAnimation(result)
    end
end

local function closeAndPutBack(chestGui)
    suppressUnequipCloseUntilAnimationDone = false
    setGuiOpen(chestGui, false)
    currentChestId = nil

    local holdItemRE = ReplicatedStorage:FindFirstChild("HoldItemRE")
    if holdItemRE then
        holdItemRE:FireServer(nil)
    end
end

local function beginChestIAPPurchase(chestId)
    local prepareChestIAPPurchaseRE = ReplicatedStorage:FindFirstChild("PrepareChestIAPPurchaseRE")
    if not prepareChestIAPPurchaseRE then
        UIEffectUtil.ShowTip("Chest purchase is not ready.")
        return false
    end

    pendingIAPChestId = chestId
    pendingIAPPurchase = true
    isOpeningChest = true
    suppressUnequipCloseUntilAnimationDone = true

    prepareChestIAPPurchaseRE:FireServer(chestId)
    MarketplaceService:PromptProductPurchase(player, CHEST_OPEN_PRODUCT_ID)
    return true
end

local function bindChestGui(chestGui)
    disconnectGuiConnections()

    local unlockButton = findButton(chestGui, "Unlock")
    local putBackButton = findButton(chestGui, "PutBack") or findButton(chestGui, "Discard")
    updateIAPTextVisibility(chestGui, currentChestId)

    if putBackButton then
        setText(putBackButton, "PutBack")
        table.insert(guiConnections, putBackButton.Activated:Connect(function()
            if isOpeningChest then
                return
            end
            closeAndPutBack(chestGui)
        end))
    end

    if unlockButton then
        table.insert(guiConnections, unlockButton.Activated:Connect(function()
            if isOpeningChest then
                return
            end

            if not currentChestId then
                UIEffectUtil.ShowTip("Please hold a chest first.")
                return
            end

            local requestChestId = currentChestId
            isOpeningChest = true
            suppressUnequipCloseUntilAnimationDone = true
            unlockButton.Active = false
            unlockButton.AutoButtonColor = false

            local useChestRF = ReplicatedStorage:FindFirstChild("UseChestRF")
            local ok, success, result = false, false, "Chest service is not ready."
            if useChestRF then
                ok, success, result = pcall(function()
                    return useChestRF:InvokeServer(requestChestId)
                end)
            end

            if not ok then
                suppressUnequipCloseUntilAnimationDone = false
                currentChestId = requestChestId
                UIEffectUtil.ShowTip("Chest opening failed.")
            elseif not success then
                suppressUnequipCloseUntilAnimationDone = false
                currentChestId = requestChestId
                if tostring(result) == "Not enough Sun." then
                    beginChestIAPPurchase(requestChestId)
                else
                    UIEffectUtil.ShowTip(tostring(result or "Chest opening failed."))
                    updateIAPTextVisibility(chestGui, requestChestId)
                end
            else
                playChestOpenResult(chestGui, result)
            end

            unlockButton.Active = true
            unlockButton.AutoButtonColor = true
            if not pendingIAPPurchase then
                isOpeningChest = false
            end
        end))
    else
        warn("[ChestController] Unlock button was not found in ChestGui")
    end

end

local function openChestGui(chestId)
    local chestGui = findChestGui()
    if not chestGui then
        UIEffectUtil.ShowTip("Chest UI is not ready.")
        return
    end

    currentChestId = chestId
    suppressUnequipCloseUntilAnimationDone = false
    updateChestInfo(chestGui, chestId)
    resetFishingStyleAnimationState(chestGui)
    bindChestGui(chestGui)
    setGuiOpen(chestGui, true)
end

local function handleEquippedChanged(character)
    local equippedId = character and character:GetAttribute("EquippedSeed")
    if type(equippedId) == "string" and string.sub(equippedId, 1, 6) == "Chest_" then
        local chestId = string.sub(equippedId, 7)
        openChestGui(chestId)
        return
    end

    if suppressUnequipCloseUntilAnimationDone and isOpeningChest then
        return
    end

    local chestGui = findChestGui()
    if chestGui then
        setGuiOpen(chestGui, false)
    end
    currentChestId = nil
end

local function bindCharacter(character)
    if characterConnection then
        characterConnection:Disconnect()
        characterConnection = nil
    end

    characterConnection = character:GetAttributeChangedSignal("EquippedSeed"):Connect(function()
        handleEquippedChanged(character)
    end)

    handleEquippedChanged(character)
end

local function handleChestIAPOpenResult(success, result)
    pendingIAPPurchase = false

    local chestGui = findChestGui()
    if not success then
        isOpeningChest = false
        suppressUnequipCloseUntilAnimationDone = false
        UIEffectUtil.ShowTip(tostring(result or "Chest opening failed."))
        if chestGui and currentChestId then
            updateIAPTextVisibility(chestGui, currentChestId)
        end
        return
    end

    if not chestGui then
        isOpeningChest = false
        suppressUnequipCloseUntilAnimationDone = false
        UIEffectUtil.ShowTip("Reward added to inventory.")
        return
    end

    currentChestId = (type(result) == "table" and result.ChestId) or pendingIAPChestId
    isOpeningChest = true
    suppressUnequipCloseUntilAnimationDone = true
    setGuiOpen(chestGui, true)
    playChestOpenResult(chestGui, result)

    pendingIAPChestId = nil
    isOpeningChest = false
end

function ChestController.Init()
    local chestGui = findChestGui()
    if chestGui then
        setGuiOpen(chestGui, false)
    end

    local chestIAPOpenResultRE = ReplicatedStorage:WaitForChild("ChestIAPOpenResultRE", 10)
    if chestIAPOpenResultRE then
        chestIAPOpenResultRE.OnClientEvent:Connect(handleChestIAPOpenResult)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if productId ~= CHEST_OPEN_PRODUCT_ID or userId ~= player.UserId then
            return
        end

        if not pendingIAPPurchase then
            return
        end

        if not isPurchased then
            pendingIAPPurchase = false
            pendingIAPChestId = nil
            isOpeningChest = false
            suppressUnequipCloseUntilAnimationDone = false
            local currentGui = findChestGui()
            if currentGui and currentChestId then
                updateIAPTextVisibility(currentGui, currentChestId)
            end
            return
        end

        task.delay(20, function()
            if pendingIAPPurchase then
                isOpeningChest = false
                suppressUnequipCloseUntilAnimationDone = false
                UIEffectUtil.ShowTip("Purchase is processing.")
            end
        end)
    end)

    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function(newData)
            cachedPlayerData = newData
            local currentGui = findChestGui()
            if currentGui and currentChestId then
                updateIAPTextVisibility(currentGui, currentChestId)
            end
        end)
    end

    local playerDataPatchRE = ReplicatedStorage:FindFirstChild("PlayerDataPatchRE") or ReplicatedStorage:WaitForChild("PlayerDataPatchRE", 10)
    if playerDataPatchRE then
        playerDataPatchRE.OnClientEvent:Connect(function(patch)
            if type(patch) ~= "table" then
                return
            end

            cachedPlayerData = cachedPlayerData or {}
            for key, value in pairs(patch) do
                cachedPlayerData[key] = value
            end

            local currentGui = findChestGui()
            if currentGui and currentChestId then
                updateIAPTextVisibility(currentGui, currentChestId)
            end
        end)
    end

    if player.Character then
        bindCharacter(player.Character)
    end

    player.CharacterAdded:Connect(bindCharacter)
end

return ChestController

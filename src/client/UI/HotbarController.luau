-- src/client/UI/HotbarController.luau
local HotbarController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local BaseItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BaseItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

function HotbarController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local hotbarFrame = playProperty:WaitForChild("HotbarFrame")

    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates", 5)
    local slotTemplate = uiTemplates:WaitForChild("ItemTemplate", 5)
    local closeBtnTemplate = uiTemplates:WaitForChild("CloseBtn", 5)

    local currentEquippedId = nil
    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local TOUCH_REMOVE_HOLD_DURATION = 2

    local function isPrimaryPointerInput(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
    end

    local function hideCloseButtons(exceptSlot)
        for _, slot in ipairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") and slot ~= exceptSlot then
                local closeButton = slot:FindFirstChild("CloseBtn")
                if closeButton and closeButton:IsA("GuiObject") then
                    closeButton.Visible = false
                end
            end
        end
    end

    local responsiveScale = hotbarFrame:FindFirstChild("ResponsiveScale")
    if not responsiveScale or not responsiveScale:IsA("UIScale") then
        responsiveScale = Instance.new("UIScale")
        responsiveScale.Name = "ResponsiveScale"
        responsiveScale.Parent = hotbarFrame
    end

    local function updateResponsiveScale()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local viewportWidth = camera.ViewportSize.X
        local scale = 1
        if UserInputService.TouchEnabled then
            scale = math.clamp(viewportWidth / 1280, 0.65, 0.8)
        end

        responsiveScale.Scale = scale
    end

    local viewportConnection = nil
    local function bindCurrentCamera()
        if viewportConnection then
            viewportConnection:Disconnect()
            viewportConnection = nil
        end

        local camera = Workspace.CurrentCamera
        if camera then
            viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
        end

        updateResponsiveScale()
    end

    bindCurrentCamera()
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera)

    if not slotTemplate:FindFirstChild("UIScale") then Instance.new("UIScale", slotTemplate) end

    local function toggleEquip(targetSlot)
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") then table.insert(activeSlots, child) end
        end
        local targetId = targetSlot and targetSlot.Name or nil

        if currentEquippedId == targetId then
            currentEquippedId = nil;
            ReplicatedStorage:WaitForChild("HoldItemRE"):FireServer(nil)
        else
            currentEquippedId = targetId;
            ReplicatedStorage:WaitForChild("HoldItemRE"):FireServer(targetId)
        end

        for _, slot in pairs(activeSlots) do
            local isSelected = (slot.Name == currentEquippedId)
            local scaleObj = slot:FindFirstChild("UIScale")
            if scaleObj then TweenService:Create(scaleObj, tweenInfo, {Scale = isSelected and 1.15 or 1.0}):Play() end
        end
    end

    local function RefreshHotbar(newData)
        if not newData or not newData.Inventory then return end
        hideCloseButtons()

        local currentItems, hotbarList = {}, newData.Hotbar or {}
        local seedQuantityMap, plantQuantityMap, chestQuantityMap, itemQuantityMap = {}, {}, {}, {}

        if newData.Inventory.Seeds then
            for _, s in ipairs(newData.Inventory.Seeds) do seedQuantityMap[s.ID] = s.Quantity end
        end

        if newData.Inventory.Plants then
            for _, p in ipairs(newData.Inventory.Plants) do
                local mut = p.Mutation or 1
                plantQuantityMap[p.ID .. "_" .. mut] = p.Quantity
            end
        end

        if newData.Inventory.Chests then
            for _, c in ipairs(newData.Inventory.Chests) do
                chestQuantityMap[c.ID] = c.Quantity
            end
        end

        if newData.Inventory.Items then
            for _, itemData in ipairs(newData.Inventory.Items) do
                itemQuantityMap[itemData.ID] = itemData.Quantity
            end
        end

        local displayIndex = 1
        for index, compositeId in ipairs(hotbarList) do
            if compositeId == "System_Backpack" then continue end

            local parts = string.split(compositeId, "_")
            local itemType, realId = parts[1], parts[2]
            local mutLvl = tonumber(parts[3]) or 1

            local qty, itemDetail = 0, nil

            if itemType == "Seed" then
                qty = seedQuantityMap[realId] or 0;
                itemDetail = ItemConfig.Seeds and ItemConfig.Seeds[realId]
            elseif itemType == "Plant" then
                qty = plantQuantityMap[realId .. "_" .. mutLvl] or 0;
                itemDetail = ItemConfig.Plants and ItemConfig.Plants[realId]
            elseif itemType == "Chest" then
                qty = chestQuantityMap[realId] or 0
                itemDetail = ItemConfig.Chests and ItemConfig.Chests[realId]
            elseif itemType == "Item" then
                qty = itemQuantityMap[realId] or 0
                itemDetail = ItemConfig.Items and ItemConfig.Items[realId]
            elseif itemType == "Tool" then
                qty = "INF";
                itemDetail = BaseItemConfig.Tools and BaseItemConfig.Tools[realId]
            end

            if (type(qty) == "string" or qty > 0) and itemDetail then
                local targetLayoutOrder, keyHint
                if displayIndex == 1 then
                    targetLayoutOrder = 1;
                    keyHint = "1"
                else
                    targetLayoutOrder = displayIndex + 1
                    local hintNum = displayIndex + 1
                    keyHint = (hintNum == 10) and "0" or tostring(hintNum)
                end

                if displayIndex >= 10 then break end

                currentItems[compositeId] = true
                local targetSlot = hotbarFrame:FindFirstChild(compositeId)

                local lastClickTick = 0
                local function onSlotClicked()
                    if os.clock() - lastClickTick < 0.1 then return end;
                    lastClickTick = os.clock(); toggleEquip(targetSlot)
                end

                if not targetSlot then
                    targetSlot = slotTemplate:Clone();
                    targetSlot.Name = compositeId; targetSlot.Visible = true; targetSlot.Parent = hotbarFrame

                    local isHoveringSlot = false;
                    local isHoveringBtn = false
                    local touchPressToken = 0
                    local activeTouchInput = nil
                    local touchLongPressTriggered = false
                    local canTouchHoldRemove = (itemType == "Seed" or itemType == "Plant" or itemType == "Chest" or itemType == "Item")
                    local handleRemove = nil

                    if canTouchHoldRemove then
                        local cBtn = closeBtnTemplate:Clone()
                        cBtn.Name = "CloseBtn"
                        cBtn.AnchorPoint = Vector2.new(0.5, 1)
                        cBtn.Position = UDim2.new(0.5, 0, 0, 0)
                        cBtn.ZIndex = 0;
                        cBtn.Visible = false; cBtn.Parent = targetSlot
                        cBtn.Active = true

                        local function updateVisibility()
                            task.delay(0.05, function() if cBtn and cBtn.Parent then cBtn.Visible = (isHoveringSlot or isHoveringBtn) end end)
                        end

                        targetSlot.MouseEnter:Connect(function() isHoveringSlot = true; updateVisibility() end)
                        targetSlot.MouseLeave:Connect(function() isHoveringSlot = false; updateVisibility() end)
                        cBtn.MouseEnter:Connect(function() isHoveringBtn = true; updateVisibility() end)
                        cBtn.MouseLeave:Connect(function() isHoveringBtn = false; updateVisibility() end)

                        handleRemove = function()
                            hideCloseButtons()
                            ReplicatedStorage:WaitForChild("RemoveHotbarRE"):FireServer(compositeId)
                            if currentEquippedId == compositeId then toggleEquip(nil) end
                        end

                        local closePressInput = nil
                        cBtn.InputBegan:Connect(function(input)
                            if not isPrimaryPointerInput(input) then
                                return
                            end

                            closePressInput = input
                            isHoveringBtn = true
                            cBtn.Visible = true
                            if input.UserInputType == Enum.UserInputType.Touch then
                                touchPressToken += 1
                                activeTouchInput = nil
                                touchLongPressTriggered = false
                            end
                        end)

                        cBtn.InputEnded:Connect(function(input)
                            if input ~= closePressInput or not isPrimaryPointerInput(input) then
                                return
                            end

                            closePressInput = nil
                            isHoveringBtn = false
                            handleRemove()
                        end)
                    end

                    targetSlot.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.Touch then
                            if isHoveringBtn then return end
                            hideCloseButtons(targetSlot)

                            touchPressToken += 1
                            local myPressToken = touchPressToken
                            activeTouchInput = input
                            touchLongPressTriggered = false

                            task.delay(TOUCH_REMOVE_HOLD_DURATION, function()
                                if myPressToken ~= touchPressToken or activeTouchInput ~= input then
                                    return
                                end

                                if not targetSlot.Parent then
                                    return
                                end

                                if canTouchHoldRemove and handleRemove then
                                    touchLongPressTriggered = true
                                    activeTouchInput = nil
                                    handleRemove()
                                end
                            end)
                        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
                            if isHoveringBtn then return end;
                            onSlotClicked()
                        end
                    end)

                    targetSlot.InputEnded:Connect(function(input)
                        if input.UserInputType ~= Enum.UserInputType.Touch or input ~= activeTouchInput then
                            return
                        end

                        touchPressToken += 1
                        activeTouchInput = nil

                        if touchLongPressTriggered then
                            touchLongPressTriggered = false
                            return
                        end

                        onSlotClicked()
                    end)
                end

                targetSlot.LayoutOrder = targetLayoutOrder
                local bgImag = targetSlot:FindFirstChild("BGImag", true)
                local icomNode = targetSlot:FindFirstChild("Icom", true)
                local customIcon = targetSlot:FindFirstChild("CustomIcon", true)

                if itemType == "Tool" or itemType == "Item" then
                    if bgImag then bgImag.Visible = true; bgImag.ZIndex = 1 end
                    if icomNode then icomNode.Visible = false end
                    if not customIcon then
                        customIcon = Instance.new("ImageLabel")
                        customIcon.Name = "CustomIcon";
                        customIcon.Size = UDim2.new(1, -10, 1, -10)
                        customIcon.Position = UDim2.new(0.5, 0, 0.5, 0);
                        customIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                        customIcon.BackgroundTransparency = 1;
                        customIcon.ScaleType = Enum.ScaleType.Fit
                        customIcon.ZIndex = 2; customIcon.Active = false; customIcon.Parent = targetSlot
                    end
                    if itemDetail and itemDetail.IconId then
                        customIcon.Image = itemDetail.IconId
                    else
                        customIcon.Image = "rbxthumb://type=Asset&id=129146573433376&w=150&h=150"
                    end
                    customIcon.Visible = true
                else
                    if customIcon then customIcon.Visible = false end
                    if bgImag then bgImag.Visible = true; bgImag.ZIndex = 1 end
                    if icomNode then
                        icomNode.Visible = true
                        if icomNode:IsA("ViewportFrame") then
                            UIEffectUtil.RenderToViewport(icomNode, realId, itemType, mutLvl)
                        elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then
                            icomNode.Image = itemDetail.IconId or ""
                        end
                        if not icomNode:GetAttribute("ClickBound") then
                            icomNode:SetAttribute("ClickBound", true)
                            icomNode.InputBegan:Connect(function(input) end)
                        end
                    end
                end

                local nameLabel = targetSlot:FindFirstChild("ItemName", true)
                if nameLabel then
                    local mutPrefix = ""
                    if itemType == "Plant" and mutLvl > 1 then
                        mutPrefix = "[" .. (ItemConfig.MutationName and ItemConfig.MutationName[mutLvl] or "Variant") .. "] "
                    end
                    nameLabel.Text = mutPrefix .. (itemDetail.Name or "")
                    nameLabel.TextWrapped = true
                    nameLabel.TextScaled = true
                    nameLabel.ZIndex = 3
                    nameLabel.Visible = true
                end

                local indexLabel = targetSlot:FindFirstChild("Index")
                if indexLabel then indexLabel.Text = keyHint; indexLabel.ZIndex = 3; indexLabel.Visible = true end

                if targetSlot:FindFirstChild("Quantity") then
                    if itemType == "Tool" then targetSlot.Quantity.Visible = false
                    else targetSlot.Quantity.Text = (type(qty) == "number" and "x" or "") .. tostring(qty); targetSlot.Quantity.ZIndex = 3; targetSlot.Quantity.Visible = true end
                end

                -- 兼容种子和植物，只要本体可投掷，就显示角标签
                local isExplosive = false
                local plantRef = ItemConfig.Plants and ItemConfig.Plants[realId]
                if plantRef and plantRef.IsThrowable then
                    isExplosive = true
                end

                local expIcon = targetSlot:FindFirstChild("ExplosionIcon")
                if isExplosive then
                    if not expIcon then
                        expIcon = Instance.new("ImageLabel")
                        expIcon.Name = "ExplosionIcon"
                        expIcon.Size = UDim2.new(0, 24, 0, 24)
                        expIcon.Position = UDim2.new(0, 4, 0, 4) -- 统一左上角
                        expIcon.BackgroundTransparency = 1
                        expIcon.Image = "rbxassetid://5652766180"
                        expIcon.ZIndex = 100 -- 确保渲染在最顶层
                        expIcon.Parent = targetSlot
                    end
                    expIcon.Visible = true
                else
                    if expIcon then expIcon.Visible = false end
                end

                displayIndex += 1
            end
        end

        local backpackId = "System_Backpack"
        local backpackDetail = BaseItemConfig.System and BaseItemConfig.System.Backpack
        currentItems[backpackId] = true

        local backpackSlot = hotbarFrame:FindFirstChild(backpackId)
        local lastBpClickTick = 0
        local function onBackpackClicked()
            if os.clock() - lastBpClickTick < 0.1 then return end;
            lastBpClickTick = os.clock()
            local scaleObj = backpackSlot and backpackSlot:FindFirstChild("UIScale")
            if scaleObj then TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play(); task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end) end
            local invGui = basicGui:FindFirstChild("InventoryGui")
            if invGui then invGui.Enabled = not invGui.Enabled end
        end

        if not backpackSlot then
            backpackSlot = slotTemplate:Clone();
            backpackSlot.Name = backpackId; backpackSlot.Visible = true; backpackSlot.Parent = hotbarFrame
            backpackSlot.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onBackpackClicked() end end)
        end

        local bpBgImag = backpackSlot:FindFirstChild("BGImag", true)
        if bpBgImag then bpBgImag.Visible = true; bpBgImag.ZIndex = 1 end
        local bpIcom = backpackSlot:FindFirstChild("Icom", true)
        if bpIcom then bpIcom.Visible = false end
        local bpCustomIcon = backpackSlot:FindFirstChild("CustomIcon", true)
        if not bpCustomIcon then
            bpCustomIcon = Instance.new("ImageLabel")
            bpCustomIcon.Name = "CustomIcon";
            bpCustomIcon.Size = UDim2.new(1, -10, 1, -10)
            bpCustomIcon.Position = UDim2.new(0.5, 0, 0.5, 0);
            bpCustomIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            bpCustomIcon.BackgroundTransparency = 1;
            bpCustomIcon.ScaleType = Enum.ScaleType.Fit
            bpCustomIcon.ZIndex = 2; bpCustomIcon.Active = false;
            bpCustomIcon.Parent = backpackSlot
        end
        bpCustomIcon.Image = "rbxthumb://type=Asset&id=108540025723786&w=150&h=150"
        bpCustomIcon.Visible = true;
        backpackSlot.LayoutOrder = 2
        local bpIndexLabel = backpackSlot:FindFirstChild("Index")
        if bpIndexLabel then bpIndexLabel.Text = "2"; bpIndexLabel.ZIndex = 3; bpIndexLabel.Visible = true end
        if backpackSlot:FindFirstChild("Quantity") then backpackSlot.Quantity.Visible = false end
        local bpNameLabel = backpackSlot:FindFirstChild("ItemName", true)
        if bpNameLabel then
            bpNameLabel.Text = (backpackDetail and backpackDetail.Name) or "Backpack"
            bpNameLabel.TextWrapped = true
            bpNameLabel.TextScaled = true
            bpNameLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            bpNameLabel.ZIndex = 3
            bpNameLabel.Visible = true
        end

        for _, slot in pairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") and not currentItems[slot.Name] then
                if currentEquippedId == slot.Name then toggleEquip(nil) end
                slot:Destroy()
            end
         end

         for _, slot in pairs(hotbarFrame:GetChildren()) do
             if slot:IsA("Frame") then
                 local scaleObj = slot:FindFirstChild("UIScale")
                 if scaleObj then
                     scaleObj.Scale = (slot.Name == currentEquippedId) and 1.15 or 1.0
                 end
             end
         end
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local keyMap = {
            [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3",
            [Enum.KeyCode.Four] = "4", [Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6",
            [Enum.KeyCode.Seven] = "7", [Enum.KeyCode.Eight] = "8", [Enum.KeyCode.Nine] = "9",
            [Enum.KeyCode.Zero] = "0"
        }

        local pressedNum = keyMap[input.KeyCode]
        if not pressedNum then return end

        for _, slot in pairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") then
                local indexLabel = slot:FindFirstChild("Index")

                if indexLabel and indexLabel.Text == pressedNum and slot.Visible then
                    if slot.Name == "System_Backpack" then
                        local scaleObj = slot:FindFirstChild("UIScale")
                        if scaleObj then
                            TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play()
                            task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end)
                        end
                        local invGui = basicGui:FindFirstChild("InventoryGui")
                        if invGui then invGui.Enabled = not invGui.Enabled end
                    else
                        toggleEquip(slot)
                    end
                    break
                end
            end
        end
    end)

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshHotbar(getPlayerDataRF:InvokeServer())
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(RefreshHotbar)

    local forceSelectRE = ReplicatedStorage:WaitForChild("ForceSelectRE", 5)
    if forceSelectRE then
        forceSelectRE.OnClientEvent:Connect(function(compositeId)
            local targetSlot = hotbarFrame:FindFirstChild(compositeId)
            if targetSlot then
                if currentEquippedId ~= compositeId then
                    toggleEquip(targetSlot)
                end
            end
        end)
    end

    local function onEquipChanged()
        local char = player.Character
        if not char then return end

        local realEquipped = char:GetAttribute("EquippedSeed")
        currentEquippedId = realEquipped

        for _, slot in pairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") then
                local isSelected = (slot.Name == currentEquippedId)
                local scaleObj = slot:FindFirstChild("UIScale")
                if scaleObj then
                    TweenService:Create(scaleObj, tweenInfo, {Scale = isSelected and 1.15 or 1.0}):Play()
                end
            end
        end
    end

    local function bindCharacter(char)
        char:GetAttributeChangedSignal("EquippedSeed"):Connect(onEquipChanged)
        onEquipChanged()
    end

    if player.Character then bindCharacter(player.Character) end
    player.CharacterAdded:Connect(bindCharacter)

    print("Client: HotbarController fixed; fully supports icons for all explosive items.")
end

return HotbarController

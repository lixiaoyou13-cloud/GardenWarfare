-- src/client/UI/HotbarController.luau
local HotbarController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") 

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local BaseItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BaseItemConfig"))

-- [🌟 引入通用特效系统]
local function ApplyMutationEffects(model, mutationLevel)
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

local function RenderToViewport(viewport, modelName, itemType, mutationLevel)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    for _, c in pairs(viewport:GetChildren()) do if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end end
    viewport.Ambient = Color3.fromRGB(200, 200, 200);
    viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
    if itemType == "Seed" then targetModel = itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    elseif itemType == "Tool" or itemType == "System" then targetModel = itemModelsFolder:FindFirstChild(modelName) end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do 
            if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end 
        end
        if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
        
        if itemType == "Plant" then
            ApplyMutationEffects(displayModel, mutationLevel)
        end

        if displayModel.PrimaryPart then displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0)) end
        
        displayModel.Parent = viewport
        local camera = Instance.new("Camera")
        camera.FieldOfView = 40;
        viewport.CurrentCamera = camera; camera.Parent = viewport

        local cframe, size = displayModel:GetBoundingBox()
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end 
        local zDist = maxDim * 1.5 + 1
        camera.CFrame = CFrame.lookAt(Vector3.new(cframe.Position.X, cframe.Position.Y + size.Y/6, cframe.Position.Z + zDist), cframe.Position)
    end
end

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
            -- [🌟 核心修复]：移除了 `if targetId then` 判断！
            -- 哪怕 targetId 是 nil，也必须向服务器发送指令来卸下手里拿着的东西！
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
        local currentItems, hotbarList = {}, newData.Hotbar or {} 
        local seedQuantityMap, plantQuantityMap = {}, {}
        
        if newData.Inventory.Seeds then 
            for _, s in ipairs(newData.Inventory.Seeds) do seedQuantityMap[s.ID] = s.Quantity end 
        end
        
        if newData.Inventory.Plants then 
            for _, p in ipairs(newData.Inventory.Plants) do 
                local mut = p.Mutation or 1
                plantQuantityMap[p.ID .. "_" .. mut] = p.Quantity 
            end 
        end

        for index, compositeId in ipairs(hotbarList) do
            if index > 8 then break end 
            local targetLayoutOrder, keyHint = index, ""
            if index == 1 then targetLayoutOrder = 1; keyHint = "1" 
            else targetLayoutOrder = index + 1; keyHint = tostring(index + 1) end
            
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
            elseif itemType == "Tool" then 
                qty = "∞";
                itemDetail = BaseItemConfig.Tools and BaseItemConfig.Tools[realId] 
            end

            if (type(qty) == "string" or qty > 0) and itemDetail then
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

                    local isHoveringSlot = false
                    local isHoveringBtn = false

                    if itemType == "Seed" or itemType == "Plant" then
                        local cBtn = closeBtnTemplate:Clone()
                        cBtn.Name = "CloseBtn"
                    
                        -- [🌟 重点 2：强制锁定在 UI 的中上方]
                        cBtn.AnchorPoint = Vector2.new(0.5, 1) 
                        cBtn.Position = UDim2.new(0.5, 0, 0, 0) 
                        -- [🌟 层级修复]：将 100 调低到了 10
                        cBtn.ZIndex = 0
                        cBtn.Visible = false
                        cBtn.Parent = targetSlot
                        
                        local function updateVisibility()
                            task.delay(0.05, function()
                                if cBtn and cBtn.Parent then
                                    cBtn.Visible = (isHoveringSlot or isHoveringBtn)
                                end
                            end)
                        end

                        targetSlot.MouseEnter:Connect(function()
                            isHoveringSlot = true
                            updateVisibility()
                        end)
                        
                        targetSlot.MouseLeave:Connect(function()
                            isHoveringSlot = false
                            updateVisibility()
                        end)

                        cBtn.MouseEnter:Connect(function()
                            isHoveringBtn = true
                            updateVisibility()
                        end)
                        
                        cBtn.MouseLeave:Connect(function()
                            isHoveringBtn = false
                            updateVisibility()
                        end)

                        local function handleRemove()
                            ReplicatedStorage:WaitForChild("RemoveHotbarRE"):FireServer(compositeId)
                            -- [🌟 重点]：如果删除的是当前手里的物品，强制传 nil 卸下！
                            if currentEquippedId == compositeId then 
                                toggleEquip(nil) 
                            end
                        end

                        if cBtn:IsA("GuiButton") then
                            cBtn.Activated:Connect(handleRemove)
                        else
                            cBtn.InputBegan:Connect(function(input)
                                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                                    handleRemove()
                                end
                            end)
                        end
                    end
                    
                    targetSlot.InputBegan:Connect(function(input) 
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
                            if isHoveringBtn then return end
                            onSlotClicked() 
                        end 
                    end)
                end

                targetSlot.LayoutOrder = targetLayoutOrder
                
                local bgImag = targetSlot:FindFirstChild("BGImag", true)
                local icomNode = targetSlot:FindFirstChild("Icom", true)
                local customIcon = targetSlot:FindFirstChild("CustomIcon", true)

                if itemType == "Tool" then
                    if bgImag then bgImag.Visible = true; bgImag.ZIndex = 1 end
                    if icomNode then icomNode.Visible = false end
                    if not customIcon then
                        customIcon = Instance.new("ImageLabel")
                        customIcon.Name = "CustomIcon"; customIcon.Size = UDim2.new(1, -10, 1, -10)
                        customIcon.Position = UDim2.new(0.5, 0, 0.5, 0); customIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                        customIcon.BackgroundTransparency = 1; customIcon.ScaleType = Enum.ScaleType.Fit
                        customIcon.ZIndex = 2; customIcon.Active = false; customIcon.Parent = targetSlot
                    end
                    customIcon.Image = "rbxthumb://type=Asset&id=129146573433376&w=150&h=150"
                    customIcon.Visible = true
                else
                    if customIcon then customIcon.Visible = false end
                    if bgImag then bgImag.Visible = true; bgImag.ZIndex = 1 end
                    if icomNode then
                        icomNode.Visible = true
                        if icomNode:IsA("ViewportFrame") then 
                            RenderToViewport(icomNode, realId, itemType, mutLvl) 
                        elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then 
                            icomNode.Image = itemDetail.IconId or "" 
                        end
                        if not icomNode:GetAttribute("ClickBound") then
                            icomNode:SetAttribute("ClickBound", true)
                            icomNode.InputBegan:Connect(function(input) 
                                -- 穿透事件
                            end)
                        end
                    end
                end

                local nameLabel = targetSlot:FindFirstChild("ItemName", true)
                if nameLabel then 
                    local mutPrefix = ""
                    if itemType == "Plant" and mutLvl > 1 then
                        mutPrefix = "[" .. (ItemConfig.MutationName and ItemConfig.MutationName[mutLvl] or "变异") .. "] "
                    end
                    nameLabel.Text = mutPrefix .. (itemDetail.Name or "")
                    nameLabel.ZIndex = 3; nameLabel.Visible = true
                end
                
                local indexLabel = targetSlot:FindFirstChild("Index")
                if indexLabel then indexLabel.Text = keyHint; indexLabel.ZIndex = 3; indexLabel.Visible = true end
                
                if targetSlot:FindFirstChild("Quantity") then
                    if itemType == "Tool" then targetSlot.Quantity.Visible = false
                    else 
                        targetSlot.Quantity.Text = (type(qty) == "number" and "x" or "") .. tostring(qty)
                        targetSlot.Quantity.ZIndex = 3; targetSlot.Quantity.Visible = true 
                    end
                end
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
            if scaleObj then TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play();
            task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end) end
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
            bpCustomIcon.Name = "CustomIcon"; bpCustomIcon.Size = UDim2.new(1, -10, 1, -10)
            bpCustomIcon.Position = UDim2.new(0.5, 0, 0.5, 0); bpCustomIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            bpCustomIcon.BackgroundTransparency = 1; bpCustomIcon.ScaleType = Enum.ScaleType.Fit
            bpCustomIcon.ZIndex = 2; bpCustomIcon.Active = false; bpCustomIcon.Parent = backpackSlot
        end
        bpCustomIcon.Image = "rbxthumb://type=Asset&id=108540025723786&w=150&h=150"
        bpCustomIcon.Visible = true; backpackSlot.LayoutOrder = 2
        local bpIndexLabel = backpackSlot:FindFirstChild("Index")
        if bpIndexLabel then bpIndexLabel.Text = "2"; bpIndexLabel.ZIndex = 3; bpIndexLabel.Visible = true end
        if backpackSlot:FindFirstChild("Quantity") then backpackSlot.Quantity.Visible = false end
        local bpNameLabel = backpackSlot:FindFirstChild("ItemName", true)
        if bpNameLabel then 
            bpNameLabel.Text = (backpackDetail and backpackDetail.Name) or "背包"
            bpNameLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            bpNameLabel.ZIndex = 3; bpNameLabel.Visible = true 
        end
        
        for _, slot in pairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") and not currentItems[slot.Name] then
                if currentEquippedId == slot.Name then toggleEquip(nil) end
                slot:Destroy()
            end
        end
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end 
        if input.KeyCode == Enum.KeyCode.One then
            for _, child in pairs(hotbarFrame:GetChildren()) do if child:IsA("Frame") and string.split(child.Name, "_")[1] == "Tool" then toggleEquip(child); break end end
            return
        end
        if input.KeyCode == Enum.KeyCode.Two then
            local backpackSlot = hotbarFrame:FindFirstChild("System_Backpack")
            local scaleObj = backpackSlot and backpackSlot:FindFirstChild("UIScale")
            if scaleObj then TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play(); task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end) end
            local invGui = basicGui:FindFirstChild("InventoryGui")
            if invGui then invGui.Enabled = not invGui.Enabled end
            return
        end
        
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") then 
                local prefix = string.split(child.Name, "_")[1]; 
                if prefix == "Seed" or prefix == "Plant" then table.insert(activeSlots, child) end 
            end
        end
        table.sort(activeSlots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        local keyMap = { [Enum.KeyCode.Three] = 1, [Enum.KeyCode.Four] = 2, [Enum.KeyCode.Five] = 3, [Enum.KeyCode.Six] = 4, [Enum.KeyCode.Seven] = 5, [Enum.KeyCode.Eight] = 6, [Enum.KeyCode.Nine] = 7 }
        local idx = keyMap[input.KeyCode]
        if idx and idx <= #activeSlots then toggleEquip(activeSlots[idx]) end
    end)

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshHotbar(getPlayerDataRF:InvokeServer())
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(RefreshHotbar)
    print("客户端：HotbarController 加载完毕！删除按钮坐标已强制居中浮空！")
end

return HotbarController
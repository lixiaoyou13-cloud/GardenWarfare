-- src/client/UI/HotbarController.luau
local HotbarController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") 

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function HotbarController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local hotbarFrame = playProperty:WaitForChild("HotbarFrame")
    
    local slotTemplate = hotbarFrame:WaitForChild("Slot")
    slotTemplate.Visible = false 
    
    local currentEquippedId = nil
    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    if not slotTemplate:FindFirstChild("UIScale") then
        local scale = Instance.new("UIScale")
        scale.Parent = slotTemplate
    end

    local function toggleEquip(targetSlot)
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "Slot" then
                table.insert(activeSlots, child)
            end
        end

        local targetId = targetSlot and targetSlot.Name or nil

        if currentEquippedId == targetId then
            currentEquippedId = nil
            ReplicatedStorage:WaitForChild("HoldItemRE"):FireServer(nil)
        else
            currentEquippedId = targetId
            if targetId then 
                ReplicatedStorage:WaitForChild("HoldItemRE"):FireServer(targetId)
            end
        end
        
        for _, slot in pairs(activeSlots) do
            local isSelected = (slot.Name == currentEquippedId)
            local scaleObj = slot:FindFirstChild("UIScale")
            if scaleObj then
                local targetScale = isSelected and 1.15 or 1.0
                TweenService:Create(scaleObj, tweenInfo, {Scale = targetScale}):Play()
            end
        end
    end

    local function RefreshHotbar(newData)
        if not newData or not newData.Inventory then return end
        
        local currentItems = {}
        local hotbarList = newData.Hotbar or {} 
        
        local seedQuantityMap = {}
        if newData.Inventory.Seeds then
            for _, s in ipairs(newData.Inventory.Seeds) do seedQuantityMap[s.ID] = s.Quantity end
        end
        local plantQuantityMap = {}
        if newData.Inventory.Plants then
             for _, p in ipairs(newData.Inventory.Plants) do plantQuantityMap[p.ID] = p.Quantity end
        end

        for index, compositeId in ipairs(hotbarList) do
            if index > 8 then break end 
            
            local targetLayoutOrder = index
            if index >= 2 then
                targetLayoutOrder = index + 1
            end
            
            local parts = string.split(compositeId, "_")
            local itemType = parts[1]
            local realId = parts[2]

            local qty = 0
            local itemDetail = nil

            if itemType == "Seed" then
                qty = seedQuantityMap[realId] or 0
                itemDetail = ItemConfig.Seeds[realId]
            elseif itemType == "Plant" then
                qty = plantQuantityMap[realId] or 0
                itemDetail = ItemConfig.Plants[realId]
            elseif itemType == "Tool" then
                qty = "∞"
                itemDetail = {Name = "铲子"}
            end

            if (type(qty) == "string" or qty > 0) and itemDetail then
                currentItems[compositeId] = true
                local targetSlot = hotbarFrame:FindFirstChild(compositeId)
                
                if targetSlot then
                    targetSlot.Quantity.Text = (type(qty) == "number" and "x" or "") .. tostring(qty)
                    targetSlot.LayoutOrder = targetLayoutOrder 
                else
                    targetSlot = slotTemplate:Clone()
                    targetSlot.Name = compositeId
                    targetSlot.LayoutOrder = targetLayoutOrder
                    targetSlot.Visible = true
                    
                    targetSlot.ItemName.Text = itemDetail.Name 
                    targetSlot.Quantity.Text = (type(qty) == "number" and "x" or "") .. tostring(qty)
                    
                    local closeBtn = targetSlot:FindFirstChild("Close")
                    if itemType == "Tool" and closeBtn then
                        closeBtn:Destroy()
                        closeBtn = nil
                    end

                    if closeBtn then
                        closeBtn.Visible = false 
                        local isHoveringSlot = false
                        local isHoveringClose = false
                        local hideThread = nil 

                        local function updateCloseBtnVisibility()
                            if isHoveringSlot or isHoveringClose then
                                closeBtn.Visible = true
                                if hideThread then task.cancel(hideThread); hideThread = nil end
                            else
                                if not hideThread then
                                    hideThread = task.delay(0.5, function()
                                        if not isHoveringSlot and not isHoveringClose then closeBtn.Visible = false end
                                        hideThread = nil
                                    end)
                                end
                            end
                        end

                        targetSlot.MouseEnter:Connect(function() isHoveringSlot = true; updateCloseBtnVisibility() end)
                        targetSlot.MouseLeave:Connect(function() isHoveringSlot = false; updateCloseBtnVisibility() end)

                        if closeBtn:IsA("GuiButton") then
                            closeBtn.MouseEnter:Connect(function() isHoveringClose = true; updateCloseBtnVisibility() end)
                            closeBtn.MouseLeave:Connect(function() isHoveringClose = false; updateCloseBtnVisibility() end)
                            closeBtn.MouseButton1Click:Connect(function()
                                if currentEquippedId == targetSlot.Name then toggleEquip(nil) end
                                ReplicatedStorage:WaitForChild("RemoveHotbarRE"):FireServer(compositeId)
                            end)
                        end
                    end

                    targetSlot.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            toggleEquip(targetSlot)
                        end
                    end)

                    targetSlot.Parent = hotbarFrame
                end

                if itemType == "Tool" then
                    if targetSlot:FindFirstChild("Quantity") then targetSlot.Quantity.Visible = false end
                    if targetSlot:FindFirstChild("ID") then targetSlot.ID.Visible = false end
                else
                    if targetSlot:FindFirstChild("Quantity") then targetSlot.Quantity.Visible = true end
                    if targetSlot:FindFirstChild("ID") then targetSlot.ID.Visible = true end
                end

            end
        end
        
        local backpackId = "System_Backpack"
        currentItems[backpackId] = true 
        
        local backpackSlot = hotbarFrame:FindFirstChild(backpackId)
        if not backpackSlot then
            backpackSlot = slotTemplate:Clone()
            backpackSlot.Name = backpackId
            backpackSlot.Visible = true
            
            backpackSlot.ItemName.Text = "🎒 背包"
            backpackSlot.ItemName.TextColor3 = Color3.fromRGB(255, 215, 0) 
            
            local closeBtn = backpackSlot:FindFirstChild("Close")
            if closeBtn then closeBtn:Destroy() end
            
            backpackSlot.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    local scaleObj = backpackSlot:FindFirstChild("UIScale")
                    if scaleObj then
                        TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play()
                        task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end)
                    end
                    
                    local invMain = basicGui:FindFirstChild("InventoryGui") and basicGui.InventoryGui:FindFirstChild("MainFrame")
                    if invMain then
                        invMain.Visible = not invMain.Visible
                    end
                end
            end)
            backpackSlot.Parent = hotbarFrame
        end
        
        backpackSlot.LayoutOrder = 2
        
        if backpackSlot:FindFirstChild("Quantity") then backpackSlot.Quantity.Visible = false end
        if backpackSlot:FindFirstChild("ID") then backpackSlot.ID.Visible = false end
        
        for _, slot in pairs(hotbarFrame:GetChildren()) do
            if slot:IsA("Frame") and slot.Name ~= "Slot" and not currentItems[slot.Name] then
                if currentEquippedId == slot.Name then toggleEquip(nil) end
                slot:Destroy()
            end
        end
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end 

        if input.KeyCode == Enum.KeyCode.B then
            local invMain = basicGui:FindFirstChild("InventoryGui") and basicGui.InventoryGui:FindFirstChild("MainFrame")
            if invMain then
                invMain.Visible = not invMain.Visible
            end
            
            local backpackSlot = hotbarFrame:FindFirstChild("System_Backpack")
            local scaleObj = backpackSlot and backpackSlot:FindFirstChild("UIScale")
            if scaleObj then
                TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play()
                task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end)
            end
            return
        end
        
        if input.KeyCode == Enum.KeyCode.V then
            for _, child in pairs(hotbarFrame:GetChildren()) do
                if child:IsA("Frame") and string.split(child.Name, "_")[1] == "Tool" then
                    toggleEquip(child)
                    break
                end
            end
            return
        end
        
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "Slot" then
                local prefix = string.split(child.Name, "_")[1]
                if prefix == "Seed" or prefix == "Plant" then
                    table.insert(activeSlots, child)
                end
            end
        end
        
        table.sort(activeSlots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)

        local slotIndex = nil
        if input.KeyCode == Enum.KeyCode.One then slotIndex = 1 end
        if input.KeyCode == Enum.KeyCode.Two then slotIndex = 2 end
        if input.KeyCode == Enum.KeyCode.Three then slotIndex = 3 end
        if input.KeyCode == Enum.KeyCode.Four then slotIndex = 4 end
        if input.KeyCode == Enum.KeyCode.Five then slotIndex = 5 end
        
        if slotIndex and slotIndex <= #activeSlots then
            toggleEquip(activeSlots[slotIndex])
        end
    end)

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshHotbar(getPlayerDataRF:InvokeServer())

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    updateInventoryRE.OnClientEvent:Connect(function(latestData)
        RefreshHotbar(latestData)
    end)

    local forceSelectRE = ReplicatedStorage:WaitForChild("ForceSelectRE")
    forceSelectRE.OnClientEvent:Connect(function(seedId)
        local targetSlot = hotbarFrame:FindFirstChild(seedId)
        if targetSlot then
            if currentEquippedId ~= seedId then
                toggleEquip(targetSlot)
            end
        end
    end)

    print("客户端：自定义快捷栏加载完毕！内置动态手指支持！")
end

return HotbarController
-- src/client/UI/HotbarController.luau
local HotbarController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") 

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local BaseItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BaseItemConfig"))

function HotbarController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local hotbarFrame = playProperty:WaitForChild("HotbarFrame")
    
    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates", 5)
    if not uiTemplates then warn("❌ 找不到 ReplicatedStorage/UITemplates") return end
    
    local slotTemplate = uiTemplates:WaitForChild("ItemTemplate", 5)
    if not slotTemplate then warn("❌ 找不到 ItemTemplate") return end
    
    local currentEquippedId = nil
    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    if not slotTemplate:FindFirstChild("UIScale") then
        local scale = Instance.new("UIScale")
        scale.Parent = slotTemplate
    end

    local function toggleEquip(targetSlot)
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") then
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
            local keyHint = ""
            
            if index == 1 then
                targetLayoutOrder = 1
                keyHint = "1"
            else
                targetLayoutOrder = index + 1
                keyHint = tostring(index + 1)
            end
            
            local parts = string.split(compositeId, "_")
            local itemType = parts[1]
            local realId = parts[2]

            local qty = 0
            local itemDetail = nil

            if itemType == "Seed" then
                qty = seedQuantityMap[realId] or 0
                itemDetail = ItemConfig.Seeds and ItemConfig.Seeds[realId]
            elseif itemType == "Plant" then
                qty = plantQuantityMap[realId] or 0
                itemDetail = ItemConfig.Plants and ItemConfig.Plants[realId]
            elseif itemType == "Tool" then
                qty = "∞"
                itemDetail = BaseItemConfig.Tools and BaseItemConfig.Tools[realId]
            end

            if (type(qty) == "string" or qty > 0) and itemDetail then
                currentItems[compositeId] = true
                local targetSlot = hotbarFrame:FindFirstChild(compositeId)
                
                if not targetSlot then
                    targetSlot = slotTemplate:Clone()
                    targetSlot.Name = compositeId
                    targetSlot.Visible = true
                    targetSlot.Parent = hotbarFrame
                    
                    targetSlot.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            toggleEquip(targetSlot)
                        end
                    end)
                end

                targetSlot.LayoutOrder = targetLayoutOrder
                
                if targetSlot:FindFirstChild("ItemName") then 
                    targetSlot.ItemName.Text = itemDetail.Name or "" 
                end
                
                -- [🌟 修复点 1：使用 Icom 读取 IconId]
                if targetSlot:FindFirstChild("Icom") then
                    targetSlot.Icom.Image = itemDetail.IconId or ""
                end
                
                if targetSlot:FindFirstChild("Index") then 
                    targetSlot.Index.Text = keyHint
                    targetSlot.Index.Visible = true 
                end

                if targetSlot:FindFirstChild("Quantity") then
                    if itemType == "Tool" then
                        targetSlot.Quantity.Visible = false
                    else
                        targetSlot.Quantity.Text = (type(qty) == "number" and "x" or "") .. tostring(qty)
                        targetSlot.Quantity.Visible = true
                    end
                end
            end
        end
        
        local backpackId = "System_Backpack"
        local backpackDetail = BaseItemConfig.System and BaseItemConfig.System.Backpack
        currentItems[backpackId] = true 
        
        local backpackSlot = hotbarFrame:FindFirstChild(backpackId)
        if not backpackSlot then
            backpackSlot = slotTemplate:Clone()
            backpackSlot.Name = backpackId
            backpackSlot.Visible = true
            backpackSlot.Parent = hotbarFrame
            
            backpackSlot.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    local scaleObj = backpackSlot:FindFirstChild("UIScale")
                    if scaleObj then
                        TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play()
                        task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end)
                    end
                    
                    local invMain = basicGui:FindFirstChild("InventoryGui") and basicGui.InventoryGui:FindFirstChild("MainFrame")
                    if invMain then invMain.Visible = not invMain.Visible end
                end
            end)
        end
        
        backpackSlot.LayoutOrder = 2
        
        if backpackSlot:FindFirstChild("Index") then 
            backpackSlot.Index.Text = "2"
            backpackSlot.Index.Visible = true
        end
        if backpackSlot:FindFirstChild("Quantity") then 
            backpackSlot.Quantity.Visible = false
        end
        if backpackSlot:FindFirstChild("ItemName") then 
            backpackSlot.ItemName.Text = (backpackDetail and backpackDetail.Name) or "背包" 
            backpackSlot.ItemName.TextColor3 = Color3.fromRGB(255, 215, 0)
        end
        -- [🌟 使用 Icom]
        if backpackSlot:FindFirstChild("Icom") then
            backpackSlot.Icom.Image = (backpackDetail and backpackDetail.IconId) or ""
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
            for _, child in pairs(hotbarFrame:GetChildren()) do
                if child:IsA("Frame") and string.split(child.Name, "_")[1] == "Tool" then
                    toggleEquip(child)
                    break
                end
            end
            return
        end

        if input.KeyCode == Enum.KeyCode.Two then
            local backpackSlot = hotbarFrame:FindFirstChild("System_Backpack")
            local scaleObj = backpackSlot and backpackSlot:FindFirstChild("UIScale")
            if scaleObj then
                TweenService:Create(scaleObj, tweenInfo, {Scale = 0.9}):Play()
                task.delay(0.1, function() TweenService:Create(scaleObj, tweenInfo, {Scale = 1}):Play() end)
            end
            
            local invMain = basicGui:FindFirstChild("InventoryGui") and basicGui.InventoryGui:FindFirstChild("MainFrame")
            if invMain then invMain.Visible = not invMain.Visible end
            return
        end
        
        local activeSlots = {}
        for _, child in pairs(hotbarFrame:GetChildren()) do
            if child:IsA("Frame") then
                local prefix = string.split(child.Name, "_")[1]
                if prefix == "Seed" or prefix == "Plant" then
                    table.insert(activeSlots, child)
                end
            end
        end
        table.sort(activeSlots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)

        local keyMap = {
            [Enum.KeyCode.Three] = 1, [Enum.KeyCode.Four] = 2, [Enum.KeyCode.Five] = 3,
            [Enum.KeyCode.Six] = 4, [Enum.KeyCode.Seven] = 5, [Enum.KeyCode.Eight] = 6, [Enum.KeyCode.Nine] = 7
        }
        local idx = keyMap[input.KeyCode]
        if idx and idx <= #activeSlots then toggleEquip(activeSlots[idx]) end
    end)

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshHotbar(getPlayerDataRF:InvokeServer())

    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(latestData)
        RefreshHotbar(latestData)
    end)
end

return HotbarController
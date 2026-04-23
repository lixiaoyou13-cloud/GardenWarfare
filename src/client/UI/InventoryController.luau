-- src/client/UI/InventoryController.luau
local InventoryController = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil) -- [🌟 引入模块]

function InventoryController.Init()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

    local BasicGui = playerGui:WaitForChild("BasicGui")
    local inventoryGui = BasicGui:WaitForChild("InventoryGui")
    local mainFrame = inventoryGui:WaitForChild("MainFrame")
    local openButton = inventoryGui:FindFirstChild("OpenButton")
    local closeButton = mainFrame:WaitForChild("CloseButton")
    local tabButtons = mainFrame:WaitForChild("TabButtons")
    local pages = mainFrame:WaitForChild("Pages")

    local PlayProperty = BasicGui:FindFirstChild("PlayProperty")
    local CoinLabel = PlayProperty and PlayProperty:FindFirstChild("CoinLabel")
    
    local uiTemplatesFolder = ReplicatedStorage:WaitForChild("UITemplates")
    local itemTemplate = uiTemplatesFolder:WaitForChild("ItemTemplate")
    local seedPage = pages:WaitForChild("SeedPage")
    local plantPage = pages:WaitForChild("PlantPage")

    mainFrame.Visible = true; mainFrame.Active = true 
    local rootGui = mainFrame:FindFirstAncestorOfClass("ScreenGui")
    if rootGui then rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; rootGui.DisplayOrder = 100 end

    mainFrame.ZIndex = mainFrame.ZIndex + 10000
    for _, uiElement in pairs(mainFrame:GetDescendants()) do if uiElement:IsA("GuiObject") then uiElement.ZIndex = uiElement.ZIndex + 10000 end end

    local function RefreshInventory(newData)
        if not newData or not newData.Inventory then return end
        
        if CoinLabel and (CoinLabel:IsA("TextLabel") or CoinLabel:IsA("TextButton")) then 
            -- [🌟 极简修改：删除了 "💰 " 前缀，现在只会显示纯粹的数字 (例如 1.5K)]
            UIEffectUtil.RollNumber(CoinLabel, newData.Coins, "") 
        end
        
        local currentSeedItems, currentPlantItems = {}, {}

        if newData.Inventory.Seeds then
            for _, seedData in ipairs(newData.Inventory.Seeds) do
                currentSeedItems[seedData.ID] = true 
                local existingSlot = seedPage:FindFirstChild(seedData.ID)
                if existingSlot then existingSlot.Quantity.Text = "x" .. tostring(seedData.Quantity)
                else
                    local itemDetail = ItemConfig.Seeds[seedData.ID]
                    if itemDetail then
                        local newSlot = itemTemplate:Clone()
                        newSlot.Index.Visible = false; newSlot.Name = seedData.ID 
                        newSlot.ItemName.Text = itemDetail.Name; newSlot.Quantity.Text = "x" .. tostring(seedData.Quantity)
                        
                        local lastClickTick = 0
                        local function onSeedEquip() 
                            if os.clock() - lastClickTick < 0.1 then return end; lastClickTick = os.clock(); 
                            ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Seed_" .. seedData.ID) 
                        end
                        newSlot.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onSeedEquip() end end)

                        local icomNode = newSlot:FindFirstChild("Icom")
                        if icomNode then
                            if icomNode:IsA("ViewportFrame") then 
                                UIEffectUtil.RenderToViewport(icomNode, seedData.ID, "Seed") 
                            elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then icomNode.Image = itemDetail.IconId or "" end
                            
                            if icomNode:IsA("GuiButton") then icomNode.Activated:Connect(onSeedEquip)
                            else icomNode.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onSeedEquip() end end) end
                        end
                        newSlot.Parent = seedPage
                    end
                end
            end
        end

        if newData.Inventory.Plants then
            for _, plantData in ipairs(newData.Inventory.Plants) do
                local mutLevel = plantData.Mutation or 1
                local uniqueSlotId = plantData.ID .. "_" .. mutLevel
                currentPlantItems[uniqueSlotId] = true 
                
                local existingSlot = plantPage:FindFirstChild(uniqueSlotId)
                if existingSlot then existingSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
                else
                    local itemDetail = ItemConfig.Plants[plantData.ID]
                    if itemDetail then
                        local newSlot = itemTemplate:Clone()
                        newSlot.Index.Visible = false; newSlot.Name = uniqueSlotId 
                        
                        local mutName = ItemConfig.MutationName and ItemConfig.MutationName[mutLevel] or "未知"
                        if mutLevel > 1 then newSlot.ItemName.Text = "[" .. mutName .. "] " .. itemDetail.Name
                        else newSlot.ItemName.Text = itemDetail.Name end
                        newSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
    
                        local lastClickTick = 0
                        local function onPlantEquip() 
                            if os.clock() - lastClickTick < 0.1 then return end; lastClickTick = os.clock();
                            ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Plant_" .. plantData.ID .. "_" .. mutLevel) 
                        end
                        newSlot.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onPlantEquip() end end)

                        local icomNode = newSlot:FindFirstChild("Icom")
                        if icomNode then
                            if icomNode:IsA("ViewportFrame") then 
                                UIEffectUtil.RenderToViewport(icomNode, plantData.ID, "Plant", mutLevel) 
                            elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then icomNode.Image = itemDetail.IconId or "" end
                            
                            if icomNode:IsA("GuiButton") then icomNode.Activated:Connect(onPlantEquip)
                            else icomNode.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onPlantEquip() end end) end
                        end
                        newSlot.Parent = plantPage
                    end
                end
            end
        end
        
        for _, slot in pairs(seedPage:GetChildren()) do if slot:IsA("Frame") and not currentSeedItems[slot.Name] then slot:Destroy() end end
        for _, slot in pairs(plantPage:GetChildren()) do if slot:IsA("Frame") and not currentPlantItems[slot.Name] then slot:Destroy() end end
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshInventory(getPlayerDataRF:InvokeServer())
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(RefreshInventory)

    if openButton then openButton.MouseButton1Click:Connect(function() inventoryGui.Enabled = true end) end
    closeButton.MouseButton1Click:Connect(function() inventoryGui.Enabled = false end)

    local function switchTab(targetPageName)
        for _, page in pairs(pages:GetChildren()) do
            if page:IsA("Frame") or page:IsA("ScrollingFrame") then page.Visible = (page.Name == targetPageName) end
        end
        for _, btn in pairs(tabButtons:GetChildren()) do
            if btn:IsA("GuiObject") then
                local stroke = btn:FindFirstChildOfClass("UIStroke")
                if stroke then
                    local isSelected = (btn.Name == "SeedTabBtn" and targetPageName == "SeedPage") or (btn.Name == "PlantTabBtn" and targetPageName == "PlantPage")
                    stroke.Color = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                end
            end
        end
    end

    switchTab("SeedPage")
    tabButtons:WaitForChild("SeedTabBtn").MouseButton1Click:Connect(function() switchTab("SeedPage") end)
    tabButtons:WaitForChild("PlantTabBtn").MouseButton1Click:Connect(function() switchTab("PlantPage") end)

    print("客户端：InventoryController 精简版加载完毕！无金币标志已实装！")
end

return InventoryController
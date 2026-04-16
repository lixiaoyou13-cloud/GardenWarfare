-- src/client/UI/InventoryController.luau
local InventoryController = {}

local TweenService = game:GetService("TweenService") -- [🌟 新增动画服务]

function InventoryController.Init()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

    mainFrame.Active = true 
    local rootGui = mainFrame:FindFirstAncestorOfClass("ScreenGui")
    if rootGui then
        rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        rootGui.DisplayOrder = 100 
    end

    mainFrame.ZIndex = mainFrame.ZIndex + 10000
    for _, uiElement in pairs(mainFrame:GetDescendants()) do
        if uiElement:IsA("GuiObject") then
            uiElement.ZIndex = uiElement.ZIndex + 10000
        end
    end

    local function RefreshInventory(newData)
        if not newData or not newData.Inventory then return end

        if CoinLabel and (CoinLabel:IsA("TextLabel") or CoinLabel:IsA("TextButton")) then
            CoinLabel.Text = "💰 " .. tostring(newData.Coins)
        end
        
        local currentSeedItems = {}
        local currentPlantItems = {}

        -- 1. 刷新种子
        if newData.Inventory.Seeds then
            for _, seedData in ipairs(newData.Inventory.Seeds) do
                currentSeedItems[seedData.ID] = true 
                local existingSlot = seedPage:FindFirstChild(seedData.ID)
                if existingSlot then
                    existingSlot.Quantity.Text = "x" .. tostring(seedData.Quantity)
                else
                    local itemDetail = ItemConfig.Seeds[seedData.ID]
                    if itemDetail then
                        local newSlot = itemTemplate:Clone()
                        newSlot.Index.Visible = false
                        newSlot.Name = seedData.ID 
                        newSlot.ItemName.Text = itemDetail.Name 
                        newSlot.Quantity.Text = "x" .. tostring(seedData.Quantity)
                        newSlot.InputBegan:Connect(function(input)
                            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                                ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Seed_" .. seedData.ID)
                            end
                        end)
                        newSlot.Parent = seedPage
                    end
                end
            end
        end

        -- 2. 刷新植物
        if newData.Inventory.Plants then
            for _, plantData in ipairs(newData.Inventory.Plants) do
                currentPlantItems[plantData.ID] = true 
                local targetSlot = nil

                local existingSlot = plantPage:FindFirstChild(plantData.ID)
                if existingSlot then
                    existingSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
                    targetSlot = existingSlot
                else
                    local itemDetail = ItemConfig.Plants[plantData.ID]
                    if itemDetail then
                        local newSlot = itemTemplate:Clone()
                        newSlot.Index.Visible = false
                        newSlot.Name = plantData.ID 
                        newSlot.ItemName.Text = itemDetail.Name 
                        newSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
                        newSlot.InputBegan:Connect(function(input)
                            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                                ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Plant_" .. plantData.ID)
                            end
                        end)
                        newSlot.Parent = plantPage
                        targetSlot = newSlot
                    end
                end

            end
        end
        
        for _, slot in pairs(seedPage:GetChildren()) do
            if slot:IsA("Frame") and not currentSeedItems[slot.Name] then slot:Destroy() end
        end
        for _, slot in pairs(plantPage:GetChildren()) do
            if slot:IsA("Frame") and not currentPlantItems[slot.Name] then slot:Destroy() end
        end
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    local initialData = getPlayerDataRF:InvokeServer()
    RefreshInventory(initialData)

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    updateInventoryRE.OnClientEvent:Connect(function(latestData)
        RefreshInventory(latestData)
    end)

    if openButton then
        openButton.MouseButton1Click:Connect(function() mainFrame.Visible = true end)
    end
    closeButton.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

    local function switchTab(targetPageName)
        for _, page in pairs(pages:GetChildren()) do
            if page:IsA("Frame") or page:IsA("ScrollingFrame") then
                page.Visible = (page.Name == targetPageName)
            end
        end
    end

    tabButtons:WaitForChild("SeedTabBtn").MouseButton1Click:Connect(function() switchTab("SeedPage") end)
    tabButtons:WaitForChild("PlantTabBtn").MouseButton1Click:Connect(function() switchTab("PlantPage") end)

    print("背包 UI 模块加载成功！（内置引导手指支持版）")
end

return InventoryController
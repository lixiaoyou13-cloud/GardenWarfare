-- src/client/UI/InventoryController.luau
local InventoryController = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [🌟 终极特效控制系统：支持 Attachment 容器穿透]
local function ApplyMutationEffects(model, mutationLevel)
    mutationLevel = mutationLevel or 1
    local effectMap = { [2] = "Glow", [3] = "Lightning", [4] = "HolyLight" }
    
    for lvl, fxName in pairs(effectMap) do
        local shouldEnable = (mutationLevel == lvl)
        
        -- 遍历模型中所有元件
        for _, node in ipairs(model:GetDescendants()) do
            -- 如果找到了对应名字的元件（比如 Glow 附件）
            if node.Name == fxName then
                -- 2. [🌟 核心修复] 如果这个节点是附件(Attachment)或文件夹，遍历并开关它【里面】的所有特效！
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                        child.Enabled = shouldEnable
                    end
                end
                
            end
        end
    end
end
-- [🌟 核心修改]：传入变异等级，在 3D 预览盒中渲染特效
local function RenderToViewport(viewport, modelName, itemType, mutationLevel)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    for _, c in pairs(viewport:GetChildren()) do if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end end

    viewport.Ambient = Color3.fromRGB(200, 200, 200)
    viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
    if itemType == "Seed" then targetModel = itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then 
        targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do
            if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end
        end
        if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
        
        -- [🌟 激活背包内的 3D 特效预览！]
        ApplyMutationEffects(displayModel, mutationLevel)

        if displayModel.PrimaryPart then displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0)) end
        
        displayModel.Parent = viewport
        local camera = Instance.new("Camera")
        camera.FieldOfView = 40; viewport.CurrentCamera = camera; camera.Parent = viewport

        local cframe, size = displayModel:GetBoundingBox()
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end 
        local zDist = maxDim * 1.5 + 1
        camera.CFrame = CFrame.lookAt(Vector3.new(cframe.Position.X, cframe.Position.Y + size.Y/6, cframe.Position.Z + zDist), cframe.Position)
    end
end

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

    mainFrame.Visible = true
    mainFrame.Active = true 
    local rootGui = mainFrame:FindFirstAncestorOfClass("ScreenGui")
    if rootGui then rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; rootGui.DisplayOrder = 100 end

    mainFrame.ZIndex = mainFrame.ZIndex + 10000
    for _, uiElement in pairs(mainFrame:GetDescendants()) do if uiElement:IsA("GuiObject") then uiElement.ZIndex = uiElement.ZIndex + 10000 end end

    local function RefreshInventory(newData)
        if not newData or not newData.Inventory then return end
        if CoinLabel and (CoinLabel:IsA("TextLabel") or CoinLabel:IsA("TextButton")) then CoinLabel.Text = "💰 " .. tostring(newData.Coins) end
        
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
                            if icomNode:IsA("ViewportFrame") then RenderToViewport(icomNode, seedData.ID, "Seed")
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
                -- [🌟 核心修改]：将 植物ID_变异等级 作为唯一槽位名字，彻底物理隔开
                local uniqueSlotId = plantData.ID .. "_" .. mutLevel
                currentPlantItems[uniqueSlotId] = true 
                
                local existingSlot = plantPage:FindFirstChild(uniqueSlotId)
                if existingSlot then 
                    existingSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
                else
                    local itemDetail = ItemConfig.Plants[plantData.ID]
                    if itemDetail then
                        local newSlot = itemTemplate:Clone()
                        newSlot.Index.Visible = false
                        newSlot.Name = uniqueSlotId 
                        
                        -- [🌟 核心修改]：名称显示加上对应变异前缀
                        local mutName = ItemConfig.MutationName[mutLevel] or "未知"
                        if mutLevel > 1 then
                            newSlot.ItemName.Text = "[" .. mutName .. "] " .. itemDetail.Name
                        else
                            newSlot.ItemName.Text = itemDetail.Name
                        end
                        
                        newSlot.Quantity.Text = "x" .. tostring(plantData.Quantity)
                        
                        local lastClickTick = 0
                        local function onPlantEquip() 
                            if os.clock() - lastClickTick < 0.1 then return end; lastClickTick = os.clock(); 
                            -- 装备时直接带上具体的变异等级信息发送给服务器！
                            ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Plant_" .. plantData.ID .. "_" .. mutLevel) 
                        end

                        newSlot.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then onPlantEquip() end end)

                        local icomNode = newSlot:FindFirstChild("Icom")
                        if icomNode then
                            if icomNode:IsA("ViewportFrame") then 
                                RenderToViewport(icomNode, plantData.ID, "Plant", mutLevel)
                            elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then 
                                icomNode.Image = itemDetail.IconId or "" 
                            end
                            
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
            if page:IsA("Frame") or page:IsA("ScrollingFrame") then
                page.Visible = (page.Name == targetPageName)
            end
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

    print("背包 UI 3D 模块加载成功！变异拆分与预览特效已实装！")
end

return InventoryController
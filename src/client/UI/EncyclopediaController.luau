-- src/client/UI/EncyclopediaController.luau
local EncyclopediaController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local BaseItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BaseItemConfig"))

-- [🌟 万能 3D 模型渲染引擎]
local function RenderToViewport(viewport, modelName, itemType, isSilhouette)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    
    for _, c in pairs(viewport:GetChildren()) do
        if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end
    end

    viewport.Ambient = Color3.fromRGB(200, 200, 200)
    viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
    if itemType == "Seed" then
        targetModel = itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then
        targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    elseif itemType == "Tool" or itemType == "System" then
        targetModel = itemModelsFolder:FindFirstChild(modelName)
    end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do
            if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end
        end
        
        if isSilhouette then
           for _, p in pairs(displayModel:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Color = Color3.fromRGB(0, 0, 0)
                    -- 🌟 核心修复：改为 Neon 材质，消除所有反光和阴影，实现纯粹的死黑
                    p.Material = Enum.Material.Neon
                end
            end
        end

        if not displayModel.PrimaryPart then
            displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true)
        end
        if displayModel.PrimaryPart then
            displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(210), 0))
        end
        
        displayModel.Parent = viewport

        local camera = Instance.new("Camera")
        camera.FieldOfView = 40
        viewport.CurrentCamera = camera
        camera.Parent = viewport

        local cframe, size = displayModel:GetBoundingBox()
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end 
        local zDist = maxDim * 1.5 + 1

        local cameraPos = Vector3.new(cframe.Position.X, cframe.Position.Y + size.Y/6, cframe.Position.Z + zDist)
        camera.CFrame = CFrame.lookAt(cameraPos, cframe.Position)
        
        return displayModel
    end
    return nil
end

function EncyclopediaController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local openCodexBtn = playProperty:WaitForChild("Codex")
    
    local codexGui = basicGui:WaitForChild("Codex")
    -- 【🌟 核心路径修正】：现在直接找 MainFrame
    local mainFrame = codexGui:WaitForChild("MainFrame")

    local descriptionFrame = mainFrame:WaitForChild("DescriptionFrame")
    local descPlantImage = descriptionFrame:WaitForChild("Plant")
    local descBgImage = descriptionFrame:WaitForChild("BG")
    local descNameText = descriptionFrame:WaitForChild("NameText")
    local descQualityText = descriptionFrame:WaitForChild("QualityText")
    local descSourceText = descriptionFrame:WaitForChild("SourceText")
    local descHpText = descriptionFrame:WaitForChild("HPText")
    local descAtkText = descriptionFrame:WaitForChild("ATKText")
    local descDetails = descriptionFrame:WaitForChild("Details")
    
    descriptionFrame.ZIndex = 100
    for _, desc in pairs(descriptionFrame:GetDescendants()) do
        if desc:IsA("GuiObject") then desc.ZIndex = desc.ZIndex + 100 end
    end
    descriptionFrame.Visible = false

    local scrollingFrames = {}
    local categoryBtns = {}
    for i = 1, 4 do
        scrollingFrames[i] = mainFrame:WaitForChild("ScrollingFrame" .. i)
        categoryBtns[i] = mainFrame:WaitForChild("Category" .. i)
    end
    
    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates")
    local itemTemplate = uiTemplates:WaitForChild("ItemTemplate")

    local function LoadCodexItems(tabIndex)
        local currentScroll = scrollingFrames[tabIndex]
        if not currentScroll then return end

        for _, child in pairs(currentScroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        local mutationLabel = ItemConfig.MutationName and ItemConfig.MutationName[tabIndex] or "未知"
        local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 5)
        local playerData = getPlayerDataRF and getPlayerDataRF:InvokeServer() or {}
        local unlockedMutations = playerData.UnlockedMutations or {}

        for plantId, plantDetail in pairs(ItemConfig.Plants) do
            local slot = itemTemplate:Clone()
            slot.Name = plantId
            slot.Visible = true
            
            -- [🌟 新增：获取品质颜色并设置槽位中 BGImag 的描边]
            local qualityId = plantDetail.Quality or 1
            local qColor = (ItemConfig.QualityColor and ItemConfig.QualityColor[qualityId]) or Color3.fromRGB(255, 255, 255)
            local bgImag = slot:FindFirstChild("BGImag")
            if bgImag then
                local stroke = bgImag:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = qColor
                end
            end
            
            if slot:FindFirstChild("ItemName") then
                slot.ItemName.Text = plantDetail.Name or plantId
            end
            
            local isOwned = (unlockedMutations[plantId] and unlockedMutations[plantId][tabIndex]) and true or false
            
            local icomNode = slot:FindFirstChild("Icom")
            if icomNode then
                if icomNode:IsA("ViewportFrame") then
                    RenderToViewport(icomNode, plantId, "Plant", not isOwned)
                elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then
                    icomNode.Image = plantDetail.IconId or ""
                    icomNode.ImageColor3 = isOwned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                end
                
                icomNode.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        local qualityConfig = BaseItemConfig.Item and BaseItemConfig.Item[qualityId]
                        
                        -- [🌟 新增：点击后设置详情页 BG 的描边颜色]
                        if descBgImage then
                            local bgStroke = descBgImage:FindFirstChildOfClass("UIStroke")
                            if bgStroke then
                                bgStroke.Color = qColor
                            end
                        end
                        
                        if descPlantImage:IsA("ViewportFrame") then
                            RenderToViewport(descPlantImage, plantId, "Plant", not isOwned)
                        elseif descPlantImage:IsA("ImageLabel") then
                            descPlantImage.Image = plantDetail.IconId or ""
                            descPlantImage.ImageColor3 = isOwned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
                        end

                        if descBgImage:IsA("ImageLabel") then
                            descBgImage.Image = qualityConfig and qualityConfig.IconId or ""
                        end
                        
                        descNameText.Text = plantDetail.Name or plantId
                        descQualityText.Text = (qualityConfig and qualityConfig.Name or "未知")
                        descSourceText.Text = "来源：" .. (plantDetail.Source or "未知")
                        descHpText.Text = "生命值：" .. tostring(plantDetail.HP or 0)
                        descAtkText.Text = "攻击力：" .. (plantDetail.Attack and tostring(plantDetail.Attack) or "--")
                        descDetails.Text = plantDetail.Description or "暂无说明信息。"
                        
                        descriptionFrame.Visible = true
                    end
                end)
            end
            
            if slot:FindFirstChild("Quantity") then
                slot.Quantity.Text = mutationLabel
                slot.Quantity.Visible = true
                if tabIndex == 1 then slot.Quantity.TextColor3 = Color3.fromRGB(255, 255, 255)
                elseif tabIndex == 2 then slot.Quantity.TextColor3 = Color3.fromRGB(85, 170, 255)
                elseif tabIndex == 3 then slot.Quantity.TextColor3 = Color3.fromRGB(170, 85, 255)
                elseif tabIndex == 4 then slot.Quantity.TextColor3 = Color3.fromRGB(255, 170, 0)
                end
            end
            
            if slot:FindFirstChild("Index") then slot.Index.Visible = false end
            slot.Parent = currentScroll
        end
    end

    local function SwitchTab(tabIndex)
        descriptionFrame.Visible = false 
        for i = 1, 4 do
            scrollingFrames[i].Visible = (i == tabIndex)
            local btn = categoryBtns[i]
            local stroke = btn:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = (i == tabIndex) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0) end
        end
        LoadCodexItems(tabIndex)
    end

    for i = 1, 4 do categoryBtns[i].MouseButton1Click:Connect(function() SwitchTab(i) end) end

    local function handleOpenCodex()
        codexGui.Enabled = true
        -- 【🌟 核心路径修正】
        mainFrame.Visible = true
        SwitchTab(1) 
    end

    if openCodexBtn:IsA("GuiButton") then openCodexBtn.Activated:Connect(handleOpenCodex)
    else openCodexBtn.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then handleOpenCodex() end end) end
    
    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 5)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function()
            if codexGui.Enabled then for i = 1, 4 do if scrollingFrames[i].Visible then LoadCodexItems(i) break end end end
        end)
    end

    -- 【🌟 核心路径修正】：关闭按钮直接在 MainFrame 下
    local closeBtn = mainFrame:FindFirstChild("Close") or mainFrame:FindFirstChild("CloseBtn", true)
    if closeBtn then
        local function handleCloseCodex() codexGui.Enabled = false; descriptionFrame.Visible = false end
        if closeBtn:IsA("GuiButton") then closeBtn.Activated:Connect(handleCloseCodex)
        else closeBtn.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then handleCloseCodex() end end) end
    end 
    print("图典模块：已适配统一后的层级结构（不再寻找 Plant，改找 mainFrame）！")
end

return EncyclopediaController
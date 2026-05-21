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
    local currentCodexLoadTicket = 0
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

        -- 🌟 [修复 1]：每次调用生成一个新的专属令牌
        currentCodexLoadTicket = currentCodexLoadTicket + 1
        local myTicket = currentCodexLoadTicket

        -- (注意：这里不要过早清理UI，等数据回来了再清理，防闪烁)

        local mutationLabel = ItemConfig.MutationName and ItemConfig.MutationName[tabIndex] 
        local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 5)
        
        -- 👉 这里线程会挂起，等待服务器响应
        local playerData = getPlayerDataRF and getPlayerDataRF:InvokeServer() or {}
        local unlockedMutations = playerData.UnlockedMutations or {}

        -- 🌟 [修复 2]：数据返回后，检查当前令牌是否过期。
        -- 如果在等待网络请求期间，玩家又切了别的Tab或触发了新刷新，直接废弃这次的渲染！
        if myTicket ~= currentCodexLoadTicket then return end

        -- 🌟 [修复 3]：确认是最新请求后，再安全地清空旧 UI 节点
        for _, child in pairs(currentScroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        local sortedPlants = {}
        for plantId, plantDetail in pairs(ItemConfig.Plants) do
            -- 从 Seeds 配置中获取数字 ID 用于排序。如果找不到则默认给 9999 放到最后
            local numericId = (ItemConfig.Seeds[plantId] and ItemConfig.Seeds[plantId].Id) or 9999
            
            table.insert(sortedPlants, {
                plantId = plantId,
                plantDetail = plantDetail,
                quality = plantDetail.Quality or 1,
                numericId = numericId
            })
        end

        -- 排序逻辑：优先比较品质（从小到大），品质相同则比较 ID（从小到大）
        table.sort(sortedPlants, function(a, b)
            if a.quality == b.quality then
                return a.numericId < b.numericId
            end
            return a.quality < b.quality
        end)

        -- ==========================================
        -- [🌟 修改：使用排序后的数组遍历生成槽位]
        -- ==========================================
        for index, data in ipairs(sortedPlants) do
            local plantId = data.plantId
            local plantDetail = data.plantDetail

            local slot = itemTemplate:Clone()
            slot.Name = plantId
            slot.Visible = true
            
            -- 🌟 关键点：利用 LayoutOrder 决定在 UI 网格/列表中的实际显示顺序
            slot.LayoutOrder = index 
            
            -- [下方保持你原有的渲染逻辑不变]
            -- 获取品质颜色并设置槽位中 BGImag 的描边
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
                        descQualityText.Text = (qualityConfig and qualityConfig.Name or "Unknown")
                        descSourceText.Text = "Source: " .. (plantDetail.Source or "Shop / Seeds")
                        
                        -- 🌟 修复：获取当前变异等级的属性乘区 (tabIndex 对应 1:Normal, 2:Shiny, 3:Thunder, 4:Divine)
                        local mutationStat = ItemConfig.MutationStats[tabIndex] or {DamageMul = 1.0, HealthMul = 1.0}
                        
                        -- 🌟 修复：计算变异后的血量并取整
                        local finalHp = math.floor((plantDetail.HP or 0) * mutationStat.HealthMul)
                        descHpText.Text = "HP:" .. tostring(finalHp)
                        
                        local baseAttack = plantDetail.Attack
                        local intervalValue = plantDetail.AttackInterval
    
                        if baseAttack then
                            -- 🌟 修复：计算变异后的攻击力并取整
                            local finalAttack = math.floor(baseAttack * mutationStat.DamageMul)
                            
                            if intervalValue then
                                -- 如果两者都有，显示为攻击力/间隔（即 DPS 模式）
                                descAtkText.Text = "DPS: " .. tostring(finalAttack) .. "/" .. tostring(intervalValue)
                            else
                                -- 如果只有攻击力没有间隔（如土豆雷、辣椒等瞬发植物），仅显示攻击力
                                descAtkText.Text = "ATK: " .. tostring(finalAttack)
                            end
                        else
                            -- 如果完全没有攻击力配置（如坚果墙），显示默认占位符
                            descAtkText.Text = "ATK: --"
                        end
                        
                        descDetails.Text = plantDetail.Description or "No description available."
                        descDetails.TextWrapped = true -- [建议新增] 确保长篇描述可以正确换行
                        descDetails.TextXAlignment = Enum.TextXAlignment.Left -- [建议] 左对齐更美观
                        descDetails.TextYAlignment = Enum.TextYAlignment.Top  -- [建议] 顶部对齐
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
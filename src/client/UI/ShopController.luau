-- src/client/UI/ShopController.luau
local ShopController = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local function RenderToViewport(viewport, modelName, itemType)
    if not viewport or not viewport:IsA("ViewportFrame") then return end
    for _, c in pairs(viewport:GetChildren()) do if c:IsA("Model") or c:IsA("Camera") then c:Destroy() end end
    viewport.Ambient = Color3.fromRGB(200, 200, 200); viewport.LightColor = Color3.fromRGB(255, 255, 255)

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if not itemModelsFolder then return nil end

    local targetModel = nil
    if itemType == "Seed" then targetModel = itemModelsFolder:FindFirstChild("Seed")
    elseif itemType == "Plant" then targetModel = itemModelsFolder:FindFirstChild(modelName .. "_Plant") or itemModelsFolder:FindFirstChild(modelName)
    end

    if targetModel then
        local displayModel = targetModel:Clone()
        for _, desc in pairs(displayModel:GetDescendants()) do if desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end end
        if not displayModel.PrimaryPart then displayModel.PrimaryPart = displayModel:FindFirstChildWhichIsA("BasePart", true) end
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

function ShopController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local shopGui = basicGui:WaitForChild("ShopGui")
    local shopFrame = shopGui:WaitForChild("ShopFrame")
    local closeBtn = shopFrame:WaitForChild("CloseBtn")
    local itemList = shopFrame:WaitForChild("ItemList")

    local shopSlotTemplate = itemList:WaitForChild("ShopSlot")
    shopSlotTemplate.Visible = false 
    local headUp = shopFrame:WaitForChild("HeadUp")
    local timerLabel = headUp:WaitForChild("TimeText")

    shopFrame.Visible = true

    if itemList:IsA("ScrollingFrame") then
        itemList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        itemList.CanvasSize = UDim2.new(0, 0, 0, 0)
        itemList.ScrollBarThickness = 6
    end

    local layout = itemList:FindFirstChildWhichIsA("UIGridLayout") or itemList:FindFirstChildWhichIsA("UIListLayout")
    if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end

    local currentStockData = {}
    local targetRefreshTime = 0
    local localPlayerData = nil

    local function RenderShop()
        if not localPlayerData or not currentStockData then return end

        for _, child in pairs(itemList:GetChildren()) do
            if child:IsA("Frame") and child ~= shopSlotTemplate then child:Destroy() end
        end

        for i = 1, 10 do
            local slotData = currentStockData[i]
            local slot = shopSlotTemplate:Clone()
            slot.Name = string.format("%02d_Slot", i); slot.LayoutOrder = i
            
            if not slotData or not slotData.SeedId then
                slot.Visible = true
                if slot:FindFirstChild("ItemName") then slot.ItemName.Text = "待上架" end
                if slot:FindFirstChild("BuyBtn") then slot.BuyBtn.Visible = false end
                if slot:FindFirstChild("PriceText") then slot.PriceText.Visible = false end
                if slot:FindFirstChild("StockText") then slot.StockText.Visible = false end
                slot.Parent = itemList
                continue
            end

            local itemDetail = ItemConfig.Seeds[slotData.SeedId]
            if not itemDetail then continue end

            local reqLvl = itemDetail.UnlockLevel or 1
            local isUnlocked = localPlayerData.UnlockedLevel >= reqLvl
            local displayStock = isUnlocked and slotData.Stock or 0
            local hasStock = displayStock > 0

            for _, child in pairs(slot:GetChildren()) do if child:IsA("UIStroke") or child.Name == "QualityStrokeContainer" then child:Destroy() end end

            local quality = itemDetail.Quality or 1
            local lightColor = ItemConfig.QualityColor[quality] or ItemConfig.QualityColor[1]
            local h, s, v = lightColor:ToHSV()
            local darkColor = Color3.fromHSV(h, math.min(1, s * 1.6), v * 0.4)
            
            local blackStroke = Instance.new("UIStroke")
            blackStroke.Name = "BlackOuterStroke"; blackStroke.Thickness = 4; blackStroke.Color = Color3.fromRGB(0, 0, 0); blackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; blackStroke.Parent = slot

            local qualityContainer = Instance.new("Frame")
            qualityContainer.Name = "QualityStrokeContainer"; qualityContainer.Size = UDim2.new(1, -4, 1, -4); qualityContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
            qualityContainer.AnchorPoint = Vector2.new(0.5, 0.5); qualityContainer.BackgroundTransparency = 1; qualityContainer.ZIndex = 3; qualityContainer.Parent = slot
            
            local slotCorner = slot:FindFirstChildOfClass("UICorner")
            if slotCorner then local newCorner = slotCorner:Clone(); newCorner.Parent = qualityContainer end

            local qStroke = Instance.new("UIStroke")
            qStroke.Name = "InnerQualityStroke"; qStroke.Thickness = 2; qStroke.Color = Color3.new(1, 1, 1); qStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; qStroke.Parent = qualityContainer

            local qGradient = Instance.new("UIGradient")
            qGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, lightColor), ColorSequenceKeypoint.new(1, darkColor)}); qGradient.Rotation = 90; qGradient.Parent = qStroke

            if slot:FindFirstChild("ItemName") then slot.ItemName.Text = itemDetail.Name end
            if slot:FindFirstChild("StockText") then slot.StockText.Text = "x" .. displayStock end
            
            local icomNode = slot:FindFirstChild("Icom")
            if icomNode then 
                for _, child in pairs(icomNode:GetChildren()) do if child:IsA("UIStroke") then child:Destroy() end end

                local icomStroke = Instance.new("UIStroke")
                icomStroke.Name = "IcomQualityStroke"; icomStroke.Thickness = 2; icomStroke.Color = Color3.new(1, 1, 1); icomStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; icomStroke.Parent = icomNode

                local icomGradient = Instance.new("UIGradient")
                icomGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, lightColor), ColorSequenceKeypoint.new(1, darkColor)}); icomGradient.Rotation = 90; icomGradient.Parent = icomStroke

                -- [🌟 智能渲染：调用万能函数]
                if icomNode:IsA("ViewportFrame") then
                    RenderToViewport(icomNode, slotData.SeedId, "Seed")
                elseif icomNode:IsA("ImageLabel") or icomNode:IsA("ImageButton") then
                    icomNode.Image = itemDetail.IconId or ""
                end
            end
            
            local outPriceText = slot:FindFirstChild("PriceText")
            if outPriceText then outPriceText.Text = "$" .. itemDetail.BuyPrice end

            local buyBtn = slot:FindFirstChild("BuyBtn")
            if buyBtn then
                local inPriceText = buyBtn:FindFirstChild("PriceText")
                if not isUnlocked then
                    if inPriceText then inPriceText.Text = reqLvl .. "关解锁" end
                    if buyBtn:IsA("ImageButton") then buyBtn.ImageColor3 = Color3.fromRGB(150, 150, 150) end
                elseif not hasStock then
                    if inPriceText then inPriceText.Text = "售罄" end
                    if buyBtn:IsA("ImageButton") then buyBtn.ImageColor3 = Color3.fromRGB(200, 50, 50) end
                else
                    if inPriceText then inPriceText.Text = "$" .. itemDetail.BuyPrice end
                    if buyBtn:IsA("ImageButton") then buyBtn.ImageColor3 = Color3.fromRGB(255, 255, 255) end
                    
                    local isProcessing = false
                    buyBtn.Activated:Connect(function()
                        if isProcessing then return end
                        isProcessing = true
                        
                        local success, msg = ReplicatedStorage:WaitForChild("BuyItemRF"):InvokeServer(i, 1)
                        if success then StarterGui:SetCore("SendNotification", { Title = "成功", Text = "获得 " .. itemDetail.Name, Duration = 2 })
                        else StarterGui:SetCore("SendNotification", { Title = "失败", Text = msg, Duration = 2 }) end
                        
                        task.wait(0.3); isProcessing = false
                    end)
                end
            end
            
            slot.Visible = true; slot.Parent = itemList
        end
    end

    local getShopDataRF = ReplicatedStorage:WaitForChild("GetShopDataRF")
    local function UpdateData() currentStockData, targetRefreshTime = getShopDataRF:InvokeServer(); localPlayerData = ReplicatedStorage:WaitForChild("GetPlayerDataRF"):InvokeServer(); RenderShop() end
    UpdateData()

    RunService.RenderStepped:Connect(function()
        if shopGui.Enabled and targetRefreshTime > 0 then
            local timeLeft = math.max(0, targetRefreshTime - os.time())
            timerLabel.Text = string.format("%02d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
        end
    end)

    ReplicatedStorage:WaitForChild("UpdateShopRE").OnClientEvent:Connect(function(stock, rTime) currentStockData = stock; targetRefreshTime = rTime; RenderShop() end)
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(pData) localPlayerData = pData; RenderShop() end)

    local shopNPC = Workspace:WaitForChild("ShopNPC")
    local prompt = shopNPC:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then prompt.Triggered:Connect(function() shopGui.Enabled = true end) end
    closeBtn.MouseButton1Click:Connect(function() shopGui.Enabled = false end)
end

return ShopController
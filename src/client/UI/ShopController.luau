-- src/client/UI/ShopController.luau
local ShopController = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil) 

local function GetConfiguredProductId(itemDetail)
    if type(itemDetail.ProductId) == "number" and itemDetail.ProductId > 0 then
        return itemDetail.ProductId
    end
    if type(itemDetail.IAPProductId) == "number" and itemDetail.IAPProductId > 0 then
        return itemDetail.IAPProductId
    end
    return nil
end

function ShopController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    -- 商店界面
    local shopGui = basicGui:WaitForChild("ShopGui") 
    local shopFrame = shopGui:WaitForChild("ShopFrame")
    local closeBtn = shopFrame:WaitForChild("CloseBtn")
    local itemList = shopFrame:WaitForChild("ItemList")
    local timerLabel = shopFrame:WaitForChild("HeadUp"):WaitForChild("TimeText")

    -- 对话框及按钮
    local dialogPage = basicGui:WaitForChild("DialogPage")
    local shopDialog = dialogPage:WaitForChild("ShopDialog")
    local openShopBtn = shopDialog:WaitForChild("OpenShop")
    local closeDialogBtn = shopDialog:WaitForChild("Close")
    
    -- 获取 Sell, SellAll, Price 按钮
    local sellBtn = shopDialog:WaitForChild("Sell")
    local sellAllBtn = shopDialog:WaitForChild("SellAll")
    local priceBtn = shopDialog:WaitForChild("Price")

    -- 🌟 新增：追踪当前正在交互的戴夫模型和最大距离阈值
    local currentInteractingDave = nil
    local MAX_DISTANCE = 15 

    local shopSlotTemplate = itemList:WaitForChild("ShopSlot")
    shopSlotTemplate.Visible = false 

    local currentStockData = {}
    local targetRefreshTime = 0
    local localPlayerData = nil

    -- [渲染逻辑]
    local function RenderShop()
        if not localPlayerData or not currentStockData then return end
        for _, child in pairs(itemList:GetChildren()) do
            if child:IsA("Frame") and child ~= shopSlotTemplate then child:Destroy() end
        end

        for i = 1, #currentStockData do
            local slotData = currentStockData[i]
            local slot = shopSlotTemplate:Clone()
            slot.Name = string.format("%02d_Slot", i)
            slot.LayoutOrder = i
            
            if not slotData or not slotData.SeedId then
                slot.Visible = true
                slot.Parent = itemList; continue
            end

            local itemDetail = ItemConfig.Seeds[slotData.SeedId]
            if not itemDetail then continue end

            local reqLvl = itemDetail.UnlockLevel or 1
            local isUnlocked = localPlayerData.UnlockedLevel >= reqLvl
            local displayStock = isUnlocked and slotData.Stock or 0
            
            if slot:FindFirstChild("ItemName") then slot.ItemName.Text = itemDetail.Name end
            if slot:FindFirstChild("StockText") then slot.StockText.Text = "x" .. displayStock end
            
            local icomNode = slot:FindFirstChild("Icom")
            if icomNode and icomNode:IsA("ViewportFrame") then
                UIEffectUtil.RenderToViewport(icomNode, slotData.SeedId, "Seed")
            end
            
            local buyBtn = slot:FindFirstChild("BuyBtn")
            if buyBtn then
                local inPriceText = buyBtn:FindFirstChild("PriceText")
                if not isUnlocked then
                    if inPriceText then inPriceText.Text = "Unlock Lv".. reqLvl end
                    buyBtn.ImageColor3 = Color3.fromRGB(150, 150, 150)
                elseif displayStock <= 0 then
                    if inPriceText then inPriceText.Text = "Sold Out" end
                    buyBtn.ImageColor3 = Color3.fromRGB(200, 50, 50)
                else
                    if inPriceText then inPriceText.Text = UIEffectUtil.FormatNumber(itemDetail.BuyPrice or 0) end
                    buyBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
                    buyBtn.Activated:Connect(function()
                        local success, msg = ReplicatedStorage:WaitForChild("BuyItemRF"):InvokeServer(i, 1)
                        if success then 
                            UIEffectUtil.ShowTip("Obtained " .. itemDetail.Name)
                            
                            -- 👇 [🌟 新增：购买成功后自动装备]
                            -- 商店购买的都是 Seed 类型，拼接出真实的物品 ID
                            local compositeId = "Seed_" .. tostring(slotData.SeedId)
                            
                            -- 延迟 0.15 秒，确保服务端已经把物品塞进你的快捷栏并且 UI 更新完毕
                            task.delay(0.15, function()
                                -- 发送装备请求给服务端，模拟玩家点击了快捷栏
                                ReplicatedStorage:WaitForChild("HoldItemRE"):FireServer(compositeId)
                            end)
                            -- 👆 新增结束
                            
                        else 
                            UIEffectUtil.ShowTip(msg)
                        end
                    end)
                end
            end

            local iapBuyBtn = slot:FindFirstChild("IAPBuyBtn")
            if iapBuyBtn then
                local productId = GetConfiguredProductId(itemDetail)
                local hasProduct = productId ~= nil
                local iapPriceText = iapBuyBtn:FindFirstChild("PriceText")

                iapBuyBtn.Visible = hasProduct
                iapBuyBtn.Active = hasProduct
                iapBuyBtn.AutoButtonColor = hasProduct

                if iapPriceText then
                    iapPriceText.Text = UIEffectUtil.FormatNumber(itemDetail.IAPPrice or 0)
                end

                if hasProduct then
                    iapBuyBtn.Activated:Connect(function()
                        MarketplaceService:PromptProductPurchase(player, productId)
                    end)
                end
            end

            slot.Visible = true
            slot.Parent = itemList
        end
    end

    local getShopDataRF = ReplicatedStorage:WaitForChild("GetShopDataRF")
    local function UpdateData() 
        currentStockData, targetRefreshTime = getShopDataRF:InvokeServer()
        localPlayerData = ReplicatedStorage:WaitForChild("GetPlayerDataRF"):InvokeServer()
        RenderShop() 
    end
    UpdateData()

    RunService.RenderStepped:Connect(function()
        if shopGui.Enabled and targetRefreshTime > 0 then
            local timeLeft = math.max(0, targetRefreshTime - os.time())
            timerLabel.Text = string.format("%02d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
        end
    end)

    -- 🌟 新增：每帧检测距离，过远自动关闭页面
    RunService.Heartbeat:Connect(function()
        if (shopDialog.Visible or shopGui.Enabled) and currentInteractingDave then
            local char = player.Character
            if char then
                local playerPart = char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
                local davePart = currentInteractingDave.PrimaryPart or currentInteractingDave:FindFirstChild("HumanoidRootPart") or currentInteractingDave:FindFirstChild("Head")
                
                if playerPart and davePart then
                    local distance = (playerPart.Position - davePart.Position).Magnitude
                    if distance > MAX_DISTANCE then
                        -- 距离超过阈值，关闭页面并清理状态
                        shopDialog.Visible = false
                        shopGui.Enabled = false
                        currentInteractingDave = nil
                    end
                end
            end
        end
    end)

    ReplicatedStorage:WaitForChild("UpdateShopRE").OnClientEvent:Connect(function(stock, rTime) 
        currentStockData = stock; targetRefreshTime = rTime; RenderShop() 
    end)
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(pData) 
        localPlayerData = pData; RenderShop()
    end)

    -- 🌟 修改：主动关闭页面时，重置 currentInteractingDave
    closeBtn.MouseButton1Click:Connect(function() 
        shopGui.Enabled = false 
        currentInteractingDave = nil 
    end)

    openShopBtn.MouseButton1Click:Connect(function()
        shopDialog.Visible = false 
        shopGui.Enabled = true     
    end)

    -- 🌟 修改：主动关闭页面时，重置 currentInteractingDave
    closeDialogBtn.MouseButton1Click:Connect(function()
        shopDialog.Visible = false 
        currentInteractingDave = nil
    end)

    -- 价格计算核心函数
    local function GetEquippedPrice(compositeId)
        if not compositeId or compositeId == "" then return nil end
        
        local parts = string.split(compositeId, "_")
        local itemType = parts[1]
        local realId = parts[2]
        local mutLvl = tonumber(parts[3]) or 1

        if itemType ~= "Seed" and itemType ~= "Plant" then return nil end

        local seedDetail = ItemConfig.Seeds[realId]
        if not seedDetail then return nil end

        local baseBuyPrice = seedDetail.BuyPrice or 0

        if itemType == "Seed" then
            return math.floor(baseBuyPrice * 0.8)
        elseif itemType == "Plant" then
            local price = baseBuyPrice * 1.2
            if mutLvl == 2 then price = price * 2
            elseif mutLvl == 3 then price = price * 3
            elseif mutLvl == 4 then price = price * 4
            end
            return math.floor(price)
        end
        return nil
    end

    -- 戴夫头顶的文字 BillboardGui 生成器
    local priceTagGui = nil
    local function ShowTagAboveDave(daveModel, textStr)
        if not priceTagGui then
            priceTagGui = Instance.new("BillboardGui")
            priceTagGui.Name = "PriceTag"
            priceTagGui.Size = UDim2.new(0, 200, 0, 50)
            priceTagGui.StudsOffset = Vector3.new(0, 3, 0)
            priceTagGui.AlwaysOnTop = true

            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            textLabel.TextStrokeTransparency = 0
            textLabel.TextScaled = true
            textLabel.Font = Enum.Font.FredokaOne
            textLabel.Parent = priceTagGui
        end
        priceTagGui.TextLabel.Text = textStr
        priceTagGui.Parent = daveModel:FindFirstChild("Head") or daveModel.PrimaryPart
    end

    -- Sell 按钮逻辑
    sellBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        local equippedId = char and char:GetAttribute("EquippedSeed")

        if not equippedId or equippedId == "" or string.find(equippedId, "Tool") then
            UIEffectUtil.ShowTip("Please equip a plant or seed")
            return
        end

        local success, msg = ReplicatedStorage:WaitForChild("SellEquippedRF"):InvokeServer()
        if success then
            UIEffectUtil.ShowTip(msg)
            if priceTagGui then priceTagGui:Destroy(); priceTagGui = nil end
        else
            UIEffectUtil.ShowTip(msg)
        end
    end)

    -- SellAll 按钮逻辑
    sellAllBtn.MouseButton1Click:Connect(function()
        local success, msg = ReplicatedStorage:WaitForChild("SellAllHotbarRF"):InvokeServer()
        if success then
            UIEffectUtil.ShowTip(msg)
            if priceTagGui then priceTagGui:Destroy(); priceTagGui = nil end
        else
            UIEffectUtil.ShowTip(msg)
        end
    end)

    -- Price 按钮逻辑
    priceBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        local equippedId = char and char:GetAttribute("EquippedSeed")

        local myDave = nil
        local plots = Workspace:WaitForChild("Plots")
        for _, plot in ipairs(plots:GetChildren()) do
            if plot:GetAttribute("OwnerId") == player.UserId then
                myDave = plot:FindFirstChild("CrazyDave")
                break
            end
        end

        if not myDave then return end

        if not equippedId or equippedId == "" or string.find(equippedId, "Tool") then
            ShowTagAboveDave(myDave, "Not Equipped")
            return
        end

        local price = GetEquippedPrice(equippedId)
        if price then
            ShowTagAboveDave(myDave, "Price: $" .. UIEffectUtil.FormatNumber(price))
        end
    end)

    -- 🌟 修改：交互绑定戴夫时，记录当前的戴夫对象
    local function bindDave(daveModel)
        task.spawn(function()
            local prompt = nil
            for i = 1, 50 do
                prompt = daveModel:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then break end
                task.wait(0.2)
            end

            if prompt then
                prompt.ActionText = "Talk to Dave"
                prompt.Triggered:Connect(function() 
                    currentInteractingDave = daveModel -- 记录交互对象
                    shopDialog.Visible = true 
                    if priceTagGui then priceTagGui:Destroy(); priceTagGui = nil end 
                end)
            end
            
            local clicker = daveModel:FindFirstChildWhichIsA("ClickDetector", true)
            if clicker then
                clicker.MouseClick:Connect(function() 
                    currentInteractingDave = daveModel -- 记录交互对象
                    shopDialog.Visible = true 
                    if priceTagGui then priceTagGui:Destroy(); priceTagGui = nil end
                end)
            end
        end)
    end

    local function searchMyDave()
        local plots = Workspace:WaitForChild("Plots")
        for _, plot in ipairs(plots:GetChildren()) do
            if plot:GetAttribute("OwnerId") == player.UserId then
                local dave = plot:FindFirstChild("CrazyDave")
                if dave then bindDave(dave); return true end
            end
        end
        return false
    end

    if not searchMyDave() then
        Workspace:WaitForChild("Plots").DescendantAdded:Connect(function(desc)
            if desc.Name == "CrazyDave" and desc.Parent:GetAttribute("OwnerId") == player.UserId then
                bindDave(desc)
            end
        end)
    end
end

return ShopController
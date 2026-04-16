-- src/client/UI/ShopController.luau
local ShopController = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService") -- [🌟 新增动画服务]

-- 引入配置表
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

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

    shopFrame.Visible = false

    local layout = itemList:FindFirstChildWhichIsA("UIGridLayout") or itemList:FindFirstChildWhichIsA("UIListLayout")
    if layout then
        layout.SortOrder = Enum.SortOrder.LayoutOrder
    end

    local function LoadShopItems(playerData)
        if not playerData then return end

        -- 1. 清空旧货架
        for _, child in pairs(itemList:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "ShopSlot" then child:Destroy() end
        end

        -- 2. 挑出允许上架的商品，存入数组准备排序
        local availableItems = {}
        for seedId, itemDetail in pairs(ItemConfig.Seeds) do
            if itemDetail.BuyPrice and itemDetail.BuyPrice > 0 then
                local isUnlocked = false
                if seedId == "RandomSeed" then
                    isUnlocked = (playerData.UnlockedLevel > 1)
                else
                    isUnlocked = playerData.UnlockedSeeds and playerData.UnlockedSeeds[seedId]
                end

                if isUnlocked then
                    table.insert(availableItems, seedId)
                end
            end
        end

        -- 3. 排序
        table.sort(availableItems, function(a, b)
            local idA = ItemConfig.Seeds[a].Id or 0
            local idB = ItemConfig.Seeds[b].Id or 0
            return idA > idB 
        end)

        -- 4. 按排好的顺序铺货
        for index, seedId in ipairs(availableItems) do
            local itemDetail = ItemConfig.Seeds[seedId]
            
            local newSlot = shopSlotTemplate:Clone()
            newSlot.Name = seedId
            newSlot.Visible = true
            newSlot.LayoutOrder = index 
            
            newSlot.ItemName.Text = itemDetail.Name
            if seedId == "RandomSeed" then 
                newSlot.ItemName.TextColor3 = Color3.fromRGB(255, 170, 255) 
            end
            newSlot.PriceText.Text = "💰 " .. tostring(itemDetail.BuyPrice)
            
            local buyBtn = newSlot:WaitForChild("BuyBtn")
            local isProcessing = false
            
            if buyBtn:IsA("GuiButton") then
                buyBtn.MouseButton1Click:Connect(function()
                    if isProcessing then return end
                    isProcessing = true
                    
                    local success, msg = ReplicatedStorage:WaitForChild("BuyItemRF"):InvokeServer(seedId, 1)
                    if success then
                        StarterGui:SetCore("SendNotification", { Title = "购买成功", Text = "你已获得: " .. itemDetail.Name, Duration = 3 })
                        ReplicatedStorage:WaitForChild("EquipItemRE"):FireServer("Seed_" .. seedId)
                    else
                        StarterGui:SetCore("SendNotification", { Title = "交易失败", Text = msg or "金币不足！", Duration = 4 })
                    end
                    task.wait(0.5)
                    isProcessing = false
                end)
            end
            newSlot.Parent = itemList
        end
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    LoadShopItems(getPlayerDataRF:InvokeServer())

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    updateInventoryRE.OnClientEvent:Connect(function(latestData)
        LoadShopItems(latestData)
    end)

    local shopNPC = Workspace:WaitForChild("ShopNPC")
    local prompt = shopNPC:FindFirstChildWhichIsA("ProximityPrompt", true)

    if prompt then
        prompt.Triggered:Connect(function()
            shopFrame.Visible = true
        end)
    end

    closeBtn.MouseButton1Click:Connect(function()
        shopFrame.Visible = false
    end)

    print("客户端：ShopController 加载完毕！引导动画支持已启用。")
end

return ShopController

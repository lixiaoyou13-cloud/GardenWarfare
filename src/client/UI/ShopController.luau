-- src/client/UI/ShopController.luau
local ShopController = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil) 

function ShopController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    -- 🌟 核心：ShopGui 是 ScreenGui，需使用 .Enabled 属性
    local shopGui = basicGui:WaitForChild("ShopGui") 
    local shopFrame = shopGui:WaitForChild("ShopFrame")
    local closeBtn = shopFrame:WaitForChild("CloseBtn")
    local itemList = shopFrame:WaitForChild("ItemList")
    local timerLabel = shopFrame:WaitForChild("HeadUp"):WaitForChild("TimeText")

    local shopSlotTemplate = itemList:WaitForChild("ShopSlot")
    shopSlotTemplate.Visible = false 

    local currentStockData = {}
    local targetRefreshTime = 0
    local localPlayerData = nil

    -- [渲染逻辑保持不变]
    local function RenderShop()
        if not localPlayerData or not currentStockData then 
            return 
        end
        for _, child in pairs(itemList:GetChildren()) do
            if child:IsA("Frame") and child ~= shopSlotTemplate then child:Destroy() end
        end

        for i = 1 , 10 do
            local slotData = currentStockData[i]
            local slot = shopSlotTemplate:Clone()
            slot.Name = string.format("%02d_Slot", i); slot.LayoutOrder = i
            
            if not slotData or not slotData.SeedId then
                slot.Visible = true; slot.Parent = itemList; continue
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
                    if inPriceText then inPriceText.Text = reqLvl .. "关解锁" end
                    buyBtn.ImageColor3 = Color3.fromRGB(150, 150, 150)
                elseif displayStock <= 0 then
                    if inPriceText then inPriceText.Text = "售罄" end
                    buyBtn.ImageColor3 = Color3.fromRGB(200, 50, 50)
                else
                    if inPriceText then inPriceText.Text = "$" .. itemDetail.BuyPrice end
                    buyBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
                    buyBtn.Activated:Connect(function()
                        local success, msg = ReplicatedStorage:WaitForChild("BuyItemRF"):InvokeServer(i, 1)
                        if success then 
                            StarterGui:SetCore("SendNotification", { Title = "成功", Text = "获得 " .. itemDetail.Name, Duration = 2 })
                        else 
                            StarterGui:SetCore("SendNotification", { Title = "失败", Text = msg, Duration = 2 }) 
                        end
                    end)
                end
            end
            slot.Visible = true; slot.Parent = itemList
        end
    end

    -- 数据同步
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

    ReplicatedStorage:WaitForChild("UpdateShopRE").OnClientEvent:Connect(function(stock, rTime) 
        currentStockData = stock; targetRefreshTime = rTime; RenderShop() 
    end)
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(pData) 
        localPlayerData = pData; RenderShop() 
    end)

    closeBtn.MouseButton1Click:Connect(function() shopGui.Enabled = false end)

    -- [🌟 交互绑定：直接打开商店]
    local function bindDave(daveModel)
        task.spawn(function()
            local prompt = nil
            for i = 1, 50 do
                prompt = daveModel:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then break end
                task.wait(0.2)
            end

            if prompt then
                prompt.ActionText = "打开商店"
                prompt.Triggered:Connect(function() 
                    shopGui.Enabled = not shopGui.Enabled 
                end)
            end
            
            local clicker = daveModel:FindFirstChildWhichIsA("ClickDetector", true)
            if clicker then
                clicker.MouseClick:Connect(function() 
                    shopGui.Enabled = not shopGui.Enabled 
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
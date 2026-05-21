-- src/client/UI/NewbieGiftController.luau
local NewbieGiftController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local PRODUCT_ID = 3594585526
local TIME_LIMIT_SECONDS = 24 * 60 * 60 -- 24 小时

function NewbieGiftController.Init()
    local player = Players.LocalPlayer
    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    local startNewbieGiftRF = ReplicatedStorage:WaitForChild("StartNewbieGiftRF")
    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    
    task.spawn(function()
        local data = getPlayerDataRF:InvokeServer()
        
        -- 1. 等待玩家打完新手教程（TutorialStep >= 9）
        while (data.TutorialStep or 0) < 9 do
            task.wait(2)
            data = getPlayerDataRF:InvokeServer()
        end

        -- 2. 如果已经买过了，直接退出
        if data.NewbieGiftPurchased then return end

        -- 3. 如果倒计时没开始过，通知服务器记录开始时间
        local startTime = data.NewbieGiftStartTime
        if not startTime or startTime == 0 then
            local success, realStartTime = startNewbieGiftRF:InvokeServer()
            if success then startTime = realStartTime end
        end

        -- 4. 计算剩余时间并检查是否过期
        local function getTimeLeft()
            return TIME_LIMIT_SECONDS - (os.time() - startTime)
        end
        if getTimeLeft() <= 0 then return end -- 已经过期，不再出现

        -- 5. 克隆并配置 UI
        local playerGui = player:WaitForChild("PlayerGui")
        local basicGui = playerGui:WaitForChild("BasicGui")
        local playProperty = basicGui:WaitForChild("PlayProperty")
        local template = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("Newbie_TimeLimitGift")
        
        local giftUI = template:Clone()
        giftUI.Position = UDim2.new(0.938, 0, 0.482, 0)
        giftUI.Parent = playProperty
        
        local timeTextLabel = giftUI:FindFirstChild("TimeText", true)
        
        -- 6. 绑定点击事件，拉起支付
        local clickBtn = giftUI:IsA("GuiButton") and giftUI or giftUI:FindFirstChildWhichIsA("GuiButton", true)
        local clickConn
        if clickBtn then
            clickConn = clickBtn.MouseButton1Click:Connect(function()
                MarketplaceService:PromptProductPurchase(player, PRODUCT_ID)
            end)
        end

        -- 7. 监听数据变化 (检测是否已付款)
        local isPurchased = false
        local dataConn = updateInventoryRE.OnClientEvent:Connect(function(newData)
            if newData.NewbieGiftPurchased then
                isPurchased = true
            end
        end)

        -- 8. 倒计时核心循环
        local loopConn
        local lastTick = tick()
        loopConn = RunService.Heartbeat:Connect(function()
            -- 每1秒刷新一次UI，节省性能
            if tick() - lastTick >= 1 then
                lastTick = tick()
                
                local timeLeft = getTimeLeft()
                
                -- 如果已经购买，或者时间到了 -> 销毁 UI
                if isPurchased or timeLeft <= 0 then
                    giftUI:Destroy()
                    if loopConn then loopConn:Disconnect() end
                    if clickConn then clickConn:Disconnect() end
                    if dataConn then dataConn:Disconnect() end
                    return
                end

                -- 格式化时间并更新 Text
                if timeTextLabel then
                    local h = math.floor(timeLeft / 3600)
                    local m = math.floor((timeLeft % 3600) / 60)
                    local s = timeLeft % 60
                    timeTextLabel.Text = string.format("%02d:%02d:%02d", h, m, s)
                end
            end
        end)
    end)
end

return NewbieGiftController
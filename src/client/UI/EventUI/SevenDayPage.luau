-- src/client/UI/EventUI/SevenDayPage.luau
local SevenDayPage = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local PRODUCT_ID = 3582734340 -- 内购 ID

-- 封装埋点上报函数
local function ReportAnalytics(eventName, eventData)
    local analyticsRE = ReplicatedStorage:FindFirstChild("AnalyticsRE")
    if analyticsRE then
        analyticsRE:FireServer("Custom", eventName, eventData)
    end
end


-- 引入 Viewport 渲染工具
local UIEffectUtil = require(script.Parent.Parent.Parent.Utils.UIEffectUtil)

-- 定义颜色渐变
local GREEN_GRADIENT = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 127)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 0))
}
local GREY_GRADIENT = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 180)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100))
}
-- 👇 新增：已领取按钮的专属渐变（清爽蓝）
local CLAIMED_GRADIENT = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 100, 200))
}
local CLAIMED_STROKE = Color3.fromRGB(0, 50, 100) -- 按钮描边颜色
-- 特殊奖励天数配置
local SPECIAL_REWARDS = {
    [2] = "SnowPea",
    [5] = "SnowPea",
    [7] = "SnowPea"
}

-- 辅助函数：格式化倒计时
local function GetFormattedRemainingTime()
    local now = os.date("*t", os.time())
    local tomorrowMidnight = os.time({
        year = now.year, month = now.month, day = now.day + 1, 
        hour = 0, min = 0, sec = 0
    })
    local diff = tomorrowMidnight - os.time()
    
    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = diff % 60
    
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function RenderUI(sevenDayFrame, playerData)
    if not playerData then return end
    
    local timeText = sevenDayFrame:FindFirstChild("TimeText", true)
    local signInDays = playerData.SignInDays or 0
    local lastTime = playerData.LastSignInTime or 0
    
    local isClaimedToday = false
    if lastTime > 0 then
        local lastDate = os.date("*t", lastTime)
        local currDate = os.date("*t", os.time())
        isClaimedToday = (lastDate.year == currDate.year and lastDate.month == currDate.month and lastDate.day == currDate.day)
    end

    if timeText then timeText.Visible = isClaimedToday end
    -- ==========================================
    -- 👇 新增：控制内购按钮的显示与隐藏
    local claimAllBtn = sevenDayFrame:FindFirstChild("ClaimAllBattle", true)
    if claimAllBtn then
        
        
        --“7天奖励全部领完后，才隐藏内购按钮”
         claimAllBtn.Visible = (signInDays < 7)
        
    end
    -- ==========================================

    local BLACK_STROKE = Color3.new(0, 0, 0)
    local GREEN_STROKE = Color3.fromRGB(0, 100, 0)

    for i = 1, 7 do
        local dayNode = sevenDayFrame:FindFirstChild("Day_" .. i, true)
        if not dayNode then continue end
        
        -- ==========================================
        -- [🌟 修正：直接使用名为 ImageLabel 的 ViewportFrame 渲染 3D 植物]
        -- ==========================================
        if SPECIAL_REWARDS[i] then
            -- 找到你那个名字叫 ImageLabel，但其实是 ViewportFrame 的节点
            local viewport = dayNode:FindFirstChild("ImageLabel", true)
            
            if viewport and viewport:IsA("ViewportFrame") then
                -- 直接渲染 SnowPea 模型进去
                UIEffectUtil.RenderToViewport(viewport, SPECIAL_REWARDS[i], "Plant")

                -- 执行平滑旋转动画
                if not viewport:GetAttribute("IsRotating") then
                    viewport:SetAttribute("IsRotating", true)
                    task.spawn(function()
                        while viewport and viewport.Parent do
                            local dt = RunService.RenderStepped:Wait()
                            local model = viewport:FindFirstChildOfClass("Model")
                            if model then
                                -- 以每秒 60 度的速度旋转
                                model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(60 * dt), 0))
                            end
                        end
                    end)
                end
            end
        end

        local claimBtn = dayNode:FindFirstChild("ImageButton")
        if not claimBtn then continue end
        
        local btnText = claimBtn:FindFirstChild("TextLabel")
        local gradient = claimBtn:FindFirstChildOfClass("UIGradient")
        local btnStroke = claimBtn:FindFirstChildOfClass("UIStroke")

        local targetText, targetGradient, targetStrokeColor, isActive = "", nil, nil, false

        if i <= signInDays then
            -- 👇 修改：这里把 GREEN_GRADIENT 换成了新加的 CLAIMED_GRADIENT
            targetText = "Claimed"; targetGradient = CLAIMED_GRADIENT; targetStrokeColor = CLAIMED_STROKE; isActive = false
        elseif i == signInDays + 1 and not isClaimedToday then
            -- 保持原本的绿色
            targetText = "Claim"; targetGradient = GREEN_GRADIENT; targetStrokeColor = GREEN_STROKE; isActive = true
        else
            -- 保持原本的灰色
            targetText = "Locked"; targetGradient = GREY_GRADIENT; targetStrokeColor = BLACK_STROKE; isActive = false
        end

        if btnText then 
            btnText.Text = targetText; btnText.TextStrokeColor3 = targetStrokeColor; btnText.TextStrokeTransparency = 0 
            local textUIStroke = btnText:FindFirstChildOfClass("UIStroke")
            if textUIStroke then textUIStroke.Enabled = true; textUIStroke.Color = targetStrokeColor end
        end
        if gradient then gradient.Color = targetGradient end
        if btnStroke then btnStroke.Enabled = true; btnStroke.Color = targetStrokeColor; btnStroke.Thickness = 2 end

        claimBtn.Active = isActive; claimBtn.AutoButtonColor = isActive

        if isActive and not claimBtn:GetAttribute("IsBound") then
            claimBtn:SetAttribute("IsBound", true)
            claimBtn.MouseButton1Click:Connect(function()
                -- 埋点：玩家尝试领取第几天的奖励
                ReportAnalytics("SignIn_ClaimAttempt", {
                    DayIndex = i,
                    IsPremium = false
                })

                local claimSignInRF = ReplicatedStorage:WaitForChild("ClaimSignInRF")
                local success = claimSignInRF:InvokeServer()
                if success then
                    -- 埋点：领取成功
                    ReportAnalytics("SignIn_ClaimSuccess", {
                        DayIndex = i,
                        CurrentTotalDays = signInDays + 1
                    })
                end
                local rewardTips = {
                        [1] = "签到成功！获得了 200 金币",
                        [2] = "签到成功！获得了 2000 金币",
                        [3] = "签到成功！获得了 1个 寒冰射手种子",
                        [4] = "签到成功！获得了 10,000 阳光",
                        [5] = "签到成功！获得了 2个 寒冰射手种子",
                        [6] = "签到成功！获得了 100,000 阳光",
                        [7] = "签到成功！获得了 3个 寒冰射手种子"
                    }
                    
                    if rewardTips[i] then
                        UIEffectUtil.ShowTip(rewardTips[i])
                    else
                        UIEffectUtil.ShowTip("领取成功！")
                    end
                    -- ==========================================
            end)
        end
    end
end

function SevenDayPage.Init(sevenDayFrame)
    if not sevenDayFrame then return end
    
    local closeBtn = sevenDayFrame:FindFirstChild("CloseBtn", true)
    local timeText = sevenDayFrame:FindFirstChild("TimeText", true)
    local claimAllBtn = sevenDayFrame:FindFirstChild("ClaimAllBattle", true)
    
    sevenDayFrame.Visible = true
    if closeBtn then closeBtn.MouseButton1Click:Connect(function() sevenDayFrame.Visible = false end) end
    
    task.spawn(function()
        while true do
            if sevenDayFrame.Visible and timeText and timeText.Visible then
                timeText.Text = "Next reward will appear in " .. GetFormattedRemainingTime()
            end
            task.wait(1)
        end
    end)
    
    task.spawn(function()
        local data = ReplicatedStorage:WaitForChild("GetPlayerDataRF"):InvokeServer(Players.LocalPlayer)
        RenderUI(sevenDayFrame, data)
    end)

    if claimAllBtn then
       claimAllBtn.MouseButton1Click:Connect(function()
            -- 埋点：点击内购按钮（追踪付费意向）
            ReportAnalytics("SignIn_PurchaseClick", {
                ProductId = PRODUCT_ID,
                Price = 29 -- 这里填入你的实际定价
            })
            MarketplaceService:PromptProductPurchase(Players.LocalPlayer, PRODUCT_ID)
        end)
    end

        -- 监听内购结果回调
    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if productId == PRODUCT_ID then
            -- 埋点：内购最终状态（成功或取消）
            ReportAnalytics("SignIn_PurchaseResult", {
                ProductId = productId,
                Status = isPurchased and "Success" or "Cancelled/Failed"
            })
            
            if isPurchased then
                -- 埋点：成功一键解锁 7 天奖励
                ReportAnalytics("SignIn_BatchUnlockSuccess", {
                    UnlockType = "AllSevenDays"
                })
            end
        end
    end)
        
    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(newData)
        if sevenDayFrame.Visible then RenderUI(sevenDayFrame, newData) end
    end)
end

return SevenDayPage
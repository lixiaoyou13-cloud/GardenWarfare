-- src/client/UI/EventUI/SevenDayPage.luau
local SevenDayPage = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local PRODUCT_ID = 3582734340

local UIEffectUtil = require(script.Parent.Parent.Parent.Utils.UIEffectUtil)
local SignInRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SignInRewardConfig"))

local DAYS_PER_TIER = SignInRewardConfig.DaysPerTier or 7

local GREEN_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 127)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 0)),
})

local GREY_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 180)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),
})

local CLAIMED_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 100, 200)),
})

local CLAIMED_STROKE = Color3.fromRGB(0, 50, 100)
local BLACK_STROKE = Color3.new(0, 0, 0)
local GREEN_STROKE = Color3.fromRGB(0, 100, 0)

local function getFormattedRemainingTime()
    local now = os.date("*t", os.time())
    local tomorrowMidnight = os.time({
        year = now.year,
        month = now.month,
        day = now.day + 1,
        hour = 0,
        min = 0,
        sec = 0,
    })
    local diff = math.max(0, tomorrowMidnight - os.time())

    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = diff % 60

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function isTextNode(node)
    return node and (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
end

local function getClaimButton(dayNode)
    return dayNode:FindFirstChild("ImageButton") or dayNode:FindFirstChild("ClaimBattle", true)
end

local function isClaimButtonText(dayNode, node)
    local claimBtn = getClaimButton(dayNode)
    return claimBtn and node:IsDescendantOf(claimBtn)
end

local function setFirstText(root, names, text)
    for _, name in ipairs(names) do
        local node = root:FindFirstChild(name, true)
        if isTextNode(node) then
            node.Text = text
            return node
        end
    end
    return nil
end

local function getRewardAmountText(rewardCfg)
    local amount = tonumber(rewardCfg.Amount) or 1
    return "x" .. UIEffectUtil.FormatNumber(amount)
end

local function applyRewardText(dayNode, rewardCfg)
    if not rewardCfg then
        return
    end

    local amountText = getRewardAmountText(rewardCfg)
    for _, node in ipairs(dayNode:GetDescendants()) do
        if node.Name == "TextLabel" and isTextNode(node) and not isClaimButtonText(dayNode, node) then
            node.Text = amountText
            return
        end
    end
end

local function clearViewport(viewport)
    if not (viewport and viewport:IsA("ViewportFrame")) then
        return
    end

    for _, child in ipairs(viewport:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera") then
            child:Destroy()
        end
    end
end

local function getRewardViewport(dayNode)
    for _, node in ipairs(dayNode:GetDescendants()) do
        if node:IsA("ViewportFrame") and not isClaimButtonText(dayNode, node) then
            return node
        end
    end
    return nil
end

local function updateRewardVisual(dayNode, rewardCfg)
    applyRewardText(dayNode, rewardCfg)

    local viewport = getRewardViewport(dayNode)
    if not viewport then
        return
    end

    if rewardCfg and rewardCfg.RewardType == "Seed" and rewardCfg.ItemId then
        viewport.Visible = true
        UIEffectUtil.RenderToViewport(viewport, rewardCfg.ItemId, "Plant")

        if not viewport:GetAttribute("IsRotating") then
            viewport:SetAttribute("IsRotating", true)
            task.spawn(function()
                while viewport and viewport.Parent do
                    local dt = RunService.RenderStepped:Wait()
                    local model = viewport:FindFirstChildOfClass("Model")
                    if model then
                        model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(60 * dt), 0))
                    end
                end
            end)
        end
    else
        clearViewport(viewport)
        viewport.Visible = false
    end
end

local function updateStageText(sevenDayFrame, tier)
    setFirstText(sevenDayFrame, { "StageText", "PageText", "RoundText", "Title" }, "Sign-in Round " .. tostring(tier))
end

local function isClaimedToday(lastTime)
    if (tonumber(lastTime) or 0) <= 0 then
        return false
    end

    local lastDate = os.date("*t", lastTime)
    local currDate = os.date("*t", os.time())
    return lastDate.year == currDate.year and lastDate.month == currDate.month and lastDate.day == currDate.day
end

local function renderUI(sevenDayFrame, playerData)
    if not playerData then
        return
    end

    local signInTier = SignInRewardConfig.NormalizeTier(playerData.SignInTier or 1)
    local signInDays = math.clamp(math.floor(tonumber(playerData.SignInDays) or 0), 0, DAYS_PER_TIER)
    local claimedToday = isClaimedToday(playerData.LastSignInTime)
    local purchasedClaimAllToday = isClaimedToday(playerData.LastSignInPurchaseTime)

    updateStageText(sevenDayFrame, signInTier)

    local timeText = sevenDayFrame:FindFirstChild("TimeText", true)
    if timeText then
        timeText.Visible = claimedToday
    end

    local claimAllBtn = sevenDayFrame:FindFirstChild("ClaimAllBattle", true)
    if claimAllBtn then
        local canPurchaseClaimAll = signInDays < DAYS_PER_TIER and not purchasedClaimAllToday
        claimAllBtn.Visible = canPurchaseClaimAll
        claimAllBtn.Active = canPurchaseClaimAll
        claimAllBtn.AutoButtonColor = canPurchaseClaimAll
    end

    for i = 1, DAYS_PER_TIER do
        local dayNode = sevenDayFrame:FindFirstChild("Day_" .. i, true)
        if not dayNode then
            continue
        end

        local rewardCfg = SignInRewardConfig.GetReward(signInTier, i)
        updateRewardVisual(dayNode, rewardCfg)

        local claimBtn = dayNode:FindFirstChild("ImageButton")
        if not claimBtn then
            continue
        end

        local btnText = claimBtn:FindFirstChild("TextLabel")
        local gradient = claimBtn:FindFirstChildOfClass("UIGradient")
        local btnStroke = claimBtn:FindFirstChildOfClass("UIStroke")

        local targetText = "Locked"
        local targetGradient = GREY_GRADIENT
        local targetStrokeColor = BLACK_STROKE
        local isActive = false

        if i <= signInDays then
            targetText = "Claimed"
            targetGradient = CLAIMED_GRADIENT
            targetStrokeColor = CLAIMED_STROKE
        elseif i == signInDays + 1 and not claimedToday then
            targetText = "Claim"
            targetGradient = GREEN_GRADIENT
            targetStrokeColor = GREEN_STROKE
            isActive = true
        end

        if btnText then
            btnText.Text = targetText
            btnText.TextStrokeColor3 = targetStrokeColor
            btnText.TextStrokeTransparency = 0

            local textUIStroke = btnText:FindFirstChildOfClass("UIStroke")
            if textUIStroke then
                textUIStroke.Enabled = true
                textUIStroke.Color = targetStrokeColor
            end
        end

        if gradient then
            gradient.Color = targetGradient
        end

        if btnStroke then
            btnStroke.Enabled = true
            btnStroke.Color = targetStrokeColor
            btnStroke.Thickness = 2
        end

        claimBtn.Active = isActive
        claimBtn.AutoButtonColor = isActive
        claimBtn:SetAttribute("SignInTier", signInTier)
        claimBtn:SetAttribute("SignInDay", i)

        if not claimBtn:GetAttribute("IsBound") then
            claimBtn:SetAttribute("IsBound", true)
            claimBtn.Activated:Connect(function()
                if not claimBtn.Active then
                    return
                end

                local attemptTier = SignInRewardConfig.NormalizeTier(claimBtn:GetAttribute("SignInTier") or 1)
                local attemptDay = math.floor(tonumber(claimBtn:GetAttribute("SignInDay")) or i)

                local claimSignInRF = ReplicatedStorage:WaitForChild("ClaimSignInRF")
                local success, claimedTier, claimedDay = claimSignInRF:InvokeServer()
                if success then
                    claimedTier = SignInRewardConfig.NormalizeTier(claimedTier or attemptTier)
                    claimedDay = math.floor(tonumber(claimedDay) or attemptDay)

                    local currentReward = SignInRewardConfig.GetReward(claimedTier, claimedDay)
                    UIEffectUtil.ShowTip((currentReward and currentReward.Tip) or "Claimed!")
                end
            end)
        end
    end
end

function SevenDayPage.Init(sevenDayFrame)
    if not sevenDayFrame then
        return
    end

    local closeBtn = sevenDayFrame:FindFirstChild("CloseBtn", true)
    local timeText = sevenDayFrame:FindFirstChild("TimeText", true)
    local claimAllBtn = sevenDayFrame:FindFirstChild("ClaimAllBattle", true)

    if closeBtn then
        closeBtn.Activated:Connect(function()
            sevenDayFrame.Visible = false
        end)
    end

    task.spawn(function()
        while true do
            if sevenDayFrame.Visible and timeText and timeText.Visible then
                timeText.Text = "Next reward will appear in " .. getFormattedRemainingTime()
            end
            task.wait(1)
        end
    end)

    task.spawn(function()
        local data = ReplicatedStorage:WaitForChild("GetPlayerDataRF"):InvokeServer(Players.LocalPlayer)
        renderUI(sevenDayFrame, data)
    end)

    if claimAllBtn then
        claimAllBtn.Activated:Connect(function()
            local preparePurchaseRF = ReplicatedStorage:WaitForChild("PrepareSignInClaimAllPurchaseRF", 10)
            if not preparePurchaseRF then
                UIEffectUtil.ShowTip("Purchase is not ready. Please try again later.")
                return
            end

            local ok, canPurchase, message = pcall(function()
                return preparePurchaseRF:InvokeServer()
            end)

            if not ok then
                UIEffectUtil.ShowTip("Purchase is not ready. Please try again later.")
                return
            end

            if not canPurchase then
                UIEffectUtil.ShowTip(tostring(message or "You can purchase all sign-in rewards once per day."))
                local data = ReplicatedStorage:WaitForChild("GetPlayerDataRF"):InvokeServer(Players.LocalPlayer)
                renderUI(sevenDayFrame, data)
                return
            end

            MarketplaceService:PromptProductPurchase(Players.LocalPlayer, PRODUCT_ID)
        end)
    end

    ReplicatedStorage:WaitForChild("UpdateInventoryRE").OnClientEvent:Connect(function(newData)
        if sevenDayFrame.Visible then
            renderUI(sevenDayFrame, newData)
        end
    end)
end

return SevenDayPage

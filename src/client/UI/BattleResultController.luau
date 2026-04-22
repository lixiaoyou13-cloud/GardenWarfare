-- src/client/UI/BattleResultController.luau
local BattleResultController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

function BattleResultController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BattleResultGui"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 999 
    screenGui.Parent = playerGui

    local bgOverlay = Instance.new("Frame")
    bgOverlay.Size = UDim2.new(1, 0, 1, 0)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bgOverlay.BackgroundTransparency = 0.5
    bgOverlay.Visible = false
    bgOverlay.Parent = screenGui

    local mainPanel = Instance.new("Frame")
    mainPanel.Size = UDim2.new(0, 350, 0, 420)
    mainPanel.Position = UDim2.new(0.5, -175, 0.5, -210)
    mainPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    mainPanel.BackgroundTransparency = 0.1
    Instance.new("UICorner", mainPanel).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", mainPanel)
    stroke.Color = Color3.fromRGB(0, 0, 0); stroke.Thickness = 3
    
    local uiScale = Instance.new("UIScale", mainPanel)
    uiScale.Scale = 0 
    
    mainPanel.Parent = bgOverlay

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 60)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Font = Enum.Font.FredokaOne
    titleLabel.TextSize = 40
    titleLabel.Parent = mainPanel

    local listLayout = Instance.new("UIListLayout", mainPanel)
    listLayout.Padding = UDim.new(0, 10); listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local function createBanner(order, height, strokeColor, title, value)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0.9, 0, 0, height)
        frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        frame.BackgroundTransparency = 0.3
        frame.LayoutOrder = order
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        local fStroke = Instance.new("UIStroke", frame)
        fStroke.Color = strokeColor; fStroke.Thickness = 2
        
        local tLabel = Instance.new("TextLabel", frame)
        tLabel.Size = UDim2.new(0.5, 10, 1, 0); tLabel.Position = UDim2.new(0, 15, 0, 0)
        tLabel.BackgroundTransparency = 1; tLabel.Text = title; tLabel.TextColor3 = strokeColor
        tLabel.Font = Enum.Font.SourceSansBold; tLabel.TextSize = 22; tLabel.TextXAlignment = Enum.TextXAlignment.Left
        
        local vLabel = Instance.new("TextLabel", frame)
        vLabel.Name = "ValueLabel"; vLabel.Size = UDim2.new(0.4, 0, 1, 0); vLabel.Position = UDim2.new(0.5, -15, 0, 0)
        vLabel.BackgroundTransparency = 1; vLabel.Text = value or ""; vLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        vLabel.Font = Enum.Font.FredokaOne; vLabel.TextSize = 30; vLabel.TextXAlignment = Enum.TextXAlignment.Right
        
        frame.Parent = mainPanel
        return frame
    end

    local recordBanner = createBanner(2, 40, Color3.fromRGB(85, 255, 127), "全新记录！", "")
    local levelBanner = createBanner(3, 40, Color3.fromRGB(200, 200, 200), "关卡信息", "")
    local killBanner = createBanner(4, 70, Color3.fromRGB(85, 170, 255), "⚔️ 已击败", "0")
    local rewardBanner = createBanner(5, 70, Color3.fromRGB(255, 215, 0), "💰 战利品", "0")

    local okBtn = Instance.new("TextButton", mainPanel)
    okBtn.Size = UDim2.new(0, 140, 0, 45); okBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    okBtn.TextColor3 = Color3.fromRGB(255, 255, 255); okBtn.Font = Enum.Font.FredokaOne; okBtn.TextSize = 24
    okBtn.LayoutOrder = 6; Instance.new("UICorner", okBtn).CornerRadius = UDim.new(0, 8)

    local lastBattleWasVictory = false
    local showResultRE = ReplicatedStorage:WaitForChild("ShowBattleResultRE")
    
    showResultRE.OnClientEvent:Connect(function(isVictory, levelId, isNewRecord, zombiesDefeated, coins, seeds)
        lastBattleWasVictory = isVictory
        
        -- [🌟 核心：自动战斗拦截并重开逻辑]
        if player:GetAttribute("AutoBattle") then
            task.delay(1.2, function()
                if not player:GetAttribute("AutoBattle") then return end
                
                local claimRE = ReplicatedStorage:FindFirstChild("ClaimBattleRewardsRE")
                if claimRE then claimRE:FireServer() end 

                local startRE = ReplicatedStorage:FindFirstChild("StartBattleRE")
                if startRE then
                    startRE:FireServer(isVictory and nil or 1) -- 胜利传空(下一关)，失败传1(第一关)
                end
            end)
            return 
        end
        
        if isVictory then
            titleLabel.Text = "突袭结束！"; titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            okBtn.Text = "下一关"; levelBanner:FindFirstChildOfClass("TextLabel").Text = "守住了第 " .. levelId .. " 关！"
        else
            titleLabel.Text = "防线崩溃！"; titleLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
            okBtn.Text = "好的"; levelBanner:FindFirstChildOfClass("TextLabel").Text = "止步于第 " .. levelId .. " 关"
        end

        recordBanner.Visible = isNewRecord
        killBanner.ValueLabel.Text = tostring(zombiesDefeated)
        rewardBanner.ValueLabel.Text = "💰" .. coins .. " 🎁" .. seeds
        
        bgOverlay.Visible = true
        TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    end)

    okBtn.MouseButton1Click:Connect(function()
        ReplicatedStorage.ClaimBattleRewardsRE:FireServer()
        local t = TweenService:Create(uiScale, TweenInfo.new(0.2), {Scale = 0})
        t:Play(); t.Completed:Wait()
        bgOverlay.Visible = false
        if lastBattleWasVictory then ReplicatedStorage.StartBattleRE:FireServer() end
    end)
end

return BattleResultController
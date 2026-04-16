-- src/client/UI/BattleResultController.luau
local BattleResultController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

function BattleResultController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- 1. 创建主屏幕 GUI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BattleResultGui"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 999 -- 盖在所有东西上面
    screenGui.Parent = playerGui

    -- 2. 暗色全屏遮罩
    local bgOverlay = Instance.new("Frame")
    bgOverlay.Size = UDim2.new(1, 0, 1, 0)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bgOverlay.BackgroundTransparency = 0.5
    bgOverlay.Visible = false
    bgOverlay.Parent = screenGui

    -- 3. 居中的结算面板
    local mainPanel = Instance.new("Frame")
    mainPanel.Size = UDim2.new(0, 350, 0, 420)
    mainPanel.Position = UDim2.new(0.5, -175, 0.5, -210)
    mainPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    mainPanel.BackgroundTransparency = 0.1
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = mainPanel
    local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(0, 0, 0); stroke.Thickness = 3; stroke.Parent = mainPanel
    
    -- ==========================================
    -- [🌟 核心修复：引入 UIScale 专门用于缩放动画]
    -- ==========================================
    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 0 
    uiScale.Parent = mainPanel
    
    mainPanel.Parent = bgOverlay

    -- 4. 大标题
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 60)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "突袭结束！"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Font = Enum.Font.FredokaOne
    titleLabel.TextSize = 40
    titleLabel.TextStrokeTransparency = 0
    titleLabel.Parent = mainPanel

    -- 5. 列表布局
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 10)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = mainPanel
    
    local spacer = Instance.new("Frame"); spacer.Size = UDim2.new(1, 0, 0, 60); spacer.BackgroundTransparency = 1; spacer.LayoutOrder = 1; spacer.Parent = mainPanel

    -- 通用条目生成函数
    local function createBanner(order, height, strokeColor, title, value)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0.9, 0, 0, height)
        frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        frame.BackgroundTransparency = 0.3
        frame.LayoutOrder = order
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        
        local fStroke = Instance.new("UIStroke")
        fStroke.Color = strokeColor
        fStroke.Thickness = 2
        fStroke.Parent = frame
        
        local tLabel = Instance.new("TextLabel")
        tLabel.Size = UDim2.new(0.5, 10, 1, 0)
        tLabel.Position = UDim2.new(0, 15, 0, 0)
        tLabel.BackgroundTransparency = 1
        tLabel.Text = title
        tLabel.TextColor3 = strokeColor
        tLabel.Font = Enum.Font.SourceSansBold
        tLabel.TextSize = 22
        tLabel.TextXAlignment = Enum.TextXAlignment.Left
        tLabel.Parent = frame
        
        local vLabel = Instance.new("TextLabel")
        vLabel.Name = "ValueLabel"
        vLabel.Size = UDim2.new(0.4, 0, 1, 0)
        vLabel.Position = UDim2.new(0.5, -15, 0, 0)
        vLabel.BackgroundTransparency = 1
        vLabel.Text = value or ""
        vLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        vLabel.Font = Enum.Font.FredokaOne
        vLabel.TextSize = 30
        vLabel.TextXAlignment = Enum.TextXAlignment.Right
        vLabel.Parent = frame
        
        frame.Parent = mainPanel
        return frame
    end

    -- 创建各个信息条
    local recordBanner = createBanner(2, 40, Color3.fromRGB(85, 255, 127), "全新高分记录！", "")
    recordBanner:FindFirstChild("ValueLabel"):Destroy()
    recordBanner:FindFirstChildOfClass("TextLabel").Size = UDim2.new(1, 0, 1, 0)
    recordBanner:FindFirstChildOfClass("TextLabel").TextXAlignment = Enum.TextXAlignment.Center

    local levelBanner = createBanner(3, 40, Color3.fromRGB(200, 200, 200), "您已达到第 X 波！", "")
    levelBanner:FindFirstChild("ValueLabel"):Destroy()
    levelBanner:FindFirstChildOfClass("TextLabel").Size = UDim2.new(1, 0, 1, 0)
    levelBanner:FindFirstChildOfClass("TextLabel").TextXAlignment = Enum.TextXAlignment.Center

    local killBanner = createBanner(4, 70, Color3.fromRGB(85, 170, 255), "⚔️ 已击败敌人", "0")
    local rewardBanner = createBanner(5, 70, Color3.fromRGB(255, 215, 0), "💰 战利品", "0")

    -- 6. 确认按钮
    local okBtn = Instance.new("TextButton")
    okBtn.Size = UDim2.new(0, 140, 0, 45)
    okBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    okBtn.Text = "好的"
    okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    okBtn.Font = Enum.Font.FredokaOne
    okBtn.TextSize = 24
    okBtn.LayoutOrder = 6
    Instance.new("UICorner", okBtn).CornerRadius = UDim.new(0, 8)
    local btnStroke = Instance.new("UIStroke", okBtn); btnStroke.Thickness = 2; btnStroke.Color = Color3.fromRGB(0, 100, 0)
    okBtn.Parent = mainPanel

    -- 记录状态
    local lastBattleWasVictory = false
    local showResultRE = ReplicatedStorage:WaitForChild("ShowBattleResultRE")
    
    showResultRE.OnClientEvent:Connect(function(isVictory, levelId, isNewRecord, zombiesDefeated, coins, seeds)
        lastBattleWasVictory = isVictory
        
        if isVictory then
            titleLabel.Text = "突袭结束！"
            titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            okBtn.Text = "下一关"
            levelBanner:FindFirstChildOfClass("TextLabel").Text = "您成功防守了第 " .. levelId .. " 关！"
        else
            titleLabel.Text = "防线崩溃！"
            titleLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
            okBtn.Text = "好的"
            levelBanner:FindFirstChildOfClass("TextLabel").Text = "您止步于第 " .. levelId .. " 关"
        end

        recordBanner.Visible = isNewRecord
        killBanner.ValueLabel.Text = tostring(zombiesDefeated)
        rewardBanner.ValueLabel.Text = "💰" .. coins .. " 🎁" .. seeds
        
        -- [🌟 修复：对 uiScale 进行动画播放，而不是直接改 Frame]
        bgOverlay.Visible = true
        local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        TweenService:Create(uiScale, tweenInfo, {Scale = 1}):Play()
    end)

    okBtn.MouseButton1Click:Connect(function()
        local claimRE = ReplicatedStorage:FindFirstChild("ClaimBattleRewardsRE")
        if claimRE then
            claimRE:FireServer()
        end

        -- [🌟 修复：对 uiScale 进行动画播放]
        local tween = TweenService:Create(uiScale, TweenInfo.new(0.2), {Scale = 0})
        tween:Play()
        tween.Completed:Wait()
        bgOverlay.Visible = false
        
        -- 关卡连战衔接
        if lastBattleWasVictory then
            local startRE = ReplicatedStorage:FindFirstChild("StartBattleRE")
            if startRE then
                startRE:FireServer()
            end
        end
    end)

    print("客户端：BattleResultController (结算面板) 加载完毕！动画修复成功！")
end

return BattleResultController
-- src/client/UI/EncyclopediaController.luau
local EncyclopediaController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function EncyclopediaController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EncyclopediaGui"
    screenGui.Parent = playerGui

    -- 在右侧创建一个打开图鉴的按钮
    local openBtn = Instance.new("TextButton")
    openBtn.Name = "OpenEncyclopediaBtn"
    openBtn.Size = UDim2.new(0, 60, 0, 60)
    openBtn.Position = UDim2.new(1, -80, 0, 160) 
    openBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
    openBtn.Text = "📖\n图鉴"
    openBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    openBtn.Font = Enum.Font.FredokaOne
    openBtn.TextSize = 16
    local corner1 = Instance.new("UICorner"); corner1.CornerRadius = UDim.new(0, 12); corner1.Parent = openBtn
    openBtn.Parent = screenGui

    -- 图鉴主面板
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 500, 0, 400)
    mainFrame.Position = UDim2.new(0.5, -250, 0.5, -200)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    mainFrame.Visible = false
    local corner2 = Instance.new("UICorner"); corner2.CornerRadius = UDim.new(0, 8); corner2.Parent = mainFrame
    mainFrame.Parent = screenGui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.Text = "📚 农场图鉴"
    title.TextColor3 = Color3.fromRGB(255, 215, 0)
    title.Font = Enum.Font.FredokaOne
    title.TextSize = 24
    title.Parent = mainFrame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 40, 0, 40)
    closeBtn.Position = UDim2.new(1, -45, 0, 5)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 85, 85)
    closeBtn.Font = Enum.Font.FredokaOne
    closeBtn.TextSize = 24
    closeBtn.Parent = mainFrame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -30, 1, -70)
    scroll.Position = UDim2.new(0, 15, 0, 55)
    scroll.BackgroundTransparency = 1
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = mainFrame

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, 105, 0, 120)
    grid.CellPadding = UDim2.new(0, 15, 0, 15)
    grid.Parent = scroll

    openBtn.MouseButton1Click:Connect(function() mainFrame.Visible = not mainFrame.Visible end)
    closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

    -- 动态刷新图鉴格子
    local function RefreshEncyclopedia(data)
        if not data or not data.UnlockedSeeds then return end
        
        for _, child in pairs(scroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        for _, key in ipairs(ItemConfig.IdToSeedKey) do
            local seedConfig = ItemConfig.Seeds[key]
            if seedConfig then
                local card = Instance.new("Frame")
                card.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                local cardCorner = Instance.new("UICorner"); cardCorner.CornerRadius = UDim.new(0, 8); cardCorner.Parent = card
                
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
                nameLabel.Position = UDim2.new(0, 0, 0.65, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.SourceSansBold
                nameLabel.TextScaled = true

                local icon = Instance.new("TextLabel")
                icon.Size = UDim2.new(1, 0, 0.65, 0)
                icon.BackgroundTransparency = 1
                icon.TextScaled = true
                
                -- 判断是否点亮图鉴
                if data.UnlockedSeeds[key] then
                    nameLabel.Text = seedConfig.Name
                    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    icon.Text = "🌱" 
                else
                    nameLabel.Text = "未知植物"
                    nameLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
                    icon.Text = "🔒"
                    card.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                end

                nameLabel.Parent = card
                icon.Parent = card
                card.Parent = scroll
            end
        end
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    RefreshEncyclopedia(getPlayerDataRF:InvokeServer())

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    updateInventoryRE.OnClientEvent:Connect(function(newData)
        RefreshEncyclopedia(newData)
    end)
    
    print("客户端：EncyclopediaController (图鉴系统) 加载完毕！")
end

return EncyclopediaController
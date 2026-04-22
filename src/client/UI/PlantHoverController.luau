-- src/client/UI/PlantHoverController.luau
local PlantHoverController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function PlantHoverController.Init()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local playerGui = player:WaitForChild("PlayerGui")

    -- ==========================================
    -- [🎨 精美血条 UI 面板]
    -- ==========================================
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlantHoverUI"
    billboard.Size = UDim2.new(0, 120, 0, 45)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0) 
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 40 
    billboard.Enabled = false
    
    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 1, 0)
    bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bgFrame.BackgroundTransparency = 0.5
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 6); bgCorner.Parent = bgFrame
    bgFrame.Parent = billboard

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.05, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.Parent = bgFrame

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(0.9, 0, 0.35, 0)
    barBg.Position = UDim2.new(0.05, 0, 0.55, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    barBg.BackgroundTransparency = 0.5
    local barCorner = Instance.new("UICorner"); barCorner.CornerRadius = UDim.new(0, 4);
    barCorner.Parent = barBg
    barBg.Parent = bgFrame

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(85, 255, 127) 
    local fillCorner = Instance.new("UICorner");
    fillCorner.CornerRadius = UDim.new(0, 4); fillCorner.Parent = barFill
    barFill.Parent = barBg

    local hpText = Instance.new("TextLabel")
    hpText.Size = UDim2.new(1, 0, 1, 0)
    hpText.BackgroundTransparency = 1
    hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpText.TextStrokeTransparency = 0.2
    hpText.TextScaled = true
    hpText.Font = Enum.Font.SourceSansBold
    hpText.ZIndex = 2
    hpText.Parent = barBg

    billboard.Parent = playerGui

    -- ==========================================
    -- [🌟 核心：状态管理器]
    -- ==========================================
    local currentTarget = nil
    local hpConnection = nil

    local function updateUI()
        if not currentTarget or not currentTarget.Parent then return end
        
        nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
        nameLabel.Position = UDim2.new(0, 0, 0.05, 0)
        barBg.Visible = true 
        
        local currentHP = currentTarget:GetAttribute("Health") or 0
        local maxHP = currentTarget:GetAttribute("MaxHealth") or 1
        local ratio = math.clamp(currentHP / maxHP, 0, 1)

        hpText.Text = math.floor(currentHP) .. " / " .. maxHP
        
        local targetColor = Color3.fromRGB(85, 255, 127)
        if ratio <= 0.3 then targetColor = Color3.fromRGB(255, 85, 85)
        elseif ratio <= 0.6 then targetColor = Color3.fromRGB(255, 170, 0) end

        TweenService:Create(barFill, TweenInfo.new(0.2), {
            Size = UDim2.new(ratio, 0, 1, 0),
            BackgroundColor3 = targetColor
        }):Play()

        local plantId = currentTarget.Name
        local plantConfig = ItemConfig.Plants[plantId]
        nameLabel.Text = plantConfig and plantConfig.Name or plantId
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    -- ==========================================
    -- [🌟 纯净版雷达：只扫描战斗植物血条]
    -- ==========================================
    RunService.RenderStepped:Connect(function()
        local targetPart = mouse.Target
        local foundPlant = nil

        if targetPart then
            local currentObj = targetPart
            while currentObj and currentObj ~= Workspace do
                -- 仅判断是否为战斗植物
                if currentObj:IsA("Model") and currentObj:GetAttribute("IsCombatPlant") then
                    foundPlant = currentObj
                    break
                end
                currentObj = currentObj.Parent
            end
        end

        if foundPlant then
            if currentTarget ~= foundPlant then
                currentTarget = foundPlant
                
                billboard.Adornee = foundPlant:IsA("Model") and (foundPlant.PrimaryPart or foundPlant:FindFirstChildWhichIsA("BasePart")) or foundPlant
                billboard.Enabled = true
                
                if hpConnection then hpConnection:Disconnect() end
                hpConnection = currentTarget:GetAttributeChangedSignal("Health"):Connect(updateUI)
                
                updateUI()
            end
        else
            if currentTarget then
                currentTarget = nil
                billboard.Enabled = false
                billboard.Adornee = nil
                if hpConnection then hpConnection:Disconnect(); hpConnection = nil end
            end
        end
    end)

    print("客户端：PlantHoverController 加载完毕！已剥离旧版铲除高亮逻辑！")
end

return PlantHoverController
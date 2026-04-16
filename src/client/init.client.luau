-- src/client/init.client.luau
print("客户端启动！开始加载各个模块...")

local InventoryController = require(script.UI.InventoryController)
local HotbarController = require(script.UI.HotbarController) 
local ShopController = require(script.UI.ShopController)
local CoinDropController = require(script.Services.CoinDropController)
local PlantUIController = require(script.Services.PlantUIController)
local HighlightController = require(script.Services.HighlightController)
local PlantHoverController = require(script.UI.PlantHoverController)
local ToolController = require(script.Services.ToolController)
local EncyclopediaController = require(script.UI.EncyclopediaController)
local BattleResultController = require(script.UI.BattleResultController)

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage") 

-- ==========================================
-- [🌟 核心：UI 按键接管系统（战斗控制 + 内部倍速）]
-- ==========================================
task.spawn(function()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- 等待基础 UI 加载
    local basicGui = playerGui:WaitForChild("BasicGui")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    
    -- 获取战斗相关的 UI 节点
    local startBattleBtn = playProperty:WaitForChild("StartBattle", 5)
    local inBattleFrame = playProperty:WaitForChild("InBattle", 5)
    local endBattleBtn = inBattleFrame and inBattleFrame:WaitForChild("EndBattle", 5)
    local levelText = inBattleFrame and inBattleFrame:WaitForChild("LevelText", 5)
    
   -- [🌟 获取 3 个全新的独立倍速按钮]
    local btnSpeed1 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*1", 5)
    local btnSpeed1_5 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*1.5", 5)
    local btnSpeed4 = inBattleFrame and inBattleFrame:WaitForChild("SpeedButton*4", 5)

    -- 确保所有按钮都找到了再执行
    if startBattleBtn and inBattleFrame and endBattleBtn and levelText and btnSpeed1 and btnSpeed1_5 and btnSpeed4 then
        -- 1. 初始 UI 状态切换
        startBattleBtn.Visible = true
        inBattleFrame.Visible = false

        -- 2. 战斗开始/结束逻辑
        startBattleBtn.MouseButton1Click:Connect(function()
            ReplicatedStorage:WaitForChild("StartBattleRE"):FireServer()
        end)

        endBattleBtn.MouseButton1Click:Connect(function()
            ReplicatedStorage:WaitForChild("EndBattleRE"):FireServer()
        end)

        -- ==========================================
        -- [🌟 3. 三键互斥倍速逻辑]
        -- ==========================================
        local setSpeedRE = ReplicatedStorage:WaitForChild("SetSpeedRE")

        -- 负责更新按钮高亮颜色的内部函数
        local function updateSpeedUI(activeSpeed)
            -- 先把所有按钮重置为灰色 (未选中状态)
            local defaultColor = Color3.fromRGB(200, 200, 200)
            btnSpeed1.BackgroundColor3 = defaultColor
            btnSpeed1_5.BackgroundColor3 = defaultColor
            btnSpeed4.BackgroundColor3 = defaultColor
            
            -- 给当前选中的按钮上高亮色 (橘黄色)
            local activeColor = Color3.fromRGB(255, 170, 0)
            if activeSpeed == 1.5 then
                btnSpeed1_5.BackgroundColor3 = activeColor
            elseif activeSpeed == 4 then
                btnSpeed4.BackgroundColor3 = Color3.fromRGB(255, 85, 85) -- 4倍速可以给个激进点的红色
            else
                btnSpeed1.BackgroundColor3 = activeColor
            end
        end

        -- 绑定三个按钮的点击事件
        btnSpeed1.MouseButton1Click:Connect(function() setSpeedRE:FireServer(1) end)
        btnSpeed1_5.MouseButton1Click:Connect(function() setSpeedRE:FireServer(1.5) end)
        btnSpeed4.MouseButton1Click:Connect(function() setSpeedRE:FireServer(4) end)

        -- 接收服务器确认，更新 UI 状态
        setSpeedRE.OnClientEvent:Connect(function(newSpeed)
            updateSpeedUI(newSpeed)
        end)

        -- 刚进游戏时，强制初始化为 1 倍速 UI
        updateSpeedUI(1)

        -- 4. 接收服务器的 UI 同步指令（切换界面可见性）
        local syncBattleUI_RE = ReplicatedStorage:WaitForChild("SyncBattleUI_RE", 5)
        if syncBattleUI_RE then
            syncBattleUI_RE.OnClientEvent:Connect(function(isActive, currentLevelId)
                if isActive then
                    startBattleBtn.Visible = false
                    inBattleFrame.Visible = true
                    levelText.Text = "第 " .. currentLevelId .. " 关"
                else
                    startBattleBtn.Visible = true
                    inBattleFrame.Visible = false
                end
            end)
        end
    end
end)

-- ==========================================
-- [🌟 消息通知系统]
-- ==========================================
local showNotifRE = ReplicatedStorage:WaitForChild("ShowNotificationRE")
showNotifRE.OnClientEvent:Connect(function(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = 3, 
    })
end)

-- ==========================================
-- [🌟 启动各个独立控制器]
-- ==========================================
InventoryController.Init()
HotbarController.Init()
ShopController.Init()
CoinDropController.Init()
PlantUIController.Init()
HighlightController.Init()
PlantHoverController.Init()
ToolController.Init()
EncyclopediaController.Init()
BattleResultController.Init()

print("客户端所有模块加载完毕！倍速按钮已成功移至战斗面板中。")
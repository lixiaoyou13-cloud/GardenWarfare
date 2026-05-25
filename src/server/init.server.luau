

-- src/server/init.server.luau
print("服务端启动！准备加载核心模块...")

-- ==========================================
-- [🌟 新增：全局碰撞组设定]
-- ==========================================
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

-- 1. 注册两个组：玩家组、僵尸组
pcall(function()
    PhysicsService:RegisterCollisionGroup("Players")
    PhysicsService:RegisterCollisionGroup("Zombies")
end)

-- 2. 设定规则：玩家穿透僵尸(false)，僵尸穿透僵尸(false)
PhysicsService:CollisionGroupSetCollidable("Players", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)

-- 3. 玩家一出生，就把他的身体扔进 "Players" 组里，并挂载头衔
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- ==========================================
        -- [🌟 新增：设置玩家初始移动速度]
        -- ==========================================
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.WalkSpeed = 30 -- 👈 将 24 修改为你想要的移动速度 (默认是16)
        
        -- 给身体所有的手脚、躯干打上玩家组标签
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CollisionGroup = "Players" end
        end
        -- 如果玩家中途穿了新装备，也立刻打上标签
        character.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then desc.CollisionGroup = "Players" end
        end)

        -- ==========================================
        -- [🌟 新增：玩家头顶最高通关层数头衔 (英文)]
        -- ==========================================
        task.spawn(function()
            local head = character:WaitForChild("Head", 5)
            if not head then return end
            
            -- 获取数据管理器 (动态 require 确保安全)
            local PDManager = require(script.PlayerDataManager)
            
            -- 等待玩家真实数据从 DataStore 中加载完毕
            local data = nil
            while not data do
                data = PDManager.GetPlayerData(player)
                if not data then task.wait(0.5) end
            end

            -- 计算通关层数：(当前解锁层数 - 1)，使用 math.max 兜底防止出现负数
            local maxCleared = math.max(0, (data.UnlockedLevel or 1) - 1)
            
            -- 清理旧头衔（防止角色重置时重复生成）
            local oldTitle = head:FindFirstChild("PlayerTitleGui")
            if oldTitle then oldTitle:Destroy() end

            -- 创建一个悬浮 GUI (BillboardGui)
            local titleGui = Instance.new("BillboardGui")
            titleGui.Name = "PlayerTitleGui"
            titleGui.Size = UDim2.new(0, 140, 0, 30)
            titleGui.StudsOffset = Vector3.new(0, 2.5, 0) -- 悬浮在头顶上方 2.5 格
            titleGui.AlwaysOnTop = true
            titleGui.MaxDistance = 80 -- 超过 80 米不可见

            -- 创建文字标签
            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.Text = "MAX  " .. tostring(maxCleared)
            
            textLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- 亮金色文字
            textLabel.TextStrokeTransparency = 0.2
            textLabel.TextStrokeColor3 = Color3.fromRGB(60, 30, 0) -- 深棕色描边，提升质感
            textLabel.TextScaled = true
            textLabel.Font = Enum.Font.LuckiestGuy
            textLabel.Parent = titleGui

            -- 将 GUI 挂载到玩家头部
            titleGui.Parent = head
        end)
    end)
end)
-- =========================================

local PlayerDataManager = require(script.PlayerDataManager)
PlayerDataManager.Init()

local InventoryService = require(script.Services.InventoryService)
InventoryService.Init()

local EquipmentService = require(script.Services.EquipmentService)
EquipmentService.Init()

local ShopService = require(script.Services.ShopService)
ShopService.Init()

local PlotService = require(script.Services.PlotService)
PlotService.Init()

local CoinDropService = require(script.Services.CoinDropService)
CoinDropService.Init()

local PlantService = require(script.Services.PlantService)
PlantService.Init()

local BaseMerchantService = require(script.Services.BaseMerchantService)
BaseMerchantService.Init()

local CombatService = require(script.Services.CombatService)
CombatService.Init()

local ZombieService = require(script.Services.ZombieService)
ZombieService.Init()
local FreeRewardService = require(script.Services.FreeRewardService)
FreeRewardService.Init()

local LevelService = require(script.Services.LevelService)
LevelService.Init()

local ToolService = require(script.Services.ToolService)
ToolService.Init()
local LuckyDropService = require(script.Services.LuckyDropService)
LuckyDropService.Init()
-- 找到你原来 require 其他 Service 的地方，加上这一句：
local RankingService = require(script.Services.RankingService)

-- 然后在下方的执行区域，加上初始化：
RankingService.Init()

require(script.Services.IAPService).Init()

require(script.Services.BaseSunflowerService).Init()

require(script.Services.ZombieBoxService)
--[[Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        if msg == "/testbomb" then
            -- 给发消息的玩家直接塞 20 个樱桃炸弹
            local PDManager = require(script.PlayerDataManager)
            PDManager.GivePlant(player, "CobCannon", 20, 1)
            
            -- 在控制台打印提示
            print("【开发者测试】已发放 20 个樱桃炸弹给: " .. player.Name)
            
            -- 给客户端弹个提示框
            local showTipRE = game:GetService("ReplicatedStorage"):FindFirstChild("ShowTipRE")
            if showTipRE then
                showTipRE:FireClient(player, "获得测试道具：樱桃炸弹 x20！")
            end
        end
    end)
end)]]

print("所有服务端模块加载完毕！")
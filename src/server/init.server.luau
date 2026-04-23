

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

-- 3. 玩家一出生，就把他的身体扔进 "Players" 组里
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- 给身体所有的手脚、躯干打上玩家组标签
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CollisionGroup = "Players" end
        end
        -- 如果玩家中途穿了新装备，也立刻打上标签
        character.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then desc.CollisionGroup = "Players" end
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


local CombatService = require(script.Services.CombatService)
CombatService.Init()

local ZombieService = require(script.Services.ZombieService)
ZombieService.Init()


local LevelService = require(script.Services.LevelService)
LevelService.Init()

local ToolService = require(script.Services.ToolService)
ToolService.Init()

require(script.Services.BaseSunflowerService).Init()


print("所有服务端模块加载完毕！")
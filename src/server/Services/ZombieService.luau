-- src/server/Services/ZombieService.luau
local ZombieService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") 
local PhysicsService = game:GetService("PhysicsService")


local ZombieConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZombieConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local CoinDropService = require(script.Parent.CoinDropService)

local activeSessions = {}
local LevelConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("LevelConfig"))

ZombieService.AnimationCache = {}



-- ==========================================
-- [🌟 新增：战斗结束，复活所有隐藏的植物]
-- ==========================================
function ZombieService.RestorePlotPlants(plot, player)
    local lawnFolder = plot:FindFirstChild("Lawn")
    if not lawnFolder then return end
    
    local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
    
    for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
        if lawnPart:IsA("BasePart") then
            for _, child in pairs(lawnPart:GetChildren()) do
                if child:IsA("Model") and child:GetAttribute("IsCombatPlant") then
                    if child:GetAttribute("IsDead") then
                        -- 1. 数据恢复
                        local maxHP = child:GetAttribute("MaxHealth") or 300
                        child:SetAttribute("Health", maxHP)
                        child:SetAttribute("IsDead", false)
                        child:SetAttribute("Exploded", false) 
                        
                        -- 2. 同步回数据库
                        if player then 
                            PlayerDataManager.UpdateCombatPlantHP(player, lawnPart.Name, maxHP) 
                        end
                        
                        -- 3. 视觉恢复
                        for _, p in pairs(child:GetDescendants()) do
                            if p:IsA("BasePart") then
                                local origT = p:GetAttribute("OriginalTransparency")
                                if origT then 
                                    p.Transparency = origT 
                                else 
                                    p.Transparency = 0 
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- src/server/Services/ZombieService.luau
function ZombieService.TriggerGameOver(plot, player)
    if plot:GetAttribute("IsGameOver") then return end
    plot:SetAttribute("IsGameOver", true)
    plot:SetAttribute("IsLevelActive", false)

    print("【关卡系统】防守失败！僵尸进入了房间！")

    -- 1. 恢复植物 (只需调用一次)
    ZombieService.RestorePlotPlants(plot, player)

    -- 2. 触发最终结算 (内部会自动打包数据并发送 UI 弹窗，不需要在这重复写了)
    ZombieService.FinalSettlement(player, plot, false)

    -- 3. 清理场上所有的僵尸
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChild("HumanoidRootPart") then
            if obj.HumanoidRootPart.CollisionGroup == "Zombies" then
                obj:Destroy()
            end
        end
    end
end

-- ==========================================
-- [核心：僵尸生成与 AI]
-- ==========================================
function ZombieService.SpawnZombie(plot, rowNum, zombieId, player)
    local lawnFolder = plot:FindFirstChild("Lawn")
    local tombstonesFolder = plot:FindFirstChild("Tombstones") 
    local homeBlock = plot:FindFirstChild("Home") 
    local houseEndFolder = plot:FindFirstChild("HouseEnd")
    local houseEndBlock = houseEndFolder and houseEndFolder:FindFirstChild("HouseEnd" .. rowNum)
    
    if not lawnFolder then return end

    local startBlock = lawnFolder:FindFirstChild("Lawn" .. rowNum .. "_9")
    local endBlock = lawnFolder:FindFirstChild("Lawn" .. rowNum .. "_1")
    if not startBlock or not endBlock then return end

    local tombstone = tombstonesFolder and tombstonesFolder:FindFirstChild("Tombstone" .. rowNum)
    local spawnX, spawnZ
    
    if tombstone then
        spawnX = tombstone.Position.X
        spawnZ = tombstone.Position.Z
        for _, part in pairs(tombstone:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
        if tombstone:IsA("BasePart") then tombstone.CanCollide = false end
    else
        local directionVector = (startBlock.Position - endBlock.Position).Unit
        local fallbackPos = startBlock.Position + directionVector * 8
        spawnX = fallbackPos.X
        spawnZ = fallbackPos.Z
    end

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local zombieTemplate = itemModelsFolder:FindFirstChild(zombieId) 
    if not zombieTemplate then return end

    plot:SetAttribute("ActiveZombies", (plot:GetAttribute("ActiveZombies") or 0) + 1)

    local zombie = zombieTemplate:Clone()
    
    for _, part in pairs(zombie:GetDescendants()) do
        if part:IsA("BasePart") then 
            -- [🌟 修改：破土期间设为 Default 组，植物的探测器会直接无视它，达成“无敌/不可选中”]
            part.CollisionGroup = "Default" 
            
            -- [🌟 新增：记录零件原本的碰撞状态，并强制关闭碰撞，实现彻底的“无碰撞模式”]
            part:SetAttribute("OriginalCanCollide", part.CanCollide)
            part.CanCollide = false
        end
        if part:IsA("Sound") then part:Destroy() end
    end
    
  local rootPart = zombie:FindFirstChild("HumanoidRootPart") or zombie.PrimaryPart
    local humanoid = zombie:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return end

    -- [🌟 核心双重保险：剥夺僵尸“摔倒”、“趴下”的能力]
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)

    local groundY = startBlock.Position.Y + rootPart.Size.Y/2 + 1.5
    local targetPos = Vector3.new(spawnX, groundY, spawnZ)
    local startPos = targetPos - Vector3.new(0, 4.5, 0) 
    local lookPos = Vector3.new(endBlock.Position.X, groundY, endBlock.Position.Z)

    local targetCFrame = CFrame.lookAt(targetPos, lookPos)
    local startCFrame = CFrame.lookAt(startPos, lookPos)

    rootPart.Anchored = true 
    zombie:PivotTo(startCFrame)

    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    local animTracks = {}
    
    local function loadAnimation(name, id)
        if not ZombieService.AnimationCache[id] then
            local anim = Instance.new("Animation")
            anim.AnimationId = id
            ZombieService.AnimationCache[id] = anim
        end
        local track = animator:LoadAnimation(ZombieService.AnimationCache[id])
        track.Priority = Enum.AnimationPriority.Movement
        track.Looped = true
        animTracks[name] = track
    end

    local config = ZombieConfig[zombieId]
    
    loadAnimation("Walk", config.Anims.Walk)
    loadAnimation("Eat", config.Anims.Eat)
    
    humanoid.MaxHealth = config.HP
    humanoid.Health = config.HP
    humanoid.WalkSpeed = 0 
    -- ==========================================
    -- [🌟 新增：动态血条 UI 与 防具击碎特效]
    -- ==========================================
    local dropPart = zombie:FindFirstChild("Drop", true)
    local baseZombieHP = 270 -- 普通僵尸的裸体血量
    local hasDropped = false

    -- 1. 纯代码构建精致血条 (挂在僵尸头顶)
    local hpBillboard = Instance.new("BillboardGui")
    hpBillboard.Name = "HPBar"
    hpBillboard.Size = UDim2.new(0, 50, 0, 6) -- 细长优雅的尺寸
    hpBillboard.StudsOffset = Vector3.new(0, 2.5, 0)
    hpBillboard.AlwaysOnTop = true
    hpBillboard.MaxDistance = 80
    hpBillboard.Enabled = false -- 默认隐藏，只有挨打才显示！
    
    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 1, 0)
    bgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bgFrame.BackgroundTransparency = 0.5
    Instance.new("UICorner", bgFrame).CornerRadius = UDim.new(0, 4)

    -- [🌟 新增：为血条背景添加黑色描边]
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0) -- 纯黑色
    stroke.Thickness = 1.5 -- 描边粗细，1.5 看起来最精致
    stroke.Parent = bgFrame

    bgFrame.Parent = hpBillboard

    local fillFrame = Instance.new("Frame")
    fillFrame.Size = UDim2.new(1, 0, 1, 0)
    fillFrame.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    Instance.new("UICorner", fillFrame).CornerRadius = UDim.new(0, 4)
    fillFrame.Parent = bgFrame
    
    hpBillboard.Parent = zombie:FindFirstChild("Head") or rootPart

    -- 2. 统一监听血量变化 (同时处理血条刷新与防具掉落)
    humanoid.HealthChanged:Connect(function(newHealth)
        
        -- 【更新血条】
        if newHealth < config.HP and newHealth > 0 then
            hpBillboard.Enabled = true
            local ratio = math.clamp(newHealth / config.HP, 0, 1)
            fillFrame.Size = UDim2.new(ratio, 0, 1, 0)
            
            -- 细节：如果有防具，防具没碎之前显示银色血条，碎了变成红色！
            if config.HP > baseZombieHP and newHealth > baseZombieHP then
                fillFrame.BackgroundColor3 = Color3.fromRGB(200, 200, 200) 
            else
                fillFrame.BackgroundColor3 = Color3.fromRGB(255, 60, 60) 
            end
        else
            hpBillboard.Enabled = false
        end

        -- 【防具掉落物理运算】
        if dropPart and config.HP > baseZombieHP then
            if not hasDropped and newHealth <= baseZombieHP and newHealth > 0 then
                hasDropped = true
                dropPart.Anchored = false
                dropPart.CanCollide = true
                
                -- 剪断物理连接
                for _, joint in pairs(zombie:GetDescendants()) do
                    if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
                        if joint.Part0 == dropPart or joint.Part1 == dropPart then
                            joint:Destroy()
                        end
                    end
                end
                
                -- 赋予击飞弹力
                local randomX = math.random(-8, 8)
                local randomZ = math.random(-8, 8)
                dropPart.AssemblyLinearVelocity = Vector3.new(randomX, 15, randomZ)
                
                task.delay(1, function()
                    if dropPart then dropPart:Destroy() end
                end)
            end
        end
    end)
    -- ==========================================
    local currentState = "None"
    local function switchState(newState)
        if currentState == newState then return end
        if animTracks[currentState] then animTracks[currentState]:Stop() end
        if animTracks[newState] then 
            animTracks[newState]:Play() 
            local speedMult = plot:GetAttribute("GameSpeed") or 1
            if newState == "Walk" then
                animTracks[newState]:AdjustSpeed(1.5 * speedMult) 
            else
                animTracks[newState]:AdjustSpeed(1.0 * speedMult)
            end
        end
        currentState = newState
    end

    zombie.Parent = Workspace

    task.spawn(function()
        switchState("Walk")
        
        -- ==========================================
        -- [🌟 关键修复：对抗 Humanoid 自动重置碰撞！]
        -- 等待一帧，让 Humanoid 进 Workspace 的默认物理重置先跑完
        -- 然后我们再强行把所有零件碰撞设为 false，确保万无一失！
        -- ==========================================
        task.wait() 
 
        -- ==========================================
        -- [🌟 破土修复：手写平滑算法，完美适配动态二倍速]
        -- ==========================================
       local riseTime = 2.5
        local currentRiseTime = 0
        while currentRiseTime < riseTime do
            if plot:GetAttribute("IsGameOver") then return end
            
            local speedMult = plot:GetAttribute("GameSpeed") or 1
            local dt = task.wait(0.03) -- 帧同步刷新
            currentRiseTime += (dt * speedMult)
            
            local alpha = math.clamp(currentRiseTime / riseTime, 0, 1)
            rootPart.CFrame = startCFrame:Lerp(targetCFrame, alpha)
        end
        
        -- ==========================================
        -- [🌟 终极防摔倒修复 1：严格切断四肢碰撞]
        -- 不再盲目恢复所有碰撞！强制让手脚变成幻影，只保留核心躯干的碰撞，
        -- 彻底杜绝走路动画中脚底板撞击地面把躯干掀翻的 Bug！
        -- ==========================================
        for _, part in pairs(zombie:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" or part.Name == "Torso" or part.Name == "UpperTorso" then
                    part.CanCollide = true
                else
                    part.CanCollide = false
                end
            end
        end

        --- 结束破土动画 (必须先解除固定，僵尸才会往下掉)
        rootPart.Anchored = false
        
        -- ==========================================
        -- [🌟 终极防摔倒修复 2：锁定服务器物理所有权]
        -- 强制剥夺客户端对僵尸的物理接管权，防止玩家靠近时产生抢夺卡顿！
        -- ==========================================
        pcall(function()
            rootPart:SetNetworkOwner(nil)
        end)
        
        -- ==========================================
        -- [核心逻辑：着地检测 + 激活战斗身份]
        -- ==========================================
        local landWaitTime = 0
        -- 1. 等待双脚着地，防止在空中就开始跑导致绊倒
        while humanoid.FloorMaterial == Enum.Material.Air and landWaitTime < 1 do
            landWaitTime += task.wait(0.07)
        end
        task.wait(0.2) -- 给物理引擎一点缓冲时间回正重心
      

        -- 2. 只有此时，才正式把碰撞组改回 "Zombies"，让植物开始攻击它
        for _, part in pairs(zombie:GetDescendants()) do
            if part:IsA("BasePart") then 
                part.CollisionGroup = "Zombies" 
            end
        end

        -- 3. 此时再给速度，开始前进
        humanoid.WalkSpeed = config.Speed

        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = {zombie}

        local currentTargetPos = endBlock.Position 
        local hasReachedEndBlock = false 
        local hasReachedHouseEnd = false 

        local timeAccumulated = config.AttackInterval 
        
        while zombie.Parent and humanoid.Health > 0 do
            if plot:GetAttribute("IsGameOver") then zombie:Destroy(); break end
            
            local speedMult = plot:GetAttribute("GameSpeed") or 1
            -- 时间累加与物理循环等待
            local dt = task.wait(0.1 / speedMult)
            timeAccumulated += (dt * speedMult)

            -- [🌟 核心修复 1：在循环中实时更新 WalkSpeed，确保玩家中途点击倍速也能立刻生效]
            if currentState == "Walk" then
                if animTracks["Walk"] then animTracks["Walk"]:AdjustSpeed(1.5 * speedMult) end
                humanoid.WalkSpeed = config.Speed * speedMult -- 动态物理加速！
            elseif currentState == "Eat" then
                if animTracks["Eat"] then animTracks["Eat"]:AdjustSpeed(1.0 * speedMult) end
                humanoid.WalkSpeed = 0
            end
            
            local flatRootPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
            
            if not hasReachedEndBlock then
                local flatEndPos = Vector3.new(endBlock.Position.X, 0, endBlock.Position.Z)
                if (flatRootPos - flatEndPos).Magnitude < 1 then hasReachedEndBlock = true end
            end

            if hasReachedEndBlock and not hasReachedHouseEnd then
                 if houseEndBlock then
                    currentTargetPos = houseEndBlock.Position
                    local flatHouseEndPos = Vector3.new(houseEndBlock.Position.X, 0, houseEndBlock.Position.Z)
                    if (flatRootPos - flatHouseEndPos).Magnitude < 1 then hasReachedHouseEnd = true end
                else
                    hasReachedHouseEnd = true 
                end
            end

            if hasReachedHouseEnd and homeBlock then
                currentTargetPos = homeBlock.Position
                local flatHomePos = Vector3.new(homeBlock.Position.X, 0, homeBlock.Position.Z)
                if (flatRootPos - flatHomePos).Magnitude < 1 then
                    ZombieService.TriggerGameOver(plot, player) 
                    break
                end
            end

            local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -2)
            local checkSize = Vector3.new(4, 5, 4) 
            local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
            
            local isFacingPlant = false
            local targetPlant = nil 

            for _, part in ipairs(hitParts) do
               local hitModel = part:FindFirstAncestorOfClass("Model")
                if hitModel and hitModel:GetAttribute("IsCombatPlant") and not hitModel:GetAttribute("IsDead") then
                    isFacingPlant = true
                    targetPlant = hitModel
                    break 
                end
            end

            if isFacingPlant and targetPlant then
                humanoid.WalkSpeed = 0 
                switchState("Eat")

                if timeAccumulated >= config.AttackInterval then
                    timeAccumulated = 0 
                    
                    local currentPlantHP = targetPlant:GetAttribute("Health") or 0
                    currentPlantHP = currentPlantHP - config.Attack
                    targetPlant:SetAttribute("Health", currentPlantHP)
                    
                    local gridName = targetPlant:GetAttribute("GridName")
                    if gridName and player then
                        PlayerDataManager.UpdateCombatPlantHP(player, gridName, currentPlantHP)
                    end
                    
                    for _, p in pairs(targetPlant:GetDescendants()) do
                        if p:IsA("BasePart") then
                            if not p:GetAttribute("OriginalColor") then
                                p:SetAttribute("OriginalColor", p.Color)
                            end
                            p.Color = Color3.fromRGB(255, 50, 50)
                            
                            task.delay(0.15, function() 
                                if p and p.Parent then 
                                    p.Color = p:GetAttribute("OriginalColor") 
                                end 
                            end)
                        end
                    end

                    if currentPlantHP <= 0 then
                        targetPlant:SetAttribute("IsDead", true)
                        
                        for _, p in pairs(targetPlant:GetDescendants()) do
                            if p:IsA("BasePart") then
                                if not p:GetAttribute("OriginalTransparency") then
                                    p:SetAttribute("OriginalTransparency", p.Transparency)
                                end
                                p.Transparency = 1 
                            end
                        end
                    end
                end
            else
                -- [🌟 核心修复 2：恢复行走时，重新赋予包含倍速的移动速度]
                humanoid.WalkSpeed = config.Speed * speedMult 
                humanoid:MoveTo(currentTargetPos) 
                switchState("Walk")
            end
        end
        
        if humanoid.Health <= 0 then
            plot:SetAttribute("ZombiesDefeated", (plot:GetAttribute("ZombiesDefeated") or 0) + 1)
            
            -- 确保击杀数被正确统计到结算面板
            if activeSessions[player.UserId] then
                activeSessions[player.UserId].TotalKills += 1
            end
            
            -- 掉落金币
            local dropPos = rootPart.Position + Vector3.new(0, 3, 0)
            CoinDropService.DropCoins(player, dropPos, math.random(1, 2), math.random(10, 20))

            -- ==========================================
            -- [🌟 终极融合版：原汁原味的击飞 + 完美穿透]
            -- ==========================================
            -- 1. 瞬间销毁 Humanoid，变成纯物理模型
            humanoid:Destroy() 
            rootPart.Anchored = false 

            -- 2. 设置碰撞组为“尸体”，只和地面碰撞，绝对无视其他僵尸
            for _, p in pairs(zombie:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = true  -- 保证不掉进虚空
                    p.CanTouch = false   
                    p.CanQuery = false   
                    p.CollisionGroup = "Corpses" 
                end
            end
            
            -- 3. 核心修改：取消所有平移动能，只给一个向后仰倒的旋转力
            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0) -- 强制清零移动速度，绝不后退！
            rootPart.AssemblyAngularVelocity = rootPart.CFrame.RightVector * -8 -- 像木板一样原地向后倒下
            
            -- 4. 尸体平滑渐隐消失逻辑 (支持倍速)
            task.spawn(function()
                -- 倒在地上躺 1.5 秒
                local dieTime = 1.5
                local currentDieTime = 0
                while currentDieTime < dieTime do
                    local sm = plot:GetAttribute("GameSpeed") or 1
                    currentDieTime += task.wait(0.1) * sm
                end

                if zombie and zombie.Parent then
                    -- 使用 Tween 平滑变透明
                    local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
                    for _, p in pairs(zombie:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Color = Color3.fromRGB(50, 50, 50) -- 尸体变暗
                            TweenService:Create(p, fadeInfo, {Transparency = 1}):Play()
                        end
                    end
                    
                    task.wait(0.5) -- 等待透明动画播放完毕
                    if zombie and zombie.Parent then
                        zombie:Destroy()
                    end
                end
            end)
        end
        
        plot:SetAttribute("ActiveZombies", (plot:GetAttribute("ActiveZombies") or 0) - 1)
    end)
end
function ZombieService.StartLevel(plot, levelId, player)
    if not activeSessions[player.UserId] or levelId == 1 then
        activeSessions[player.UserId] = { TotalCoins = 0, TotalSeeds = 0, TotalKills = 0 }
        plot:SetAttribute("ZombiesDefeated", 0)
    end
    local session = activeSessions[player.UserId]

    plot:SetAttribute("IsLevelActive", true)
    plot:SetAttribute("IsGameOver", false)
    plot:SetAttribute("CurrentLevel", levelId)
    plot:SetAttribute("ActiveZombies", 0) 

    local syncBattleUI_RE = game:GetService("ReplicatedStorage"):FindFirstChild("SyncBattleUI_RE")
    if syncBattleUI_RE then syncBattleUI_RE:FireClient(player, true, levelId) end

    -- ==========================================
    -- [🌟 核心一：获取关卡数据，如果没有手配，则调用无尽生成器！]
    -- ==========================================
    local levelData = LevelConfig[levelId] or ZombieService.GenerateInfiniteLevel(levelId)
    
    -- [🌟 核心二：同屏防卡顿限流器]
    local MAX_ACTIVE_ZOMBIES = 30 
    
    if levelData and levelData.Waves then
        for waveIndex, wave in ipairs(levelData.Waves) do
            if plot:GetAttribute("IsGameOver") then break end
            
            task.spawn(function()
                if wave.Zombies then
                    for _, zombieGroup in ipairs(wave.Zombies) do
                        for i = 1, zombieGroup.Count do
                            if plot:GetAttribute("IsGameOver") then break end
                            
                            -- [🌟 核心排队：如果场上僵尸满了，出怪口暂时塞车等待！]
                            while (plot:GetAttribute("ActiveZombies") or 0) >= MAX_ACTIVE_ZOMBIES do
                                if plot:GetAttribute("IsGameOver") then return end
                                task.wait(0.5) 
                            end
                            
                            local randomRow = math.random(1, 6)
                            ZombieService.SpawnZombie(plot, randomRow, zombieGroup.Type, player)
                            
                            local speedMult = plot:GetAttribute("GameSpeed") or 1
                            task.wait(math.random(10, 25) / 10 / speedMult) 
                        end
                    end
                end
            end)
            
            if wave.NextWaveTime and wave.NextWaveTime > 0 then
                local currentWait = 0
                while currentWait < wave.NextWaveTime do
                    if plot:GetAttribute("IsGameOver") then break end
                    local speedMult = plot:GetAttribute("GameSpeed") or 1
                    currentWait += task.wait(0.5) * speedMult
                end
            end
        end
    end

    repeat
        task.wait(1)
    until (plot:GetAttribute("ActiveZombies") <= 0) or (plot:GetAttribute("IsGameOver") == true)

    if not plot:GetAttribute("IsGameOver") then
        local waveCoins = 100 + (levelId * 20)
        local waveSeeds = (levelId % 3 == 0) and 1 or 0
        
        session.TotalCoins += waveCoins
        session.TotalSeeds += waveSeeds

        local nextLevelId = levelId + 1
        print("【关卡连战】第 "..levelId.." 关清理完毕，2秒后开始下一关...")
        task.wait(2)
        -- 无限模式，这里永远会执行 StartLevel！
        ZombieService.StartLevel(plot, nextLevelId, player)
    end
end
function ZombieService.FinalSettlement(player, plot, isVictory)
    local session = activeSessions[player.UserId]
    if not session then return end

    local lastLevel = plot:GetAttribute("CurrentLevel") or 1
    local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
    local data = PlayerDataManager.GetPlayerData(player)
    
    -- [🌟 修复：只有当前关卡超过存档里的最高解锁关卡时，才算破纪录！]
    local isNewRecord = data and lastLevel > (data.UnlockedLevel or 1)
    
    local showResultRE = ReplicatedStorage:FindFirstChild("ShowBattleResultRE")
    
    if showResultRE then
        -- 这里的第四个参数换成 isNewRecord
        showResultRE:FireClient(player, isVictory, lastLevel, isNewRecord, session.TotalKills, session.TotalCoins, session.TotalSeeds)
    end
    
    -- 锁定领地状态
    plot:SetAttribute("IsLevelActive", false)
end
function ZombieService.Init()
   -- ==========================================
    -- [🌟 从物理底层断绝所有异常碰撞！(终极防打断版)]
    -- ==========================================
    -- 1. 独立注册，防止因为某个组已存在而导致整体代码罢工
    pcall(function() PhysicsService:RegisterCollisionGroup("Zombies") end)
    pcall(function() PhysicsService:RegisterCollisionGroup("Corpses") end) 
    pcall(function() PhysicsService:RegisterCollisionGroup("Players") end) -- 确保 Players 组存在
    
    -- 2. 独立设置规则，确保 100% 被执行
    pcall(function()
        -- 规则 1：活僵尸和活僵尸之间绝对不碰撞（完美解决出生时互相挤压、绊倒！）
        PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
        
        -- 规则 2：活僵尸和尸体互不碰撞
        PhysicsService:CollisionGroupSetCollidable("Zombies", "Corpses", false)
        
        -- 规则 3：尸体和尸体之间互不碰撞
        PhysicsService:CollisionGroupSetCollidable("Corpses", "Corpses", false)

        -- [🌟 新增终极规则：彻底断绝僵尸（含存活与尸体）与玩家的任何碰撞]
        PhysicsService:CollisionGroupSetCollidable("Players", "Zombies", false)
        PhysicsService:CollisionGroupSetCollidable("Players", "Corpses", false)
    end)
    
    if not ReplicatedStorage:FindFirstChild("ShowBattleResultRE") then
        local re = Instance.new("RemoteEvent")
        re.Name = "ShowBattleResultRE"
        re.Parent = ReplicatedStorage
    end
    
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    if itemModelsFolder then
        for zombieId, config in pairs(ZombieConfig) do
            local template = itemModelsFolder:FindFirstChild(zombieId)
            if template then
                local dummy = template:Clone()
                local humanoid = dummy:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
                    for animName, animId in pairs(config.Anims) do
                        if not ZombieService.AnimationCache[animId] then
                            local anim = Instance.new("Animation")
                            anim.AnimationId = animId
                            ZombieService.AnimationCache[animId] = anim
                        end
                        animator:LoadAnimation(ZombieService.AnimationCache[animId])
                    end
                end

                local rootPart = dummy:FindFirstChild("HumanoidRootPart") or dummy.PrimaryPart
                if rootPart then
                    rootPart.Anchored = true 
                    dummy:PivotTo(CFrame.new(0, 50000, 0))
                end
                
                dummy.Parent = Workspace
                for _, p in pairs(dummy:GetDescendants()) do
                    if p:IsA("BasePart") then p.Transparency = 0.5 end
                end
                
                task.delay(0.2, function()
                    if dummy and dummy.Parent then dummy:Destroy() end
                end)
            end
        end
    end
end


-- ==========================================
-- [🌟 新增：玩家确认领奖，核销会话数据]
-- ==========================================
function ZombieService.ClaimBattleRewards(player)
    local session = activeSessions[player.UserId]
    if session then
        local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
        PlayerDataManager.ApplyBattleRewards(player, session.TotalCoins, session.TotalSeeds)
        -- 领完立刻清空，防止利用漏洞重复领奖！
        activeSessions[player.UserId] = nil 
    end
end

-- ==========================================
-- [🌟 新增：服务端的无尽关卡生成引擎]
-- ==========================================
function ZombieService.GenerateInfiniteLevel(levelId)
    local waveCount = math.clamp(math.floor(levelId / 2) + 2, 4, 15) 
    local waves = {}

    for w = 1, waveCount do
        local waveZombies = {}
        local totalZombiesInWave = math.floor(levelId * 0.8) + math.random(3, 6)
        
        for i = 1, totalZombiesInWave do
            local pool = {}
            local totalWeight = 0
            
            for _, zInfo in ipairs(LevelConfig.InfiniteZombiePool) do
                if levelId >= zInfo.UnlockLevel then
                    table.insert(pool, zInfo)
                    totalWeight += zInfo.Weight
                end
            end
            
            local rand = math.random(1, totalWeight)
            local currentWeight = 0
            local selectedType = "NormalZombie"
            
            for _, zInfo in ipairs(pool) do
                currentWeight += zInfo.Weight
                if rand <= currentWeight then
                    selectedType = zInfo.Type
                    break
                end
            end
            
            local found = false
            for _, group in ipairs(waveZombies) do
                if group.Type == selectedType then
                    group.Count += 1
                    found = true; break
                end
            end
            if not found then table.insert(waveZombies, { Type = selectedType, Count = 1 }) end
        end

        table.insert(waves, { NextWaveTime = math.random(15, 22), Zombies = waveZombies })
    end

    return { LevelName = "无尽挑战 第 " .. levelId .. " 关", Waves = waves }
end
return ZombieService
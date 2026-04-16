-- src/server/Services/CombatService.luau
local CombatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local EquipmentService = require(script.Parent.EquipmentService)
local PlotService = require(script.Parent.PlotService)
local Debris = game:GetService("Debris")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- [🌟 核心提取：将生成植物的逻辑做成通用模块]
local function SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP)
    local itemDetail = ItemConfig.Plants[plantId]
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local combatModel = itemModelsFolder:FindFirstChild(plantId .. "_Plant") or itemModelsFolder:FindFirstChild(plantId)
    
    if combatModel and itemDetail then
        local newFighter = combatModel:Clone()
        newFighter.Name = plantId
       
        newFighter:SetAttribute("IsCombatPlant", true)
        newFighter:SetAttribute("Health", currentHP)
        newFighter:SetAttribute("MaxHealth", maxHP)

        newFighter.PrimaryPart:SetAttribute("GridName", lawnPart.Name)
        newFighter:SetAttribute("GridName", lawnPart.Name)
        
        if newFighter:IsA("Model") and newFighter.PrimaryPart then
            newFighter:PivotTo(lawnPart.CFrame * CFrame.new(0, lawnPart.Size.Y/2 + newFighter.PrimaryPart.Size.Y/2, 0))
        end

        local targetAnimId = itemDetail.IdleAnimId
        for _, part in pairs(newFighter:GetDescendants()) do
            if part:IsA("BasePart") then 
                -- [🌟 关闭碰撞，防止卡住玩家或僵尸]
                part.CanCollide = false 
                part.CanQuery = true -- 保留这行，确保鼠标悬停检测依然生效
                
                if targetAnimId and newFighter.PrimaryPart and part == newFighter.PrimaryPart then
                    part.Anchored = true
                else
                    part.Anchored = not targetAnimId 
                end
            end
        end
        
        if targetAnimId then
            local animController = newFighter:FindFirstChildOfClass("AnimationController") or newFighter:FindFirstChildOfClass("Humanoid")
            if not animController then animController = Instance.new("AnimationController"); animController.Parent = newFighter end
            local animator = animController:FindFirstChildOfClass("Animator")
            if not animator then animator = Instance.new("Animator"); animator.Parent = animController end
            local anim = Instance.new("Animation"); anim.AnimationId = targetAnimId
            local track = animator:LoadAnimation(anim); track.Priority = Enum.AnimationPriority.Idle; track.Looped = true; track:Play()
        end

        newFighter.Parent = lawnPart
        lawnPart:SetAttribute("OccupiedBy", plantId)
        
        local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Enabled = false end -- 种了植物就隐藏提示框

        -- ==========================================
        -- [🌟 起爆器支持重复利用！]
        -- ==========================================
        if itemDetail.ExplosionType then
            local connection
            connection = newFighter:GetAttributeChangedSignal("Health"):Connect(function()
                local hp = newFighter:GetAttribute("Health")
                -- 检查 Exploded 标记，防止同一波重复引爆，但不销毁监听器！
                if hp <= 0 and not newFighter:GetAttribute("Exploded") then
                    newFighter:SetAttribute("Exploded", true)
                    
                    local rootPart = newFighter.PrimaryPart or newFighter:FindFirstChildWhichIsA("BasePart")
                    if not rootPart then return end

                    -- 1. 划定爆炸波及范围
                    local checkCFrame = rootPart.CFrame
                    local checkSize = Vector3.new(14, 10, 14)
                    
                    if itemDetail.ExplosionType == "Row" then
                        checkSize = Vector3.new(4, 15, 100) 
                    end

                    -- 2. 扫描范围内的僵尸
                    local overlapParams = OverlapParams.new()
                    local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
                    local damagedZombies = {} 

                    for _, part in ipairs(hitParts) do
                        if part.CollisionGroup == "Zombies" then
                            local zModel = part:FindFirstAncestorOfClass("Model")
                            if zModel and not damagedZombies[zModel] then
                                damagedZombies[zModel] = true
                                local zHum = zModel:FindFirstChildOfClass("Humanoid")
                                
                                if zHum and zHum.Health > 0 then
                                    zHum.Health = zHum.Health - (itemDetail.ExplosionDamage or 1800)
                                    for _, p in pairs(zModel:GetDescendants()) do
                                        if p:IsA("BasePart") then
                                            p.Color = Color3.fromRGB(20, 20, 20) 
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- 3. 召唤特效
                    local effectPart = Instance.new("Part")
                    effectPart.Anchored = true; effectPart.CanCollide = false; effectPart.Transparency = 1
                    effectPart.Parent = Workspace

                    if itemDetail.ExplosionType == "Row" then
                        effectPart.Size = Vector3.new(6, 1, 100) 
                        effectPart.Position = rootPart.Position - Vector3.new(0, 1.5, 0)
                        
                        local particles = Instance.new("ParticleEmitter", effectPart)
                        particles.Enabled = false 
                        particles.Texture = "rbxassetid://248625108" 
                        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
                        particles.Lifetime = NumberRange.new(0.05, 0.12)
                        particles.LightEmission = 1
                        particles.EmissionDirection = Enum.NormalId.Top 
                        particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10)})
                        particles.Speed = NumberRange.new(60, 100)
                        particles.Drag = 10
                        
                        task.delay(0.05, function()
                            if particles then particles:Emit(100) end
                        end)
                    else
                        effectPart.Position = rootPart.Position
                        local attachment = Instance.new("Attachment", effectPart)
                        local particles = Instance.new("ParticleEmitter", attachment)
                        particles.Enabled = false 
                        particles.Texture = "rbxassetid://248625108" 
                        particles.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0))
                        particles.LightEmission = 1
                        particles.Lifetime = NumberRange.new(0.2, 0.4) 
                        particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12)})
                        particles.Speed = NumberRange.new(30, 50)
                        
                        task.delay(0.05, function()
                            if particles then particles:Emit(60) end
                        end)
                    end
                    Debris:AddItem(effectPart, 2)
                end
            end)
        end

        -- ==========================================
        -- [🌟 休眠式智能大脑 (死亡时不退出循环，而是休眠)]
        -- ==========================================
        if itemDetail.CanAttack then
            task.spawn(function()
                local attackInterval = itemDetail.AttackInterval or 1.5
                local attackDamage = itemDetail.Attack or 20
                local timeAccumulated = attackInterval 
                local plot = lawnPart.Parent.Parent 

                while newFighter.Parent do
                    -- 如果植物死了，进入休眠等待复活，不退出循环
                    local hp = newFighter:GetAttribute("Health") or 0
                    if hp <= 0 or newFighter:GetAttribute("IsDead") then
                        task.wait(0.5)
                        continue
                    end

                    local speedMult = plot:GetAttribute("GameSpeed") or 1
                    local dt = task.wait(0.1 / speedMult)
                    timeAccumulated += (dt * speedMult)

                    if timeAccumulated >= attackInterval then
                        local rootPart = newFighter.PrimaryPart or newFighter:FindFirstChildWhichIsA("BasePart")
                        if rootPart then
                            local overlapParams = OverlapParams.new()
                            overlapParams.FilterType = Enum.RaycastFilterType.Exclude
                            overlapParams.FilterDescendantsInstances = {newFighter}
                            
                            local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -50)
                            local checkSize = Vector3.new(4, 5, 100) 
                            local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)
                            
                            -- ==========================================
                            -- [🌟 核心优化 1：雷达扫描，精准锁定最前方的第一个活僵尸]
                            -- ==========================================
                            local targetZombieModel = nil
                            local targetHum = nil
                            local targetRoot = nil
                            local minDistance = math.huge

                            for _, part in ipairs(hitParts) do
                                if part.CollisionGroup == "Zombies" then
                                    local zModel = part:FindFirstAncestorOfClass("Model")
                                    local zHum = zModel and zModel:FindFirstChildOfClass("Humanoid")
                                    
                                    if zHum and zHum.Health > 0 then
                                        local zRoot = zModel.PrimaryPart or zModel:FindFirstChild("HumanoidRootPart")
                                        if zRoot then
                                            -- 测算距离，选出离植物最近的那个倒霉蛋
                                            local dist = (zRoot.Position - rootPart.Position).Magnitude
                                            if dist < minDistance then
                                                minDistance = dist
                                                targetZombieModel = zModel
                                                targetHum = zHum
                                                targetRoot = zRoot
                                            end
                                        end
                                    end
                                end
                            end

                            -- 如果成功锁定了目标
                            if targetZombieModel and targetHum and targetRoot then
                                timeAccumulated = 0 

                                local projName = itemDetail.ProjectileName
                                local ammoFolder = ReplicatedStorage:FindFirstChild("Ammo")
                                local projTemplate = ammoFolder and ammoFolder:FindFirstChild(projName)
                                if not projTemplate then return end

                                -- 生成没有物理引擎参与的“视觉豌豆”
                                local projectile = projTemplate:Clone()
                                projectile.CanCollide = false 
                                projectile.Anchored = true
                                projectile.CFrame = rootPart.CFrame * CFrame.new(0, 1.5, -1.5) 
                                projectile.Parent = Workspace

                                Debris:AddItem(projectile, 10)

                                -- ==========================================
                                -- [🌟 核心优化 2：代码接管飞行，强制因果律命中]
                                -- ==========================================
                                task.spawn(function()
                                    local baseSpeed = 25 -- 豌豆的飞行速度
                                    local hasHit = false
                                    
                                    -- 只要豌豆还在，就不断拉近它和目标的距离
                                    while projectile and projectile.Parent do
                                        
                                        -- 【🌟 关键需求达成：飞行过程中目标死了，直接销毁豌豆！】
                                        if not targetZombieModel.Parent or targetHum.Health <= 0 then
                                            projectile:Destroy()
                                            break
                                        end

                                        local currentSpeedMult = plot:GetAttribute("GameSpeed") or 1
                                        local dtLoop = task.wait() 
                                        
                                        -- 动态获取僵尸当前位置（稍微往上抬一点，瞄准胸口）
                                        local targetPos = targetRoot.Position + Vector3.new(0, 1, 0)
                                        local currentPos = projectile.Position
                                        local direction = (targetPos - currentPos)
                                        
                                        local distanceToTarget = direction.Magnitude
                                        local moveStep = baseSpeed * currentSpeedMult * dtLoop
                                        
                                        -- 判断是否足够接近，接近即视为击中
                                        if distanceToTarget <= moveStep then
                                            hasHit = true
                                            break
                                        else
                                            -- 让豌豆平滑飞向目标
                                            projectile.CFrame = CFrame.lookAt(currentPos + direction.Unit * moveStep, targetPos)
                                        end
                                    end
                                    
                                    if projectile and projectile.Parent then
                                        projectile:Destroy() 
                                    end
                                
                                    -- 【命中结算】
                                    if hasHit and targetHum and targetHum.Health > 0 then
                                        local hitPos = projectile.Position
                                        projectile:Destroy() 
                                        
                                        -- 1. 精准扣血，绝不误伤
                                        targetHum.Health = targetHum.Health - attackDamage
                                        
                                        -- 2. 召唤命中特效
                                        local effectPart = Instance.new("Part")
                                        effectPart.Size = Vector3.new(1, 1, 1)
                                        effectPart.Transparency = 1
                                        effectPart.Anchored = true
                                        effectPart.CanCollide = false
                                        effectPart.Position = hitPos
                                        effectPart.Parent = Workspace
                                        
                                        local attachment = Instance.new("Attachment", effectPart)
                                        local particles = Instance.new("ParticleEmitter", attachment)
                                        particles.Texture = itemDetail.HitEffectTexture or "rbxassetid://243098098"
                                        local effectColor = itemDetail.HitEffectColor or Color3.fromRGB(255, 215, 0)
                                        particles.Color = ColorSequence.new(effectColor)
                                        particles.Size = NumberSequence.new(1, 0)
                                        particles.Rate = 500
                                        particles.Speed = NumberRange.new(5, 10)
                                        particles.Lifetime = NumberRange.new(0.1, 0.3)
                                        
                                        particles:Emit(15) 
                                        Debris:AddItem(effectPart, 0.5) 
                                        
                                        -- 3. 僵尸受击闪红反馈
                                        for _, p in pairs(targetZombieModel:GetDescendants()) do
                                            if p:IsA("BasePart") then
                                                if not p:GetAttribute("OriginalColor") then
                                                    p:SetAttribute("OriginalColor", p.Color)
                                                end
                                                p.Color = Color3.fromRGB(255, 0, 0)
                                                task.delay(0.1, function()
                                                    if p and p.Parent and targetHum and targetHum.Health > 0 then 
                                                        p.Color = p:GetAttribute("OriginalColor") 
                                                    end
                                                end)
                                            end
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end)
        end

        return newFighter
    end
end

function CombatService.Init()
    local plotsFolder = Workspace:WaitForChild("Plots")

    -- ==========================================
    -- [🌟 玩家上线读档系统] 恢复他的钢铁防线！
    -- ==========================================
    Players.PlayerAdded:Connect(function(player)
        local plot = nil
        for i = 1, 20 do
            plot = PlotService.GetPlayerPlot(player)
            if plot then break end
            task.wait(0.5)
        end
        if not plot then return end

        local data = PlayerDataManager.GetPlayerData(player)
        if not data or not data.CombatPlants then return end

        local lawnFolder = plot:WaitForChild("Lawn")
       -- 遍历玩家数据库里的战斗植物，重新种出来！
        for gridName, plantInfo in pairs(data.CombatPlants) do
            local lawnPart = lawnFolder:FindFirstChild(gridName)
            if lawnPart then
                local itemDetail = ItemConfig.Plants[plantInfo.PlantId]
                if itemDetail then
                    -- [🌟 核心修复：彻底无视旧存档里的残血，统统满血复活！]
                    local maxHP = itemDetail.HP or 300
                    SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP)
                end
            end
        end
    end)

    -- ==========================================
    -- 1. 扫描领地，部署交互点
    -- ==========================================
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local lawnFolder = plot:WaitForChild("Lawn")
        for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
            if lawnPart:IsA("BasePart") then
                local prompt = Instance.new("ProximityPrompt")
                prompt.ActionText = "部署"
                prompt.ObjectText = "草坪"
                prompt.KeyboardKeyCode = Enum.KeyCode.F
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 8 
                prompt.Parent = lawnPart
                prompt.HoldDuration = 0.2 

                prompt.Triggered:Connect(function(player)
                    local myPlot = PlotService.GetPlayerPlot(player)
                    if myPlot ~= plot then return end
                    
                    -- [🌟 战斗状态检查]
                    if plot:GetAttribute("IsLevelActive") then
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then
                            showNotifRE:FireClient(player, "⚠️ 无法操作", "战斗已经开始，无法在此时部署新植物！")
                        end
                        return 
                    end
                    if lawnPart:GetAttribute("OccupiedBy") then return end

                    local character = player.Character
                    if not character then return end
                    local equippedCompositeId = character:GetAttribute("EquippedSeed")
                    if not equippedCompositeId then return end

                    local parts = string.split(equippedCompositeId, "_")
                    local itemType = parts[1]
                    local plantId = parts[2]

                    if itemType ~= "Plant" then return end

                    if PlayerDataManager.ConsumePlant(player, plantId, 1) then
                        local data = PlayerDataManager.GetPlayerData(player)
                        local hasStock = false
                        if data and data.Inventory.Plants then
                            for _, pData in ipairs(data.Inventory.Plants) do
                                if pData.ID == plantId and pData.Quantity > 0 then hasStock = true; break end
                            end
                        end
                        if not hasStock then
                            EquipmentService.UpdateHoldItem(player, nil)
                            local holdItemRE = ReplicatedStorage:FindFirstChild("HoldItemRE")
                            if holdItemRE then holdItemRE:FireClient(player, nil) end
                        end

                        -- [🌟 调用通用模块生成植物，并存入数据库！]
                        local itemDetail = ItemConfig.Plants[plantId]
                        local maxHP = itemDetail.HP or 300
                        SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP)
                        PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP)
                    end
                end)
            end
        end
    end
    print("服务端：CombatService 加载完毕！追踪子弹系统已实装！")
end

return CombatService
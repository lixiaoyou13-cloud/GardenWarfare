-- src/server/Services/ZombieService.luau
local ZombieService = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local AnalyticsService = game:GetService("AnalyticsService")


local ZombieConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZombieConfig"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PassQuestConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PassQuestConfig"))
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local CoinDropService = require(script.Parent.CoinDropService)
local PlantCombatAI = require(script.Parent.PlantCombatAI)

local activeSessions = {}
local LevelConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("LevelConfig"))

ZombieService.AnimationCache = {}

local warnedAnimationIssues = {}
local failedAnimationIds = {}
local DANCING_ZOMBIE_ID = "DancingZombie"
local DANCING_ZOMBIE_LEVEL_CHANCE = 1
local LANE_CORRECTION_DEADZONE = 0.25
local LANE_CORRECTION_HARD_OFFSET = 3

local function getFlatVector(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function getFlatUnit(vector, fallback)
    if typeof(vector) == "Vector3" then
        local flat = getFlatVector(vector)
        if flat.Magnitude > 0.001 then
            return flat.Unit
        end
    end

    if typeof(fallback) == "Vector3" then
        local flatFallback = getFlatVector(fallback)
        if flatFallback.Magnitude > 0.001 then
            return flatFallback.Unit
        end
    end

    return Vector3.new(0, 0, -1)
end

local function getLawnRowFromGridName(gridName)
    if type(gridName) ~= "string" then
        return nil
    end

    return tonumber(string.match(gridName, "^Lawn(%d+)_"))
end

local function getCombatPlantRow(plantModel)
    if not plantModel then
        return nil
    end

    local rowNum = getLawnRowFromGridName(plantModel:GetAttribute("GridName"))
    if rowNum then
        return rowNum
    end

    local parent = plantModel.Parent
    if parent and parent:IsA("BasePart") then
        return getLawnRowFromGridName(parent.Name)
    end

    return nil
end

local function warnAnimationOnce(animationId, context, err)
    local key = tostring(animationId) .. ":" .. tostring(context)
    if warnedAnimationIssues[key] then return end
    warnedAnimationIssues[key] = true
    warn(("[ZombieService] Animation %s failed in %s: %s"):format(tostring(animationId), tostring(context), tostring(err)))
end

local function getCachedAnimation(animationId)
    if animationId == nil then
        return nil
    end

    animationId = tostring(animationId)
    if animationId == "" then
        return nil
    end

    if not ZombieService.AnimationCache[animationId] then
        local anim = Instance.new("Animation")
        anim.AnimationId = animationId
        ZombieService.AnimationCache[animationId] = anim
    end

    return ZombieService.AnimationCache[animationId], animationId
end

local function safeLoadAnimation(animator, animationId, context)
    if not animator then
        return nil
    end

    if animationId == nil then
        return nil
    end

    animationId = tostring(animationId)
    if animationId == "" or failedAnimationIds[animationId] then
        return nil
    end

    local anim, normalizedId = getCachedAnimation(animationId)
    if not anim then
        return nil
    end

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(anim)
    end)

    if not ok or not trackOrErr then
        failedAnimationIds[normalizedId] = true
        warnAnimationOnce(normalizedId, context, trackOrErr)
        return nil
    end

    return trackOrErr
end

local function GetSyncBattleUIRemote()
    return ReplicatedStorage:FindFirstChild("SyncBattleUI_RE")
end

local function CountLevelZombies(levelData)
    local totalZombies = 0
    if levelData and levelData.Waves then
        for _, wave in ipairs(levelData.Waves) do
            if wave.Zombies then
                for _, zombieGroup in ipairs(wave.Zombies) do
                    totalZombies += zombieGroup.Count or 0
                end
            end
        end
    end
    return totalZombies
end

local function SyncBattleProgress(player, plot, isActive, levelId)
    local syncBattleUI_RE = GetSyncBattleUIRemote()
    if not syncBattleUI_RE then return end

    syncBattleUI_RE:FireClient(
        player,
        isActive,
        levelId or plot:GetAttribute("CurrentLevel") or 1,
        plot:GetAttribute("TotalZombies") or 0,
        plot:GetAttribute("ZombiesDefeated") or 0
    )
end

local function IsBattleCancelled(plot, player, battleToken)
    if not plot then return true end
    if battleToken and plot:GetAttribute("BattleToken") ~= battleToken then return true end
    if plot:GetAttribute("IsGameOver") then return true end
    if not player or not player.Parent then return true end
    if plot:GetAttribute("OwnerId") ~= player.UserId then return true end
    return false
end

local function GetZombieSlowMultiplier(zombie)
    local slowMultiplier = tonumber(zombie and zombie:GetAttribute("SlowMultiplier")) or 1
    if slowMultiplier <= 0 or slowMultiplier > 1 then
        return 1
    end
    return slowMultiplier
end

-- 战斗，复活所有隐藏的植物
function ZombieService.RestorePlotPlants(plot, player)
    local lawnFolder = plot:FindFirstChild("Lawn")
    if not lawnFolder then return end

    local MUTATION_TAGS = { Glow = true, Lightning = true, HolyLight = true }

    for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
        if lawnPart:IsA("BasePart") then
            for _, child in pairs(lawnPart:GetChildren()) do
                if child:IsA("Model") and child:GetAttribute("IsCombatPlant") then

                    -- 1. 恢复基础状态
                    local maxHP = child:GetAttribute("MaxHealth") or 300
                    child:SetAttribute("Health", maxHP)
                    child:SetAttribute("IsDead", false)
                    child:SetAttribute("Exploded", false)

                    -- 2. 透明度恢复
                    for _, p in pairs(child:GetDescendants()) do
                        if p:IsA("BasePart") then
                            -- 规则 1：如果名字是特效标签，强制 Transparency 为 1
                            if MUTATION_TAGS[p.Name] then
                                p.Transparency = 1
                            else
                                -- 规则 2：其他零件，严格按照出生时间记录的状态恢复
                                local origT = p:GetAttribute("OriginalTransparency")
                                -- 如果 origT 还是 nil，则根据它当前是否可见来决定（防止意外显示）
                                p.Transparency = origT or p.Transparency
                            end
                        elseif p:IsA("ParticleEmitter") or p:IsA("Light") or p:IsA("Beam") or p:IsA("Highlight") or p:IsA("Trail") then
                            -- 恢复特效开启状态
                            local origE = p:GetAttribute("OriginalEnabled")
                            if origE ~= nil then
                                p.Enabled = origE
                            end
                        end
                    end
                end
            end
        end
    end
end

function ZombieService.TriggerGameOver(plot, player)
    if plot:GetAttribute("IsGameOver") then return end
    plot:SetAttribute("IsGameOver", true)
    plot:SetAttribute("IsLevelActive", false)

    print("[LevelService] Defense failed; zombies reached the room!")

    ZombieService.RestorePlotPlants(plot, player)
    ZombieService.FinalSettlement(player, plot, false)

    -- 这里增加对 OwnerId 的判断
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute("IsZombie") and obj:GetAttribute("OwnerId") == player.UserId then
            obj:Destroy()
        end
    end
end

-- 僵尸生成与 AI
function ZombieService.SpawnZombie(plot, rowNum, zombieId, player)
    local lawnFolder = plot:FindFirstChild("Lawn")
    local tombstonesFolder = plot:FindFirstChild("Tombstones")
    local homeBlock = plot:FindFirstChild("Home")
    local houseEndFolder = plot:FindFirstChild("HouseEnd")
    local houseEndBlock = houseEndFolder and houseEndFolder:FindFirstChild("HouseEnd" .. rowNum)

    if not lawnFolder then return false end

    local startBlock = lawnFolder:FindFirstChild("Lawn" .. rowNum .. "_9")
    local endBlock = lawnFolder:FindFirstChild("Lawn" .. rowNum .. "_1")
    if not startBlock or not endBlock then return false end

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
    if not itemModelsFolder then return false end
    local zombieTemplate = itemModelsFolder:FindFirstChild(zombieId)
    if not zombieTemplate and zombieId == DANCING_ZOMBIE_ID then
        zombieTemplate = itemModelsFolder:FindFirstChild("Zombie")
    end
    if not zombieTemplate then return false end

    local zombie = zombieTemplate:Clone()
    zombie.Name = zombieId
    zombie:SetAttribute("IsZombie", true)
    zombie:SetAttribute("ZombieId", zombieId)
    zombie:SetAttribute("LaneRow", tonumber(rowNum) or rowNum)

    if player then
        zombie:SetAttribute("OwnerId", player.UserId)
    end

    for _, part in pairs(zombie:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "Default"
            part:SetAttribute("OriginalCanCollide", part.CanCollide)
            part.CanCollide = false
        end
        if part:IsA("Sound") then part:Destroy() end
    end

    local rootPart = zombie:FindFirstChild("HumanoidRootPart") or zombie.PrimaryPart
    local humanoid = zombie:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then
        zombie:Destroy()
        return false
    end

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
    local laneStartFlat = getFlatVector(startBlock.Position)
    local laneEndFlat = getFlatVector(endBlock.Position)
    local laneVector = laneEndFlat - laneStartFlat
    local laneDirection = getFlatUnit(laneVector, lookPos - targetPos)

    rootPart.Anchored = true
    zombie:PivotTo(startCFrame)

    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    local animTracks = {}

    local function loadAnimation(name, id)
        local track = safeLoadAnimation(animator, id, tostring(zombieId) .. "." .. tostring(name))
        if not track then return end

        track.Priority = Enum.AnimationPriority.Movement
        track.Looped = true
        animTracks[name] = track
    end

   local config = ZombieConfig[zombieId]
    if not config or not config.Anims then
        zombie:Destroy()
        return false
    end

    -- 获取当前关卡数，如果没有则默认为1
    local currentLevel = plot:GetAttribute("CurrentLevel") or 1

    -- 动态血量计算：从第11关开始（无尽模式），每关增加 15% 的最大生命值
    -- 加强版：僵尸成长倍率 从第21关开始，每关增加 38% 的最大生命值和攻击力
    local hpMultiplier = 1
    if currentLevel > 20 then
        hpMultiplier = 1 + (currentLevel - 20) * 0.38
    end

    local finalHP = math.floor(config.HP * hpMultiplier)
    -- Attack no longer scales with level
    local finalAttack = math.floor(config.Attack)

    loadAnimation("Walk", config.Anims.Walk)
    loadAnimation("Eat", config.Anims.Eat)

    humanoid.MaxHealth = finalHP
    humanoid.Health = finalHP
    humanoid.WalkSpeed = 0
    -- 动态血条与防具逻辑
    local dropPart = zombie:FindFirstChild("Drop", true)
    local baseZombieHP = 270
    local hasDropped = false

    local hpBillboard = Instance.new("BillboardGui")
    hpBillboard.Name = "HPBar"
    hpBillboard.Size = UDim2.new(0, 50, 0, 6)
    hpBillboard.StudsOffset = Vector3.new(0, 2.5, 0)
    hpBillboard.AlwaysOnTop = true
    hpBillboard.MaxDistance = 80
    hpBillboard.Enabled = false

    local bgFrame = Instance.new("Frame")
    bgFrame.Size = UDim2.new(1, 0, 1, 0)
    bgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bgFrame.BackgroundTransparency = 0.5
    Instance.new("UICorner", bgFrame).CornerRadius = UDim.new(0, 4)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Parent = bgFrame
    bgFrame.Parent = hpBillboard

    local fillFrame = Instance.new("Frame")
    fillFrame.Size = UDim2.new(1, 0, 1, 0)
    fillFrame.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    Instance.new("UICorner", fillFrame).CornerRadius = UDim.new(0, 4)
    fillFrame.Parent = bgFrame

    hpBillboard.Parent = zombie:FindFirstChild("Head") or rootPart

    humanoid.HealthChanged:Connect(function(newHealth)
        if newHealth < finalHP and newHealth > 0 then
            hpBillboard.Enabled = true
            local ratio = math.clamp(newHealth / finalHP, 0, 1)
            fillFrame.Size = UDim2.new(ratio, 0, 1, 0)

            if finalHP > baseZombieHP and newHealth > baseZombieHP then
                fillFrame.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
            else
                fillFrame.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
            end
        else
            hpBillboard.Enabled = false
        end

        if dropPart and finalHP > baseZombieHP then
            if not hasDropped and newHealth <= baseZombieHP and newHealth > 0 then
                hasDropped = true
                dropPart.Anchored = false
                dropPart.CanCollide = true

                for _, joint in pairs(zombie:GetDescendants()) do
                    if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
                        if joint.Part0 == dropPart or joint.Part1 == dropPart then
                            joint:Destroy()
                        end
                    end
                end

                local randomX = math.random(-8, 8)
                local randomZ = math.random(-8, 8)
                dropPart.AssemblyLinearVelocity = Vector3.new(randomX, 15, randomZ)

                task.delay(1, function()
                    if dropPart then dropPart:Destroy() end
                end)
            end
        end
    end)

    local currentState = "None"
    local function switchState(newState)
        if currentState == newState then return end
        if animTracks[currentState] then animTracks[currentState]:Stop() end
        if animTracks[newState] then
            animTracks[newState]:Play()
            local speedMult = plot:GetAttribute("GameSpeed") or 1
            local slowMultiplier = GetZombieSlowMultiplier(zombie)
            if newState == "Walk" then
                animTracks[newState]:AdjustSpeed(1.5 * speedMult * slowMultiplier)
            else
                animTracks[newState]:AdjustSpeed(1.0 * speedMult)
            end
        end
        currentState = newState
    end

    plot:SetAttribute("ActiveZombies", (plot:GetAttribute("ActiveZombies") or 0) + 1)
    zombie.Parent = Workspace

    task.spawn(function()
        switchState("Walk")
        task.wait()

        local riseTime = 2.5
        local currentRiseTime = 0
        while currentRiseTime < riseTime do
            if IsBattleCancelled(plot, player) then
                if zombie then zombie:Destroy() end
                return
            end

            local speedMult = plot:GetAttribute("GameSpeed") or 1
            local dt = task.wait(0.03)
            currentRiseTime += (dt * speedMult)

            local alpha = math.clamp(currentRiseTime / riseTime, 0, 1)
            rootPart.CFrame = startCFrame:Lerp(targetCFrame, alpha)
        end

        for _, part in pairs(zombie:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" or part.Name == "Torso" or part.Name == "UpperTorso" then
                    part.CanCollide = true
                else
                    part.CanCollide = false
                end
            end
        end

        rootPart.Anchored = false

        pcall(function()
            rootPart:SetNetworkOwner(nil)
        end)

        local landWaitTime = 0
        while humanoid.FloorMaterial == Enum.Material.Air and landWaitTime < 1 do
            if IsBattleCancelled(plot, player) then
                if zombie then zombie:Destroy() end
                return
            end
            landWaitTime += task.wait(0.07)
        end
        task.wait(0.2)

        for _, part in pairs(zombie:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CollisionGroup = "Zombies"
            end
        end

        humanoid.WalkSpeed = config.Speed * GetZombieSlowMultiplier(zombie)

        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = {zombie}

        local currentTargetPos = endBlock.Position
        local hasReachedEndBlock = false
        local hasReachedHouseEnd = false
        local laneRowNum = tonumber(rowNum)

        local function correctZombieLane()
            if hasReachedHouseEnd or not rootPart or not rootPart.Parent then
                return
            end

            local rootFlat = getFlatVector(rootPart.Position)
            local alongLane = (rootFlat - laneStartFlat):Dot(laneDirection)
            local laneCenterFlat = laneStartFlat + laneDirection * alongLane
            local lateralOffset = (rootFlat - laneCenterFlat).Magnitude
            if lateralOffset <= LANE_CORRECTION_DEADZONE then
                return
            end

            local correctionAlpha = lateralOffset >= LANE_CORRECTION_HARD_OFFSET and 1 or 0.45
            local correctedFlat = rootFlat:Lerp(laneCenterFlat, correctionAlpha)
            local correctedPosition = Vector3.new(correctedFlat.X, rootPart.Position.Y, correctedFlat.Z)
            rootPart.CFrame = CFrame.lookAt(correctedPosition, correctedPosition + laneDirection)

            local velocity = rootPart.AssemblyLinearVelocity
            local forwardVelocity = laneDirection * velocity:Dot(laneDirection)
            rootPart.AssemblyLinearVelocity = forwardVelocity + Vector3.new(0, velocity.Y, 0)
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end

        local function isPlantInZombieLane(plantModel)
            if not laneRowNum then
                return true
            end

            return getCombatPlantRow(plantModel) == laneRowNum
        end

        local timeAccumulated = config.AttackInterval

        while zombie and zombie.Parent and humanoid and humanoid.Health > 0 do
            if IsBattleCancelled(plot, player) then
                if zombie then zombie:Destroy() end
                break
            end

            local speedMult = plot:GetAttribute("GameSpeed") or 1
            local dt = task.wait(0.1 / speedMult)
            timeAccumulated += (dt * speedMult)
            local slowMultiplier = GetZombieSlowMultiplier(zombie)

            if currentState == "Walk" then
                if animTracks["Walk"] then animTracks["Walk"]:AdjustSpeed(1.5 * speedMult * slowMultiplier) end
                humanoid.WalkSpeed = config.Speed * speedMult * slowMultiplier
            elseif currentState == "Eat" then
                if animTracks["Eat"] then animTracks["Eat"]:AdjustSpeed(1.0 * speedMult) end
                humanoid.WalkSpeed = 0
            end

            correctZombieLane()
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
                if hitModel
                    and hitModel:GetAttribute("IsCombatPlant")
                    and not hitModel:GetAttribute("IsDead")
                    and isPlantInZombieLane(hitModel)
                then
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
                    -- 使用经过 38% 倍率放大的最终攻击力
                    currentPlantHP = currentPlantHP - finalAttack
                    local plantDetail = ItemConfig.Plants[targetPlant.Name]
                    if plantDetail and plantDetail.ReactiveOnDamaged then
                        PlantCombatAI.TriggerDamagedReactiveAttack(
                            targetPlant,
                            plantDetail,
                            targetPlant:GetAttribute("MutationLevel") or 1,
                            plot
                        )
                    end

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
                                -- 只有在没有初始记录的情况下才记录，防止把受击过程中的中间状态记下来
                                if p:GetAttribute("OriginalTransparency") == nil then
                                    p:SetAttribute("OriginalTransparency", p.Transparency)
                                end
                                p.Transparency = 1 -- 死亡消失
                            elseif p:IsA("ParticleEmitter") or p:IsA("Light") or p:IsA("Beam") or p:IsA("Highlight") or p:IsA("Trail") then
                                if p:GetAttribute("OriginalEnabled") == nil then
                                    p:SetAttribute("OriginalEnabled", p.Enabled)
                                end
                                p.Enabled = false
                            end
                        end
                    end
                end
            else
                humanoid.WalkSpeed = config.Speed * speedMult * slowMultiplier
                humanoid:MoveTo(currentTargetPos)
                switchState("Walk")
            end
        end

        -- 由于手动撤退会调用 obj:Destroy()，在此处增加安全判断，防止访问已销毁的实例
        if zombie and zombie.Parent and humanoid and humanoid.Parent and humanoid.Health <= 0 and not zombie:GetAttribute("DeathRewardProcessed") then
            zombie:SetAttribute("DeathRewardProcessed", true)
            plot:SetAttribute("ZombiesDefeated", (plot:GetAttribute("ZombiesDefeated") or 0) + 1)
            PlayerDataManager.AddPassQuestProgress(player, PassQuestConfig.TaskIds.DefeatZombies, 1)
            SyncBattleProgress(player, plot, true)

            if activeSessions[player.UserId] then
                activeSessions[player.UserId].TotalKills += 1
            end

            local dropPos = rootPart.Position + Vector3.new(0, 3, 0)

            plot:SetAttribute("LastZombieDeathPos", rootPart.Position)
            -- 动态掉落逻辑
            -- 以 200 血（普通僵尸基础血量）为 1 倍掉落基准
            local dropMultiplier = math.max(1, finalHP / 200)

            -- 计算掉落数量和单价
            local coinCount = math.random(1, 2) + math.floor(dropMultiplier / 5)
            local coinValue = math.floor(math.random(10, 20) * dropMultiplier)

            if coinCount > 5 then
                coinValue = math.floor(coinValue * (coinCount / 5))
                coinCount = 5
            end

            local valuePerCoin = math.floor(coinValue / coinCount)
            if valuePerCoin < 1 then valuePerCoin = 1 end
            local totalDropValue = valuePerCoin * coinCount

            CoinDropService.DropCoins(player, dropPos, 1, totalDropValue)

            local ZombieBoxService = require(script.Parent.ZombieBoxService)
            if math.random(1, 100) == 1 then
                ZombieBoxService.SpawnBox(player, dropPos)
            end


            humanoid:Destroy()
            rootPart.Anchored = false

            for _, p in pairs(zombie:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide = true
                    p.CanTouch = false
                    p.CanQuery = false
                    p.CollisionGroup = "Corpses"
                end
            end

            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            rootPart.AssemblyAngularVelocity = rootPart.CFrame.RightVector * -8

            task.spawn(function()
                local dieTime = 1.5
                local currentDieTime = 0
                while currentDieTime < dieTime do
                    local sm = plot:GetAttribute("GameSpeed") or 1
                    currentDieTime += task.wait(0.1) * sm
                end

                if zombie and zombie.Parent then
                    local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
                    for _, p in pairs(zombie:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.Color = Color3.fromRGB(50, 50, 50)
                            TweenService:Create(p, fadeInfo, {Transparency = 1}):Play()
                        end
                    end

                    task.wait(0.5)
                    if zombie and zombie.Parent then
                        zombie:Destroy()
                    end
                end
            end)
        end

        plot:SetAttribute("ActiveZombies", math.max(0, (plot:GetAttribute("ActiveZombies") or 0) - 1))
    end)
    return true
end

function ZombieService.StartLevel(plot, levelId, player)
    if IsBattleCancelled(plot, player) then return end

    local levelData = LevelConfig[levelId] or ZombieService.GenerateInfiniteLevel(levelId)
    local totalZombies = CountLevelZombies(levelData)
    local shouldSpawnDancingZombie = math.random(1, 100) <= DANCING_ZOMBIE_LEVEL_CHANCE
    if shouldSpawnDancingZombie then
        totalZombies += 1
    end

    if not activeSessions[player.UserId] or levelId == 1 then
        activeSessions[player.UserId] = { TotalCoins = 0, TotalSeeds = 0, TotalKills = 0 }
    end
    local session = activeSessions[player.UserId]
    local battleToken = (plot:GetAttribute("BattleToken") or 0) + 1
    plot:SetAttribute("BattleToken", battleToken)
    plot:SetAttribute("LastZombieDeathPos", nil)

    plot:SetAttribute("IsLevelActive", true)
    plot:SetAttribute("IsGameOver", false)
    plot:SetAttribute("CurrentLevel", levelId)
    plot:SetAttribute("ActiveZombies", 0)
    plot:SetAttribute("TotalZombies", totalZombies)
    plot:SetAttribute("ZombiesDefeated", 0)

    SyncBattleProgress(player, plot, true, levelId)
    local MAX_ACTIVE_ZOMBIES = 30
    local pendingSpawnTasks = 0

    local function markPlannedZombieFailed()
        totalZombies = math.max(0, totalZombies - 1)
        plot:SetAttribute("TotalZombies", totalZombies)

        local defeated = plot:GetAttribute("ZombiesDefeated") or 0
        if defeated > totalZombies then
            plot:SetAttribute("ZombiesDefeated", totalZombies)
        end

        SyncBattleProgress(player, plot, true, levelId)
    end

    if shouldSpawnDancingZombie then
        pendingSpawnTasks += 1
        task.spawn(function()
            local function spawnDancingZombie()
                local speedMult = plot:GetAttribute("GameSpeed") or 1
                task.wait(math.random(10, 25) / 10 / speedMult)

                if IsBattleCancelled(plot, player, battleToken) then return end

                while (plot:GetAttribute("ActiveZombies") or 0) >= MAX_ACTIVE_ZOMBIES do
                    if IsBattleCancelled(plot, player, battleToken) then return end
                    task.wait(0.5)
                end

                if IsBattleCancelled(plot, player, battleToken) then return end

                local randomRow = math.random(1, 6)
                local spawned = ZombieService.SpawnZombie(plot, randomRow, DANCING_ZOMBIE_ID, player)
                if not spawned and not IsBattleCancelled(plot, player, battleToken) then
                    markPlannedZombieFailed()
                end
            end

            spawnDancingZombie()
            pendingSpawnTasks = math.max(0, pendingSpawnTasks - 1)
        end)
    end

    if levelData and levelData.Waves then
        for waveIndex, wave in ipairs(levelData.Waves) do
            -- 如果手动点击了撤退，立即跳出波次生成循环
            if IsBattleCancelled(plot, player, battleToken) then break end

            pendingSpawnTasks += 1
            task.spawn(function()
                local function runWaveSpawn()
                    if wave.Zombies then
                        for _, zombieGroup in ipairs(wave.Zombies) do
                            for i = 1, zombieGroup.Count do
                                if IsBattleCancelled(plot, player, battleToken) then return end

                                while (plot:GetAttribute("ActiveZombies") or 0) >= MAX_ACTIVE_ZOMBIES do
                                    if IsBattleCancelled(plot, player, battleToken) then return end
                                    task.wait(0.5)
                                end

                                if IsBattleCancelled(plot, player, battleToken) then return end

                                local randomRow = math.random(1, 6)
                                local spawned = ZombieService.SpawnZombie(plot, randomRow, zombieGroup.Type, player)
                                if not spawned and not IsBattleCancelled(plot, player, battleToken) then
                                    markPlannedZombieFailed()
                                end

                                local speedMult = plot:GetAttribute("GameSpeed") or 1
                                task.wait(math.random(10, 25) / 10 / speedMult)
                            end
                        end
                    end
                end

                runWaveSpawn()
                pendingSpawnTasks = math.max(0, pendingSpawnTasks - 1)
            end)

            if wave.NextWaveTime and wave.NextWaveTime > 0 then
                local currentWait = 0
                while currentWait < wave.NextWaveTime do
                    if IsBattleCancelled(plot, player, battleToken) then break end
                    local speedMult = plot:GetAttribute("GameSpeed") or 1
                    currentWait += task.wait(0.5) * speedMult
                end
            end
        end
    end

    repeat
        task.wait(1)
    until IsBattleCancelled(plot, player, battleToken)
        or (
            pendingSpawnTasks <= 0
            and (plot:GetAttribute("ActiveZombies") or 0) <= 0
            and (plot:GetAttribute("ZombiesDefeated") or 0) >= (plot:GetAttribute("TotalZombies") or totalZombies)
        )

    -- 逻辑：确保无论是手动还是正常递归，状态都能被正确清理
    if IsBattleCancelled(plot, player, battleToken) then
        -- 这里不需要重复调用 FinalSettlement，因为 LevelService 已经调过了
        -- 但我们需要确保 activeSessions 即使在手动时间也能被清理
        return
    end

    -- 正常通关逻辑
    local waveCoins = 100 + (levelId * 20)
    local waveSeeds = (levelId % 3 == 0) and 1 or 0

    session.TotalCoins += waveCoins
    session.TotalSeeds += waveSeeds

    PlayerDataManager.UnlockNextLevel(player, levelId)

   local AnalyticsService = game:GetService("AnalyticsService")
    local data = PlayerDataManager.GetPlayerData(player)
    local currentCoins = data and data.Coins or 0
    -- 正确获取 RandomSeed 的最新库存
    local currentSeeds = 0
    if data and data.Inventory and data.Inventory.Seeds then
        for _, sInfo in ipairs(data.Inventory.Seeds) do
            if sInfo.ID == "RandomSeed" then
                currentSeeds = sInfo.Quantity
                break
            end
        end
    end

    -- 记录金币获取 (Source)
    AnalyticsService:LogEconomyEvent(
        player,
        Enum.AnalyticsEconomyFlowType.Source, -- 表示获取/产出
        "Coins", -- 货币名称
        waveCoins, -- 增加的数量
        currentCoins, -- 变动后的余额
        Enum.AnalyticsEconomyTransactionType.Gameplay.Name, -- 交易场景 (转为字符串)
        "LevelClearReward_Level_" .. tostring(levelId) -- 物品/明细
    )

    -- 记录种子获取 (Source)
    if waveSeeds > 0 then
        AnalyticsService:LogEconomyEvent(
            player,
            Enum.AnalyticsEconomyFlowType.Source,
            "Seeds",
            waveSeeds,
            currentSeeds,
            Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
            "LevelClearReward_Level_" .. tostring(levelId)
        )
    end

    local boxDropPos = plot:GetAttribute("LastZombieDeathPos")
    if typeof(boxDropPos) == "Vector3" then
        boxDropPos += Vector3.new(0, 5, 0)
    elseif plot:IsA("Model") then
        boxDropPos = plot:GetPivot().Position + Vector3.new(0, 5, 0)
    elseif plot:IsA("BasePart") then
        boxDropPos = plot.Position + Vector3.new(0, 5, 0)
    else
        boxDropPos = Vector3.new(0, 5, 0)
    end

    local ZombieBoxService = require(script.Parent.ZombieBoxService)
    ZombieBoxService.SpawnBox(player, boxDropPos)

    local nextLevelId = levelId + 1
    print("[Level chain] Level " .. tostring(levelId) .. " cleared; starting next level in 2 seconds...")
    task.wait(2)
    if IsBattleCancelled(plot, player, battleToken) then
        print("[Level chain] Auto advance from Level " .. tostring(levelId) .. " cancelled because the battle token changed.")
        return
    end
    ZombieService.StartLevel(plot, nextLevelId, player)
end

function ZombieService.FinalSettlement(player, plot, isVictory)
    local session = activeSessions[player.UserId]
    local lastLevel = plot:GetAttribute("CurrentLevel") or 1

    if not session then
        -- 如果 session 已经没了，说明已经结算过了，直接重置状态
        plot:SetAttribute("IsLevelActive", false)
        SyncBattleProgress(player, plot, false, lastLevel)
        return
    end

    local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
    local data = PlayerDataManager.GetPlayerData(player)

    local isNewRecord = data and lastLevel > (data.UnlockedLevel or 1)
    -- 埋点击代码
    if isVictory and isNewRecord then
        if lastLevel == 1 then
            AnalyticsService:LogFunnelStepEvent(player, "Progression", nil, 1, "Cleared_Level_1")
            AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 3, "Step_3_First_Victory")
        elseif lastLevel == 5 then
            AnalyticsService:LogFunnelStepEvent(player, "Progression", nil, 5, "Cleared_Level_5")
        elseif lastLevel == 10 then
            AnalyticsService:LogFunnelStepEvent(player, "Progression", nil, 10, "Cleared_Level_10")
        end
    end
    local showResultRE = ReplicatedStorage:FindFirstChild("ShowBattleResultRE")

    if showResultRE then
        showResultRE:FireClient(player, isVictory, lastLevel, isNewRecord, session.TotalKills, session.TotalCoins, session.TotalSeeds)
    end
    -- 埋点击代码：带数值的事件，记录单局击杀数
    if session.TotalKills > 0 then
        AnalyticsService:LogCustomEvent(player, "Level_Kill_Efficiency", session.TotalKills)
    end

    -- 清理缓存并释放锁定
    activeSessions[player.UserId] = nil
    plot:SetAttribute("IsLevelActive", false)
    SyncBattleProgress(player, plot, false, lastLevel)
end

function ZombieService.Init()
    pcall(function() PhysicsService:RegisterCollisionGroup("Zombies") end)
    pcall(function() PhysicsService:RegisterCollisionGroup("Corpses") end)
    pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)

    pcall(function()
        PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
        PhysicsService:CollisionGroupSetCollidable("Zombies", "Corpses", false)
        PhysicsService:CollisionGroupSetCollidable("Corpses", "Corpses", false)
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
                        safeLoadAnimation(animator, animId, tostring(zombieId) .. ".preload." .. tostring(animName))
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
function ZombieService.GenerateInfiniteLevel(levelId)
    -- 无尽模式固定阵容 直接复制第 20的配置，数量和种类不再随机
    local baseLevelConfig = LevelConfig[20]

    return {
        LevelName = "Infinite Challenge Level " .. levelId,
        Waves = baseLevelConfig.Waves
    }
end
-- 玩家退出时间强制清理战斗会话与僵尸
function ZombieService.CleanupPlayerBattle(player)
    local userId = player.UserId

    -- 1. 清理战斗会话记录，防止内存泄漏
    if activeSessions[userId] then
        activeSessions[userId] = nil
    end

    -- 2. 强力销毁该玩家地块关联的所有僵尸
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute("IsZombie") and obj:GetAttribute("OwnerId") == userId then
            obj:Destroy()
        end
    end
end
return ZombieService

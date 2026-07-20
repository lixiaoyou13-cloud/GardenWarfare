-- src/server/Services/ToolService.luau
local ToolService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local PlotService = require(script.Parent.PlotService)
local PlantCombatAI = require(script.Parent.PlantCombatAI)
local CombatRegistry = require(script.Parent.CombatRegistry)
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SET_REJECT_INTERACTION_REMOTE_NAME = "SetRejectInteractionRE"
local REJECT_INTERACTION_ATTRIBUTE = "RejectInteractionEnabled"
local STEALING_PLANT_ATTRIBUTE = "IsStealingPlant"
local VISUAL_EVENT_RADIUS = 220
local HIT_EFFECT_TEXTURE = "rbxassetid://243098098"
local HIT_EFFECT_COLOR = Color3.fromRGB(255, 215, 0)

local plantAttackVisualRE = ReplicatedStorage:FindFirstChild("PlantAttackVisualRE")
if not plantAttackVisualRE then
    plantAttackVisualRE = Instance.new("RemoteEvent")
    plantAttackVisualRE.Name = "PlantAttackVisualRE"
    plantAttackVisualRE.Parent = ReplicatedStorage
end

local function addVisualRecipient(recipients, recipientSet, player)
    if not player or recipientSet[player] then
        return
    end

    recipientSet[player] = true
    table.insert(recipients, player)
end

local function getCharacterRoot(player)
    local character = player and player.Character
    return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) or nil
end

local function collectVisualRecipients(ownerUserId, originPosition)
    local recipients = {}
    local recipientSet = {}

    if ownerUserId then
        addVisualRecipient(recipients, recipientSet, Players:GetPlayerByUserId(ownerUserId))
    end

    if typeof(originPosition) == "Vector3" then
        for _, player in ipairs(Players:GetPlayers()) do
            local rootPart = getCharacterRoot(player)
            if rootPart and (rootPart.Position - originPosition).Magnitude <= VISUAL_EVENT_RADIUS then
                addVisualRecipient(recipients, recipientSet, player)
            end
        end
    end

    return recipients
end

local function fireToolVisualEvent(ownerUserId, originPosition, ...)
    for _, player in ipairs(collectVisualRecipients(ownerUserId, originPosition)) do
        plantAttackVisualRE:FireClient(player, ...)
    end
end

local function GetCombatEditCost(player)
    local plot = PlotService.GetPlayerPlot(player)
    local currentLevel = plot and plot:GetAttribute("CurrentLevel") or 1
    currentLevel = math.max(1, tonumber(currentLevel) or 1)
    return 100 + (currentLevel - 1) * 100
end

local function ApplyKnockback(targetCharacter, attackerCharacter)
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
    local targetHum = targetCharacter:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not attackerRoot or not targetHum then return end

    local oldVelocity = targetRoot:FindFirstChild("KnockbackVelocity")
    local oldAttachment = targetRoot:FindFirstChild("KnockbackAttachment")

    if oldVelocity then oldVelocity:Destroy() end
    if oldAttachment then oldAttachment:Destroy() end

    local direction = (targetRoot.Position - attackerRoot.Position).Unit
    local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit

    local horizontalForce = 50
    local verticalForce = 35
    local duration = 0.15

    local knockbackVector = (flatDirection * horizontalForce) + Vector3.new(0, verticalForce, 0)

    local attachment = Instance.new("Attachment")
    attachment.Name = "KnockbackAttachment"
    attachment.Parent = targetRoot

    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Name = "KnockbackVelocity"
    linearVelocity.Attachment0 = attachment
    linearVelocity.MaxForce = 999999
    linearVelocity.VectorVelocity = knockbackVector
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVelocity.Parent = targetRoot

    targetHum.PlatformStand = true

    local mass = targetRoot.AssemblyMass
    local spinForce = mass * math.random(30, 50)
    local randomAxis = Vector3.new(
        math.random(-10, 10),
        math.random(-10, 10),
        math.random(-10, 10)
    ).Unit

    targetRoot:ApplyAngularImpulse(randomAxis * spinForce)

    task.delay(duration, function()
        if linearVelocity then linearVelocity:Destroy() end
        if attachment then attachment:Destroy() end
    end)

    task.delay(1, function()
        if targetHum and targetHum.Parent and targetHum.Health > 0 then
            targetHum.PlatformStand = false
        end
    end)
end

local function isCarryingAirdrop(player, character)
    if not player or not character then
        return false
    end

    local head = character:FindFirstChild("Head")
    if not head then
        return false
    end

    local airdropWeld = head:FindFirstChild("AirdropWeld")
    if not (airdropWeld and airdropWeld:IsA("WeldConstraint") and airdropWeld.Part1) then
        return false
    end

    local airdropBox = airdropWeld.Part1:FindFirstAncestorOfClass("Model")
    while airdropBox and airdropBox ~= Workspace do
        if airdropBox:GetAttribute("Carrier") ~= nil then
            break
        end
        airdropBox = airdropBox.Parent
    end

    return airdropBox
        and airdropBox:IsA("Model")
        and tonumber(airdropBox:GetAttribute("Carrier")) == player.UserId
end

local function canKnockbackPlayer(targetPlayer, targetCharacter)
    if not targetPlayer then
        return true
    end

    if targetPlayer:GetAttribute(REJECT_INTERACTION_ATTRIBUTE) ~= true then
        return true
    end

    if targetPlayer:GetAttribute(STEALING_PLANT_ATTRIBUTE) == true then
        return true
    end

    return isCarryingAirdrop(targetPlayer, targetCharacter)
end

function ToolService.Init()
    local setRejectInteractionRE = ReplicatedStorage:FindFirstChild(SET_REJECT_INTERACTION_REMOTE_NAME)
    if not setRejectInteractionRE then
        setRejectInteractionRE = Instance.new("RemoteEvent")
        setRejectInteractionRE.Name = SET_REJECT_INTERACTION_REMOTE_NAME
        setRejectInteractionRE.Parent = ReplicatedStorage
    end

    setRejectInteractionRE.OnServerEvent:Connect(function(player, enabled)
        player:SetAttribute(REJECT_INTERACTION_ATTRIBUTE, enabled == true)
    end)

    Players.PlayerRemoving:Connect(function(player)
        player:SetAttribute(REJECT_INTERACTION_ATTRIBUTE, nil)
        player:SetAttribute(STEALING_PLANT_ATTRIBUTE, nil)
    end)

    local shovelRE = Instance.new("RemoteEvent")
    shovelRE.Name = "ShovelActionRE"
    shovelRE.Parent = ReplicatedStorage

    shovelRE.OnServerEvent:Connect(function(player, targetObj, isCombatRecycle)
        if not targetObj or not targetObj.Parent then return end

        local character = player.Character
        if not character or character:GetAttribute("EquippedSeed") ~= "Tool_Shovel" then return end

        local targetPos = targetObj:IsA("Model") and (targetObj.PrimaryPart and targetObj.PrimaryPart.Position or targetObj:GetPivot().Position) or targetObj.Position
        local charPos = character.PrimaryPart and character.PrimaryPart.Position
        if not charPos then return end

        if (charPos - targetPos).Magnitude > 35 then return end

        -- 优先处理南瓜保护罩，只移除保护罩，不影响格子里的主植物。
        if targetObj:GetAttribute("IsPumpkinShield") == true then
            local lawnPart = targetObj.Parent
            if lawnPart and string.match(lawnPart.Name, "Lawn") then
                local gridName = lawnPart.Name
                local myPlot = PlotService.GetPlayerPlot(player)
                if myPlot ~= lawnPart.Parent.Parent then return end

                if myPlot:GetAttribute("IsLevelActive") then
                    if isCombatRecycle then
                        local cost = GetCombatEditCost(player)
                        if not PlayerDataManager.ConsumeCoins(player, cost) then
                            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                            if showNotifRE then
                                showNotifRE:FireClient(player, "Notice", "Not enough Sun! Need " .. tostring(cost) .. " Sun.")
                            end
                            return
                        end
                    else
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then
                            showNotifRE:FireClient(player, "Notice", "Cannot remove Pumpkin Shield during combat!")
                        end
                        return
                    end
                end

                local pData = PlayerDataManager.GetPlayerData(player)
                local combatInfo = pData and pData.CombatPlants and pData.CombatPlants[gridName]
                local shieldInfo = type(combatInfo) == "table" and combatInfo.PumpkinShield or nil
                local savedShieldMutation = type(shieldInfo) == "table" and tonumber(shieldInfo.Mutation) or nil
                local mutationLvl = tonumber(targetObj:GetAttribute("MutationLevel")) or savedShieldMutation or 1

                PlayerDataManager.GivePlant(player, targetObj.Name, 1, mutationLvl)
                PlayerDataManager.RemoveCombatPumpkinShield(player, gridName)

                lawnPart:SetAttribute("PumpkinShield", nil)
                if targetObj:GetAttribute("OccupiesEmptyGrid") == true or lawnPart:GetAttribute("OccupiedBy") == targetObj.Name then
                    lawnPart:SetAttribute("OccupiedBy", nil)
                    local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                    if prompt then prompt.Enabled = true end
                end

                targetObj:Destroy()
            end
            return
        end

        -- 回收战斗植物本体。
        if targetObj:GetAttribute("IsCombatPlant") then
            local lawnPart = targetObj.Parent
            if lawnPart and string.match(lawnPart.Name, "Lawn") then
                local gridName = lawnPart.Name
                local myPlot = PlotService.GetPlayerPlot(player)
                if myPlot ~= lawnPart.Parent.Parent then return end

                if myPlot:GetAttribute("IsLevelActive") then
                    -- 战斗中铲除扣费校验
                    if isCombatRecycle then
                        local cost = GetCombatEditCost(player)
                        if not PlayerDataManager.ConsumeCoins(player, cost) then
                            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                            if showNotifRE then
                                showNotifRE:FireClient(player, "Notice", "Not enough Sun! Need " .. tostring(cost) .. " Sun.")
                            end
                            return -- 直接拦截回收操作
                        end
                    else
                        -- 兜底拦截：如果客户端恶意绕过弹窗
                        local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                        if showNotifRE then
                            showNotifRE:FireClient(player, "Notice", "Cannot remove plants during combat!")
                        end
                        return
                    end
                end

                local pData = PlayerDataManager.GetPlayerData(player)
                local combatInfo = pData.CombatPlants and pData.CombatPlants[gridName]
                local plantIdToReturn = combatInfo and combatInfo.PlantId or targetObj.Name
                local mutationLvl = (combatInfo and combatInfo.Mutation) or targetObj:GetAttribute("MutationLevel") or 1

                -- 静默发奖：战斗植物退回背包
                PlayerDataManager.GivePlant(player, plantIdToReturn, 1, mutationLvl)
                PlayerDataManager.RemoveCombatPlant(player, gridName)

                local hasPumpkinShield = lawnPart:GetAttribute("PumpkinShield") ~= nil
                lawnPart:SetAttribute("OccupiedBy", hasPumpkinShield and "PumpkinShield" or nil)
                local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then prompt.Enabled = true end

                targetObj:Destroy()
            end
            return
        end

        -- 分支 2：回收农田植物/种子
        local plantedOnSoilName = targetObj:GetAttribute("PlantedOn")
        if plantedOnSoilName then
            if targetObj:GetAttribute("IsMature") then
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then showNotifRE:FireClient(player, "Notice", "Harvest mature plants directly. Cannot use shovel!") end
                return
            end

            local plot = targetObj.Parent and targetObj.Parent.Parent
            if not plot or PlotService.GetPlayerPlot(player) ~= plot then return end

            local soilsFolder = plot:FindFirstChild("Soils")
            local soilPart = soilsFolder and soilsFolder:FindFirstChild(plantedOnSoilName)

            if soilPart then
                local pData = PlayerDataManager.GetPlayerData(player)
                local plantedInfo = pData.PlantedPlants and pData.PlantedPlants[plantedOnSoilName]
                local seedIdToReturn = plantedInfo and plantedInfo.SeedId or string.gsub(targetObj.Name, "_Plant", "")

                -- 追加传入了参数 `true`，抑制全屏的获得横幅提示和礼花
                PlayerDataManager.GiveSeed(player, seedIdToReturn, 1, true)
                PlayerDataManager.RemovePlantedPlant(player, plantedOnSoilName)

                local prompt = soilPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then
                    prompt.ActionText ="Plant"
                    prompt.Enabled = true
                end
                targetObj:Destroy()
            end
        end
    end)

    -- 武器近战攻击判定
    local weaponAttackRE = Instance.new("RemoteEvent")
    weaponAttackRE.Name = "WeaponAttackRE"
    weaponAttackRE.Parent = ReplicatedStorage

   weaponAttackRE.OnServerEvent:Connect(function(player, hitTargets)
        local character = player.Character
        if not character or character:GetAttribute("EquippedSeed") ~= "Tool_WeaponBlock" then return end

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not rootPart then return end

        if type(hitTargets) ~= "table" then return end

        local damagedZombies = {}
        local damagedPlayers = {}

        for _, targetModel in ipairs(hitTargets) do
            if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then continue end

            local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
            local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart

            if not targetHum or targetHum.Health <= 0 or not targetRoot then continue end

            local distance = (rootPart.Position - targetRoot.Position).Magnitude
            if distance > 16 then
                continue
            end

            -- 僵尸受击判定
            if targetModel:GetAttribute("IsZombie") and targetModel:GetAttribute("OwnerId") == player.UserId then
                if not damagedZombies[targetModel] then
                    damagedZombies[targetModel] = true

                    targetHum.Health = math.max(0, targetHum.Health - 25)

                    if PlantCombatAI.ShowDamageText then
                        PlantCombatAI.ShowDamageText(targetModel, 25)
                    end

                    fireToolVisualEvent(
                        player.UserId,
                        targetRoot.Position,
                        "Hit",
                        targetModel,
                        nil,
                        targetRoot.Position + Vector3.new(0, 1, 0),
                        HIT_EFFECT_TEXTURE,
                        HIT_EFFECT_COLOR,
                        player.UserId
                    )
                end

            -- Player PVP 受击击飞判定
            elseif targetModel ~= character then
                local enemyPlayer = Players:GetPlayerFromCharacter(targetModel)
                local isDummy = (targetModel.Name == "Dummy")

                if (enemyPlayer or isDummy) and not damagedPlayers[targetModel] then
                    if enemyPlayer and not canKnockbackPlayer(enemyPlayer, targetModel) then
                        continue
                    end

                    damagedPlayers[targetModel] = true

                    fireToolVisualEvent(
                        player.UserId,
                        targetRoot.Position,
                        "Hit",
                        targetModel,
                        nil,
                        targetRoot.Position + Vector3.new(0, 1, 0),
                        HIT_EFFECT_TEXTURE,
                        HIT_EFFECT_COLOR,
                        player.UserId
                    )

                    ApplyKnockback(targetModel, character)

                    local enemyHead = targetModel:FindFirstChild("Head")
                    if enemyHead then
                        local airdropWeld = enemyHead:FindFirstChild("AirdropWeld")
                        if airdropWeld and airdropWeld.Part1 then
                            local airdropBox = airdropWeld.Part1.Parent
                            while airdropBox and airdropBox ~= Workspace do
                                if airdropBox:GetAttribute("Carrier") then break end
                                airdropBox = airdropBox.Parent
                            end

                            if not airdropBox or not airdropBox:IsA("Model") then
                                airdropBox = airdropWeld.Part1:FindFirstAncestorOfClass("Model")
                            end

                            if airdropBox then
                                airdropWeld:Destroy()

                                if targetHum and targetHum:GetAttribute("WalkSpeedBeforeAirdrop") then
                                    targetHum.WalkSpeed = targetHum:GetAttribute("WalkSpeedBeforeAirdrop")
                                    targetHum:SetAttribute("WalkSpeedBeforeAirdrop", nil)
                                end

                                for _, p in pairs(airdropBox:GetDescendants()) do
                                    if p:IsA("BasePart") then
                                        p.CanCollide = true
                                        p.Massless = false
                                    end
                                end

                                if airdropBox.PrimaryPart then
                                    airdropBox.PrimaryPart:SetNetworkOwner(nil)
                                    airdropBox.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 50, 0)
                                    airdropBox.PrimaryPart.AssemblyAngularVelocity = Vector3.new(math.random(-20,20), math.random(-20,20), math.random(-20,20))

                                    local prompt = airdropBox.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
                                    if prompt then
                                        prompt.Enabled = true
                                    end
                                end

                                airdropBox:SetAttribute("Carrier", nil)
                                if not CollectionService:HasTag(airdropBox, "AirdropBox") then
                                    CollectionService:AddTag(airdropBox, "AirdropBox")
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    -- 樱桃炸弹：服务端接收投掷请求、生成特效与范围伤害
    -- 樱桃炸弹：空中抛物线动画与范围爆炸
    local throwBombRE = ReplicatedStorage:FindFirstChild("ThrowBombRE")
    if not throwBombRE then
        throwBombRE = Instance.new("RemoteEvent")
        throwBombRE.Name = "ThrowBombRE"
        throwBombRE.Parent = ReplicatedStorage
    end

   throwBombRE.OnServerEvent:Connect(function(player, equippedItem, targetPosition)
        local character = player.Character
        if not character then return end
        if character:GetAttribute("EquippedSeed") ~= equippedItem then return end

        -- 点击：解析真正的物品 ID 和 变异等级
        -- 客户端传来的 equippedItem 格式通常是 "Plant_CherryBomb_1"
        local plantId = "CherryBomb"
        local mutationLevel = 1

        local parts = string.split(equippedItem, "_")
        if parts[1] == "Plant" and parts[2] then
            plantId = parts[2]
            mutationLevel = tonumber(parts[3]) or 1
        elseif equippedItem == "CherryBomb" then
            plantId = "CherryBomb"
        end

        local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
        local plantConfig = ItemConfig.Plants[plantId]
        if not plantConfig then return end
        if typeof(targetPosition) ~= "Vector3" then return end

        local plot = PlotService.GetPlayerPlot(player)
        local characterRoot = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
        if not plot or not characterRoot then return end

        -- 使用解析出的 plantId 和 mutationLevel 进行扣除
        if not PlayerDataManager.ConsumePlant(player, plantId, 1, mutationLevel) then
            return -- 如果库存不足扣除失败，则不扔炸弹
        end

        -- 扣除成功后，服务端只广播表现指令，真实伤害仍在落点结算。
        task.spawn(function()
            local startPos = characterRoot.Position + Vector3.new(0, 2, 0)
            local height = 15
            local duration = 0.5
            fireToolVisualEvent(
                player.UserId,
                startPos,
                "ThrownPlantVisual",
                plantId,
                startPos,
                targetPosition,
                height,
                duration,
                player.UserId
            )

            task.wait(duration)

            -- 落地瞬间：客户端播放爆炸表现，服务端做范围伤害结算。
            local effectName = plantConfig.ExplosionEffect
            if effectName then
                fireToolVisualEvent(
                    player.UserId,
                    targetPosition,
                    "EffectBurst",
                    effectName,
                    CFrame.new(targetPosition + Vector3.new(0, 1.5, 0)),
                    player.UserId
                )
            end
            -- 4. 落地瞬间：群体范围扣血
            local radius = plantConfig.ExplosionRadius or 18
            local damage = plantConfig.ExplosionDamage or 2500

            local registryTargets = CombatRegistry.CollectZombiesInRadius(plot, targetPosition, radius)

            for _, target in ipairs(registryTargets) do
                local targetModel = target.Model
                local targetHum = target.Humanoid
                if targetModel and targetHum and targetHum.Health > 0 then
                    targetHum.Health = math.max(0, targetHum.Health - damage)

                        -- 伤害飘字
                    if PlantCombatAI.ShowDamageText then
                        PlantCombatAI.ShowDamageText(targetModel, damage)
                    end
                end
            end
        end)
    end)

    print("Server: ToolService loaded; recycle prompts are force-silent.")
end

return ToolService

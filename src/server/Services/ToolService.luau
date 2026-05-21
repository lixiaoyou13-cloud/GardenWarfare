-- src/server/Services/ToolService.luau
local ToolService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local PlotService = require(script.Parent.PlotService)
local PlantCombatAI = require(script.Parent.PlantCombatAI)
local CollectionService = game:GetService("CollectionService") 
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

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

function ToolService.Init()
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

        -- ==========================================
        -- 【分支 1：回收战斗植物】
        -- ==========================================
        if targetObj:GetAttribute("IsCombatPlant") then
            local lawnPart = targetObj.Parent
            if lawnPart and string.match(lawnPart.Name, "Lawn") then
                local gridName = lawnPart.Name
                local myPlot = PlotService.GetPlayerPlot(player)
                if myPlot ~= lawnPart.Parent.Parent then return end

                if myPlot:GetAttribute("IsLevelActive") then
                    -- 👇 [🌟 新增：战斗中铲除扣费校验]
                    if isCombatRecycle then
                        -- 如果身上金币(阳光)不足 1000
                        if not PlayerDataManager.ConsumeCoins(player, 1000) then
                            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                            if showNotifRE then 
                                showNotifRE:FireClient(player, "Notice", "Not enough Sun!") 
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
                
                lawnPart:SetAttribute("OccupiedBy", nil)
                local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then prompt.Enabled = true end
                
                targetObj:Destroy()
            end
            return
        end

        -- ==========================================
        -- 【分支 2：回收农田植物/种子】
        -- ==========================================
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
 
    -- ==========================================
    -- [武器近战攻击判定]
    -- ==========================================
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

            -- ==========================================
            -- [僵尸受击判定]
            -- ==========================================
            if targetModel:GetAttribute("IsZombie") and targetModel:GetAttribute("OwnerId") == player.UserId then
                if not damagedZombies[targetModel] then
                    damagedZombies[targetModel] = true
                    
                    targetHum.Health = math.max(0, targetHum.Health - 25)

                    if PlantCombatAI.ShowDamageText then
                        PlantCombatAI.ShowDamageText(targetModel, 25)
                    end

                    if not targetModel:GetAttribute("IsFlashing") then
                        targetModel:SetAttribute("IsFlashing", true)
                        local originalColors = {}
                        for _, p in pairs(targetModel:GetDescendants()) do
                            if p:IsA("BasePart") then
                                originalColors[p] = p.Color
                                p.Color = Color3.fromRGB(255, 80, 80)
                            end
                        end
                        task.delay(0.15, function()
                            if targetModel and targetModel.Parent then
                                for p, color in pairs(originalColors) do
                                    if p and p.Parent then p.Color = color end
                                end
                                targetModel:SetAttribute("IsFlashing", false)
                            end
                        end)
                    end

                    if targetRoot then
                        local effectPart = Instance.new("Part")
                        effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
                        effectPart.Transparency = 1
                        effectPart.Anchored = true
                        effectPart.CanCollide = false
                        effectPart.Position = targetRoot.Position + Vector3.new(0, 1, 0)
                        effectPart.Parent = Workspace
                        
                        local attachment = Instance.new("Attachment", effectPart)
                        local particles = Instance.new("ParticleEmitter", attachment)
                        particles.Texture = "rbxassetid://243098098" 
                        particles.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
                        particles.Size = NumberSequence.new(1, 0)
                        particles.Rate = 0
                        particles.Speed = NumberRange.new(5, 10)
                        particles.Lifetime = NumberRange.new(0.1, 0.3)
                        particles:Emit(15) 
                        
                        game:GetService("Debris"):AddItem(effectPart, 1.5)
                    end
                end

            -- ==========================================
            -- [玩家 PVP 受击击飞判定]
            -- ==========================================
            elseif targetModel ~= character then
                local enemyPlayer = Players:GetPlayerFromCharacter(targetModel)
                local isDummy = (targetModel.Name == "Dummy")
                
                if (enemyPlayer or isDummy) and not damagedPlayers[targetModel] then
                    damagedPlayers[targetModel] = true
                    
                    if not targetModel:GetAttribute("IsFlashing") then
                        targetModel:SetAttribute("IsFlashing", true)
                        local originalColors = {}
                        for _, p in pairs(targetModel:GetDescendants()) do
                            if p:IsA("BasePart") then
                                originalColors[p] = p.Color
                                p.Color = Color3.fromRGB(255, 80, 80) 
                            end
                        end
                        task.delay(0.15, function()
                            if targetModel and targetModel.Parent then
                                for p, color in pairs(originalColors) do
                                    if p and p.Parent then p.Color = color end
                                end
                                targetModel:SetAttribute("IsFlashing", false)
                            end
                        end)
                    end

                    local effectPart = Instance.new("Part")
                    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
                    effectPart.Transparency = 1
                    effectPart.Anchored = true
                    effectPart.CanCollide = false
                    effectPart.Position = targetRoot.Position + Vector3.new(0, 1, 0)
                    effectPart.Parent = Workspace
                    
                    local attachment = Instance.new("Attachment", effectPart)
                    local particles = Instance.new("ParticleEmitter", attachment)
                    particles.Texture = "rbxassetid://243098098" 
                    particles.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
                    particles.Size = NumberSequence.new(1.5, 0) 
                    particles.Rate = 0
                    particles.Speed = NumberRange.new(10, 20) 
                    particles.Lifetime = NumberRange.new(0.2, 0.4)
                    particles:Emit(20) 
                    
                    game:GetService("Debris"):AddItem(effectPart, 1.5)

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
    
    print("服务端：ToolService 加载完毕！回收提示强制静默功能已上线！")
end

return ToolService
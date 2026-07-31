-- src/server/Services/CombatService.luau
local CombatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))
local PlantCombatAI = require(script.Parent.PlantCombatAI)
local CombatRegistry = require(script.Parent.CombatRegistry)

local TUTORIAL_AUTO_DEPLOY_PLANT_ID = "Peashooter"
local TUTORIAL_AUTO_DEPLOY_MIN_STEP = 5
local TUTORIAL_AUTO_DEPLOY_MAX_STEP = 6
local TUTORIAL_AUTO_DEPLOY_LAWNS = {
	Lawn2_1 = true,
	Lawn3_1 = true,
	Lawn4_1 = true,
	Lawn5_1 = true,
	Lawn6_1 = true,
}

-- 校验新手教程自动补位部署，避免客户端伪造 plantId 免费生成任意植物。
local function canUseTutorialAutoDeploy(player, lawnName, plantId)
	if plantId ~= TUTORIAL_AUTO_DEPLOY_PLANT_ID or TUTORIAL_AUTO_DEPLOY_LAWNS[lawnName] ~= true then
		return false
	end

	local data = PlayerDataManager.GetPlayerData(player)
	if type(data) ~= "table" then
		return false
	end

	local tutorialStep = math.floor(tonumber(data.TutorialStep) or 0)
	if tutorialStep < TUTORIAL_AUTO_DEPLOY_MIN_STEP or tutorialStep > TUTORIAL_AUTO_DEPLOY_MAX_STEP then
		return false
	end

	local combatPlants = data.CombatPlants
	if type(combatPlants) ~= "table" then
		return false
	end

	for gridName, combatInfo in pairs(combatPlants) do
		if gridName ~= lawnName
			and type(combatInfo) == "table"
			and combatInfo.PlantId == TUTORIAL_AUTO_DEPLOY_PLANT_ID
		then
			return true
		end
	end

	return false
end

-- 判断植物是否为南瓜保护罩这类覆盖型防御植物。
local function isPumpkinShieldPlant(plantId)
	local detail = ItemConfig.Plants and ItemConfig.Plants[plantId]
	return detail and detail.IsPumpkinShield == true
end

-- 判断草坪是否只有南瓜保护罩，没有内部主植物。
local function isPumpkinShieldOnlyLawn(lawnPart)
	if not (lawnPart and lawnPart:GetAttribute("PumpkinShield")) then
		return false
	end

	local occupiedBy = lawnPart:GetAttribute("OccupiedBy")
	return occupiedBy == nil or isPumpkinShieldPlant(occupiedBy)
end

-- 清理空地南瓜转为保护普通植物后的占空标记。
local function clearPumpkinShieldEmptyOccupancy(lawnPart)
	if not (lawnPart and lawnPart:GetAttribute("PumpkinShield")) then
		return
	end

	for _, child in ipairs(lawnPart:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("IsPumpkinShield") == true then
			child:SetAttribute("OccupiesEmptyGrid", nil)
		end
	end
end

-- 通过配置里的模型名查找植物模型，兼容配置 ID 和资源命名不一致的植物。
local function findPlantModelTemplate(itemModelsFolder, plantId, itemDetail)
	if not itemModelsFolder then
		return nil
	end

	local modelName = (itemDetail and itemDetail.ModelName) or plantId
	return itemModelsFolder:FindFirstChild(modelName .. "_Plant")
		or itemModelsFolder:FindFirstChild(modelName)
		or itemModelsFolder:FindFirstChild(plantId .. "_Plant")
		or itemModelsFolder:FindFirstChild(plantId)
end

-- 没有变异的植物固定使用普通形态。
local function normalizePlantMutation(plantId, mutationLevel)
	local detail = ItemConfig.Plants and ItemConfig.Plants[plantId]
	if detail and detail.NoMutation == true then
		return 1
	end

	return math.max(1, math.floor(tonumber(mutationLevel) or 1))
end

-- 判断是否为模型自身的一次性 VFX 容器。
local function isModelVFXContainer(part)
	return part and part:IsA("BasePart") and string.upper(part.Name) == "VFX"
end

-- 独立发射定位点必须保持静止，避免动画模型解除锚定后受重力下落。
local function isStaticProjectileOrigin(part)
	return part and part:IsA("BasePart") and string.lower(part.Name) == "pos"
end

-- 把未参与骨骼/关节的 VFX 容器固定到主节点，防止进入战斗后掉落。
local function weldModelVFXContainer(part, rootPart)
	if not (part and rootPart) or part == rootPart then
		return
	end

	local weld = part:FindFirstChild("ModelVFXWeld")
	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = "ModelVFXWeld"
		weld.Parent = part
	end

	weld.Part0 = rootPart
	weld.Part1 = part
end

-- 按配置和变异等级计算战斗植物生命上限。
local function getCombatPlantMaxHP(plantId, mutationLevel)
	local itemDetail = ItemConfig.Plants and ItemConfig.Plants[plantId]
	if not itemDetail then
		return nil
	end

	local mLevel = normalizePlantMutation(plantId, mutationLevel)
	local stats = ItemConfig.MutationStats[mLevel] or ItemConfig.MutationStats[1]
	local healthMul = tonumber(stats and stats.HealthMul) or 1
	return math.floor((itemDetail.HP or 300) * healthMul), mLevel
end

-- 生成战斗植物
function CombatService.SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel, options)
	local itemDetail = ItemConfig.Plants[plantId]
	local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
	if not itemModelsFolder then return nil end
	local combatModel = findPlantModelTemplate(itemModelsFolder, plantId, itemDetail)

	if not combatModel or not itemDetail then return nil end

	options = type(options) == "table" and options or {}
	local isShield = options.AsPumpkinShield == true or isPumpkinShieldPlant(plantId)
	mutationLevel = normalizePlantMutation(plantId, mutationLevel)

	local newFighter = combatModel:Clone()
	newFighter.Name = plantId
	newFighter:SetAttribute("PlantId", plantId)
	newFighter:SetAttribute("IsCombatPlant", true)
	newFighter:SetAttribute("IsPumpkinShield", isShield == true)
	newFighter:SetAttribute("Health", currentHP)
	newFighter:SetAttribute("MaxHealth", maxHP)
	newFighter:SetAttribute("MutationLevel", mutationLevel or 1)
	newFighter:SetAttribute("OwnerId", lawnPart.Parent and lawnPart.Parent.Parent and lawnPart.Parent.Parent:GetAttribute("OwnerId") or 0)

	newFighter:SetAttribute("GridName", lawnPart.Name)
	if newFighter.PrimaryPart then newFighter.PrimaryPart:SetAttribute("GridName", lawnPart.Name) end
	local plot = lawnPart.Parent.Parent
	local rowNum = tonumber(string.match(lawnPart.Name, "^Lawn(%d+)_"))

	local function registerFighter()
		if not newFighter.Parent or (newFighter:GetAttribute("Health") or 0) <= 0 or newFighter:GetAttribute("IsDead") then
			return
		end

		local rootPart = newFighter.PrimaryPart or newFighter:FindFirstChildWhichIsA("BasePart")
		CombatRegistry.RegisterPlant(plot, newFighter, rowNum, rootPart)
	end

    -- 统一死亡结算中枢
    -- 所有的死亡、复活标签记、爆炸起爆全部在这里完成
	newFighter:GetAttributeChangedSignal("Health"):Connect(function()
		if (newFighter:GetAttribute("Health") or 0) <= 0 then
			CombatRegistry.UnregisterPlant(newFighter)
            -- 1. 标签记需要重建（防跨关卡假死）
			newFighter:SetAttribute("NeedsRebuild", true)

            -- 2. 如果配置了爆炸类型，死亡瞬间立刻引爆
            if itemDetail.ExplosionType then
                PlantCombatAI.TriggerExplosion(newFighter, itemDetail, mutationLevel)
            end
		else
			registerFighter()
		end
	end)

	newFighter.Destroying:Connect(function()
		CombatRegistry.UnregisterPlant(newFighter)
	end)

	newFighter.AncestryChanged:Connect(function(_, parent)
		if not parent then
			CombatRegistry.UnregisterPlant(newFighter)
		end
	end)

	local plotNum = tonumber(string.match(lawnPart.Parent.Parent.Name, "%d+")) or 1
	local yRotation = (plotNum <= 4) and CFrame.Angles(0, math.rad(0), 0) or CFrame.Angles(0, math.rad(0), 0)
	local spawnCFrame = lawnPart.CFrame * CFrame.new(0, lawnPart.Size.Y/2 + (newFighter.PrimaryPart and newFighter.PrimaryPart.Size.Y/2 or 2), 0) * yRotation

	if newFighter:IsA("Model") then
		newFighter:PivotTo(spawnCFrame)
	else
		newFighter.CFrame = spawnCFrame
	end

	local MUTATION_TAGS = { Glow = true, Lightning = true, HolyLight = true }
	local hasAnyAnim = itemDetail.IdleAnimId or itemDetail.AttackAnimation or itemDetail.RiseAnimation

	local cachedParts = CombatRegistry.GetCachedParts(newFighter)
	for _, part in pairs(cachedParts.BaseParts) do
		if part:IsA("BasePart") then
			local isVFXContainer = isModelVFXContainer(part)
			local isProjectileOrigin = isStaticProjectileOrigin(part)
			-- 记录原始透明度
			if not part:GetAttribute("OriginalTransparency") then
				part:SetAttribute("OriginalTransparency", part.Transparency)
			end
			-- 强制隐藏特效容器
			if MUTATION_TAGS[part.Name] or isVFXContainer then
				part.Transparency = 1
				part:SetAttribute("OriginalTransparency", 1)
			end
			part.CanCollide = false
			if isVFXContainer then
				part.CanTouch = false
				part.CanQuery = false
				weldModelVFXContainer(part, newFighter.PrimaryPart)
			else
				part.CanQuery = true
			end
			part.Anchored = (isProjectileOrigin or not hasAnyAnim or part == newFighter.PrimaryPart)
		end
	end

	EffectUtil.ApplyMutationEffects(newFighter, mutationLevel)
	CombatRegistry.RefreshCachedParts(newFighter)
	newFighter.Parent = lawnPart
	local shieldOccupiesEmptyGrid = false
	if isShield then
		lawnPart:SetAttribute("PumpkinShield", plantId)
		if not lawnPart:GetAttribute("OccupiedBy") then
			lawnPart:SetAttribute("OccupiedBy", plantId)
			newFighter:SetAttribute("OccupiesEmptyGrid", true)
			shieldOccupiesEmptyGrid = true
		end
	else
		lawnPart:SetAttribute("OccupiedBy", plantId)
		clearPumpkinShieldEmptyOccupancy(lawnPart)
	end

	local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Enabled = isShield and shieldOccupiesEmptyGrid end

	registerFighter()

	-- 动画统一交给 PlantCombatAI 管理，避免 CombatService 和 AI 重复 LoadAnimation
	if itemDetail.CanAttack then
		PlantCombatAI.StartShooterAI(newFighter, itemDetail, mutationLevel, plot)
	else
		PlantCombatAI.StartIdleAnimation(newFighter, itemDetail, plot)
	end
	if type(itemDetail.FrontHeal) == "table" then
		PlantCombatAI.StartFrontHealAI(newFighter, itemDetail, mutationLevel, plot)
	end

	return newFighter
end

local function SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel)
	return CombatService.SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel)
end

-- 避免延迟加载函数：专门对付循环依赖
-- 生成已保存的主植物与南瓜保护罩。
local function spawnSavedCombatEntry(lawnPart, plantInfo)
	if not (lawnPart and type(plantInfo) == "table") then
		return
	end

	local plantId = plantInfo.PlantId
	if type(plantId) == "string" and plantId ~= "" and not isPumpkinShieldPlant(plantId) then
		local maxHP, mutationLevel = getCombatPlantMaxHP(plantId, plantInfo.Mutation or 1)
		if maxHP then
			CombatService.SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, mutationLevel)
		end
	end

	local shieldInfo = plantInfo.PumpkinShield
	if type(shieldInfo) ~= "table" and isPumpkinShieldPlant(plantId) then
		shieldInfo = {
			PlantId = plantId,
			Mutation = plantInfo.Mutation or 1,
		}
	end

	local shieldPlantId = type(shieldInfo) == "table" and shieldInfo.PlantId or nil
	if type(shieldPlantId) == "string" and isPumpkinShieldPlant(shieldPlantId) then
		local maxHP, mutationLevel = getCombatPlantMaxHP(shieldPlantId, shieldInfo.Mutation or 1)
		if maxHP then
			CombatService.SpawnCombatPlant(lawnPart, shieldPlantId, maxHP, maxHP, mutationLevel, {
				AsPumpkinShield = true,
			})
		end
	end
end

local function GetPlotService()
	return require(script.Parent.PlotService)
end

-- 导出的公共功能

function CombatService.Init()
	if not ReplicatedStorage:FindFirstChild("ShowTipRE") then
		local showTipRE = Instance.new("RemoteEvent")
		showTipRE.Name = "ShowTipRE"
		showTipRE.Parent = ReplicatedStorage
	end
	local plotsFolder = Workspace:WaitForChild("Plots")

	Players.PlayerAdded:Connect(function(player)
		local data = PlayerDataManager.GetPlayerData(player)
		local waitLimit = 0
		while not data and waitLimit < 20 do task.wait(0.5); waitLimit += 1; data = PlayerDataManager.GetPlayerData(player) end
		if not data then return end

		local plot = nil
		for i = 1, 20 do
			plot = GetPlotService().GetPlayerPlot(player) -- 使用避免延迟加载
			if plot then break end
			task.wait(0.5)
		end
		if not plot or not data.CombatPlants then return end

		local lawnFolder = plot:FindFirstChild("Lawn")
		if not lawnFolder then return end

		for gridName, plantInfo in pairs(data.CombatPlants) do
			local lawnPart = lawnFolder:FindFirstChild(gridName)
			if lawnPart then
				spawnSavedCombatEntry(lawnPart, plantInfo)
			end
		end
	end)

	-- 草坪部署逻辑
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if not string.match(plot.Name, "Plot") then continue end
		local lawnFolder = plot:FindFirstChild("Lawn")
		if not lawnFolder then continue end

		for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
			if lawnPart:IsA("BasePart") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Deploy"; prompt.ObjectText = "Lawn"; prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false; prompt.MaxActivationDistance = 8; prompt.Parent = lawnPart

				prompt.Triggered:Connect(function(player)
					local myPlot = GetPlotService().GetPlayerPlot(player)
					if myPlot ~= plot then return end
					local occupiedBy = lawnPart:GetAttribute("OccupiedBy")
					local shieldOnlyLawn = isPumpkinShieldOnlyLawn(lawnPart)
					if occupiedBy and not shieldOnlyLawn then return end

					local character = player.Character
					local equippedCompositeId = character and character:GetAttribute("EquippedSeed")

					-- 如果没有装备物品，或者装备的不是战斗植物，则打开背包
					if not equippedCompositeId or string.split(equippedCompositeId, "_")[1] ~= "Plant" then
						local openInvRE = ReplicatedStorage:FindFirstChild("OpenInventoryRE")
						if openInvRE then
							openInvRE:FireClient(player, "PlantPage")
						end
						return
					end

					local parts = string.split(equippedCompositeId, "_")
					local plantId, targetMutation = parts[2], tonumber(parts[3]) or 1
					targetMutation = normalizePlantMutation(plantId, targetMutation)

					-- 拦截投掷类植物部署：樱桃炸弹不允许种在地上，只能丢
					local itemDetailCheck = ItemConfig.Plants[plantId]
					if shieldOnlyLawn then
						if itemDetailCheck and itemDetailCheck.IsPumpkinShield == true then
							return
						end
						if itemDetailCheck and itemDetailCheck.DisallowPumpkinShield == true then
							local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
							if showNotifRE then
								showNotifRE:FireClient(player, "Notice", "Pumpkin Shield cannot cover this plant.")
							end
							return
						end
					end
					if itemDetailCheck and itemDetailCheck.IsThrowable then
						local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
						if showTipRE then showTipRE:FireClient(player, "Click to throw this plant!") end
						return
					end

					if PlayerDataManager.ConsumePlant(player, plantId, 1, targetMutation) then
						local AnalyticsService = game:GetService("AnalyticsService")
						local itemDetail = ItemConfig.Plants[plantId]
						local maxHP = getCombatPlantMaxHP(plantId, targetMutation) or (itemDetail.HP or 300)

						AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 2, "Step_2_First_Deploy")
						local newPlant = CombatService.SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation, {
							AsPumpkinShield = itemDetail and itemDetail.IsPumpkinShield == true,
						})
						if not newPlant then
							PlayerDataManager.GivePlant(player, plantId, 1, targetMutation, true)
							return
						end

						if itemDetail and itemDetail.IsPumpkinShield == true then
							PlayerDataManager.AddCombatPumpkinShield(player, lawnPart.Name, plantId, maxHP, targetMutation)
						else
							PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
						end
					end
				end)
			end
		end
	end


	-- 接收教程部署指令
	local tutorialDeployRE = ReplicatedStorage:FindFirstChild("TutorialDeployRE") or Instance.new("RemoteEvent")
	tutorialDeployRE.Name = "TutorialDeployRE"
	tutorialDeployRE.Parent = ReplicatedStorage

	tutorialDeployRE.OnServerEvent:Connect(function(player, lawnName, plantId)
		if type(lawnName) ~= "string" or type(plantId) ~= "string" then return end
		if not canUseTutorialAutoDeploy(player, lawnName, plantId) then return end

		local myPlot = GetPlotService().GetPlayerPlot(player)
		if not myPlot then return end

		local lawnFolder = myPlot:FindFirstChild("Lawn")
		local lawnPart = lawnFolder and lawnFolder:FindFirstChild(lawnName)
		if not lawnPart or lawnPart:GetAttribute("OccupiedBy") then return end

		local itemDetail = ItemConfig.Plants[TUTORIAL_AUTO_DEPLOY_PLANT_ID]
		if not itemDetail then return end

		local targetMutation = 1
		local baseMaxHP = itemDetail.HP or 300
		local stats = ItemConfig.MutationStats[targetMutation] or ItemConfig.MutationStats[1]
		local maxHP = math.floor(baseMaxHP * stats.HealthMul)

		SpawnCombatPlant(lawnPart, TUTORIAL_AUTO_DEPLOY_PLANT_ID, maxHP, maxHP, targetMutation)
		PlayerDataManager.AddCombatPlant(player, lawnPart.Name, TUTORIAL_AUTO_DEPLOY_PLANT_ID, maxHP, targetMutation)
	end)
end

-- 版：清晰场函数
function CombatService.ClearAllCombatPlants(player)
	local plot = GetPlotService().GetPlayerPlot(player)
	if not plot then return end
	local lawnFolder = plot:FindFirstChild("Lawn")
	if not lawnFolder then return end

	for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
		for _, child in ipairs(lawnPart:GetChildren()) do
			if child:GetAttribute("IsCombatPlant") then child:Destroy() end
		end
		lawnPart:SetAttribute("OccupiedBy", nil)
		lawnPart:SetAttribute("PumpkinShield", nil)
		local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then prompt.Enabled = true end
	end
end

-- 版：智能重新载入（彻底解决阵亡假死与被啃咬隐藏不恢复的问题）
function CombatService.ReloadSavedPlants(player)
	local data = PlayerDataManager.GetPlayerData(player)
	if not data or not data.CombatPlants then return end

	local plot = GetPlotService().GetPlayerPlot(player)
	local lawnFolder = plot and plot:FindFirstChild("Lawn")
	if not lawnFolder then return end

	for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
		if lawnPart:IsA("BasePart") then
			for _, child in ipairs(lawnPart:GetChildren()) do
				if child:GetAttribute("IsCombatPlant") then
					child:Destroy()
				end
			end
			lawnPart:SetAttribute("OccupiedBy", nil)
			lawnPart:SetAttribute("PumpkinShield", nil)
			local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then prompt.Enabled = true end
		end
	end

	for gridName, plantInfo in pairs(data.CombatPlants) do
		local lawnPart = lawnFolder:FindFirstChild(gridName)
		if lawnPart then
			spawnSavedCombatEntry(lawnPart, plantInfo)
		end
	end
end

return CombatService

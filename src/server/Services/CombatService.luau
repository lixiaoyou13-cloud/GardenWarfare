-- src/server/Services/CombatService.luau
local CombatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [🌟 核心修复：移除顶部的 PlotService 引用，防止循环依赖]
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local EffectUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EffectUtil"))
local PlantCombatAI = require(script.Parent.PlantCombatAI)

-- ==========================================
-- [核心：生成战斗植物]
-- ==========================================
local function SpawnCombatPlant(lawnPart, plantId, currentHP, maxHP, mutationLevel)
	local itemDetail = ItemConfig.Plants[plantId]
	local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
	local combatModel = itemModelsFolder:FindFirstChild(plantId .. "_Plant") or itemModelsFolder:FindFirstChild(plantId)
	
	if not combatModel or not itemDetail then return end

	local newFighter = combatModel:Clone()
	newFighter.Name = plantId
	newFighter:SetAttribute("IsCombatPlant", true)
	newFighter:SetAttribute("Health", currentHP)
	newFighter:SetAttribute("MaxHealth", maxHP)
	newFighter:SetAttribute("MutationLevel", mutationLevel or 1)
	
	newFighter:SetAttribute("GridName", lawnPart.Name)
	if newFighter.PrimaryPart then newFighter.PrimaryPart:SetAttribute("GridName", lawnPart.Name) end

    -- 👇 [🌟 统一死亡结算中枢]
    -- 所有的死亡、复活标记、爆炸起爆全部在这里完成
	newFighter:GetAttributeChangedSignal("Health"):Connect(function()
		if (newFighter:GetAttribute("Health") or 0) <= 0 then
            -- 1. 标记需要重建（防跨关卡假死）
			newFighter:SetAttribute("NeedsRebuild", true)
            
            -- 2. 如果配置了爆炸类型，死亡瞬间立刻引爆！
            if itemDetail.ExplosionType then
                PlantCombatAI.TriggerExplosion(newFighter, itemDetail, mutationLevel)
            end
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

	for _, part in pairs(newFighter:GetDescendants()) do
		if part:IsA("BasePart") then 
			-- 记录原始透明度
			if not part:GetAttribute("OriginalTransparency") then
				part:SetAttribute("OriginalTransparency", part.Transparency)
			end
			-- 强制隐藏特效容器
			if MUTATION_TAGS[part.Name] then
				part.Transparency = 1
				part:SetAttribute("OriginalTransparency", 1)
			end
			part.CanCollide = false 
			part.CanQuery = true 
			part.Anchored = (not hasAnyAnim or part == newFighter.PrimaryPart)
		end
	end
	
	EffectUtil.ApplyMutationEffects(newFighter, mutationLevel)
	newFighter.Parent = lawnPart
	lawnPart:SetAttribute("OccupiedBy", plantId)

	local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Enabled = false end

	local animator = newFighter:FindFirstChildOfClass("AnimationController") or newFighter:FindFirstChildOfClass("Humanoid")
	if animator then animator = animator:FindFirstChildOfClass("Animator") or Instance.new("Animator", animator) end

	if itemDetail.IdleAnimId and itemDetail.IdleAnimId ~= "" and animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = itemDetail.IdleAnimId
		local idleTrack = animator:LoadAnimation(anim)
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack.Looped = true
		idleTrack:Play() 
	end

	local plot = lawnPart.Parent.Parent
    
    -- 👇 [🌟 独立挂载射击 AI]：去掉了 elseif 互斥限制，因为爆炸逻辑已经移交给死亡结算中枢了
	if itemDetail.CanAttack then
		PlantCombatAI.StartShooterAI(newFighter, itemDetail, mutationLevel, plot)
	end
end

-- ==========================================
-- [🌟 延迟加载函数：专门对付循环依赖]
-- ==========================================
local function GetPlotService()
	return require(script.Parent.PlotService)
end

-- ==========================================
-- [导出的公共功能]
-- ==========================================

function CombatService.Init()
	-- [🌟 新增代码：游戏启动时就创建好 ShowTipRE]
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
			plot = GetPlotService().GetPlayerPlot(player) -- 使用延迟加载
			if plot then break end
			task.wait(0.5)
		end
		if not plot or not data.CombatPlants then return end

		local lawnFolder = plot:FindFirstChild("Lawn")
		if not lawnFolder then return end

		for gridName, plantInfo in pairs(data.CombatPlants) do
			local lawnPart = lawnFolder:FindFirstChild(gridName)
			if lawnPart then
				local itemDetail = ItemConfig.Plants[plantInfo.PlantId]
				if itemDetail then
					local baseMaxHP = itemDetail.HP or 300
					local mLevel = plantInfo.Mutation or 1
					local stats = ItemConfig.MutationStats[mLevel] or ItemConfig.MutationStats[1]
					local maxHP = math.floor(baseMaxHP * stats.HealthMul)
					SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP, mLevel)
				end
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
				prompt.ActionText = "Deploy"; prompt.ObjectText = "Lawn"; prompt.KeyboardKeyCode = Enum.KeyCode.F
				prompt.RequiresLineOfSight = false; prompt.MaxActivationDistance = 8; prompt.Parent = lawnPart
				prompt.Triggered:Connect(function(player)
					local myPlot = GetPlotService().GetPlayerPlot(player)
					
					-- 1. 拦截：如果不是自己的地块，直接返回
					if myPlot ~= plot then return end
					
					-- 2. 拦截：如果该格子已经被占用了，直接返回
					if lawnPart:GetAttribute("OccupiedBy") then return end

					
					local character = player.Character
					local equippedCompositeId = character and character:GetAttribute("EquippedSeed")
					
					-- [🌟 修改代码：如果没有装备物品，或者装备的不是战斗植物 (Plant)，则打开背包并提示]
					if not equippedCompositeId or string.split(equippedCompositeId, "_")[1] ~= "Plant" then 
						local openInvRE = ReplicatedStorage:FindFirstChild("OpenInventoryRE")
						if openInvRE then
							-- 传入 "PlantPage" 参数，告诉客户端我们要打开的是植物页面
							openInvRE:FireClient(player, "PlantPage")
						end
						return 
					end

					local parts = string.split(equippedCompositeId, "_")
					local plantId, targetMutation = parts[2], tonumber(parts[3]) or 1

					if PlayerDataManager.ConsumePlant(player, plantId, 1, targetMutation) then
						local AnalyticsService = game:GetService("AnalyticsService")
						local data = PlayerDataManager.GetPlayerData(player)
						local remainingQuantity = 0
						if data and data.Inventory and data.Inventory.Plants then
							for _, pInfo in ipairs(data.Inventory.Plants) do
								if pInfo.ID == plantId and (pInfo.Mutation or 1) == targetMutation then
									remainingQuantity = pInfo.Quantity
									break
								end
							end
						end
						
						-- 记录植物消耗 (Sink)
						AnalyticsService:LogEconomyEvent(
							player, 
							Enum.AnalyticsEconomyFlowType.Sink, 
							"Plants", 
							1, 
							remainingQuantity,
							Enum.AnalyticsEconomyTransactionType.Gameplay.Name, 
							plantId 
						)
											
						-- 同步发送自定义埋点
						AnalyticsService:LogCustomEvent(player, "PlantDeployed_"..plantId, 1)
						local itemDetail = ItemConfig.Plants[plantId]
						local baseMaxHP = itemDetail.HP or 300
						local stats = ItemConfig.MutationStats[targetMutation] or ItemConfig.MutationStats[1]
						local maxHP = math.floor(baseMaxHP * stats.HealthMul)
						AnalyticsService:LogFunnelStepEvent(player, "Onboarding", nil, 2, "Step_2_First_Deploy")
						SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation)
						PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
					end
				end)
			end
		end
	end
	-- ==========================================
	-- [🌟 新增：专门接收教程的草坪战斗植物部署指令]
	-- ==========================================
	local tutorialDeployRE = ReplicatedStorage:FindFirstChild("TutorialDeployRE") or Instance.new("RemoteEvent")
	tutorialDeployRE.Name = "TutorialDeployRE"
	tutorialDeployRE.Parent = ReplicatedStorage

	tutorialDeployRE.OnServerEvent:Connect(function(player, lawnName, plantId)
		local myPlot = GetPlotService().GetPlayerPlot(player)
		if not myPlot then return end
		
		local lawnFolder = myPlot:FindFirstChild("Lawn")
		local lawnPart = lawnFolder and lawnFolder:FindFirstChild(lawnName)
		if not lawnPart or lawnPart:GetAttribute("OccupiedBy") then return end
		
		local itemDetail = ItemConfig.Plants[plantId]
		if not itemDetail then return end
		
		local targetMutation = 1
		local baseMaxHP = itemDetail.HP or 300
		local stats = ItemConfig.MutationStats[targetMutation] or ItemConfig.MutationStats[1]
		local maxHP = math.floor(baseMaxHP * stats.HealthMul)

		SpawnCombatPlant(lawnPart, plantId, maxHP, maxHP, targetMutation)
		PlayerDataManager.AddCombatPlant(player, lawnPart.Name, plantId, maxHP, targetMutation)
	end)
end

-- [🌟 修复版：清场函数]
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
		local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then prompt.Enabled = true end
	end
end

-- [🌟 修复版：智能重新载入（解决闪烁与复活假死问题）]
function CombatService.ReloadSavedPlants(player)
	local data = PlayerDataManager.GetPlayerData(player)
	if not data or not data.CombatPlants then return end
	
	local plot = GetPlotService().GetPlayerPlot(player)
	local lawnFolder = plot and plot:FindFirstChild("Lawn")
	if not lawnFolder then return end

	for gridName, plantInfo in pairs(data.CombatPlants) do
		local lawnPart = lawnFolder:FindFirstChild(gridName)
		if lawnPart then
			-- 检查是否已存在同种植物
			local existing = nil
			for _, c in ipairs(lawnPart:GetChildren()) do
				if c:GetAttribute("IsCombatPlant") then existing = c; break end
			end
			
			if existing and existing.Name == plantInfo.PlantId then 
				-- 👇 [🌟 核心修复：拦截假死与爆炸残留的植物]
				-- 只有真正存活且从未死过的植物，才允许保留并跳过重建（保留防闪烁优化）
				if not existing:GetAttribute("NeedsRebuild") and not existing:GetAttribute("Exploded") then
					continue 
				end
			end 

			if existing then existing:Destroy() end
			local itemDetail = ItemConfig.Plants[plantInfo.PlantId]
			if itemDetail then
				local baseMaxHP = itemDetail.HP or 300
				local mLevel = plantInfo.Mutation or 1
				local stats = ItemConfig.MutationStats[mLevel] or ItemConfig.MutationStats[1]
				local maxHP = math.floor(baseMaxHP * stats.HealthMul)
				SpawnCombatPlant(lawnPart, plantInfo.PlantId, maxHP, maxHP, mLevel)
			end
		end
	end
end

return CombatService
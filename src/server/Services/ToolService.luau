-- src/server/Services/ToolService.luau
local ToolService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local PlotService = require(script.Parent.PlotService)

function ToolService.Init()
    local shovelRE = Instance.new("RemoteEvent")
    shovelRE.Name = "ShovelActionRE"
    shovelRE.Parent = ReplicatedStorage

    shovelRE.OnServerEvent:Connect(function(player, targetObj)
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

                local pData = PlayerDataManager.GetPlayerData(player)
                local combatInfo = pData.CombatPlants and pData.CombatPlants[gridName]
                local plantIdToReturn = combatInfo and combatInfo.PlantId or targetObj.Name
                
                -- [🌟 修复变异吞噬 Bug]：精准读取该地块植物的变异等级
                local mutationLvl = (combatInfo and combatInfo.Mutation) or targetObj:GetAttribute("MutationLevel") or 1
                
                -- 带着变异等级返还
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
                if showNotifRE then showNotifRE:FireClient(player, "提示", "成熟的植物请直接收获，不能用铲子回收！") end
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
                
                PlayerDataManager.GiveSeed(player, seedIdToReturn, 1) 
                PlayerDataManager.RemovePlantedPlant(player, plantedOnSoilName)
                
                local prompt = soilPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then 
                    prompt.ActionText = "种植"
                    prompt.Enabled = true 
                end
                targetObj:Destroy()
            end
        end
    end)
    
    print("服务端：ToolService 加载完毕！变异回收逻辑加固完成！")
end

return ToolService
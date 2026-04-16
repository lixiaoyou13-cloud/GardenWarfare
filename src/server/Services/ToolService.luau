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
        
        local dist = (charPos - targetPos).Magnitude
        if dist > 25 then return end

        -- ==========================================
        -- 【分支 1：挖的是战斗植物 (草坪上的防线)】
        -- ==========================================
        if targetObj:GetAttribute("IsCombatPlant") then
            local lawnPart = targetObj.Parent
            if lawnPart and string.match(lawnPart.Name, "Lawn") then
                local gridName = lawnPart.Name
                
                local myPlot = PlotService.GetPlayerPlot(player)
                if myPlot ~= lawnPart.Parent.Parent then return end

                PlayerDataManager.RemoveCombatPlant(player, gridName)
                lawnPart:SetAttribute("OccupiedBy", nil)
                
                local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then prompt.Enabled = true end
                
                targetObj:Destroy()
            end
            return
        end

        -- ==========================================
        -- 【分支 2：挖的是农田里的植物/种子 (泥土上的作物)】
        -- ==========================================
        local plantedOnSoilName = targetObj:GetAttribute("PlantedOn")
        if plantedOnSoilName then
            -- [🌟 终极防作弊判定：如果是成熟的植物，绝对不准铲除！]
            if targetObj:GetAttribute("IsMature") then 
                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                if showNotifRE then
                    showNotifRE:FireClient(player, "提示", "成熟的植物请直接收获，不能用铲子铲除！")
                end
                return 
            end

            local plantsFolder = targetObj.Parent
            local plot = plantsFolder and plantsFolder.Parent
            if not plot then return end

            local myPlot = PlotService.GetPlayerPlot(player)
            if myPlot ~= plot then return end

            local soilsFolder = plot:FindFirstChild("Soils")
            local soilPart = soilsFolder and soilsFolder:FindFirstChild(plantedOnSoilName)
            
            if soilPart then
                PlayerDataManager.RemovePlantedPlant(player, plantedOnSoilName)
                
                local prompt = soilPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then 
                    prompt.ActionText = "种植"
                    prompt.Enabled = true 
                end
                
                targetObj:Destroy()
            end
            return
        end
    end)
    
    print("服务端：ToolService (铲子服务) 加载完毕！已实装成熟植物防挖锁！")
end

return ToolService
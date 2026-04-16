-- src/client/Services/ToolController.luau
local ToolController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

function ToolController.Init()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    
    mouse.Button1Down:Connect(function()
        local char = player.Character
        if not char or char:GetAttribute("EquippedSeed") ~= "Tool_Shovel" then return end
        
        local target = mouse.Target
        if target then
            local currentObj = target
            local foundPlant = nil
            
            while currentObj and currentObj ~= Workspace do
                local isCombat = currentObj:GetAttribute("IsCombatPlant")
                local isFarm = currentObj:GetAttribute("PlantedOn")
                local isMature = currentObj:GetAttribute("IsMature")
                
                -- [🌟 核心判定：战斗植物可以挖；农田植物必须是【未成熟】才能挖！]
                if isCombat or (isFarm and not isMature) then
                    foundPlant = currentObj
                    break
                end
                currentObj = currentObj.Parent
            end

            -- 只要找到了符合条件的目标本体，就呼叫服务端铲除！
            if foundPlant then
                local shovelRE = ReplicatedStorage:FindFirstChild("ShovelActionRE")
                if shovelRE then 
                    shovelRE:FireServer(foundPlant) 
                end
            end
        end
    end)
    
    print("客户端：ToolController (核心挖掘逻辑) 加载完毕！已限制成熟植物不可铲除！")
end

return ToolController
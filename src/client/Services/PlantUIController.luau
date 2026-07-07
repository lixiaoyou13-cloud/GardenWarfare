-- src/client/Services/PlantUIController.luau
local PlantUIController = {}
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

function PlantUIController.Init()
    local localPlayer = Players.LocalPlayer

    local function updatePlantUI(plant)
        local ownerId = plant:GetAttribute("OwnerId")
        local isMine = (ownerId == localPlayer.UserId)

        -- Bug：开启递归查找 (true)
        -- 因为 UI 面板被放在了 PrimaryPart(孙子层级) 里，不能直接 WaitForChild
        -- 我们用一个安全的小循环，不断深入查找它是否加载出来了
        local matureUI = nil
        for i = 1, 50 do -- 最多等 5 秒 (50 * 0.1)
            matureUI = plant:FindFirstChild("MatureUI", true)
            if matureUI then break end
            task.wait(0.1)
        end

        if matureUI then
            local statusLabel = matureUI:FindFirstChild("StatusLabel", true)
            if statusLabel then
                -- 身份识别变装
                if isMine then
                    statusLabel.Text = "Mature"
                    statusLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
                else
                    statusLabel.Text = "Stealable"
                    statusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
                end
            end
        end

        -- 2. 悄悄按键 F 的提示框文字 (仅对本地玩家生效)
        local soilName = plant:GetAttribute("PlantedOn")
        if soilName and plant.Parent and plant.Parent.Parent then
            local plot = plant.Parent.Parent
            local soilsFolder = plot:FindFirstChild("Soils")
            if soilsFolder then
                local soil = soilsFolder:FindFirstChild(soilName)
                if soil then
                    -- 同样的安全等待逻辑，确保找到按键
                    local prompt = nil
                    for i = 1, 50 do
                        prompt = soil:FindFirstChildOfClass("ProximityPrompt")
                        if prompt then break end
                        task.wait(0.1)
                    end

                    if prompt then
                        if isMine then
                            prompt.ActionText = "Harvest"
                        else
                            prompt.ActionText = "Steal"
                        end
                    end
                end
            end
        end
    end

    -- 监听游戏中途新长出来的植物
    Workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("Model") and desc:GetAttribute("IsMature") then
            updatePlantUI(desc)
        end
    end)

    -- 玩家刚上线时间，扫描地图上已经存在的成熟植物并替换视觉
    task.spawn(function()
    local plotsFolder = Workspace:WaitForChild("Plots", 5)
        if plotsFolder then
            for _, desc in pairs(plotsFolder:GetDescendants()) do
                if desc:IsA("Model") and desc:GetAttribute("IsMature") then
                    updatePlantUI(desc)
                end
            end
        end
    end)

    print("Client: PlantUIController (plant status display) loaded; steal-view assigned.")
end

return PlantUIController

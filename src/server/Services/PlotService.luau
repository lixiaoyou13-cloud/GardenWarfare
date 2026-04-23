-- src/server/Services/PlotService.luau
local PlotService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PlotUnlockConfig = require(ReplicatedStorage.Shared.PlotUnlockConfig)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local playerPlots = {}

function PlotService.AssignPlot(player)
    if playerPlots[player.UserId] then return playerPlots[player.UserId] end

    local plotsFolder = Workspace:WaitForChild("Plots")
    local chosenPlot = nil

    -- 寻找空闲地块
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not plot:GetAttribute("OwnerId") and string.match(plot.Name, "Plot") then
            plot:SetAttribute("OwnerId", player.UserId)
            chosenPlot = plot
            playerPlots[player.UserId] = plot
            break
        end
    end

    if chosenPlot then
       chosenPlot:SetAttribute("GameSpeed", 1) 
        
        -- 生成基地向日葵
        local BaseSunflowerService = require(script.Parent.BaseSunflowerService)
        BaseSunflowerService.SpawnSunflower(player, chosenPlot)

        -- 初始化并刷新这块基地里的泥土状态
        PlotService.UpdateSoilVisuals(player, chosenPlot)

        -- ==========================================
        -- [🌟 新增：生成玩家领地身份牌 (所有人可见)]
        -- ==========================================
        task.spawn(function()
            -- 找到基地的中心点（通常是出生点，如果没有就随便找个能挂载的零件）
            local spawnPart = chosenPlot:FindFirstChild("SpawnPoint") or chosenPlot:FindFirstChild("SpawnLocation") or chosenPlot:FindFirstChildWhichIsA("BasePart", true)
            
            if spawnPart and not spawnPart:FindFirstChild("OwnerBillboard") then
                local billboard = Instance.new("BillboardGui")
                billboard.Name = "OwnerBillboard"
                billboard.Size = UDim2.new(0, 320, 0, 85)
                -- 将身份牌悬浮在出生点正上方 25 格高的地方 (根据你的建筑高度自己微调 Y 轴数值)
                billboard.StudsOffset = Vector3.new(0, 25, 0) 
                billboard.AlwaysOnTop = true -- 开启穿透，隔着山或者墙也能看见
                billboard.MaxDistance = 250 -- 离得太远就隐藏，防止满屏幕乱糟糟

                -- 半透明黑色背景框
                local bgFrame = Instance.new("Frame")
                bgFrame.Size = UDim2.new(1, 0, 1, 0)
                bgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                bgFrame.BackgroundTransparency = 0.5
                local bgCorner = Instance.new("UICorner")
                bgCorner.CornerRadius = UDim.new(0, 16)
                bgCorner.Parent = bgFrame
                bgFrame.Parent = billboard

                -- 1. 玩家真实头像 (使用 Roblox 官方 API 拉取)
                local avatarImg = Instance.new("ImageLabel")
                avatarImg.Size = UDim2.new(0, 65, 0, 65)
                avatarImg.Position = UDim2.new(0, 10, 0.5, -32.5) -- 垂直居中，靠左
                avatarImg.BackgroundTransparency = 1
                -- 拉取高清的 420x420 大头贴
                local content, isReady = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                avatarImg.Image = content
                local avatarCorner = Instance.new("UICorner")
                avatarCorner.CornerRadius = UDim.new(1, 0) -- 圆形遮罩
                avatarCorner.Parent = avatarImg
                avatarImg.Parent = bgFrame

                -- 2. 装饰小图标 (例如：一个小房子、小皇冠或植物图标)
                local decIcon = Instance.new("ImageLabel")
                decIcon.Size = UDim2.new(0, 35, 0, 35)
                decIcon.Position = UDim2.new(0, 85, 0.5, -17.5)
                decIcon.BackgroundTransparency = 1
                decIcon.Image = "rbxassetid://10886326447" -- 🌟 [请在这里替换成你想用的家园图标 ID]
                decIcon.Parent = bgFrame

                -- 3. 玩家昵称 (使用 DisplayName 支持玩家自己改的名字)
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(1, -135, 1, 0)
                nameLabel.Position = UDim2.new(0, 125, 0, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = player.DisplayName 
                nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                nameLabel.TextStrokeTransparency = 0.4 -- 微微加一点描边，让白色文字在白天也能看清
                nameLabel.Font = Enum.Font.FredokaOne
                nameLabel.TextSize = 28
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.Parent = bgFrame

                -- 挂载！
                billboard.Parent = spawnPart
            end
        end)
        local dave = chosenPlot:FindFirstChild("CrazyDave")
        if dave then
            -- 寻找 Dave 身上的主零件来挂载提示符
            local targetPart = dave.PrimaryPart or dave:FindFirstChildWhichIsA("BasePart")
            if targetPart then
                -- 如果已经有了就不重复添加
                local existingPrompt = targetPart:FindFirstChildWhichIsA("ProximityPrompt")
                if not existingPrompt then
                    local prompt = Instance.new("ProximityPrompt")
                    prompt.Name = "ShopPrompt"
                    prompt.ActionText = "打开商店"
                    prompt.ObjectText = "疯狂戴夫"
                    prompt.KeyboardKeyCode = Enum.KeyCode.F -- 绑定按键 F
                    prompt.RequiresLineOfSight = false
                    prompt.MaxActivationDistance = 10 -- 触发距离
                    prompt.HoldDuration = 0 -- 瞬间触发，不需要长按
                    prompt.Parent = targetPart
                end
                
                -- 同理，如果想要点击也能打开，就加个 ClickDetector
                local existingClick = targetPart:FindFirstChildWhichIsA("ClickDetector")
                if not existingClick then
                    local clicker = Instance.new("ClickDetector")
                    clicker.MaxActivationDistance = 15
                    clicker.Parent = targetPart
                end
            else
                warn("服务端：CrazyDave 模型内找不到任何 BasePart，无法挂载交互组件！")
            end
        else
            warn("服务端：在地块 " .. chosenPlot.Name .. " 中未找到 CrazyDave！")
        end

        -- 设置玩家位置逻辑 (保持不变)
        local function teleportToPlot(character)
            task.wait(0.1)
            local rootPart = character:WaitForChild("HumanoidRootPart", 5)
            if not rootPart then return end

            local spawnPart = chosenPlot:FindFirstChild("SpawnPoint") or chosenPlot:FindFirstChild("SpawnLocation")
            
            if spawnPart and spawnPart:IsA("BasePart") then
                character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
            else
                character:PivotTo(chosenPlot:GetPivot() * CFrame.new(0, 5, 20))
            end
        end

        if player.Character then teleportToPlot(player.Character) end
        player.CharacterAdded:Connect(teleportToPlot)
    end
    
    return chosenPlot
end

function PlotService.GetPlayerPlot(player) 
    return playerPlots[player.UserId] 
end

function PlotService.Init()
    Players.PlayerAdded:Connect(function(player)
        task.wait(1) 
        PlotService.AssignPlot(player)
    end)
    
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            task.wait(1)
            PlotService.AssignPlot(player)
        end)
    end

    local setSpeedRE = ReplicatedStorage:FindFirstChild("SetSpeedRE") or Instance.new("RemoteEvent")
    setSpeedRE.Name = "SetSpeedRE"
    setSpeedRE.Parent = ReplicatedStorage
    setSpeedRE.OnServerEvent:Connect(function(player, speed)
        local plot = PlotService.GetPlayerPlot(player)
        if plot then
            plot:SetAttribute("GameSpeed", speed)
            setSpeedRE:FireClient(player, speed)
        end
    end)
    
    print("服务端：PlotService 戴夫交互组件配置完毕！")
end

-- [🌟 核心逻辑：刷新泥土状态与视觉效果]
function PlotService.UpdateSoilVisuals(player, plot)
    local unlockedCount = PlayerDataManager.GetUnlockedPlots(player)
    local targetUnlockId = unlockedCount + 1 -- 玩家当前只能解锁这块地（循序渐进）

    -- 遍历地块内所有的零件，找到泥土
    for _, soil in ipairs(plot:GetDescendants()) do
        if soil:IsA("BasePart") then
            -- 提取泥土名字中的数字 (假设你的泥土名叫 Soil1, Soil2...)
            local soilId = tonumber(string.match(soil.Name, "%d+"))
            
            if soilId and string.find(soil.Name, "Soil") then
                -- 如果是第一次运行，把泥土原来的材质/颜色保存下来，方便解锁后恢复
                if not soil:GetAttribute("OriginalColor") then
                    soil:SetAttribute("OriginalColor", soil.Color)
                end

                local prompt = soil:FindFirstChild("UnlockPrompt")

                if soilId <= unlockedCount then
                    -- 🟢 情况1：已解锁
                    soil:SetAttribute("IsUnlocked", true)
                    soil.Color = soil:GetAttribute("OriginalColor") -- 恢复原本颜色
                    if prompt then prompt:Destroy() end -- 移除购买提示

                elseif soilId == targetUnlockId then
                    -- 🟡 情况2：当前可解锁的下一块地
                    soil:SetAttribute("IsUnlocked", false)
                    soil.Color = Color3.fromRGB(124, 160, 64) -- 变成黄色

                    -- 挂载 F 键购买提示
                    if not prompt then
                        prompt = Instance.new("ProximityPrompt")
                        prompt.Name = "UnlockPrompt"
                        prompt.ActionText = "解锁土地"
                        prompt.KeyboardKeyCode = Enum.KeyCode.F
                        prompt.RequiresLineOfSight = false
                        prompt.MaxActivationDistance = 8
                        prompt.Parent = soil

                        -- 当玩家按下 F 键时触发购买
                        prompt.Triggered:Connect(function(triggerPlayer)
                            if triggerPlayer ~= player then return end -- 只有地块主人能买
                            local price = PlotUnlockConfig.UnlockPrices[soilId]
                            
                            -- 扣除金币，如果成功则解锁
                            if price and PlayerDataManager.ConsumeCoins(player, price) then
                                PlayerDataManager.IncrementUnlockedPlots(player)
                                PlotService.UpdateSoilVisuals(player, plot) -- 刷新所有土地状态
                            else
                                -- 这里你可以将来换成 UI 提示：金币不足
                                print("金币不足，需要: " .. tostring(price))
                            end
                        end)
                    end
                    -- 更新提示框上显示的价格
                    prompt.ObjectText = "价格: " .. tostring(PlotUnlockConfig.UnlockPrices[soilId])

                else
                    -- 🟢 情况3：未来才能解锁的地（跳级的地）
                    soil:SetAttribute("IsUnlocked", false)
                    soil.Color = Color3.fromRGB(22, 170, 46) -- 变成绿色
                    if prompt then prompt:Destroy() end -- 没有任何交互
                end
            end
        end
    end
end

return PlotService
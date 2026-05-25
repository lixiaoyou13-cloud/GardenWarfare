-- src/server/Services/PlotService.luau
local PlotService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PlotUnlockConfig = require(ReplicatedStorage.Shared.PlotUnlockConfig)
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local playerPlots = {}

local function ResetPlotForNextOwner(plot)
    local soilsFolder = plot:FindFirstChild("Soils")
    if soilsFolder then
        for _, soil in ipairs(soilsFolder:GetChildren()) do
            if soil:IsA("BasePart") and string.find(soil.Name, "Soil") then
                soil:SetAttribute("IsUnlocked", false)

                local unlockPrompt = soil:FindFirstChild("UnlockPrompt")
                if unlockPrompt then
                    unlockPrompt:Destroy()
                end

                -- 👇 [🌟 新增：玩家退出时清理木牌]
                local woodenSign = soil:FindFirstChild("WoodenSign")
                if woodenSign then
                    woodenSign:Destroy()
                end
                -- 👆 新增结束

                local plantPrompt = soil:FindFirstChild("PlantPrompt")
                if plantPrompt and plantPrompt:IsA("ProximityPrompt") then
                    plantPrompt.ActionText = "Plant"
                    plantPrompt.ObjectText = "Soil"
                    plantPrompt.Enabled = false
                    plantPrompt.HoldDuration = 0.5
                end
            end
        end
    end

    local lawnFolder = plot:FindFirstChild("Lawn")
    if lawnFolder then
        for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
            if lawnPart:IsA("BasePart") then
                lawnPart:SetAttribute("OccupiedBy", nil)
                local prompt = lawnPart:FindFirstChildOfClass("ProximityPrompt")
                if prompt then
                    prompt.Enabled = true
                end
            end
        end
    end

    local dave = plot:FindFirstChild("CrazyDave")
    if dave then
        local targetPart = dave.PrimaryPart or dave:FindFirstChildWhichIsA("BasePart")
        if targetPart then
            local prompt = targetPart:FindFirstChild("ShopPrompt")
            if prompt and prompt:IsA("ProximityPrompt") then
                prompt.ActionText = "Open Shop"
                prompt.ObjectText = "Crazy Dave"
                prompt.Enabled = true
            end
        end
    end
end

function PlotService.AssignPlot(player)
    if playerPlots[player.UserId] then return playerPlots[player.UserId] end

    PlayerDataManager.WaitForPlayerData(player)

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
        chosenPlot:SetAttribute("IsGameOver", false)
        chosenPlot:SetAttribute("IsLevelActive", false)

        ResetPlotForNextOwner(chosenPlot)
        
        -- 生成基地向日葵
        local BaseSunflowerService = require(script.Parent.BaseSunflowerService)
        BaseSunflowerService.SpawnSunflower(player, chosenPlot)

        -- 初始化并刷新这块基地里的泥土状态
        PlotService.UpdateSoilVisuals(player, chosenPlot)

        -- ==========================================
        -- [🌟 新增：生成玩家领地身份牌 (所有人可见)]
        -- ==========================================
      task.spawn(function()
        
            -- 获取头像数据
            local avatarUrl = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)

            -- ---------- 功能 A：恢复旧版的基地上方悬浮牌 (BillboardGui) ----------
           -- ---------- 功能 A：恢复旧版的基地上方悬浮牌 (BillboardGui) ----------
            -- 🚀 1. 改为查找基地内名为 "NameTag" 的模型或零件
            local nameTagObj = chosenPlot:FindFirstChild("NameTag", true)

            print("【排错】系统分配给玩家的地块是: " .. chosenPlot.Name .. " | 是否找到 NameTag: " .. tostring(nameTagObj ~= nil))
            local targetPart = nil
            
            if nameTagObj then
                if nameTagObj:IsA("Model") then
                    -- 【修改这里】：在找 BasePart 的时候加上 true，开启递归深度查找
                    targetPart = nameTagObj.PrimaryPart or nameTagObj:FindFirstChildWhichIsA("BasePart", true)
                elseif nameTagObj:IsA("BasePart") then
                    targetPart = nameTagObj
                end
            end

            -- 如果没有找到 NameTag，兜底使用原本的出生点
            if not targetPart then
                targetPart = chosenPlot:FindFirstChild("SpawnPoint") or chosenPlot:FindFirstChild("SpawnLocation") or chosenPlot:FindFirstChildWhichIsA("BasePart", true)
            end
            
            if targetPart then
                -- 清理可能残留的旧悬浮牌
                local existingBillboard = targetPart:FindFirstChild("OwnerBillboard")
                if existingBillboard then existingBillboard:Destroy() end

                local billboard = Instance.new("BillboardGui")
                billboard.Name = "OwnerBillboard"
                billboard.Size = UDim2.new(24, 0, 6, 0) 
                
                -- 🚀 2. 位置修改：悬浮在 NameTag 正上方 (可微调中间的 8 来改变高度)
                billboard.StudsOffset = Vector3.new(0, 20, 0) 
                
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = 250 

                -- 1. 背景框
                local bgFrame = Instance.new("Frame")
                bgFrame.Size = UDim2.new(1, 0, 1, 0)
                bgFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                bgFrame.BackgroundTransparency = 0.5
                local bgCorner = Instance.new("UICorner")
                bgCorner.CornerRadius = UDim.new(0.2, 0)
                bgCorner.Parent = bgFrame
                bgFrame.Parent = billboard

                -- 2. 玩家头像
                local avatarImg = Instance.new("ImageLabel")
                avatarImg.Size = UDim2.new(0.2, 0, 0.8, 0)
                avatarImg.Position = UDim2.new(0.05, 0, 0.1, 0)
                avatarImg.BackgroundTransparency = 1
                avatarImg.Image = avatarUrl
                local avatarCorner = Instance.new("UICorner")
                avatarCorner.CornerRadius = UDim.new(1, 0)
                avatarCorner.Parent = avatarImg
                avatarImg.Parent = bgFrame

                -- 3. 装饰小图标
                local decIcon = Instance.new("ImageLabel")
                decIcon.Size = UDim2.new(0.1, 0, 0.4, 0)
                decIcon.Position = UDim2.new(0.28, 0, 0.3, 0)
                decIcon.BackgroundTransparency = 1
                decIcon.Image = "rbxassetid://10886326447"
                decIcon.Parent = bgFrame

               -- 4. 玩家昵称
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
                nameLabel.Position = UDim2.new(0.4, 0, 0, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = player.DisplayName 
                nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                nameLabel.TextStrokeTransparency = 0.4
                nameLabel.Font = Enum.Font.FredokaOne
                nameLabel.TextScaled = true
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.Parent = bgFrame

                -- 👇 ============= 这里是关键修改区 ============= 👇
                
                -- 🚀 3. 显式指定 UI 要挂载的实体零件 (必须加这一句)
                billboard.Adornee = targetPart 
                
                billboard.Parent = targetPart
                
                -- 顺便打印一下到底挂在了哪个零件上，方便排错
                print("【UI生成】成功！已挂载至目标: " .. tostring(targetPart.Name))
            end

            -- ---------- 功能 B：额外功能 - 木牌上的表面显示 (SurfaceGui) ----------
            local paiModel = chosenPlot:FindFirstChild("pai", true)
            local targetPart = paiModel and paiModel:FindFirstChild("Text")


            
            if targetPart and targetPart:IsA("BasePart") then
                -- 清理旧的木牌 GUI
                if targetPart:FindFirstChild("PlayerIdentitySurfaceGui") then
                    targetPart.PlayerIdentitySurfaceGui:Destroy()
                end

                local surfaceGui = Instance.new("SurfaceGui")
                surfaceGui.Name = "PlayerIdentitySurfaceGui"
                surfaceGui.Face = Enum.NormalId.Front 
                surfaceGui.MaxDistance = 300 -- 您要求的300米可见
                surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
                surfaceGui.PixelsPerStud = 50

                -- 木牌头像 (70% 高度)
                local sImg = Instance.new("ImageLabel")
                sImg.Size = UDim2.new(1, 0, 0.7, 0)
                sImg.BackgroundTransparency = 1
                sImg.Image = avatarUrl
                sImg.ScaleType = Enum.ScaleType.Fit
                sImg.Parent = surfaceGui

                -- 木牌名称 (30% 高度)
                local sText = Instance.new("TextLabel")
                sText.Size = UDim2.new(1, 0, 0.3, 0)
                sText.Position = UDim2.new(0, 0, 0.7, 0)
                sText.BackgroundTransparency = 1
                sText.Text = player.DisplayName
                sText.TextColor3 = Color3.new(1, 1, 1)
                sText.TextScaled = true
                sText.Font = Enum.Font.FredokaOne
                sText.TextStrokeTransparency = 0.5
                sText.Parent = surfaceGui

                surfaceGui.Parent = targetPart
                print("【UI生成】头像获取完毕，开始创建牌子...2222222222222222222222222222")
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
                    prompt.ActionText = "Open Shop"
                    prompt.ObjectText = "Crazy Dave"
                    prompt.KeyboardKeyCode = Enum.KeyCode.E -- 绑定按键 E
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
        PlotService.AssignPlot(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        PlotService.ReleasePlot(player)
    end)
    
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            PlotService.AssignPlot(player)
        end)
    end

    local MarketplaceService = game:GetService("MarketplaceService")
    local SPEED_PASS_ID = 1811835638 
    
    local setSpeedRE = ReplicatedStorage:FindFirstChild("SetSpeedRE") or Instance.new("RemoteEvent")
    setSpeedRE.Name = "SetSpeedRE"
    setSpeedRE.Parent = ReplicatedStorage
    setSpeedRE.OnServerEvent:Connect(function(player, speed)
        local plot = PlotService.GetPlayerPlot(player)
        if plot then
            -- [🌟 服务端防作弊拦截]
            if speed == 4 then
                local hasPass = false
                pcall(function()
                    hasPass = MarketplaceService:UserOwnsGamePassAsync(player.UserId, SPEED_PASS_ID)
                end)
                
                -- 如果服务端查明该玩家没付过钱，直接 return 拦截请求！
                if not hasPass then
                    warn("玩家 " .. player.Name .. " 未购买通行证，尝试非法开启 4 倍速！")
                    return
                end
            end

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
                local woodenSign = soil:FindFirstChild("WoodenSign")

                if soilId <= unlockedCount then
                    -- 🟢 情况1：已解锁
                    soil:SetAttribute("IsUnlocked", true)
                    soil.Color = soil:GetAttribute("OriginalColor") -- 恢复原本颜色
                    if prompt then prompt:Destroy() end -- 移除购买提示
                    if woodenSign then woodenSign:Destroy() end -- 解锁后销毁木牌

                elseif soilId == targetUnlockId then
                    -- 🟡 情况2：当前可解锁的下一块地
                    soil:SetAttribute("IsUnlocked", false)
                    soil.Color = Color3.fromRGB(218, 179, 51) -- 变成黄色

                    -- 生成待解锁提示木牌
                    if not woodenSign then
                        local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
                        local signTemplate = itemModels and itemModels:FindFirstChild("WoodenSign")
                        
                        if signTemplate then
                            woodenSign = signTemplate:Clone()
                            woodenSign.Name = "WoodenSign"
                            
                            -- 坐标计算
                            if woodenSign:IsA("Model") then
                                local _, size = woodenSign:GetBoundingBox()
                                local yOffset = (soil.Size.Y / 2) + (size.Y / 2)
                                woodenSign:PivotTo(soil.CFrame * CFrame.new(0, yOffset, 0))
                            elseif woodenSign:IsA("BasePart") then
                                local yOffset = (soil.Size.Y / 2) + (woodenSign.Size.Y / 2)
                                woodenSign.CFrame = soil.CFrame * CFrame.new(0, yOffset, 0)
                            end
                            
                            -- 取消碰撞并焊死
                            for _, part in ipairs(woodenSign:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CanCollide = false
                                    part.Anchored = true
                                end
                            end
            
                            -- 在 NegativePart 上生成 Unlock 文本
                            local negativePart = woodenSign:FindFirstChild("NegativePart", true)
                            if negativePart and negativePart:IsA("BasePart") then
                                if negativePart:FindFirstChild("UnlockTextGui") then
                                    negativePart.UnlockTextGui:Destroy()
                                end

                                local surfaceGui = Instance.new("SurfaceGui")
                                surfaceGui.Name = "UnlockTextGui"
                                surfaceGui.Face = Enum.NormalId.Front
                                surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
                                surfaceGui.PixelsPerStud = 50
                                surfaceGui.AlwaysOnTop = false 

                                local textLabel = Instance.new("TextLabel")
                                textLabel.Size = UDim2.new(1, 0, 1, 0)
                                textLabel.BackgroundTransparency = 1
                                textLabel.Text = "Unlock"
                                textLabel.TextColor3 = Color3.new(1, 1, 1)
                                textLabel.TextScaled = true
                                textLabel.Font = Enum.Font.FredokaOne
                                textLabel.TextStrokeTransparency = 0.5
                                textLabel.Parent = surfaceGui

                                surfaceGui.Parent = negativePart
                            end
                            woodenSign.Parent = soil
                        end
                    end

                    -- 👇 [🌟 核心修复区：挂载购买提示，且仅对目标地块生效]
                    if not prompt then
                        prompt = Instance.new("ProximityPrompt")
                        prompt.Name = "UnlockPrompt"
                        prompt.ActionText = "Unlock Plot"
                        prompt.KeyboardKeyCode = Enum.KeyCode.E
                        prompt.RequiresLineOfSight = false
                        prompt.MaxActivationDistance = 8
                        prompt.HoldDuration = 0.5 -- [🌟 修复2] 必须长按0.5秒，杜绝按键连发穿透多块地！
                        prompt.Parent = soil

                        -- 当玩家长按 E 键时触发购买
                        prompt.Triggered:Connect(function(triggerPlayer)
                            if triggerPlayer ~= player then return end -- 只有地块主人能买
                            local price = PlotUnlockConfig.UnlockPrices[soilId]
                            
                            -- 扣除金币，如果成功则解锁
                            if price and PlayerDataManager.ConsumeCoins(player, price) then
                                local data = PlayerDataManager.GetPlayerData(player)
                                AnalyticsService:LogEconomyEvent(
                                    player,
                                    Enum.AnalyticsEconomyFlowType.Sink,
                                    "Coins",
                                    price,
                                    data and data.Coins or 0,
                                    Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
                                    "UnlockPlot_Soil_" .. tostring(soilId)
                                )
                                PlayerDataManager.IncrementUnlockedPlots(player)
                                PlotService.UpdateSoilVisuals(player, plot) -- 刷新所有土地状态
                            else
                                local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
                                if showNotifRE then 
                                    showNotifRE:FireClient(player, "Notice", "Not enough coins!") 
                                end
                            end
                        end)
                    end
                    -- 更新提示框上显示的价格
                    prompt.ObjectText = "Price:" .. tostring(PlotUnlockConfig.UnlockPrices[soilId])
                    -- 👆 [核心修复区结束]

                else
                    -- 🔴 情况3：未来才能解锁的地（跳级的地）
                    soil:SetAttribute("IsUnlocked", false)
                    soil.Color = Color3.fromRGB(163, 124, 18) -- 变成绿色
                    if prompt then prompt:Destroy() end -- 没有任何交互
                    if woodenSign then woodenSign:Destroy() end -- 兜底销毁
                end
            end
        end
    end
end
-- [🌟 新增：玩家退出时彻底清理地块]
function PlotService.ReleasePlot(player)
    local userId = player.UserId
    local plot = playerPlots[userId]
    
    if plot then
        print("【地块系统】玩家 " .. player.Name .. " 已退出，正在回收地块: " .. plot.Name)
        
        -- 0. 先停止战斗状态，避免后台刷怪协程继续运行
        plot:SetAttribute("IsGameOver", true)
        plot:SetAttribute("IsLevelActive", false)

        local okZombie, ZombieService = pcall(function()
            return require(script.Parent.ZombieService)
        end)
        if okZombie and ZombieService and ZombieService.CleanupPlayerBattle then
            ZombieService.CleanupPlayerBattle(player)
        end
        
        -- 1. 彻底销毁地块上的所有植物
        local plantsFolder = plot:FindFirstChild("Plants")
        if plantsFolder then
            for _, plant in ipairs(plantsFolder:GetChildren()) do
                plant:Destroy()
            end
        end

        -- 1.5 彻底销毁草坪上的战斗植物
        local lawnFolder = plot:FindFirstChild("Lawn")
        if lawnFolder then
            for _, lawnPart in ipairs(lawnFolder:GetChildren()) do
                if lawnPart:IsA("BasePart") then
                    for _, child in ipairs(lawnPart:GetChildren()) do
                        if child:GetAttribute("IsCombatPlant") then
                            child:Destroy()
                        end
                    end
                end
            end
        end
        -- 2.1 销毁悬浮牌 (OwnerBillboard)
        local spawnPart = plot:FindFirstChild("SpawnPoint") or plot:FindFirstChild("SpawnLocation") or plot:FindFirstChildWhichIsA("BasePart", true)
        if spawnPart then
            local billboard = spawnPart:FindFirstChild("OwnerBillboard")
            if billboard then billboard:Destroy() end
        end

       -- 2. 销毁身份名牌 (PlayerIdentitySurfaceGui)
        local paiModel = plot:FindFirstChild("pai", true)
        local targetPart = paiModel and paiModel:FindFirstChild("Text")
        
        if targetPart then
            local identityGui = targetPart:FindFirstChild("PlayerIdentitySurfaceGui")
            if identityGui then identityGui:Destroy() end
            
            -- 兜底清理旧版的纯名字名牌
            local oldNameGui = targetPart:FindFirstChild("PlayerNameSurfaceGui")
            if oldNameGui then oldNameGui:Destroy() end
        end

        local collectSunPart = plot:FindFirstChild("CollectSun", true)
        if collectSunPart then
            local harvestPrompt = collectSunPart:FindFirstChild("HarvestPrompt")
            if harvestPrompt then
                harvestPrompt:Destroy()
            end
        end

        -- 3. 兜底销毁场上的 OwnerId 关联对象（僵尸、基地向日葵、其他专属模型）
        for _, obj in pairs(game.Workspace:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("OwnerId") == userId then
                obj:Destroy()
            end
        end

        for _, obj in ipairs(plot:GetChildren()) do
            if obj:IsA("Model") and obj:GetAttribute("OwnerId") == userId then
                obj:Destroy()
            end
        end

        -- 4. 重置地块交互与视觉状态，让下一个玩家接手时是干净的
        ResetPlotForNextOwner(plot)

        -- 5. 重置地块属性，让其他新玩家可以占用
        plot:SetAttribute("OwnerId", nil)
        plot:SetAttribute("IsLevelActive", false)
        plot:SetAttribute("IsGameOver", false)
        plot:SetAttribute("CurrentLevel", 1)
        plot:SetAttribute("ActiveZombies", 0)
        plot:SetAttribute("ZombiesDefeated", 0)
        plot:SetAttribute("GameSpeed", 1)
        
        -- 6. 从缓存中移除
        playerPlots[userId] = nil
    end
end

return PlotService
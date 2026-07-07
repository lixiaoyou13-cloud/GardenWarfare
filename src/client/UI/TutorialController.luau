-- src/client/UI/TutorialController.luau
local TutorialController = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TutorialEffect = require(script.Parent.Parent.Utils.TutorialEffect)

function TutorialController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local inventoryGui = basicGui:WaitForChild("InventoryGui")
    local overlayGui = playerGui:WaitForChild("GlobalOverlayGui")
    local inventoryMain = inventoryGui:WaitForChild("MainFrame")
    local inventoryPages = inventoryMain:WaitForChild("MainFrame")
    local seedPage = inventoryPages:WaitForChild("SeedPage")
    local closeButton = inventoryMain:WaitForChild("Banner"):WaitForChild("Close")
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local hotbarFrame = playProperty:WaitForChild("HotbarFrame")
    local battleBtn = playProperty:WaitForChild("StartBattle") -- 战斗按钮

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    local playerData = getPlayerDataRF:InvokeServer()
    local currentStep = playerData.TutorialStep or 0

    -- 教程总步数从 9 步减少到 8 步
    if currentStep >= 8 then return end

    -- ==========================================
    -- 通用函数：创建提示文本
    -- ==========================================
    local function showTutorialTip(text)
        local bgFrame = Instance.new("Frame")
        bgFrame.Name = "TutorialTipBg"
        bgFrame.Position = UDim2.new(0.5, 0, 0.25, 0)
        bgFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        bgFrame.AutomaticSize = Enum.AutomaticSize.X
        bgFrame.Size = UDim2.new(0, 0, 0, 80)
        bgFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        bgFrame.BackgroundTransparency = 1
        bgFrame.BorderSizePixel = 0
        bgFrame.Parent = overlayGui

        local gradient = Instance.new("UIGradient")
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.4),
            NumberSequenceKeypoint.new(1, 1)
        })
        gradient.Parent = bgFrame

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 100)
        padding.PaddingRight = UDim.new(0, 100)
        padding.Parent = bgFrame

        local label = Instance.new("TextLabel")
        label.Name = "TutorialText"
        label.Size = UDim2.new(0, 0, 1, 0)
        label.AutomaticSize = Enum.AutomaticSize.X
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextSize = 40
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextTransparency = 1
        label.Parent = bgFrame

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2.5
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.Transparency = 1
        stroke.Parent = label

        TweenService:Create(bgFrame, TweenInfo.new(0.5), {BackgroundTransparency = 0}):Play()
        TweenService:Create(label, TweenInfo.new(0.5), {TextTransparency = 0}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.5), {Transparency = 0}):Play()

        return function()
            TweenService:Create(bgFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
            TweenService:Create(label, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
            TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
            task.delay(0.3, function() bgFrame:Destroy() end)
        end
    end

    local function getPlantOnPosition(plot, positionName)
        local plantsFolder = plot:FindFirstChild("Plants")
        if plantsFolder then
            for _, plant in ipairs(plantsFolder:GetChildren()) do
                if plant:GetAttribute("PlantedOn") == positionName then
                    return plant
                end
            end
        end
        return nil
    end

    -- ==========================================
    -- 【第 8 步】：战斗结束后引导去商店 (原第 9 步)
    -- ==========================================
    local function startStepEight()
        print("Tutorial step 8: guide player to the shop")
        local removeTip = showTutorialTip("You are not strong enough. Buy more seeds!")

        -- 寻找玩家自己的地块，并在里面寻找 CrazyDave
        local plotsFolder = Workspace:WaitForChild("Plots", 10)
        local targetPlot = nil

        if plotsFolder then
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                if plot:GetAttribute("OwnerId") == player.UserId then
                    targetPlot = plot
                    break
                end
            end
        end

        local shopNPC = targetPlot and targetPlot:FindFirstChild("CrazyDave")
        local targetPart = shopNPC and (shopNPC.PrimaryPart or shopNPC:FindFirstChildWhichIsA("BasePart"))

        if not targetPart then
            warn("Shop NPC (CrazyDave) not found; ending tutorial.")
            ReplicatedStorage.UpdateTutorialRE:FireServer(8)
            removeTip()
            return
        end

        local character = player.Character or player.CharacterAdded:Wait()
        -- 橙色引导线指向 CrazyDave
        local stopGuide = TutorialEffect.AddGuideBeam(character, targetPart, Color3.fromRGB(255, 170, 0))

        -- 寻找 CrazyDave 身上的 ProximityPrompt
        local shopPrompt = shopNPC:FindFirstChildWhichIsA("ProximityPrompt", true)
        if shopPrompt then
            local connection
            connection = shopPrompt.Triggered:Connect(function()
                connection:Disconnect()
                stopGuide()
                removeTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(8)
                print("Player opened the shop; full newbie tutorial completed.")
            end)
        else
            -- 备用方案：距离检测（靠近 CrazyDave 10格内即可完成）
            task.spawn(function()
                local completed = false
                while not completed do
                    local charRoot = character:FindFirstChild("HumanoidRootPart")
                    if charRoot and (charRoot.Position - targetPart.Position).Magnitude < 10 then
                        completed = true
                        stopGuide()
                        removeTip()
                        ReplicatedStorage.UpdateTutorialRE:FireServer(8)
                        print("Player reached the shop; newbie tutorial completed.")
                    end
                    task.wait(0.5)
                end
            end)
        end
    end

    -- ==========================================
    -- 监听战斗结束并过渡到第 8 步
    -- ==========================================
    local function handleStepSevenToEight()
        task.spawn(function()
            local plotsFolder = Workspace:WaitForChild("Plots", 10)
            local targetPlot = nil
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                if plot:GetAttribute("OwnerId") == player.UserId then
                    targetPlot = plot
                    break
                end
            end

            if targetPlot then
                -- 等待服务端开启战斗状态 (最多等2秒防错)
                local waitTime = 0
                while not targetPlot:GetAttribute("IsLevelActive") and waitTime < 2 do
                    task.wait(0.1)
                    waitTime += 0.1
                end

                -- 等待战斗结束 (IsLevelActive 变回 false)
                while targetPlot:GetAttribute("IsLevelActive") do
                    targetPlot:GetAttributeChangedSignal("IsLevelActive"):Wait()
                end
            end

            -- 等待战斗结算面板关闭后再弹出商店引导
            local resultGui = playerGui:FindFirstChild("BattleResultGui")
            if resultGui then
                local bgOverlay = resultGui:FindFirstChildOfClass("Frame")
                if bgOverlay and bgOverlay.Visible then
                    bgOverlay:GetPropertyChangedSignal("Visible"):Wait()
                end
            end

            task.wait(0.5)
            startStepEight()
        end)
    end

    -- ==========================================
    -- 【第 7 步】：引导开始战斗 (原第 8 步)
    -- ==========================================
    local function startStepSeven()
      print("Tutorial step 7: click the battle button")
        local removeTip = showTutorialTip("Here are some Peashooters! Click BATTLE to start!")

        local stopFlash = TutorialEffect.AddFlash(battleBtn)
        local stopArrow = TutorialEffect.AddUIArrow(battleBtn)

        local connection
        connection = battleBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                connection:Disconnect()
                stopFlash()
                stopArrow()
                removeTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(7)

                -- 触发战斗后，开启后台监听，等打完过渡到第 8 步
                handleStepSevenToEight()
            end
        end)
    end

    -- ==========================================
    -- 【第 6 步】：引导种植到草坪 Lawn1_1 并自动铺满一列 (原第 7 步)
    -- ==========================================
    local function startStepSix()
        print("Tutorial step 6: guide combat deployment")
        local removeTip = showTutorialTip("Deploy the Peashooter on the lawn.")

        local plotsFolder = Workspace:WaitForChild("Plots", 10)
        local targetPlot, targetLawn = nil, nil

        if plotsFolder then
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                if plot:GetAttribute("OwnerId") == player.UserId then
                    targetPlot = plot
                    local lawnFolder = plot:FindFirstChild("Lawn")
                    if lawnFolder then
                        -- 定位起始战斗格
                        targetLawn = lawnFolder:FindFirstChild("Lawn1_1")
                    end
                    break
                end
            end
        end

        if not targetPlot or not targetLawn then return end

        local character = player.Character or player.CharacterAdded:Wait()
        local stopGuide = TutorialEffect.AddGuideBeam(character, targetLawn, Color3.fromRGB(85, 255, 127))

        local function onPlanted()
            stopGuide()
            removeTip()
            ReplicatedStorage.UpdateTutorialRE:FireServer(6)

            local tutorialDeployRE = ReplicatedStorage:WaitForChild("TutorialDeployRE", 3)
            if tutorialDeployRE then
                for i = 2, 6 do
                    -- 拼接出 Lawn2_1, Lawn3_1 ... Lawn6_1
                    local nextLawn = "Lawn" .. i .. "_1"
                    tutorialDeployRE:FireServer(nextLawn, "Peashooter")
                    task.wait(0.15)
                end
            else
                warn("Tutorial error: TutorialDeployRE server event not found")
            end

            task.wait(0.5)
            startStepSeven() -- 进入点击 Battle 的引导
        end

        task.spawn(function()
            local isPlanted = false
            while not isPlanted do
                local lawnFolder = targetPlot:FindFirstChild("Lawn")
                if lawnFolder then
                    for _, lawn in ipairs(lawnFolder:GetChildren()) do
                        if lawn:GetAttribute("OccupiedBy") then
                            isPlanted = true
                            break
                        end
                    end
                end

                if isPlanted then break end
                task.wait(0.5)
            end
            onPlanted()
        end)
    end


    -- ==========================================
    -- 第 5 步：引导收获
    -- ==========================================
    local function startStepFive(targetPlot, targetSoil)
        local removeWaitTip = showTutorialTip("Plant is growing, please wait...")

        local maturePlant = nil
        while true do
            local currentPlant = getPlantOnPosition(targetPlot, targetSoil.Name)
            if currentPlant and currentPlant:GetAttribute("IsMature") then
                maturePlant = currentPlant
                break
            end
            task.wait(0.5)
        end

        if removeWaitTip then removeWaitTip() end

        local removeHarvestTip = showTutorialTip("Plant is mature! Follow the arrow and press [E] to harvest.")
        local character = player.Character or player.CharacterAdded:Wait()
        local stopGuide = TutorialEffect.AddGuideBeam(character, targetSoil, Color3.fromRGB(255, 255, 0))

        local plantsFolder = targetPlot:WaitForChild("Plants")
        local connection
        connection = plantsFolder.ChildRemoved:Connect(function(child)
            if child == maturePlant then
                connection:Disconnect()
                stopGuide()
                removeHarvestTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(5)

                task.wait(0.5)
                -- 🚀【核心修改】：删除了之前的 startStepSix (装备植物)，收获后直接跳入现在的战斗部署引导
                startStepSix()
            end
        end)
    end

    -- ==========================================
    -- 第 4 步：引导种植到农田
    -- ==========================================
   local function startStepFour()
        local removeTip = showTutorialTip("Follow the guide to the soil and press [E] to plant.")

        local plotsFolder = Workspace:WaitForChild("Plots", 10)
        local targetPlot, targetSoil = nil, nil
        for _, plot in ipairs(plotsFolder:GetChildren()) do
             if plot:GetAttribute("OwnerId") == player.UserId then
                local soils = plot:FindFirstChild("Soils")
                targetSoil = soils and (soils:FindFirstChild("Soil1") or soils:FindFirstChild("Soil_1"))
                targetPlot = plot
                break
            end
        end

        if not targetPlot or not targetSoil then return end

        local existingPlant = targetPlot:WaitForChild("Plants"):FindFirstChildWhichIsA("Model")
        if existingPlant and existingPlant:GetAttribute("PlantedOn") then
            removeTip()
            ReplicatedStorage.UpdateTutorialRE:FireServer(4)
            local actualSoilName = existingPlant:GetAttribute("PlantedOn")
            local actualSoil = targetPlot.Soils:FindFirstChild(actualSoilName) or targetSoil
            task.wait(0.5)
            startStepFive(targetPlot, actualSoil)
            return
        end

        local character = player.Character or player.CharacterAdded:Wait()
        local stopGuide = TutorialEffect.AddGuideBeam(character, targetSoil, Color3.fromRGB(85, 255, 127))

        local plantsFolder = targetPlot:WaitForChild("Plants")
         local connection
        connection = plantsFolder.ChildAdded:Connect(function(child)
            task.wait(0.1)
            if child:IsA("Model") and child:GetAttribute("PlantedOn") then
                connection:Disconnect()
                stopGuide()
                removeTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(4)

                local actualSoilName = child:GetAttribute("PlantedOn")
                local actualSoil = targetPlot.Soils:FindFirstChild(actualSoilName) or targetSoil

                task.wait(0.5)
                startStepFive(targetPlot, actualSoil)
            end
        end)
    end
    -- ==========================================
    -- 第 3 步：引导退出背包
    -- ==========================================
    local function startStepThree()
        local removeTip = showTutorialTip("Click the Close button to exit.")
        local stopFlash = TutorialEffect.AddFlash(closeButton)
        local stopArrow = TutorialEffect.AddUIArrow(closeButton)

        local connection
        connection = inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not inventoryGui.Enabled then
                connection:Disconnect()
                stopFlash()
                stopArrow()
                removeTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(3)
                task.wait(0.5)
                startStepFour()
            end
        end)
    end

    -- ==========================================
    -- 第 2 步：引导装备种子
    -- ==========================================
   local function startStepTwo()
        local removeTip = showTutorialTip("Click a seed to equip it.")

        local function getFirstSeed()
            for _, child in ipairs(seedPage:GetChildren()) do
                if child:IsA("Frame") or child:IsA("GuiButton") then return child end
            end
            return nil
        end

        local targetSeed = getFirstSeed()
        if not targetSeed then
            seedPage.ChildAdded:Wait()
            targetSeed = getFirstSeed()
        end

        if targetSeed then
             local stopFlash = TutorialEffect.AddFlash(targetSeed)
            local stopArrow = TutorialEffect.AddUIArrow(targetSeed)
            local isStepCompleted = false
            local connection

            local closeConn
            closeConn = inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
                 if not inventoryGui.Enabled and not isStepCompleted then
                    removeTip()
                    if stopFlash then stopFlash() end
                    if stopArrow then stopArrow() end
                    if connection then connection:Disconnect() end
                    closeConn:Disconnect()

                    local warningTip = showTutorialTip("Please open Inventory to continue!")

                    local reopenConn
                    reopenConn = inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
                        if inventoryGui.Enabled then
                             reopenConn:Disconnect()
                            warningTip()
                            startStepTwo()
                        end
                     end)
                end
            end)

            connection = targetSeed.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                     isStepCompleted = true
                    connection:Disconnect()
                    if closeConn then closeConn:Disconnect() end
                    stopFlash()
                    stopArrow()
                    removeTip()
                    ReplicatedStorage.UpdateTutorialRE:FireServer(2)
                    task.wait(0.5)
                    startStepThree()
                end
            end)
        end
    end
    -- ==========================================
    -- 第 1 步及恢复逻辑入口
    -- ==========================================
    if currentStep == 0 then
        local backpackBtn = hotbarFrame:WaitForChild("System_Backpack")
        local removeTip = showTutorialTip("Click the flashing icon to open Inventory.")
        local stopFlash = TutorialEffect.AddFlash(backpackBtn)
        local stopArrow = TutorialEffect.AddUIArrow(backpackBtn)

        local conn
        conn = inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if inventoryGui.Enabled then
                conn:Disconnect()
                stopFlash()
                stopArrow()
                removeTip()
                ReplicatedStorage.UpdateTutorialRE:FireServer(1)
                task.wait(0.5)
                startStepTwo()
            end
        end)
    elseif currentStep == 1 then
        if inventoryGui.Enabled then startStepTwo() else
            inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
                if inventoryGui.Enabled then startStepTwo() end
            end)
        end
    elseif currentStep == 2 then
        if inventoryGui.Enabled then startStepThree() else
            ReplicatedStorage.UpdateTutorialRE:FireServer(3)
            task.wait(0.5)
            startStepFour()
        end
    elseif currentStep == 3 then
        startStepFour()
    elseif currentStep == 4 then
        task.spawn(function()
            local plotsFolder = Workspace:WaitForChild("Plots", 10)
            local targetPlot, targetSoil = nil, nil
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                if plot:GetAttribute("OwnerId") == player.UserId then
                    local soils = plot:FindFirstChild("Soils")
                    targetSoil = soils and (soils:FindFirstChild("Soil1") or soils:FindFirstChild("Soil_1"))
                    targetPlot = plot
                    break
                 end
            end

            if targetPlot and targetSoil then
                startStepFive(targetPlot, targetSoil)
            else
                ReplicatedStorage.UpdateTutorialRE:FireServer(5)
            end
        end)
    elseif currentStep == 5 then
        startStepSix()
    elseif currentStep == 6 then
        startStepSeven()
    elseif currentStep == 7 then
        handleStepSevenToEight()
    end
end

return TutorialController

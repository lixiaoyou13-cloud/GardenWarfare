local AchievePage = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIEffectUtil = require(script.Parent.Parent.Parent:WaitForChild("Utils"):WaitForChild("UIEffectUtil"))
-- 引入奖励配置表
local LevelRewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardConfig"))
function AchievePage.Init(achieveFrame)
    if not achieveFrame then return end

    -- 获取服务器玩家真实数据
    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    local playerData = getPlayerDataRF:InvokeServer()
    local unlockedLevel = playerData and playerData.UnlockedLevel or 1

    -- 1. 绑定关闭按钮
    local closeBtn = achieveFrame:FindFirstChild("CloseButton", true)
    if closeBtn then
        closeBtn.Activated:Connect(function()
            achieveFrame.Visible = false
        end)
    end

    -- 2. 查找滚动列表和模板
    local scrollFrame = achieveFrame:FindFirstChild("AchievePage", true)
    local templates = ReplicatedStorage:FindFirstChild("UITemplates")
    local achieveItemTemplate = templates and templates:FindFirstChild("AchieveItem")

    if not scrollFrame or not achieveItemTemplate then return end

    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    for _, child in pairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    -- 3. 获取并排序关卡序列
    local levelKeys = {}
    for level, _ in pairs(LevelRewardConfig) do
        table.insert(levelKeys, level)
    end
    table.sort(levelKeys)

    -- 4. 遍历配置生成 UI
    for _, level in ipairs(levelKeys) do
        local rewardData = LevelRewardConfig[level]
        local item = achieveItemTemplate:Clone()
        item.Name = "Level_" .. tostring(level)

        local descText = item:FindFirstChild("DescriptionText", true)
        if descText then descText.Text = "Level " .. tostring(level) .. " Reward" end

        local detailsText = item:FindFirstChild("DetailsText", true)
        if detailsText then detailsText.Text = "Reach Level " .. tostring(level) .. " to get rewards" end

        -- 获取UI组件
        local progressBar = item:FindFirstChild("ProgressBarImage", true)
        local fillBar = item:FindFirstChild("Fill", true)
        local claimBtn = item:FindFirstChild("ClaimBattle", true)
        local btnText = claimBtn and claimBtn:FindFirstChild("TextLabel", true)

        if progressBar and not fillBar then
            warn("[UI Warning] Level " .. level .. " progress bar is missing a 'Fill' component; the bar cannot expand!")
        end

        -- 记录模板的默认颜色
        local defaultItemBgColor = item.BackgroundColor3
        local defaultProgressColor = Color3.new(1, 1, 1)
        local defaultFillColor = Color3.new(1, 1, 1)
        if progressBar then defaultProgressColor = progressBar.ImageColor3 end
        if fillBar then
            if fillBar:IsA("ImageLabel") then defaultFillColor = fillBar.ImageColor3
            elseif fillBar:IsA("Frame") then defaultFillColor = fillBar.BackgroundColor3 end
        end

        -- 计算真实进度与百分比
        local currentProgress = math.clamp(unlockedLevel, 0, level)
        local percent = currentProgress / level

        -- 读取服务端记录的领取状态
        local isClaimed = playerData.ClaimedAchieve and playerData.ClaimedAchieve[tostring(level)]

        -- 蒙版判定标签志
        local shouldAddMask = false

        -- 逻辑：颜色、透明度与百分比进度条
        if isClaimed then
            -- 状态：已领取 (溢出)
            shouldAddMask = true -- 已领取的也要加黑色蒙版

            if claimBtn then
                claimBtn.BackgroundColor3 = Color3.fromRGB(130, 130, 130)
                if btnText then btnText.Text = "Claimed" end
            end

            if progressBar then
                if progressBar:IsA("ImageLabel") then progressBar.ImageTransparency = 0
                elseif progressBar:IsA("Frame") then progressBar.BackgroundTransparency = 0 end

                local pText = progressBar:FindFirstChild("TextLabel", true)
                if pText then pText.Text = level .. " / " .. level end

                if fillBar then
                    fillBar.Size = UDim2.new(1, 0, 1, 0)
                    if fillBar:IsA("ImageLabel") then fillBar.ImageTransparency = 0
                    elseif fillBar:IsA("Frame") then fillBar.BackgroundTransparency = 0 end
                end
            end

        elseif unlockedLevel > level then
            -- 状态：可领取 (溢出)
            item.BackgroundColor3 = Color3.fromRGB(140, 140, 140)

            if claimBtn then
                -- 不再更新改 claimBtn 的颜色，让它保持默认的亮色
                if btnText then btnText.Text = "Claim" end

                claimBtn.Activated:Connect(function()
                    if claimBtn:GetAttribute("IsClaiming") then return end
                    claimBtn:SetAttribute("IsClaiming", true)

                    local claimLevelRewardRF = ReplicatedStorage:WaitForChild("ClaimLevelRewardRF")
                    local success, msg = claimLevelRewardRF:InvokeServer(level)

                    if success then
                        item.BackgroundColor3 = defaultItemBgColor
                        if progressBar then
                            if progressBar:IsA("ImageLabel") then progressBar.ImageColor3 = defaultProgressColor
                            elseif progressBar:IsA("Frame") then progressBar.BackgroundColor3 = defaultProgressColor end
                        end
                        if fillBar then
                            if fillBar:IsA("ImageLabel") then fillBar.ImageColor3 = defaultFillColor
                            elseif fillBar:IsA("Frame") then fillBar.BackgroundColor3 = defaultFillColor end
                        end
                        claimBtn.BackgroundColor3 = Color3.fromRGB(130, 130, 130)
                        if btnText then btnText.Text = "Claimed" end

                        -- 领取成功后，动态给当前条目盖上黑蒙版
                        local lockMask = Instance.new("Frame")
                        lockMask.Name = "LockMask"
                        lockMask.Size = UDim2.new(1, 0, 1, 0)
                        lockMask.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                        lockMask.BackgroundTransparency = 0.6
                        lockMask.BorderSizePixel = 0
                        lockMask.ZIndex = 99
                        local uiCorner = item:FindFirstChildOfClass("UICorner")
                        if uiCorner then uiCorner:Clone().Parent = lockMask end
                        lockMask.Parent = item

                        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Success", Text = msg, Duration = 3 })
                    else
                        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Failed", Text = msg, Duration = 3 })
                    end
                    task.wait(0.5)
                    claimBtn:SetAttribute("IsClaiming", nil)
                end)
            end

            if progressBar then
                if progressBar:IsA("ImageLabel") then
                    progressBar.ImageColor3 = Color3.fromRGB(110, 110, 110)
                    progressBar.ImageTransparency = 0
                elseif progressBar:IsA("Frame") then
                    progressBar.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
                    progressBar.BackgroundTransparency = 0
                end

                local pText = progressBar:FindFirstChild("TextLabel", true)
                if pText then pText.Text = level .. " / " .. level end

                if fillBar then
                    fillBar.Size = UDim2.new(1, 0, 1, 0)
                    if fillBar:IsA("ImageLabel") then
                        fillBar.ImageColor3 = Color3.fromRGB(110, 110, 110)
                        fillBar.ImageTransparency = 0
                    elseif fillBar:IsA("Frame") then
                        fillBar.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
                        fillBar.BackgroundTransparency = 0
                    end
                end
            end

        else
            -- 状态：不可领取 (未溢出)
            shouldAddMask = true -- 不可领取的加黑色蒙版

            if claimBtn then
                claimBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
                if btnText then btnText.Text = "Locked" end
            end

            if progressBar then
                if progressBar:IsA("ImageLabel") then progressBar.ImageTransparency = 0.5
                elseif progressBar:IsA("Frame") then progressBar.BackgroundTransparency = 0.5 end

                local pText = progressBar:FindFirstChild("TextLabel", true)
                if pText then pText.Text = currentProgress .. " / " .. level end

                if fillBar then
                    fillBar.Size = UDim2.new(percent, 0, 1, 0)
                    if fillBar:IsA("ImageLabel") then fillBar.ImageTransparency = 0.5
                    elseif fillBar:IsA("Frame") then fillBar.BackgroundTransparency = 0.5 end
                end
            end
        end

        -- 统一生成黑色蒙版
        if shouldAddMask then
            local lockMask = Instance.new("Frame")
            lockMask.Name = "LockMask"
            lockMask.Size = UDim2.new(1, 0, 1, 0) -- 撑满整个 Item
            lockMask.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- 纯黑
            lockMask.BackgroundTransparency = 0.6 -- 透明度 60%
            lockMask.BorderSizePixel = 0
            lockMask.ZIndex = 99 -- 层级盖住内部元素

            -- 自转适应圆角
            local uiCorner = item:FindFirstChildOfClass("UICorner")
            if uiCorner then uiCorner:Clone().Parent = lockMask end

            lockMask.Parent = item
        end

        -- 设置奖励图片标签 (Reward_1 / Reward_2)
        local reward1 = item:FindFirstChild("Reward_1", true)
        if reward1 then
            if rewardData.Seed then
                reward1.Visible = true
                local countLabel = reward1:FindFirstChild("TextLabel", true)
                if countLabel then countLabel.Text = tostring(rewardData.SeedCount or 1) end

                local vp = reward1:FindFirstChild("ViewportFrame", true)
                if vp and vp:IsA("ViewportFrame") then
                    vp:ClearAllChildren()
                    local itemModels = ReplicatedStorage:FindFirstChild("ItemModels")
                    local seedModel = itemModels and itemModels:FindFirstChild(rewardData.Seed .. "_Plant")
                    if seedModel then
                        local cloneModel = seedModel:Clone()
                        cloneModel:PivotTo(cloneModel:GetPivot() * CFrame.Angles(0, math.rad(-160), 0))
                        cloneModel.Parent = vp
                        local camera = Instance.new("Camera")
                        vp.CurrentCamera = camera
                        camera.Parent = vp
                        local cf, size = cloneModel:GetBoundingBox()
                        local dist = size.Magnitude * 0.3
                        camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist, dist*0.6, dist), cf.Position)
                    end
                end
            else
                reward1.Visible = false
            end
        end

        local reward2 = item:FindFirstChild("Reward_2", true)
        if reward2 then
            if rewardData.Sun then
                reward2.Visible = true
                local sunLabel = reward2:FindFirstChild("TextLabel", true)
                if sunLabel then sunLabel.Text = UIEffectUtil.FormatNumber(rewardData.Sun) end
            else
                reward2.Visible = false
            end
        end

        item.Parent = scrollFrame
    end
end

return AchievePage

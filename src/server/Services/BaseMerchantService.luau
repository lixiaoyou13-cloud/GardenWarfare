-- src/server/Services/BaseMerchantService.luau
local BaseMerchantService = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local PlayerDataManager = require(script.Parent.Parent:WaitForChild("PlayerDataManager"))

local REFRESH_INTERVAL = 180 -- 3分钟 (180秒)
local COIN_ICON_ID = "rbxassetid://102426033120992" -- 价格图片标签 ID

-- 记录每个玩家基地的商人状态
local activeMerchants = {}

local MERCHANT_SAVE_FIELDS = {
    "Coins",
    "Inventory",
    "Hotbar",
    "UnlockedMutations",
}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function snapshotMerchantState(data)
    local snapshot = {}
    for _, fieldName in ipairs(MERCHANT_SAVE_FIELDS) do
        snapshot[fieldName] = cloneValue(data[fieldName])
    end
    return snapshot
end

local function restoreMerchantState(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    for _, fieldName in ipairs(MERCHANT_SAVE_FIELDS) do
        data[fieldName] = cloneValue(snapshot[fieldName])
    end
end

local function fireInventoryUpdate(player, data)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    if updateInventoryRE and player and player.Parent then
        updateInventoryRE:FireClient(player, data)
    end
end

local function notifyPlayer(player, message)
    local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
    if showNotifRE and player and player.Parent then
        showNotifRE:FireClient(player, "Notice", message)
    end
end

local function rollbackMerchantPurchase(player, data, snapshot)
    restoreMerchantState(data, snapshot)
    fireInventoryUpdate(player, data)

    local rollbackSaved, rollbackErr = PlayerDataManager.ForceSave(player)
    if not rollbackSaved and rollbackErr ~= "stale_session" then
        warn("[BaseMerchantService] Failed to save rollback after merchant purchase for "
            .. tostring(player and player.Name or "unknown") .. ": " .. tostring(rollbackErr))
    end
end

-- 价格数字缩写格式化函数
local function FormatPrice(n)
    if not n then return "0" end
    if n >= 1e9 then
        local v = n / 1e9
        return (v == math.floor(v) and tostring(v) or string.format("%.1f", v)) .. "B"
    elseif n >= 1e6 then
        local v = n / 1e6
        return (v == math.floor(v) and tostring(v) or string.format("%.1f", v)) .. "M"
    elseif n >= 1e3 then
        local v = n / 1e3
        return (v == math.floor(v) and tostring(v) or string.format("%.1f", v)) .. "K"
    else
        return tostring(n)
    end
end

-- 辅助函数：获取玩家当前的地块
local function GetPlayerPlot(userId)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerId") == userId then
            return plot
        end
    end
    return nil
end

-- 函数：在基地生成随机植物
local function SpawnMerchant(player, plot)
    -- 清理旧模型
    if activeMerchants[player.UserId] and activeMerchants[player.UserId].Model then
        activeMerchants[player.UserId].Model:Destroy()
    end

    local baseModel = plot:FindFirstChild("Base")
    if not baseModel or not baseModel:IsA("Model") then
        return
    end

    for _, child in ipairs(baseModel:GetChildren()) do
        if string.find(child.Name, "BaseMerchant_") then
            child:Destroy()
        end
    end

-- 1. 随机选择一个植物 (改为从限时间稀有池 BaseLimitedSaleKey 中抽取)
    local seedKeys = ItemConfig.BaseLimitedSaleKey
    if not seedKeys or #seedKeys == 0 then return end

    local randomSeedId = seedKeys[math.random(1, #seedKeys)]
    local seedDetail = ItemConfig.Seeds[randomSeedId]

    -- 获取该植物对应的待机动画配置
    local plantConfig = ItemConfig.Plants[randomSeedId]
    local targetAnimId = plantConfig and plantConfig.IdleAnimId

    -- 2. 获取植物模型
    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local realModel = itemModelsFolder and (itemModelsFolder:FindFirstChild(randomSeedId .. "_Plant") or itemModelsFolder:FindFirstChild(randomSeedId))

    local displayModel
    if realModel then
        displayModel = realModel:Clone()
    else
        displayModel = Instance.new("Part")
        displayModel.Size = Vector3.new(2, 2, 2)
        displayModel.Color = Color3.fromRGB(85, 255, 127)
    end
    displayModel.Name = "BaseMerchant_" .. player.UserId

    -- 处理物理状态与动画兼容
    for _, node in ipairs(displayModel:GetDescendants()) do
        if node:IsA("BasePart") then
            node.CanCollide = false
            node.CanQuery = false

            if targetAnimId and displayModel.PrimaryPart and node ~= displayModel.PrimaryPart then
                node.Anchored = false
            else
                node.Anchored = true
            end

        elseif node:IsA("ParticleEmitter") or node:IsA("Light") or node:IsA("Beam") or node:IsA("Highlight") or node:IsA("Trail") then
            node.Enabled = false
        end
    end

    -- 3. 移动至 Base 正上方
    local baseCFrame, baseSize = baseModel:GetBoundingBox()
    local spawnCFrame = CFrame.new(baseCFrame.Position + Vector3.new(0, baseSize.Y / 2 + 1.2, 0))
    displayModel:PivotTo(spawnCFrame)
    displayModel.Parent = baseModel

    local modelRoot = displayModel.PrimaryPart or (displayModel:IsA("BasePart") and displayModel) or displayModel:FindFirstChildWhichIsA("BasePart")
    if not modelRoot then displayModel:Destroy(); return end

    -- 4. 加载并播放待机动画
    if targetAnimId then
        local animController = displayModel:FindFirstChildOfClass("AnimationController") or displayModel:FindFirstChildOfClass("Humanoid")
        if not animController then
            animController = Instance.new("AnimationController")
            animController.Parent = displayModel
        end
        local animator = animController:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = animController
        end

        local anim = Instance.new("Animation")
        anim.AnimationId = targetAnimId
        local track = animator:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Idle
        track.Looped = true
        track:Play()
    end

    -- 5. 计算价格
    local price = math.floor((seedDetail.BuyPrice or 100) * 0.8)
    local isSpecial = (seedDetail.IsSellable == false)

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Buy " .. (seedDetail.Name or randomSeedId)
    prompt.ObjectText = "Price: " .. FormatPrice(price)
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.MaxActivationDistance = 6
    prompt.RequiresLineOfSight = false
    prompt.Parent = modelRoot

    -- 6. UI改为固定物理大小（近大远小）
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(4.5, 0, 3, 0)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 60
    billboard.Parent = modelRoot

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Parent = billboard

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0.02, 0)
    layout.Parent = frame

    -- 植物名称
    local nameTag = Instance.new("TextLabel")
    nameTag.Size = UDim2.new(1, 0, 0.25, 0)
    nameTag.BackgroundTransparency = 1
    nameTag.Text = seedDetail.Name or randomSeedId
    nameTag.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameTag.TextStrokeTransparency = 0
    nameTag.TextScaled = true
    nameTag.Font = Enum.Font.FredokaOne
    nameTag.LayoutOrder = 0
    nameTag.Parent = frame

    -- 特殊标签
    if isSpecial then
        local specialTag = Instance.new("TextLabel")
        specialTag.Size = UDim2.new(1, 0, 0.2, 0)
        specialTag.BackgroundTransparency = 1
        specialTag.Text = "SPECIAL"
        specialTag.TextColor3 = Color3.fromRGB(170, 85, 255)
        specialTag.TextStrokeTransparency = 0
        specialTag.TextScaled = true
        specialTag.Font = Enum.Font.FredokaOne
        specialTag.LayoutOrder = 1
        specialTag.Parent = frame
    end

    -- 图片标签与价格容器
    local priceContainer = Instance.new("Frame")
    priceContainer.Size = UDim2.new(1, 0, 0.25, 0)
    priceContainer.BackgroundTransparency = 1
    priceContainer.LayoutOrder = 2
    priceContainer.Parent = frame

    local priceLayout = Instance.new("UIListLayout")
    priceLayout.FillDirection = Enum.FillDirection.Horizontal
    priceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    priceLayout.Padding = UDim.new(0.05, 0)
    priceLayout.Parent = priceContainer

    local coinIcon = Instance.new("ImageLabel")
    coinIcon.Size = UDim2.new(1, 0, 1, 0)
    coinIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
    coinIcon.BackgroundTransparency = 1
    coinIcon.Image = COIN_ICON_ID
    coinIcon.Parent = priceContainer

    local priceText = Instance.new("TextLabel")
    priceText.Size = UDim2.new(0.6, 0, 1, 0)
    priceText.BackgroundTransparency = 1
    priceText.Text = FormatPrice(price)
    priceText.TextColor3 = Color3.fromRGB(255, 215, 0)
    priceText.TextStrokeTransparency = 0
    priceText.TextScaled = true
    priceText.Font = Enum.Font.FredokaOne
    priceText.Parent = priceContainer

    -- 倒计时
    local timerTag = Instance.new("TextLabel")
    timerTag.Size = UDim2.new(1, 0, 0.25, 0)
    timerTag.BackgroundTransparency = 1
    timerTag.Text = "03:00 Post update"
    timerTag.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerTag.TextStrokeTransparency = 0
    timerTag.TextScaled = true
    timerTag.Font = Enum.Font.FredokaOne
    timerTag.LayoutOrder = 3
    timerTag.Parent = frame

    -- 保持存商人状态
    activeMerchants[player.UserId] = {
        Model = displayModel,
        SeedId = randomSeedId,
        Price = price,
        EndTime = os.time() + REFRESH_INTERVAL,
        TimerText = timerTag,
        PriceText = priceText, -- 记录价格UI以便购买后
        CoinIcon = coinIcon, -- 记录图片标签UI以便购买后隐藏
        IsRefreshing = false,
        IsSold = false -- 售罄状态
    }

    -- 7. 购买逻辑
    prompt.Triggered:Connect(function(triggerPlayer)
        if triggerPlayer.UserId ~= player.UserId then return end

        local currentShop = activeMerchants[player.UserId]
        if not currentShop or currentShop.Model ~= displayModel then return end
        if currentShop.IsSold then return end -- 防止连点击

        local data = PlayerDataManager.GetPlayerData(player)
        if not data then
            notifyPlayer(player, "Data loading. Please try again.")
            return
        end
        if not PlayerDataManager.IsDataSafeToSave(player) then
            notifyPlayer(player, "Save unavailable. Please try again.")
            return
        end

        local snapshot = snapshotMerchantState(data)
        if PlayerDataManager.ConsumeCoins(player, currentShop.Price) then
            -- 扣费成功，给种子
            PlayerDataManager.GiveSeed(player, currentShop.SeedId, 1)

            local saved, saveErr = PlayerDataManager.ForceSave(player)
            if not saved then
                warn("[BaseMerchantService] Failed to save merchant purchase for "
                    .. player.Name .. ": " .. tostring(saveErr))
                rollbackMerchantPurchase(player, data, snapshot)
                notifyPlayer(player, "Purchase failed: save failed. Please try again.")
                return
            end

            -- 购买后不直接销毁，而是进入“售罄并等待”状态
            currentShop.IsSold = true
            prompt:Destroy() -- 销毁交互按键，防止重复购买

            -- 隐藏植物实体模型 (但结构让UI继续显示)
            for _, part in ipairs(displayModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 1
                elseif part:IsA("Decal") or part:IsA("Texture") then
                    part.Transparency = 1
                end
            end

            -- 隐藏金币图片标签，并将价格文字改为 "SOLD OUT"
            if currentShop.CoinIcon then currentShop.CoinIcon.Visible = false end
            if currentShop.PriceText then
                currentShop.PriceText.Text = "SOLD OUT"
                currentShop.PriceText.TextColor3 = Color3.fromRGB(180, 180, 180) -- 变成灰色
            end

            -- 注意：这里不再将 activeMerchantsplayer.UserId 设为 nil
            -- 底下的 Init() 心跳循环会自转动接管，等到倒计时时间它才会触发刷新机制
        else
            -- 余额不足提示
            local showNotifRE = ReplicatedStorage:FindFirstChild("ShowNotificationRE")
            if showNotifRE then
                showNotifRE:FireClient(player, "Notice", "Not enough coins!")
            end
        end
    end)
end

function BaseMerchantService.Init()
    task.spawn(function()
        while task.wait(1) do
            local currentTime = os.time()
            for _, player in ipairs(Players:GetPlayers()) do
                local plot = GetPlayerPlot(player.UserId)
                local mData = activeMerchants[player.UserId]

                if plot then
                    if not mData then
                        SpawnMerchant(player, plot)
                    elseif currentTime >= mData.EndTime then
                        if not mData.IsRefreshing then
                            mData.IsRefreshing = true
                            if mData.TimerText then mData.TimerText.Text = "Refreshing..." end
                            task.delay(1, function()
                                SpawnMerchant(player, plot)
                            end)
                        end
                    else
                        -- 只要还没到时间，就会一直更新倒计时！即使已经买空了
                        local timeLeft = math.max(0, mData.EndTime - currentTime)
                        if mData.TimerText then
                            mData.TimerText.Text = string.format("%02d:%02d Post update", math.floor(timeLeft / 60), timeLeft % 60)
                        end
                    end
                else
                    if mData and mData.Model then mData.Model:Destroy() end
                    activeMerchants[player.UserId] = nil
                end
            end
        end
    end)

    print("Server: BaseMerchantService (delayed refresh version) loaded.")
end

return BaseMerchantService

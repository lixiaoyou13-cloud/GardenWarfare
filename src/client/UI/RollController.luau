-- src/client/UI/RollController.luau
local RollController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local RollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RollConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local TAB1_CASH_ROLL_COST_TEXT = "200K"
local SUN_ICON_IMAGE = "rbxassetid://102426033120992"
local TAB2_RARE_ROLL_PRODUCT_ID = 3599579545
local TAB2_RARE_ROLL_COST_TEXT = "39"
local ROBUX_ICON_IMAGE = "rbxassetid://98579817733785"

function RollController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local openPageBtn = playProperty:WaitForChild("Roll") 
    
    local rollPage = basicGui:WaitForChild("RollPage")
    rollPage.DisplayOrder = 999
    local bgFrame = rollPage:WaitForChild("BGFrame") 
    local page1 = bgFrame:FindFirstChild("Page_1") or rollPage:WaitForChild("Page_1")
    local page2 = bgFrame:FindFirstChild("Page_2") or rollPage:WaitForChild("Page_2")
    local pages = {page1, page2}
    local currentPage = pages[1]
    local cashFrame = nil
    local maskFrame = nil
    local scrollList = nil
    
    -- 🌟 获取倒计时文本标�?
    local getTimeText = nil
    
    -- 🌟 本地倒计时缓�?
    local localRollTimer = 300
    -- 👇 开启背景阻挡层，防止穿透点�?
    bgFrame.Active = true 
    
    -- 🌟【修复穿�?】创建一个全屏透明拦截网！放在最底层，绝对拦截所有穿透点�?
    if not rollPage:FindFirstChild("ClickBlockerWall") then
        local blocker = Instance.new("TextButton")
        blocker.Name = "ClickBlockerWall"
        blocker.Size = UDim2.new(1, 0, 1, 0)
        blocker.BackgroundTransparency = 1
        blocker.Text = ""
        blocker.ZIndex = -999 
        blocker.Parent = rollPage
    end
    local tab1Btn = bgFrame:WaitForChild("Tab_1")
    local tab2Btn = bgFrame:WaitForChild("Tab_2")

    tab1Btn.AnchorPoint = Vector2.new(0, 0.5)
    tab2Btn.AnchorPoint = Vector2.new(0, 0.5)
    
    local tab1OriginalPos = tab1Btn.Position
    local tab2OriginalPos = tab2Btn.Position

    local closeBtn = rollPage:WaitForChild("CloseBtn") 
    local drawBtn = nil
    
    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates")
    local rollItemTemplate = uiTemplates:WaitForChild("RollItemTemplate")
    
    local ITEM_HEIGHT = rollItemTemplate.Size.Y.Offset
    if ITEM_HEIGHT == 0 then ITEM_HEIGHT = 130 end 

    local PADDING = 10
    local FIXED_SCROLL_SLOT_COUNT = 30

    local isRolling = false
    local idleConnection = nil 
    local currentIdleY = 0
    local currentTab = 1 
    local currentTickets = {0, 0} -- 本地缓存当前的抽奖次�?
    local hasSyncedRollTickets = false

    local TAB_SELECTED_SCALE = 1.3 
    local TAB_SELECTED_OFFSET_X = 35 
    local TAB_TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local scrollSlotsByPage = {}

    local function SortSlots(slots)
        table.sort(slots, function(a, b)
            if a.LayoutOrder ~= b.LayoutOrder then
                return a.LayoutOrder < b.LayoutOrder
            end

            if a.Position.Y.Offset ~= b.Position.Y.Offset then
                return a.Position.Y.Offset < b.Position.Y.Offset
            end

            return a.Name < b.Name
        end)
    end

    local function EnsureScrollListSlots(page)
        if not page then return end

        local pageMaskFrame = page:WaitForChild("MaskFrame")
        local pageScrollList = pageMaskFrame:WaitForChild("ScrollList")
        local slots = {}

        for _, child in ipairs(pageScrollList:GetChildren()) do
            if child:IsA("GuiObject") then
                table.insert(slots, child)
            end
        end

        if #slots > 0 then
            SortSlots(slots)
            scrollSlotsByPage[page] = slots
            return
        end

        local layout = pageScrollList:FindFirstChildOfClass("UIListLayout")
        local pagePadding = layout and layout.Padding.Offset or PADDING

        for i = 1, FIXED_SCROLL_SLOT_COUNT do
            local slot = rollItemTemplate:Clone()
            slot.Name = "Slot_" .. i
            slot.LayoutOrder = i
            slot.AnchorPoint = Vector2.new(0.5, 0.5)
            slot.Position = UDim2.new(0.5, 0, 0, ((i - 1) * (ITEM_HEIGHT + pagePadding)) + (ITEM_HEIGHT / 2))
            slot.Parent = pageScrollList
            table.insert(slots, slot)
        end

        scrollSlotsByPage[page] = slots
    end

    for _, page in ipairs(pages) do
        EnsureScrollListSlots(page)
    end

    local function RefreshCurrentPageRefs()
        currentPage = pages[currentTab]
        if not currentPage then return end

        for index, page in ipairs(pages) do
            if page then
                page.Visible = index == currentTab
            end
        end

        cashFrame = currentPage:FindFirstChild("Cash")
        maskFrame = currentPage:WaitForChild("MaskFrame")
        scrollList = maskFrame:WaitForChild("ScrollList")
        drawBtn = currentPage:WaitForChild("DrawBtn")
        getTimeText = currentPage:WaitForChild("GetTimeText")

        local layout = scrollList:FindFirstChildOfClass("UIListLayout")
        PADDING = layout and layout.Padding.Offset or 10
    end

    RefreshCurrentPageRefs()

    local function RefreshDrawButtonText()
        if not drawBtn then return end

        local drawText = drawBtn:FindFirstChildWhichIsA("TextLabel")
        if drawText then
            drawText.Text = "Pull (" .. (currentTickets[currentTab] or 0) .. ")"
        else
            drawBtn.Text = "Pull (" .. (currentTickets[currentTab] or 0) .. ")"
        end
    end

    local function RefreshCashUI()
        if not cashFrame then return end

        if not hasSyncedRollTickets then
            cashFrame.Visible = false
            cashFrame.Active = false
            return
        end

        local shouldShowCash = (currentTab == 1 and (currentTickets[1] or 0) <= 0)
            or (currentTab == 2 and (currentTickets[2] or 0) <= 0)
        cashFrame.Visible = shouldShowCash
        cashFrame.Active = shouldShowCash

        if cashFrame:IsA("ImageLabel") or cashFrame:IsA("ImageButton") then
            cashFrame.Image = currentTab == 2 and ROBUX_ICON_IMAGE or SUN_ICON_IMAGE
        end

        local priceLabel = cashFrame:FindFirstChild("Price")
        if priceLabel and priceLabel:IsA("TextLabel") then
            priceLabel.Text = currentTab == 2 and TAB2_RARE_ROLL_COST_TEXT or TAB1_CASH_ROLL_COST_TEXT
        end
    end

    -- ==========================================
    -- [🌟 新增：红点通知生成器]
    -- ==========================================
    local function CreateOrUpdateRedDot(parent, count)
        if not parent then return end
        local dot = parent:FindFirstChild("RedDotNotification")
        
        if count > 0 then
            if not dot then
                -- 创建背景容器（透明�?
                dot = Instance.new("Frame")
                dot.Name = "RedDotNotification"
                dot.Size = UDim2.new(0, 15, 0, 15) -- 稍微放大一点，保证图片够清�?
                
                -- 👇 [🌟 位置修复：中心点对准按钮的最右上角像素点]
                dot.Position = UDim2.new(1, 0, 0, 0) 
                dot.AnchorPoint = Vector2.new(0.5, 0.5) 
                
                -- 👇 [🌟 背景修复：完全透明，去除原本的红色方块底色]
                dot.BackgroundTransparency = 1 
                dot.ZIndex = 50
                
                -- 直接放入你的感叹号图�?
                local icon = Instance.new("ImageLabel")
                icon.Size = UDim2.new(1, 0, 1, 0) -- 图片撑满整个透明容器
                icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1 -- 内部图片的背景同样透明
                icon.Image = "rbxassetid://24228463"
                icon.ZIndex = 51
                icon.Parent = dot
                
                dot.Parent = parent
            end
            dot.Visible = true
        else
            if dot then
                dot.Visible = false
            end
        end
    end

    -- ==========================================
    -- [🌟 新增：刷�?UI 文本与红点显示]
    -- ==========================================
    local function RefreshUI(data)
        if not data then return end
        currentTickets = data.RollTickets or {0, 0}
        hasSyncedRollTickets = true

        -- 🌟 从服务端同步最新剩余时�?
        if data.OnlineRollTimer then
            localRollTimer = data.OnlineRollTimer
        end
        
        -- 更新各个 Tab 上的红点
        CreateOrUpdateRedDot(tab1Btn, currentTickets[1])
        CreateOrUpdateRedDot(tab2Btn, currentTickets[2])
        
        -- 如果任意一个池子有次数，就在外部的总入口按钮亮起红�?
        local totalTickets = currentTickets[1] + currentTickets[2]
        CreateOrUpdateRedDot(openPageBtn, totalTickets)
        
        -- 更新抽奖按钮�?Pull (x) 文字
        RefreshDrawButtonText()

        RefreshCashUI()
    end

    -- 监听数据更新事件，随时刷新红�?
    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE")
    updateInventoryRE.OnClientEvent:Connect(RefreshUI)

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF")
    local function SyncRollTicketsFromServer()
        local success, data = pcall(function()
            return getPlayerDataRF:InvokeServer()
        end)

        if success and data then
            RefreshUI(data)
        else
            RefreshCashUI()
        end
    end
    task.spawn(SyncRollTicketsFromServer)

    -- ==========================================
    -- [🌟 新增：独立更�?UI 倒计时循环]
    -- ==========================================
    -- ==========================================
    -- [🌟 优化：即时文本刷新函�?+ 倒计时驱动]
    -- ==========================================
    local function UpdateGetTimeText()
        if not getTimeText then return end
        
        if currentTab == 1 then
            -- 页面 1 显示精确的倒计�?
            local m = math.floor(localRollTimer / 60)
            local s = localRollTimer % 60
            getTimeText.Text = string.format("(%02d:%02d) Get one chance", m, s)
        elseif currentTab == 2 then
            -- 页面 2 立刻切换为更新提�?
            getTimeText.Text = "Ultra Rare Prize Pool"
        end
    end
    task.spawn(function()
        while task.wait(1) do
            -- 本地自己先递减，保�?UI 看起来是连贯�?
            if localRollTimer > 0 then
                localRollTimer = localRollTimer - 1
            else
                localRollTimer = 300 -- 等待服务端同步期间的本地假循�?
            end
            
            -- 如果抽奖页面开着，就刷新文字
            if rollPage.Enabled and getTimeText then
                if currentTab == 1 then
                    -- 计算分和�?
                    local m = math.floor(localRollTimer / 60)
                    local s = localRollTimer % 60
                    getTimeText.Text = string.format("(%02d:%02d) Get one chance", m, s)
                elseif currentTab == 2 then
                    getTimeText.Text = "Ultra Rare Prize Pool"
                end
            end
        end
    end)

    -- ==========================================
    -- [统一装配格子的核心逻辑]
    -- ==========================================
    local function ConfigureSlot(slot, itemId)
        local viewport = slot:FindFirstChild("Icom") or slot:FindFirstChildWhichIsA("ViewportFrame")
        if viewport then
            UIEffectUtil.RenderToViewport(viewport, itemId, "Plant", 1)
        end

        local plantConfig = ItemConfig.Plants[itemId]
        local quality = plantConfig and plantConfig.Quality or 1
        local rateStr = RollConfig.GetDisplayRate(currentTab, itemId)

        local bg = slot:FindFirstChild("BG")
        if bg then
            for i = 1, 5 do
                local qNode = bg:FindFirstChild(tostring(i))
                if qNode then
                    if qNode:IsA("UIGradient") then
                        qNode.Enabled = (i == quality)
                    elseif qNode:IsA("GuiObject") then
                        qNode.Visible = (i == quality)
                    end
                end
            end
            
            local rateText = bg:FindFirstChild("RateText")
            if rateText and rateText:IsA("TextLabel") then
                rateText.Text = rateStr
            end
        end
    end

    local function GetExistingSlot(container)
        if not container then return nil end
        if container:FindFirstChild("Icom") or container:FindFirstChild("BG") or container:FindFirstChildWhichIsA("ViewportFrame") then
            return container
        end

        local namedSlot = container:FindFirstChild("Slot") or container:FindFirstChild("RollItemTemplate")
        if namedSlot and namedSlot:IsA("GuiObject") then
            return namedSlot
        end

        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("GuiObject") then
                return child
            end
        end

        return nil
    end

    local function GetScrollSlots()
        if currentPage and scrollSlotsByPage[currentPage] then
            return scrollSlotsByPage[currentPage]
        end

        local slots = {}
        if not scrollList then return slots end

        for _, child in ipairs(scrollList:GetChildren()) do
            if child:IsA("GuiObject") then
                table.insert(slots, child)
            end
        end

        SortSlots(slots)

        if currentPage then
            scrollSlotsByPage[currentPage] = slots
        end

        return slots
    end

    local function GetSlotCenterY(slot)
        if not slot then return 0 end

        local height = slot.AbsoluteSize.Y
        if height <= 0 then
            height = slot.Size.Y.Offset
        end

        return slot.Position.Y.Offset + (height * (0.5 - slot.AnchorPoint.Y))
    end

    local function GetAverageSlotSpacing(slots)
        if #slots <= 1 then
            return ITEM_HEIGHT + PADDING
        end

        local totalSpacing = 0
        local spacingCount = 0

        for i = 2, #slots do
            local spacing = GetSlotCenterY(slots[i]) - GetSlotCenterY(slots[i - 1])
            if spacing > 0 then
                totalSpacing += spacing
                spacingCount += 1
            end
        end

        if spacingCount <= 0 then
            return ITEM_HEIGHT + PADDING
        end

        return totalSpacing / spacingCount
    end

    local function GetIdleLoopHeight(slots, poolCount)
        if #slots <= 0 then
            return ITEM_HEIGHT + PADDING
        end

        -- Studio 里建议按奖池顺序预摆至少两轮 Slot；这样这里可以用第 1 轮到第 2 轮的实际距离做无缝循环。
        if poolCount > 0 and #slots >= poolCount + 1 then
            local repeatedSetHeight = GetSlotCenterY(slots[poolCount + 1]) - GetSlotCenterY(slots[1])
            if repeatedSetHeight > 0 then
                return repeatedSetHeight
            end
        end

        local averageSpacing = GetAverageSlotSpacing(slots)
        return math.max(averageSpacing, (GetSlotCenterY(slots[#slots]) - GetSlotCenterY(slots[1])) + averageSpacing)
    end

    -- ==========================================
    -- [大奖展示引擎]
    -- ==========================================
    local function SetupLowestProbShowcase()
        if not currentPage then return end
        
        local targetPool = RollConfig.Pools[currentTab] or RollConfig.Pools[1]
        local sortedPool = {}
        for _, item in ipairs(targetPool) do
            table.insert(sortedPool, item)
        end
        
        table.sort(sortedPool, function(a, b)
            return a.Weight < b.Weight 
        end)
        
        for i = 1, 3 do
            local showContainer = currentPage:FindFirstChild("Show_" .. i)
            local prizeData = sortedPool[i]

            if showContainer and prizeData then
                local slot = GetExistingSlot(showContainer)
                if slot then
                    ConfigureSlot(slot, prizeData.Id)
                end
            end
        end
    end

    -- ==========================================
    -- [3D 视觉引擎]
    -- ==========================================
    local function Update3DVisuals()
        if not maskFrame or not scrollList then return end

        local maskCenterY = maskFrame.AbsoluteSize.Y / 2 
        local listOffsetY = scrollList.Position.Y.Offset 
        local maxDist = maskCenterY + (ITEM_HEIGHT / 2) 

        for _, slot in pairs(scrollList:GetChildren()) do
            if slot:IsA("GuiObject") then
                local slotCenterY = listOffsetY + GetSlotCenterY(slot)
                local dist = math.abs(slotCenterY - maskCenterY)
                local ratio = math.clamp(dist / maxDist, 0, 1)

                local uiScale = slot:FindFirstChildOfClass("UIScale")
                if not uiScale then
                    uiScale = Instance.new("UIScale")
                    uiScale.Parent = slot
                end

                uiScale.Scale = 1 - (ratio * ratio * 0.4) 
                
                local fadeAmount = ratio * ratio * 0.9 
                slot.BackgroundTransparency = fadeAmount
                local vp = slot:FindFirstChildWhichIsA("ViewportFrame")
                if vp then
                    vp.ImageTransparency = fadeAmount
                end
                
                local bg = slot:FindFirstChild("BG")
                if bg and bg:IsA("GuiObject") then
                    bg.BackgroundTransparency = fadeAmount
                    for _, child in pairs(bg:GetDescendants()) do
                        if child:IsA("TextLabel") then
                            child.TextTransparency = fadeAmount
                            child.TextStrokeTransparency = fadeAmount 
                        elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                            child.ImageTransparency = fadeAmount
                        end
                    end
                end
            end
        end
    end
-- ==========================================
    -- [🌟 新增：展示植�?3D 自转引擎]
    -- ==========================================
    local showcaseSpinConnection = nil
    
    local function StartShowcaseSpin()
        if showcaseSpinConnection then showcaseSpinConnection:Disconnect() end
        
        -- 使用渲染步进保证 60�?144�?极致顺滑
        showcaseSpinConnection = RunService.RenderStepped:Connect(function(dt)
            if not currentPage then return end
            -- 遍历那三个展示框 (Show_1, Show_2, Show_3)
            for i = 1, 3 do
                local showContainer = currentPage:FindFirstChild("Show_" .. i)
                if showContainer then
                    for _, slot in pairs(showContainer:GetChildren()) do
                        if slot:IsA("GuiObject") then
                            local vp = slot:FindFirstChild("Icom") or slot:FindFirstChildWhichIsA("ViewportFrame")
                            if vp then
                                -- 查找 ViewportFrame 里的真实 3D 模型并进行自�?
                                for _, child in ipairs(vp:GetChildren()) do
                                    if child:IsA("Model") and child.PrimaryPart then
                                        -- 速度: 每秒转动 60 度，想快点把 60 改大
                                        child:PivotTo(child:GetPivot() * CFrame.Angles(0, dt * math.rad(60), 0))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    local function StopShowcaseSpin()
        if showcaseSpinConnection then
            showcaseSpinConnection:Disconnect()
            showcaseSpinConnection = nil
        end
    end
    -- ==========================================
    -- [状�?1]：开启无限循环滚�?
    -- ==========================================
    local function StartIdleScroll()
        if idleConnection then idleConnection:Disconnect() end

        local pool = RollConfig.Pools[currentTab] or RollConfig.Pools[1]
        local poolCount = #pool
        local slots = GetScrollSlots()

        if #slots <= 0 then
            warn("RollController: current page ScrollList has no fixed Slot. It should be initialized from RollItemTemplate once during RollController.Init().")
            return
        end

        for index, slot in ipairs(slots) do
            if poolCount > 0 then
                local poolIndex = ((index - 1) % poolCount) + 1
                ConfigureSlot(slot, pool[poolIndex].Id)
            end
        end

        local setHeight = GetIdleLoopHeight(slots, poolCount)
        currentIdleY = 0

        idleConnection = RunService.RenderStepped:Connect(function(dt)
            local speed = 80 
            currentIdleY = currentIdleY - speed * dt
            
            if currentIdleY <= -setHeight then
                currentIdleY = currentIdleY + setHeight
            end
            
            scrollList.Position = UDim2.new(0, 0, 0, currentIdleY)
            Update3DVisuals()
        end)
    end

    -- ==========================================
    -- [状�?2]：玩家点击抽�?
    -- ==========================================
    local function StartDraw()
        if isRolling then return end
        
        -- �?1 页没有免费次数时允许服务端走 200K 阳光付费抽奖；第 2 页没有次数时先引导购买稀有抽奖次数�?
        if (currentTickets[currentTab] or 0) <= 0 and currentTab ~= 1 then
            MarketplaceService:PromptProductPurchase(player, TAB2_RARE_ROLL_PRODUCT_ID)
            return
        end
        
        isRolling = true

        if idleConnection then 
            idleConnection:Disconnect() 
            idleConnection = nil
        end
        
        -- 🌟 ========================================================
        -- 【核心联动】：向服务端发送抽奖请求，真正扣除次数并下发种子！
        local success, result = ReplicatedStorage:WaitForChild("PerformRollRF"):InvokeServer(currentTab)
        if not success then
            UIEffectUtil.ShowTip(result or "Error")
            isRolling = false
            StartIdleScroll()
            return
        end
        
        -- 服务器返回了真实验证过扣除了票据的最终奖�?
        local finalPrize = result
        -- 🌟 ========================================================
        
        local ADD_ITEMS = 20
        local EXTRA_PADDING = 5
        local MIN_RECOMMENDED_SLOT_COUNT = ADD_ITEMS + EXTRA_PADDING + 1
        local slots = GetScrollSlots()
        local slotCount = #slots

        if slotCount <= 0 then
            UIEffectUtil.ShowTip("Roll slots are not configured")
            isRolling = false
            StartIdleScroll()
            return
        end

        if slotCount < MIN_RECOMMENDED_SLOT_COUNT then
            warn("RollController: current page ScrollList has " .. slotCount .. " fixed Slots; recommend at least " .. MIN_RECOMMENDED_SLOT_COUNT .. " Slots for a longer draw animation.")
        end

        local WIN_INDEX = math.clamp(ADD_ITEMS, 1, math.max(1, slotCount - EXTRA_PADDING))

        for i, slot in ipairs(slots) do
            local itemId = i == WIN_INDEX and finalPrize or RollConfig.GetRandomPrize(currentTab)
            ConfigureSlot(slot, itemId)
        end

        local maskCenterY = maskFrame.AbsoluteSize.Y / 2
        local winSlot = slots[WIN_INDEX]
        local winItemCenterY = GetSlotCenterY(winSlot)
        local targetY = maskCenterY - winItemCenterY
        
        targetY = targetY + math.random(-25, 25) 

        local drawTweenInfo = TweenInfo.new(4.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        local drawTween = TweenService:Create(scrollList, drawTweenInfo, {
            Position = UDim2.new(0, 0, 0, targetY)
        })

        drawTween:Play()

        local drawVisualConnection = RunService.RenderStepped:Connect(function()
            Update3DVisuals()
        end)

        drawTween.Completed:Connect(function()
            drawVisualConnection:Disconnect()
            print("🎊 抽奖结束！玩家抽到了: " .. finalPrize .. " 🎊")

            local getFrameTemp = uiTemplates:FindFirstChild("GetFrame")
            if getFrameTemp then
                local getFrame = getFrameTemp:Clone()
                
                local vp = getFrame:FindFirstChild("GetViewport")
                if vp and vp:IsA("ViewportFrame") then
                    UIEffectUtil.RenderToViewport(vp, finalPrize, "Plant", 1)
                end
                
                getFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                getFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
                getFrame.Parent = rollPage
                
                local uiScale = getFrame:FindFirstChildOfClass("UIScale")
                if not uiScale then
                    uiScale = Instance.new("UIScale")
                    uiScale.Parent = getFrame
                end
                uiScale.Scale = 0.5 

                local popTween = TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                    Scale = 2
                })
                popTween:Play()

                local bg = getFrame:FindFirstChild("BG")
                local rotConnection
                if bg then
                    rotConnection = RunService.RenderStepped:Connect(function(dt)
                        bg.Rotation = bg.Rotation + (120 * dt) 
                    end)
                end

                task.wait(0.8)
                
                -- 👇 [🌟 核心联动：在收起动画时播放客户端满屏的礼花和通知！]
                local itemDetail = ItemConfig.Plants[finalPrize] or ItemConfig.Seeds[finalPrize]
                local itemName = itemDetail and itemDetail.Name or finalPrize
                UIEffectUtil.PlayConfettiEffect()
                UIEffectUtil.ShowTip("Congratulations, you obtained 1x " .. itemName)
                -- 👆 =========================================================

                local flyTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
                local flyTween = TweenService:Create(getFrame, flyTweenInfo, {
                    Position = UDim2.new(0.5, 0, 1, -50) 
                })
                local scaleDownTween = TweenService:Create(uiScale, flyTweenInfo, {
                    Scale = 0 
                })

                flyTween:Play()
                scaleDownTween:Play()

                flyTween.Completed:Connect(function()
                    if rotConnection then rotConnection:Disconnect() end
                    getFrame:Destroy()
                    
                    isRolling = false
                    StartIdleScroll() 
                end)
            else
                task.wait(2)
                isRolling = false
                StartIdleScroll() 
            end
        end)
    end

    -- ==========================================
    -- [处理按钮放大和移动的补间函数]
    -- ==========================================
    local function AnimateTab(button, isSelected, originalPos)
        if not button then return end
        
        local uiScale = button:FindFirstChildOfClass("UIScale")
        if not uiScale then
            uiScale = Instance.new("UIScale")
            uiScale.Parent = button
        end

        local targetScale, targetPositionXOffset

        if isSelected then
            targetScale = TAB_SELECTED_SCALE
            targetPositionXOffset = originalPos.X.Offset + TAB_SELECTED_OFFSET_X 
        else
            targetScale = 1 
            targetPositionXOffset = originalPos.X.Offset 
        end

        TweenService:Create(button, TAB_TWEEN_INFO, {
            Position = UDim2.new(originalPos.X.Scale, targetPositionXOffset, originalPos.Y.Scale, originalPos.Y.Offset)
        }):Play()

        TweenService:Create(uiScale, TAB_TWEEN_INFO, {
            Scale = targetScale
        }):Play()
    end

    -- ==========================================
    -- [多页签切换逻辑]
    -- ==========================================
    local function SwitchTab(tabIndex)
        if isRolling then return end 
        if currentTab == tabIndex then return end 
        
        currentTab = tabIndex
        RefreshCurrentPageRefs()
        print("切换抽奖池至：Tab_" .. currentTab)
        
        -- 🌟【关键修改】在这里加入主动调用，切换的一瞬间立刻换字�?延迟�?
        UpdateGetTimeText()
        
        AnimateTab(tab1Btn, currentTab == 1, tab1OriginalPos)
        AnimateTab(tab2Btn, currentTab == 2, tab2OriginalPos)
        
        -- 刷新文字 (Pull 数量)
        RefreshDrawButtonText()
        RefreshCashUI()
        
        SetupLowestProbShowcase()
        StartIdleScroll()
    end

    if tab1Btn and tab1Btn:IsA("GuiButton") then
        tab1Btn.MouseButton1Click:Connect(function() SwitchTab(1) end)
    end

    if tab2Btn and tab2Btn:IsA("GuiButton") then
        tab2Btn.MouseButton1Click:Connect(function() SwitchTab(2) end)
    end

    -- ==========================================
    -- [按键事件绑定]
    -- ==========================================
    openPageBtn.MouseButton1Click:Connect(function()
        rollPage.Enabled = true
        rollPage.DisplayOrder = 999 
        task.wait() 
        SyncRollTicketsFromServer()
        
        local targetTab = 1
        currentTab = targetTab
        RefreshCurrentPageRefs()
        
        -- 🌟【关键修改】页面被玩家点开时，根据判定好的 targetTab 立刻刷一次文�?
        UpdateGetTimeText()
        
        RefreshDrawButtonText()
        RefreshCashUI()
        
        AnimateTab(tab1Btn, currentTab == 1, tab1OriginalPos)
        AnimateTab(tab2Btn, currentTab == 2, tab2OriginalPos)
        
        SetupLowestProbShowcase()
        StartShowcaseSpin() -- 🌟【动画接入】打开页面，三个植物立刻开始自�?
        
        if not isRolling then
            StartIdleScroll()
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        if isRolling then return end 
        rollPage.Enabled = false
        StopShowcaseSpin() -- 🌟【动画释放】关闭页面，立刻停止旋转，杜绝吃电脑性能
        
        if idleConnection then 
            idleConnection:Disconnect()
            idleConnection = nil
        end
    end)

    for _, page in ipairs(pages) do
        local pageDrawBtn = page and page:FindFirstChild("DrawBtn")
        if pageDrawBtn and pageDrawBtn:IsA("GuiButton") then
            pageDrawBtn.MouseButton1Click:Connect(function()
                StartDraw()
            end)
        end
    end
    print("客户端：RollController (真实扣费红点校验系统) 加载完毕�?)")
end

return RollController

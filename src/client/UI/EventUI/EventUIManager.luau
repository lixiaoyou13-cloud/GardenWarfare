-- src/client/UI/EventUI/EventUIManager.luau
local EventUIManager = {}

local Players = game:GetService("Players")
local SevenDayPage = require(script.Parent.SevenDayPage)
local AchievePage = require(script.Parent.AchievePage) 
local UIEffectUtil = require(script.Parent.Parent.Parent.Utils.UIEffectUtil)

function EventUIManager.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    local eventPage = basicGui:WaitForChild("EventPage")
    -- 🌟 修复延迟：还原为 FindFirstChild，去掉等待时间，解决开局加载慢的问题！
    local overlay = eventPage:FindFirstChild("Overlay") 
    local sevenDayFrame = eventPage:FindFirstChild("7Day")
    local achieveFrame = eventPage:FindFirstChild("Achieve") 
    
    local playProperty = basicGui:FindFirstChild("PlayProperty")
    local achieveBtn = playProperty and playProperty:FindFirstChild("Achieve") 

    -- 🌟 状态锁：记录当前大容器是否处于打开状态，防止虚化请求重复叠加
    local isContainerOpen = false

    -- 统一打开容器的封装
    local function OpenEventContainer(targetPage)
        if not eventPage:IsA("ScreenGui") then return end
        
        -- 1. 开启大界面
        eventPage.DisplayOrder = 100
        eventPage.Enabled = true
        
        -- 2. 隐藏下方金币/属性栏
        if playProperty then
            if playProperty:IsA("ScreenGui") then playProperty.Enabled = false
            else playProperty.Visible = false end
        end

        -- 3. 激活遮罩
        if overlay then
            overlay.Visible = true
            overlay.BackgroundTransparency = 1
            overlay.Active = true
        end

        -- 4. 精准控制子页面显示：先开目标页，再关其他页，防止闪烁
        if targetPage then targetPage.Visible = true end
        if sevenDayFrame and targetPage ~= sevenDayFrame then sevenDayFrame.Visible = false end
        if achieveFrame and targetPage ~= achieveFrame then achieveFrame.Visible = false end

        -- 5. 调用虚化（安全锁：只有之前没开过虚化，这次才调用）
        if not isContainerOpen then
            isContainerOpen = true
            UIEffectUtil.SetScreenBlur(true, overlay)
        end
    end

    -- 统一关闭容器的封装
    local function CloseEventContainer()
        -- 撤销虚化
        if isContainerOpen then
            isContainerOpen = false
            UIEffectUtil.SetScreenBlur(false, overlay)
        end

        -- 恢复下方栏
        if playProperty then
            if playProperty:IsA("ScreenGui") then playProperty.Enabled = true
            else playProperty.Visible = true end
        end

        -- 延迟关闭大容器，等待虚化动画平滑消失
        task.delay(0.3, function()
            eventPage.Enabled = false
        end)
    end

    -- 监听子界面的关闭事件
    local function OnPageClosed()
        -- 只要有任何一个页面还在显示，就不关大容器；只有两个都关了才彻底撤销虚化
        local isSevenOpen = sevenDayFrame and sevenDayFrame.Visible
        local isAchieveOpen = achieveFrame and achieveFrame.Visible
        
        if not isSevenOpen and not isAchieveOpen then
            CloseEventContainer()
        end
    end

    if sevenDayFrame then
        sevenDayFrame:GetPropertyChangedSignal("Visible"):Connect(OnPageClosed)
    end

    if achieveFrame then
        achieveFrame:GetPropertyChangedSignal("Visible"):Connect(OnPageClosed)
    end

    -- 绑定大厅成就按钮
    if achieveBtn then
        achieveBtn.MouseButton1Click:Connect(function()
            OpenEventContainer(achieveFrame)
        end)
    end

    -- ==========================================
    -- 🌟 完全还原你原版代码开局秒出的执行逻辑！
    -- ==========================================
    -- 1. 游戏一启动，瞬间强制打开签到页容器与虚化（0延迟！）
    if eventPage:IsA("ScreenGui") then
        OpenEventContainer(sevenDayFrame)
    end

    -- 2. 初始化签到逻辑，加载网络数据
    if sevenDayFrame then
        SevenDayPage.Init(sevenDayFrame)
    end

    -- 3. 初始化成就逻辑（并确保开局时被隐藏，不遮挡签到页）
    if achieveFrame then
        AchievePage.Init(achieveFrame)
        achieveFrame.Visible = false
    end
end

return EventUIManager
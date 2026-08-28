local NoticeController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
local NoticeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NoticeConfig"))

local WAIT_TIMEOUT = 10
local GENERATED_ATTRIBUTE = "NoticeGenerated"
local BLUR_OVERLAY_NAME = "NoticeBlurOverlay"
local BLUR_OVERLAY_Z_INDEX = 1
local NOTICE_PANEL_MIN_Z_INDEX = 2
local forceCloseForBossImpl = nil

local function warnMissing(path)
    warn("[NoticeController] Missing UI object: " .. tostring(path))
end

local function setGuiOpen(gui, isOpen)
    if not gui then
        return
    end

    if gui:IsA("ScreenGui") then
        gui.Enabled = isOpen
    elseif gui:IsA("GuiObject") then
        gui.Visible = isOpen
    else
        pcall(function()
            gui.Enabled = isOpen
        end)
    end
end

local function hideOverlayInstant(overlay)
    if overlay and overlay:IsA("GuiObject") then
        overlay.BackgroundTransparency = 1
        overlay.Visible = false
        overlay.Active = false
    end
end

function NoticeController.ForceCloseForBoss()
    if forceCloseForBossImpl then
        forceCloseForBossImpl()
        return
    end

    local player = Players.LocalPlayer
    local playerGui = player and player:FindFirstChild("PlayerGui")
    local basicGui = playerGui and playerGui:FindFirstChild("BasicGui")
    local noticeGui = basicGui and basicGui:FindFirstChild("NoticeGui")
    if not noticeGui then
        return
    end

    hideOverlayInstant(noticeGui:FindFirstChild(BLUR_OVERLAY_NAME, true))
    setGuiOpen(noticeGui, false)
end

local function findButton(root)
    if not root then
        return nil
    end

    if root:IsA("GuiButton") then
        return root
    end

    return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function findGuiObject(root)
    if root and root:IsA("GuiObject") then
        return root
    end

    return nil
end

local function findTextObject(root, childName)
    if not root then
        return nil
    end

    local node = childName and root:FindFirstChild(childName, true) or root
    if not node then
        return nil
    end

    if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
        return node
    end

    return node:FindFirstChildWhichIsA("TextLabel", true)
        or node:FindFirstChildWhichIsA("TextButton", true)
        or node:FindFirstChildWhichIsA("TextBox", true)
end

local function setText(root, childName, text)
    local textObject = findTextObject(root, childName)
    if textObject then
        textObject.Text = tostring(text or "")
    end
end

local function escapeRichText(text)
    local escaped = tostring(text or "")
    escaped = string.gsub(escaped, "&", "&amp;")
    escaped = string.gsub(escaped, "<", "&lt;")
    escaped = string.gsub(escaped, ">", "&gt;")
    escaped = string.gsub(escaped, "\"", "&quot;")
    return escaped
end

local function highlightCdkText(text)
    local escaped = escapeRichText(text)
    return string.gsub(escaped, "%f[%w](%u+%d[%u%d]*)%f[%W]", function(code)
        return '<font color="#FFD84A"><b>' .. code .. '</b></font>'
    end)
end

local function setRichText(root, childName, text)
    local textObject = findTextObject(root, childName)
    if textObject then
        textObject.RichText = true
        textObject.Text = highlightCdkText(text)
    end
end

local function getOrCreateChildOfClass(parent, className)
    if not parent then
        return nil
    end

    local child = parent:FindFirstChildOfClass(className)
    if child then
        return child
    end

    child = Instance.new(className)
    child.Name = className
    child.Parent = parent
    return child
end

local function setStrokeToBorder(stroke)
    pcall(function()
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    end)
end

local function styleNoticeCard(card, options)
    if not card or not card:IsA("GuiObject") then
        return
    end

    card.Size = UDim2.new(options.WidthScale, 0, 0, options.MinHeight)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = options.BackgroundColor
    card.BackgroundTransparency = options.BackgroundTransparency
    card.BorderSizePixel = 0
    card.ClipsDescendants = false

    local textObject = findTextObject(card, nil)
    if textObject then
        textObject.TextWrapped = true
        textObject.TextScaled = false
        textObject.TextSize = options.TextSize
        textObject.TextColor3 = options.TextColor
        textObject.TextStrokeTransparency = 1
        textObject.TextXAlignment = options.TextXAlignment
        textObject.TextYAlignment = options.TextYAlignment
        textObject.LineHeight = options.LineHeight
        textObject.AutomaticSize = Enum.AutomaticSize.Y
        textObject.RichText = options.RichText == true
    end

    local corner = getOrCreateChildOfClass(card, "UICorner")
    if corner then
        corner.CornerRadius = UDim.new(0, options.CornerRadius)
    end

    local padding = getOrCreateChildOfClass(card, "UIPadding")
    if padding then
        padding.PaddingLeft = UDim.new(0, options.PaddingLeft)
        padding.PaddingRight = UDim.new(0, options.PaddingRight)
        padding.PaddingTop = UDim.new(0, options.PaddingTop)
        padding.PaddingBottom = UDim.new(0, options.PaddingBottom)
    end

    local stroke = card:FindFirstChildOfClass("UIStroke")
    if options.StrokeEnabled == false then
        if stroke then
            stroke.Enabled = false
        end
    elseif options.StrokeEnabled == true then
        stroke = stroke or getOrCreateChildOfClass(card, "UIStroke")
        if stroke then
            stroke.Enabled = true
            setStrokeToBorder(stroke)
            stroke.Color = options.StrokeColor
            stroke.Transparency = options.StrokeTransparency
            stroke.Thickness = options.StrokeThickness
        end
    end
end

local TITLE_CARD_STYLE = {
    WidthScale = 0.92,
    MinHeight = 44,
    BackgroundColor = Color3.fromRGB(12, 14, 18),
    BackgroundTransparency = 0.14,
    TextColor = Color3.fromRGB(255, 255, 255),
    TextSize = 23,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    LineHeight = 1.05,
    CornerRadius = 8,
    PaddingLeft = 14,
    PaddingRight = 14,
    PaddingTop = 8,
    PaddingBottom = 8,
    StrokeEnabled = false,
    RichText = false,
}

local TITLE_COLOR_PALETTE = {
    Color3.fromRGB(255, 215, 90),
    Color3.fromRGB(105, 205, 255),
    Color3.fromRGB(135, 235, 150),
    Color3.fromRGB(255, 150, 190),
    Color3.fromRGB(255, 175, 95),
}

local CONTENT_CARD_STYLE = {
    WidthScale = 0.93,
    MinHeight = 42,
    BackgroundColor = Color3.fromRGB(9, 11, 13),
    BackgroundTransparency = 0.12,
    TextColor = Color3.fromRGB(245, 250, 240),
    TextSize = 20,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    LineHeight = 1.08,
    CornerRadius = 7,
    PaddingLeft = 14,
    PaddingRight = 14,
    PaddingTop = 9,
    PaddingBottom = 9,
    StrokeEnabled = false,
    RichText = true,
}

local function setVisualEnabled(instance, enabled)
    if not instance then
        return
    end

    if instance:IsA("GuiObject") then
        instance.Visible = enabled
        return
    end

    pcall(function()
        instance.Enabled = enabled
    end)
end

local function hideNoticeBackground(noticeFrame)
    if not noticeFrame then
        return
    end

    if noticeFrame:IsA("GuiObject") then
        noticeFrame.BackgroundTransparency = 1
    end

    local backgroundGradient = noticeFrame:FindFirstChildOfClass("UIGradient")
    if backgroundGradient then
        backgroundGradient.Enabled = false
    end

    local decor = noticeFrame:FindFirstChild("Decor")
    if decor then
        for _, descendant in ipairs(decor:GetDescendants()) do
            if descendant:IsA("GuiObject") then
                descendant.Visible = false
            else
                pcall(function()
                    descendant.Enabled = false
                end)
            end
        end
    end
end

local function clearGeneratedChildren(root)
    if not root then
        return
    end

    for _, child in ipairs(root:GetChildren()) do
        if child:GetAttribute(GENERATED_ATTRIBUTE) == true then
            child:Destroy()
        end
    end
end

local function raiseGuiTree(root, minZIndex)
    if not root then
        return
    end

    if root:IsA("GuiObject") then
        root.ZIndex = math.max(root.ZIndex, minZIndex)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            descendant.ZIndex = math.max(descendant.ZIndex, minZIndex)
        end
    end
end

local function ensureBlurOverlay(noticeGui, noticeFrame)
    if not noticeGui then
        return nil
    end

    local overlayParent = noticeGui
    if not (overlayParent:IsA("ScreenGui") or overlayParent:IsA("GuiObject")) then
        overlayParent = noticeGui:FindFirstAncestorWhichIsA("ScreenGui") or noticeFrame
    end
    if not overlayParent then
        return nil
    end

    local overlay = overlayParent:FindFirstChild(BLUR_OVERLAY_NAME)
    if not overlay then
        overlay = Instance.new("Frame")
        overlay.Name = BLUR_OVERLAY_NAME
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.Position = UDim2.new(0, 0, 0, 0)
        overlay.AnchorPoint = Vector2.new(0, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.Visible = false
        overlay.Parent = overlayParent
    end

    if overlay:IsA("GuiObject") then
        overlay.Active = true
        overlay.ZIndex = BLUR_OVERLAY_Z_INDEX
    end

    raiseGuiTree(noticeFrame, NOTICE_PANEL_MIN_Z_INDEX)
    return overlay
end

local function parseDateScore(dateText)
    if type(dateText) ~= "string" then
        return nil
    end

    local year, month, day = string.match(dateText, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    if not (year and month and day) then
        return nil
    end

    if month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end

    return year * 10000 + month * 100 + day
end

local function getNotices()
    local notices = {}
    if type(NoticeConfig.Notices) ~= "table" then
        return notices
    end

    for _, notice in ipairs(NoticeConfig.Notices) do
        if type(notice) == "table" then
            table.insert(notices, notice)
        end
    end

    return notices
end

local function getDefaultNoticeIndex(notices)
    if #notices <= 0 then
        return nil
    end

    local defaultIndex = 1
    local bestScore = parseDateScore(notices[1].PublishedAt)
    for index = 2, #notices do
        local score = parseDateScore(notices[index].PublishedAt)
        if score and (not bestScore or score > bestScore) then
            defaultIndex = index
            bestScore = score
        end
    end

    return defaultIndex
end

local function getNoticeId(notice, index)
    if type(notice) ~= "table" then
        return ""
    end

    return tostring(notice.Id or notice.PublishedAt or notice.TagText or notice.Title or ("Notice_" .. tostring(index)))
end

local function trimText(text)
    return string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1")
end

local function getTitleColor(colorIndex)
    local index = math.max(1, math.floor(tonumber(colorIndex) or 1))
    return TITLE_COLOR_PALETTE[((index - 1) % #TITLE_COLOR_PALETTE) + 1]
end

local function getDisplayTitle(title, titleIndex, totalTitles)
    local cleanTitle = trimText(title)
    if cleanTitle == "" then
        cleanTitle = "Notice"
    end

    if (tonumber(totalTitles) or 0) >= 2 then
        return tostring(titleIndex) .. ". " .. cleanTitle
    end

    return cleanTitle
end

local SENTENCE_DELIMITERS = { ".", "!", "?", "。", "！", "？", "\n" }

local function isDecimalPoint(text, index)
    local prevChar = string.sub(text, index - 1, index - 1)
    local nextChar = string.sub(text, index + 1, index + 1)
    return string.match(prevChar, "%d") ~= nil and string.match(nextChar, "%d") ~= nil
end

local function findNextSentenceDelimiter(text, startIndex)
    local bestStart = nil
    local bestEnd = nil
    local bestDelimiter = nil

    for _, delimiter in ipairs(SENTENCE_DELIMITERS) do
        local searchStart = startIndex
        local delimiterStart, delimiterEnd = string.find(text, delimiter, searchStart, true)
        while delimiter == "." and delimiterStart and isDecimalPoint(text, delimiterStart) do
            searchStart = delimiterEnd + 1
            delimiterStart, delimiterEnd = string.find(text, delimiter, searchStart, true)
        end

        if delimiterStart and (not bestStart or delimiterStart < bestStart) then
            bestStart = delimiterStart
            bestEnd = delimiterEnd
            bestDelimiter = delimiter
        end
    end

    return bestStart, bestEnd, bestDelimiter
end

local function splitContentSentences(content)
    local text = trimText(content)
    local sentences = {}
    local startIndex = 1

    while startIndex <= #text do
        local delimiterStart, delimiterEnd, delimiter = findNextSentenceDelimiter(text, startIndex)
        if not delimiterStart then
            break
        end

        local sentenceEnd = delimiter == "\n" and delimiterStart - 1 or delimiterEnd
        local sentence = trimText(string.sub(text, startIndex, sentenceEnd))
        if sentence ~= "" then
            table.insert(sentences, sentence)
        end

        startIndex = delimiterEnd + 1
    end

    local tail = trimText(string.sub(text, startIndex))
    if tail ~= "" or #sentences <= 0 then
        table.insert(sentences, tail)
    end

    return sentences
end

local function getNoticeBlocks(notice)
    local blocks = {}
    if type(notice) ~= "table" then
        return blocks
    end

    if type(notice.Sections) == "table" then
        for _, section in ipairs(notice.Sections) do
            if type(section) == "table" then
                table.insert(blocks, {
                    Title = section.Title or "",
                    Sentences = splitContentSentences(section.Content),
                })
            end
        end
    end

    if #blocks <= 0 then
        table.insert(blocks, {
            Title = notice.Title or "",
            Sentences = splitContentSentences(notice.Content),
        })
    end

    return blocks
end

function NoticeController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
    if not playerGui then
        warnMissing("PlayerGui")
        return
    end

    local basicGui = playerGui:WaitForChild("BasicGui", WAIT_TIMEOUT)
    if not basicGui then
        warnMissing("PlayerGui/BasicGui")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", WAIT_TIMEOUT)
    local noticeGui = basicGui:WaitForChild("NoticeGui", WAIT_TIMEOUT)
    if not (playProperty and noticeGui) then
        warn("[NoticeController] PlayProperty or NoticeGui was not found.")
        return
    end

    local noticeButtonRoot = playProperty:WaitForChild("Notice", WAIT_TIMEOUT)
    local openButton = findButton(noticeButtonRoot)
    local noticeNotification = findGuiObject(noticeButtonRoot and noticeButtonRoot:FindFirstChild("Notifications"))
    local noticeFrame = noticeGui:WaitForChild("Notice", WAIT_TIMEOUT)
    local header = noticeFrame and noticeFrame:WaitForChild("Header", WAIT_TIMEOUT)
    local closeButton = findButton(header and header:WaitForChild("Buttons", WAIT_TIMEOUT))
    local typeButtons = noticeFrame and noticeFrame:WaitForChild("TypeButtons", WAIT_TIMEOUT)
    local container = noticeFrame and noticeFrame:WaitForChild("Container", WAIT_TIMEOUT)
    local dateTemplate = typeButtons and typeButtons:WaitForChild("Date", WAIT_TIMEOUT)
    local titleTemplate = container and container:WaitForChild("Title", WAIT_TIMEOUT)
    local contentTemplate = container and container:WaitForChild("Content", WAIT_TIMEOUT)
    local noticeStateRF = ReplicatedStorage:WaitForChild(NoticeConfig.StateRemoteName or "GetNoticeReadStateRF", WAIT_TIMEOUT)
    local markNoticeSeenRF = ReplicatedStorage:WaitForChild(NoticeConfig.MarkSeenRemoteName or "MarkNoticeSeenRF", WAIT_TIMEOUT)

    if not (openButton and closeButton and typeButtons and container and dateTemplate and titleTemplate and contentTemplate) then
        warn("[NoticeController] Notice UI binding is incomplete.")
        return
    end

    if noticeGui:IsA("ScreenGui") then
        noticeGui.DisplayOrder = math.max(noticeGui.DisplayOrder, 100)
    end

    if dateTemplate:IsA("GuiObject") then
        dateTemplate.Visible = false
    end
    if titleTemplate:IsA("GuiObject") then
        titleTemplate.Visible = false
    end
    if contentTemplate:IsA("GuiObject") then
        contentTemplate.Visible = false
    end
    hideNoticeBackground(noticeFrame)

    local notices = getNotices()
    local latestNoticeIndex = getDefaultNoticeIndex(notices)
    local latestNoticeId = latestNoticeIndex and getNoticeId(notices[latestNoticeIndex], latestNoticeIndex) or ""
    local noticeButtons = {}
    local selectedIndex = nil
    local blurOverlay = ensureBlurOverlay(noticeGui, noticeFrame)
    local isOpen = false
    local hasUnreadLatest = false

    local function setNoticeNotificationVisible(isVisible)
        if noticeNotification then
            noticeNotification.Visible = isVisible == true
        end
    end

    local function applyNoticeReadState(state)
        hasUnreadLatest = type(state) == "table"
            and state.LatestNoticeId == latestNoticeId
            and state.HasUnreadLatest == true
        setNoticeNotificationVisible(hasUnreadLatest)
    end

    local function refreshNoticeReadState()
        if latestNoticeId == "" or not noticeStateRF then
            hasUnreadLatest = false
            setNoticeNotificationVisible(false)
            return
        end

        local ok, state = pcall(function()
            return noticeStateRF:InvokeServer()
        end)

        if not ok then
            warn("[NoticeController] Get notice read state failed: " .. tostring(state))
            setNoticeNotificationVisible(false)
            return
        end

        applyNoticeReadState(state)
    end

    local function markLatestNoticeSeen()
        if latestNoticeId == "" or not hasUnreadLatest then
            setNoticeNotificationVisible(false)
            return
        end

        hasUnreadLatest = false
        setNoticeNotificationVisible(false)

        if not markNoticeSeenRF then
            return
        end

        task.spawn(function()
            local ok, success, state = pcall(function()
                return markNoticeSeenRF:InvokeServer(latestNoticeId)
            end)

            if not ok then
                warn("[NoticeController] Mark notice seen failed: " .. tostring(success))
                refreshNoticeReadState()
                return
            end

            if success == false then
                refreshNoticeReadState()
                return
            end

            if type(state) == "table" then
                applyNoticeReadState(state)
            end
        end)
    end

    local function updateButtonVisuals()
        for index, button in ipairs(noticeButtons) do
            local isSelected = index == selectedIndex
            setVisualEnabled(button:FindFirstChild("Selected"), isSelected)
            setVisualEnabled(button:FindFirstChild("NotSelected"), not isSelected)
        end
    end

    local function renderNoticeContent(notice)
        clearGeneratedChildren(container)

        if container:IsA("ScrollingFrame") then
            container.CanvasPosition = Vector2.new(0, 0)
        end

        local nextLayoutOrder = math.min(titleTemplate.LayoutOrder, contentTemplate.LayoutOrder)
        local contentIndex = 0

        local blocks = getNoticeBlocks(notice)
        for titleIndex, block in ipairs(blocks) do
            local titleLayoutOrder = nextLayoutOrder
            nextLayoutOrder += 1

            local titleClone = titleTemplate:Clone()
            titleClone.Name = "Title_" .. tostring(titleIndex)
            titleClone:SetAttribute(GENERATED_ATTRIBUTE, true)
            if titleClone:IsA("GuiObject") then
                titleClone.Visible = true
                titleClone.LayoutOrder = titleLayoutOrder
            end
            setText(titleClone, nil, getDisplayTitle(block.Title, titleIndex, #blocks))
            styleNoticeCard(titleClone, TITLE_CARD_STYLE)
            local titleTextObject = findTextObject(titleClone, nil)
            if titleTextObject then
                titleTextObject.TextColor3 = getTitleColor((selectedIndex or 1) + titleIndex - 1)
            end
            titleClone.Parent = container

            for _, sentence in ipairs(block.Sentences) do
                contentIndex += 1

                local contentClone = contentTemplate:Clone()
                contentClone.Name = "Content_" .. tostring(contentIndex)
                contentClone:SetAttribute(GENERATED_ATTRIBUTE, true)
                if contentClone:IsA("GuiObject") then
                    contentClone.Visible = true
                    contentClone.LayoutOrder = nextLayoutOrder
                end
                styleNoticeCard(contentClone, CONTENT_CARD_STYLE)
                setRichText(contentClone, nil, sentence)
                contentClone.Parent = container

                nextLayoutOrder += 1
            end
        end
    end

    local function selectNotice(index)
        if not index or not notices[index] then
            selectedIndex = nil
            updateButtonVisuals()
            clearGeneratedChildren(container)
            return
        end

        selectedIndex = index
        updateButtonVisuals()
        renderNoticeContent(notices[index])

        if isOpen and index == latestNoticeIndex then
            markLatestNoticeSeen()
        end
    end

    local function renderNoticeButtons()
        clearGeneratedChildren(typeButtons)

        for index, notice in ipairs(notices) do
            local button = dateTemplate:Clone()
            button.Name = "Date_" .. tostring(index)
            button:SetAttribute(GENERATED_ATTRIBUTE, true)
            if button:IsA("GuiObject") then
                button.Visible = true
                button.LayoutOrder = dateTemplate.LayoutOrder + index
            end
            setText(button, "Name", notice.TagText or notice.PublishedAt or notice.Title or ("Notice " .. tostring(index)))

            local clickButton = findButton(button)
            if clickButton then
                clickButton.Activated:Connect(function()
                    selectNotice(index)
                end)
            end

            button.Parent = typeButtons
            table.insert(noticeButtons, button)
        end
    end

    renderNoticeButtons()
    selectNotice(latestNoticeIndex)
    setGuiOpen(noticeGui, false)
    setNoticeNotificationVisible(false)
    task.spawn(refreshNoticeReadState)

    local function openNotice()
        if isOpen then
            return
        end

        if hasUnreadLatest and latestNoticeIndex then
            selectNotice(latestNoticeIndex)
        end

        if not selectedIndex then
            selectNotice(latestNoticeIndex)
        end

        setGuiOpen(noticeGui, true)
        isOpen = true
        UIEffectUtil.SetScreenBlur(true, blurOverlay)

        if selectedIndex == latestNoticeIndex then
            markLatestNoticeSeen()
        end
    end

    local function closeNotice()
        if not isOpen then
            setGuiOpen(noticeGui, false)
            return
        end

        isOpen = false
        UIEffectUtil.SetScreenBlur(false, blurOverlay)
        setGuiOpen(noticeGui, false)
    end

    local function forceCloseForBoss()
        closeNotice()
        hideOverlayInstant(blurOverlay)
    end

    forceCloseForBossImpl = forceCloseForBoss

    if not openButton:GetAttribute("NoticeOpenBound") then
        openButton:SetAttribute("NoticeOpenBound", true)
        openButton.Activated:Connect(function()
            openNotice()
        end)
    end

    if not closeButton:GetAttribute("NoticeCloseBound") then
        closeButton:SetAttribute("NoticeCloseBound", true)
        closeButton.Activated:Connect(function()
            closeNotice()
        end)
    end
end

return NoticeController

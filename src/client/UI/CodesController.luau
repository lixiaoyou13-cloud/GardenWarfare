-- src/client/UI/CodesController.luau
local CodesController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

local REMOTE_NAME = "RedeemCodeRF"

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

local function findButton(root)
    if not root then
        return nil
    end

    if root:IsA("GuiButton") then
        return root
    end

    return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function findTextBox(root)
    if not root then
        return nil
    end

    if root:IsA("TextBox") then
        return root
    end

    return root:FindFirstChildWhichIsA("TextBox", true)
end

local function getFallbackText(root)
    if not root then
        return ""
    end

    if root:IsA("TextLabel") or root:IsA("TextButton") then
        return root.Text or ""
    end

    local textNode = root:FindFirstChildWhichIsA("TextLabel", true)
        or root:FindFirstChildWhichIsA("TextButton", true)
    return textNode and textNode.Text or ""
end

function CodesController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    if not basicGui then
        warn("[CodesController] BasicGui was not found.")
        return
    end

    local playProperty = basicGui:WaitForChild("PlayProperty", 10)
    local codesPage = basicGui:WaitForChild("Codes", 10)
    if not (playProperty and codesPage) then
        warn("[CodesController] PlayProperty or Codes page was not found.")
        return
    end

    local openButton = findButton(playProperty:WaitForChild("Codes", 10))
    local codesFrame = codesPage:WaitForChild("CodesFrame", 10)
    if not codesFrame then
        warn("[CodesController] CodesFrame was not found.")
        return
    end

    local topFrame = codesFrame:WaitForChild("Top", 10)
    local closeButton = topFrame and findButton(topFrame:WaitForChild("Close", 10)) or nil
    local textCodeRoot = codesFrame:WaitForChild("TextCode", 10)
    local redeemButton = findButton(codesFrame:WaitForChild("Redeem", 10))
    local redeemCodeRF = ReplicatedStorage:WaitForChild(REMOTE_NAME, 10)

    if not (openButton and closeButton and textCodeRoot and redeemButton and redeemCodeRF) then
        warn("[CodesController] Codes UI binding is incomplete.")
        return
    end

    if codesPage:IsA("ScreenGui") then
        codesPage.DisplayOrder = math.max(codesPage.DisplayOrder, 100)
    end

    local textBox = findTextBox(textCodeRoot)
    local isRedeeming = false

    openButton.Activated:Connect(function()
        setGuiOpen(codesPage, true)
    end)

    closeButton.Activated:Connect(function()
        setGuiOpen(codesPage, false)
    end)

    redeemButton.Activated:Connect(function()
        if isRedeeming then
            UIEffectUtil.ShowTip("Redeem is processing.")
            return
        end

        local codeText = ""
        if textBox then
            codeText = textBox.Text or ""
            textBox:ReleaseFocus()
        else
            codeText = getFallbackText(textCodeRoot)
        end

        isRedeeming = true
        local ok, success, message = pcall(function()
            return redeemCodeRF:InvokeServer(codeText)
        end)
        isRedeeming = false

        if not ok then
            warn("[CodesController] RedeemCodeRF failed: " .. tostring(success))
            UIEffectUtil.ShowTip("Redeem failed: please try again later.")
            return
        end

        UIEffectUtil.ShowTip(tostring(message or (success and "Redeemed." or "Redeem failed.")))
        if success and textBox then
            textBox.Text = ""
        end
    end)
end

return CodesController

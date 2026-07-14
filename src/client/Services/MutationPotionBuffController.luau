local MutationPotionBuffController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local CLONE_PREFIX = "MutationPotionBuff_"

local activeBuffs = {}
local clonesByItemId = {}
local buffContainer = nil
local luckTemplate = nil

local function isTextObject(instance)
    return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function findTextObject(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local direct = root:FindFirstChild(name, true)
        if isTextObject(direct) then
            return direct
        end
    end

    return nil
end

local function findIconObject(root)
    if not root then
        return nil
    end

    if root:IsA("ImageLabel") or root:IsA("ImageButton") then
        return root
    end

    for _, name in ipairs({ "Icon", "Icom", "Image" }) do
        local direct = root:FindFirstChild(name, true)
        if direct and (direct:IsA("ImageLabel") or direct:IsA("ImageButton")) then
            return direct
        end
    end

    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
            return desc
        end
    end

    return nil
end

local function formatRemaining(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function copyBuffMap(buffMap)
    local result = {}
    if type(buffMap) ~= "table" then
        return result
    end

    for itemId, expiresAt in pairs(buffMap) do
        if type(itemId) == "string" then
            result[itemId] = tonumber(expiresAt) or 0
        end
    end

    return result
end

local function ensureClone(itemId, itemDetail)
    local clone = clonesByItemId[itemId]
    if clone and clone.Parent then
        return clone
    end

    if not buffContainer or not luckTemplate then
        return nil
    end

    clone = luckTemplate:Clone()
    clone.Name = CLONE_PREFIX .. itemId
    clone.Parent = buffContainer
    clone.Visible = true
    if clone:IsA("GuiObject") then
        clone.LayoutOrder = -(tonumber(itemDetail.MutationLevel) or 0)
    end
    clonesByItemId[itemId] = clone
    return clone
end

local function destroyClone(itemId)
    local clone = clonesByItemId[itemId]
    if clone then
        clone:Destroy()
        clonesByItemId[itemId] = nil
    end
end

local function renderBuffs()
    if not buffContainer or not luckTemplate then
        return
    end

    local now = os.time()
    local nextActive = {}

    for itemId, expiresAt in pairs(activeBuffs) do
        local itemDetail = ItemConfig.Items and ItemConfig.Items[itemId]
        local expiry = tonumber(expiresAt)
        if itemDetail and itemDetail.ItemType == "MutationPotion" and expiry and expiry > now then
            nextActive[itemId] = expiry

            local clone = ensureClone(itemId, itemDetail)
            if clone then
                local amountText = findTextObject(clone, { "Amount" })
                if amountText then
                    amountText.Text = tostring(itemDetail.AmountText or ((itemDetail.WeightBonusPercent or 0) .. "%"))
                end

                local timeText = findTextObject(clone, { "Time" })
                if timeText then
                    timeText.Text = formatRemaining(expiry - now)
                end

                local icon = findIconObject(clone)
                if icon then
                    local mutationIcon = ItemConfig.MutationIconIds and ItemConfig.MutationIconIds[tonumber(itemDetail.MutationLevel) or 1]
                    icon.Image = mutationIcon or itemDetail.IconId or ""
                    icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
                    icon.Visible = true
                end

                clone.Visible = true
            end
        end
    end

    for itemId in pairs(clonesByItemId) do
        if not nextActive[itemId] then
            destroyClone(itemId)
        end
    end

    activeBuffs = nextActive
end

local function setBuffs(buffMap)
    activeBuffs = copyBuffMap(buffMap)
    renderBuffs()
end

function MutationPotionBuffController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui", 10)
    local playProperty = basicGui and basicGui:WaitForChild("PlayProperty", 10)
    buffContainer = playProperty and playProperty:WaitForChild("BUFF", 10)
    luckTemplate = ReplicatedStorage:WaitForChild("UITemplates", 10) and ReplicatedStorage.UITemplates:WaitForChild("Luck", 10)

    if not buffContainer then
        warn("[MutationPotionBuffController] Missing BasicGui.PlayProperty.BUFF")
        return
    end

    if not luckTemplate then
        warn("[MutationPotionBuffController] Missing ReplicatedStorage.UITemplates.Luck")
        return
    end

    local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 10)
    if getPlayerDataRF then
        local ok, data = pcall(function()
            return getPlayerDataRF:InvokeServer()
        end)
        if ok and type(data) == "table" then
            setBuffs(data.ActiveMutationPotionBuffs)
        end
    end

    local playerDataPatchRE = ReplicatedStorage:WaitForChild("PlayerDataPatchRE", 10)
    if playerDataPatchRE then
        playerDataPatchRE.OnClientEvent:Connect(function(patch)
            if type(patch) == "table" and patch.ActiveMutationPotionBuffs ~= nil then
                setBuffs(patch.ActiveMutationPotionBuffs)
            end
        end)
    end

    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 10)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function(data)
            if type(data) == "table" and data.ActiveMutationPotionBuffs ~= nil then
                setBuffs(data.ActiveMutationPotionBuffs)
            end
        end)
    end

    task.spawn(function()
        while true do
            task.wait(1)
            renderBuffs()
        end
    end)
end

return MutationPotionBuffController

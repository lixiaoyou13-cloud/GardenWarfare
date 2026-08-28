local ExclusiveRollCompensationService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ExclusiveRollConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ExclusiveRollConfig"))

local CLAIM_FLAG = "ExclusiveRollRotobagaCompensation_V1"
local CHECK_FLAG = "ExclusiveRollRotobagaCompensationChecked_V1"
local REWARD_PLANT_ID = "Rotobaga"
local REWARD_AMOUNT = 1
local REWARD_MUTATION = 1
local LEGACY_PITY_DATA_KEY = "ExclusiveRollPity_Rotobaga"
local POPUP_DELAY_SECONDS = 3
local POPUP_MESSAGE = "Exclusive Roll Compensation\n\nYou previously purchased the Exclusive Plant Roll. As compensation, 1x Rotobaga has been sent to your inventory.\n\nThank you for supporting GardenWarfare!"

local checkedPlayers = {}

local showPopupRE = ReplicatedStorage:FindFirstChild("ShowCompensationPopupRE")
if not showPopupRE then
    showPopupRE = Instance.new("RemoteEvent")
    showPopupRE.Name = "ShowCompensationPopupRE"
    showPopupRE.Parent = ReplicatedStorage
end

local function buildExclusiveProductIdSet()
    local ids = {}
    for _, productConfig in pairs(ExclusiveRollConfig.Products or {}) do
        local productId = tonumber(productConfig.ProductId)
        if productId then
            ids[tostring(productId)] = true
        end
    end
    return ids
end

local EXCLUSIVE_PRODUCT_IDS = buildExclusiveProductIdSet()

local function hasFallbackReceiptEvidence(data)
    if type(data) ~= "table" then
        return false
    end

    local function checkReceiptKey(receiptKey)
        if type(receiptKey) ~= "string" then
            return false
        end

        local productId = receiptKey:match(":(%d+)$")
        return productId ~= nil and EXCLUSIVE_PRODUCT_IDS[productId] == true
    end

    if type(data.ProcessedReceiptOrder) == "table" then
        for _, receiptKey in ipairs(data.ProcessedReceiptOrder) do
            if checkReceiptKey(receiptKey) then
                return true
            end
        end
    end

    if type(data.ProcessedReceipts) == "table" then
        for receiptKey, processed in pairs(data.ProcessedReceipts) do
            if processed == true and checkReceiptKey(receiptKey) then
                return true
            end
        end
    end

    return false
end

local function hasExclusiveRollEvidence(data)
    if type(data) ~= "table" then
        return false
    end

    if math.max(0, math.floor(tonumber(data.ExclusiveRollPurchaseCount) or 0)) > 0 then
        return true
    end

    if math.max(0, math.floor(tonumber(data.ExclusiveRollTotalRolls) or 0)) > 0 then
        return true
    end

	if math.max(0, math.floor(tonumber(data[LEGACY_PITY_DATA_KEY]) or 0)) > 0 then
        return true
    end

    return hasFallbackReceiptEvidence(data)
end

local function markChecked(player, data)
    if type(data) ~= "table" or data[CHECK_FLAG] == true then
        return
    end

    data[CHECK_FLAG] = true
    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, "exclusive roll compensation check")
    if not saveQueued and saveErr ~= "stale_session" then
        warn("[ExclusiveRollCompensation] Failed to queue checked flag save for " .. player.Name .. ": " .. tostring(saveErr))
    end
end

local function showCompensationPopup(player)
    task.delay(POPUP_DELAY_SECONDS, function()
        if player and player.Parent then
            showPopupRE:FireClient(player, POPUP_MESSAGE)
        end
    end)
end

local function processPlayer(player)
    if checkedPlayers[player] then
        return
    end
    checkedPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 20)
    if not player.Parent or not data then
        checkedPlayers[player] = nil
        return
    end

    if data[CLAIM_FLAG] == true then
        return
    end

    if data[CHECK_FLAG] == true then
        return
    end

    if not hasExclusiveRollEvidence(data) then
        markChecked(player, data)
        return
    end

    data[CHECK_FLAG] = true
    local success, message = PlayerDataManager.GrantSavedChatGift(
        player,
        CLAIM_FLAG,
        REWARD_PLANT_ID,
        REWARD_AMOUNT,
        REWARD_MUTATION,
        0
    )

    if not success then
        warn("[ExclusiveRollCompensation] Grant failed for " .. player.Name .. ": " .. tostring(message))
        return
    end

    showCompensationPopup(player)
    print("[ExclusiveRollCompensation] Granted 1x Rotobaga to " .. player.Name)
end

function ExclusiveRollCompensationService.Init()
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(processPlayer, player)
    end

    Players.PlayerAdded:Connect(function(player)
        task.spawn(processPlayer, player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        checkedPlayers[player] = nil
    end)

    print("Server: ExclusiveRollCompensationService active.")
end

return ExclusiveRollCompensationService

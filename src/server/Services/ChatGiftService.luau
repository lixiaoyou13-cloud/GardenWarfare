-- src/server/Services/ChatGiftService.luau
local ChatGiftService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local REDEEM_CODE_RF_NAME = "RedeemCodeRF"
local GIFT_CODE = "gift"
local CLAIM_FLAG = "ChatGiftClaimed_V1"
local REWARD_PLANT_ID = "IceMelonpult"
local REWARD_PLANT_AMOUNT = 1
local REWARD_SUN = 200000
local TEST_COMMAND = "ces"
local TEST_REWARD_PLANT_ID = "Rotobaga"
local TEST_REWARD_PLANT_AMOUNT = 10
local TEST_REWARD_MUTATION = 1
local BUG551_CODE = "bug551"
local BUG551_CLAIM_FLAG = "Code_BUG551_Claimed"
local BUG551_ALLOWED_USERS = {
    ["reybaconpro357"] = true,
}
local BUG551_REWARDS = {
    { PlantId = "Rotobaga", Amount = 3, Mutation = 1 },
}
local PLANT666_CODE = "shgh4dwg5"
local PLANT666_CLAIM_FLAG = "Code_Plant666_Claimed"
local PLANT666_REWARDS = {
    { PlantId = "IceMelonpult", Amount = 1, Mutation = 1 },
    { PlantId = "FumeShroom", Amount = 4, Mutation = 1 },
}
local BUG9975_CODE = "bug9975"
local BUG9975_CLAIM_FLAG = "Code_BUG9975_Claimed"
local BUG9975_ALLOWED_USER_ID = 81010452
local BUG9975_REWARDS = {
    { PlantId = "Chomper", Amount = 1, Mutation = 2 },
}
local TB1234_CODE = "tb1234"
local TB1234_CLAIM_FLAG = "Code_TB1234_Claimed"
local TB1234_REWARDS = {
    { PlantId = "CherryBomb", Amount = 100, Mutation = 1 },
}
local LUCKY_CODE = "lucky"
local LUCKY_CLAIM_FLAG = "Code_Lucky_Claimed"
local LUCKY_REWARDS = {
    { ItemId = "ThunderPotion", Amount = 3 },
}

local claimingPlayers = {}
local chatConnections = {}

local function normalizeCommand(message)
    if type(message) ~= "string" then
        return ""
    end

    local trimmed = string.gsub(message, "^%s*(.-)%s*$", "%1")
    return string.lower(trimmed)
end

local function getOrCreateRedeemCodeRF()
    local redeemCodeRF = ReplicatedStorage:FindFirstChild(REDEEM_CODE_RF_NAME)
    if not redeemCodeRF then
        redeemCodeRF = Instance.new("RemoteFunction")
        redeemCodeRF.Name = REDEEM_CODE_RF_NAME
        redeemCodeRF.Parent = ReplicatedStorage
    end

    return redeemCodeRF
end

local function sendTip(player, message)
    local showTipRE = ReplicatedStorage:FindFirstChild("ShowTipRE")
    if showTipRE then
        showTipRE:FireClient(player, message)
    end
end

local function isTestCommandAllowed(player)
    if RunService:IsStudio() then
        return true
    end

    return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function claimGift(player)
    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local success, message = PlayerDataManager.GrantSavedChatGift(
        player,
        CLAIM_FLAG,
        REWARD_PLANT_ID,
        REWARD_PLANT_AMOUNT,
        1,
        REWARD_SUN
    )

    if not success then
        claimingPlayers[player] = nil
        return false, message or "Gift failed: please try again later."
    end

    claimingPlayers[player] = nil
    return true, "Gift claimed: 1x Ice Melon-pult + 200000 Sun!"
end

local function validatePlantRewards(rewards)
    for _, reward in ipairs(rewards) do
        local plantId = type(reward) == "table" and reward.PlantId or nil
        if not (ItemConfig.Plants and ItemConfig.Plants[plantId]) then
            return false, plantId
        end
    end

    return true
end

local function validateItemRewards(rewards)
    for _, reward in ipairs(rewards) do
        local itemId = type(reward) == "table" and reward.ItemId or nil
        if not (ItemConfig.Items and ItemConfig.Items[itemId]) then
            return false, itemId
        end
    end

    return true
end

local function isBug551CodeAllowed(player)
    local username = player and player.Name
    if type(username) ~= "string" then
        return false
    end

    return BUG551_ALLOWED_USERS[string.lower(username)] == true
end

local function claimBug551Code(player)
    if not isBug551CodeAllowed(player) then
        return false, "This code is not available for your account."
    end

    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local rewardsOk, missingPlantId = validatePlantRewards(BUG551_REWARDS)
    if not rewardsOk then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] BUG551 code plant config not found: " .. tostring(missingPlantId))
        return false, "Gift failed: reward config not found."
    end

    local success, message = PlayerDataManager.GrantSavedPlantBundle(
        player,
        BUG551_CLAIM_FLAG,
        BUG551_REWARDS
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Gift failed: please try again later."
    end

    return true, "Code claimed: 3x Rotobaga!"
end

local function claimPlant666Code(player)
    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local rewardsOk, missingPlantId = validatePlantRewards(PLANT666_REWARDS)
    if not rewardsOk then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] Plant666 code plant config not found: " .. tostring(missingPlantId))
        return false, "Gift failed: reward config not found."
    end

    local success, message = PlayerDataManager.GrantSavedPlantBundle(
        player,
        PLANT666_CLAIM_FLAG,
        PLANT666_REWARDS
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Gift failed: please try again later."
    end

    return true, "Code claimed: 1x Ice Melon-pult + 4x Fume-shroom!"
end

local function isBug9975CodeAllowed(player)
    return player and player.UserId == BUG9975_ALLOWED_USER_ID
end

local function claimBug9975Code(player)
    if not isBug9975CodeAllowed(player) then
        return false, "This code is not available for your account."
    end

    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local rewardsOk, missingPlantId = validatePlantRewards(BUG9975_REWARDS)
    if not rewardsOk then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] BUG9975 code plant config not found: " .. tostring(missingPlantId))
        return false, "Gift failed: reward config not found."
    end

    local success, message = PlayerDataManager.GrantSavedPlantBundle(
        player,
        BUG9975_CLAIM_FLAG,
        BUG9975_REWARDS
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Gift failed: please try again later."
    end

    return true, "Code claimed: 1x Shiny Chomper!"
end

local function claimTB1234Code(player)
    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local rewardsOk, missingPlantId = validatePlantRewards(TB1234_REWARDS)
    if not rewardsOk then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] TB1234 code plant config not found: " .. tostring(missingPlantId))
        return false, "Gift failed: reward config not found."
    end

    local success, message = PlayerDataManager.GrantSavedPlantBundle(
        player,
        TB1234_CLAIM_FLAG,
        TB1234_REWARDS
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Gift failed: please try again later."
    end

    return true, "Code claimed: 100x Cherry Bomb!"
end

local function claimLuckyCode(player)
    if claimingPlayers[player] then
        return false, "Redeem is already processing."
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        return false, "Gift failed: data is still loading."
    end

    local rewardsOk, missingItemId = validateItemRewards(LUCKY_REWARDS)
    if not rewardsOk then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] Lucky code item config not found: " .. tostring(missingItemId))
        return false, "Gift failed: reward config not found."
    end

    local success, message = PlayerDataManager.GrantSavedItemBundle(
        player,
        LUCKY_CLAIM_FLAG,
        LUCKY_REWARDS
    )

    claimingPlayers[player] = nil

    if not success then
        return false, message or "Gift failed: please try again later."
    end

    return true, "Code claimed: 3x Thunder Potion!"
end

local function redeemCode(player, rawCode)
    local code = normalizeCommand(rawCode)
    if code == "" then
        return false, "Please enter a code."
    end

    if code == BUG551_CODE then
        return claimBug551Code(player)
    end

    if code == PLANT666_CODE then
        return claimPlant666Code(player)
    end

    if code == BUG9975_CODE then
        return claimBug9975Code(player)
    end

    if code == TB1234_CODE then
        return claimTB1234Code(player)
    end

    if code == LUCKY_CODE then
        return claimLuckyCode(player)
    end

    if code ~= GIFT_CODE then
        return false, "Invalid code."
    end

    return claimGift(player)
end

local function claimTestPlants(player)
    if not isTestCommandAllowed(player) then
        return
    end

    if claimingPlayers[player] then
        sendTip(player, "Test reward is already processing.")
        return
    end

    claimingPlayers[player] = true

    local data = PlayerDataManager.WaitForPlayerData(player, 10)
    if not data then
        claimingPlayers[player] = nil
        sendTip(player, "Test reward failed: data is still loading.")
        return
    end

    if not (ItemConfig.Plants and ItemConfig.Plants[TEST_REWARD_PLANT_ID]) then
        claimingPlayers[player] = nil
        warn("[ChatGiftService] Test plant config not found: " .. TEST_REWARD_PLANT_ID)
        sendTip(player, "Test reward failed: plant config not found.")
        return
    end

    local ok, err = pcall(function()
        PlayerDataManager.GivePlant(
            player,
            TEST_REWARD_PLANT_ID,
            TEST_REWARD_PLANT_AMOUNT,
            TEST_REWARD_MUTATION,
            true
        )
    end)

    claimingPlayers[player] = nil

    if not ok then
        warn("[ChatGiftService] Test reward failed: " .. tostring(err))
        sendTip(player, "Test reward failed: please try again later.")
        return
    end

    sendTip(player, "Test reward: 10x Rotobaga added.")
end

local function bindPlayerChat(player)
    if chatConnections[player] then
        return
    end

    chatConnections[player] = player.Chatted:Connect(function(message)
        if normalizeCommand(message) == TEST_COMMAND then
            task.spawn(claimTestPlants, player)
        end
    end)
end

function ChatGiftService.Init()
    local redeemCodeRF = getOrCreateRedeemCodeRF()
    redeemCodeRF.OnServerInvoke = function(player, rawCode)
        local ok, success, message = pcall(redeemCode, player, rawCode)
        if not ok then
            claimingPlayers[player] = nil
            warn("[ChatGiftService] Redeem failed: " .. tostring(success))
            return false, "Redeem failed: please try again later."
        end

        return success, message
    end

    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayerChat(player)
    end

    Players.PlayerAdded:Connect(bindPlayerChat)

    Players.PlayerRemoving:Connect(function(player)
        claimingPlayers[player] = nil
        if chatConnections[player] then
            chatConnections[player]:Disconnect()
            chatConnections[player] = nil
        end
    end)
end

return ChatGiftService

local TradeService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(sharedFolder:WaitForChild("ItemConfig"))
local TradeConfig = require(sharedFolder:WaitForChild("TradeConfig"))

local remoteEvent = nil
local nextInviteId = 0
local nextSessionId = 0

local pendingInvites = {}
local playerToInviteId = {}
local tradeSessions = {}
local playerToSessionId = {}

local function getOrCreateRemoteEvent()
    local remoteName = TradeConfig.RemoteName or "TradeRE"
    local existing = ReplicatedStorage:FindFirstChild(remoteName)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end

    if existing then
        warn("[TradeService] " .. tostring(remoteName) .. " exists but is not a RemoteEvent.")
        return nil
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = remoteName
    remote.Parent = ReplicatedStorage
    return remote
end

local function fireClient(player, action, payload)
    if remoteEvent and player and player.Parent == Players then
        remoteEvent:FireClient(player, action, payload)
    end
end

local function fireError(player, message)
    fireClient(player, "Error", {
        Message = tostring(message or "Trade failed."),
    })
end

local function fireInventoryUpdate(player)
    local updateInventoryRE = ReplicatedStorage:FindFirstChild("UpdateInventoryRE")
    local data = PlayerDataManager.GetPlayerData(player)
    if updateInventoryRE and data then
        updateInventoryRE:FireClient(player, data)
    end
end

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

local function snapshotTradeData(data)
    return {
        Inventory = cloneValue(data.Inventory),
        Hotbar = cloneValue(data.Hotbar),
        UnlockedMutations = cloneValue(data.UnlockedMutations),
    }
end

local function restoreTradeData(data, snapshot)
    if type(data) ~= "table" or type(snapshot) ~= "table" then
        return
    end

    data.Inventory = cloneValue(snapshot.Inventory)
    data.Hotbar = cloneValue(snapshot.Hotbar)
    data.UnlockedMutations = cloneValue(snapshot.UnlockedMutations)
end

local function saveTradePlayer(player, context)
    local saveQueued, saveErr = PlayerDataManager.RequestSave(player, context)
    if not saveQueued and saveErr ~= "stale_session" then
        warn("[TradeService] Failed to save " .. tostring(player and player.Name) .. " after " .. tostring(context) .. ": " .. tostring(saveErr))
    end
    return saveQueued, saveErr
end

local function getRootPart(player)
    local character = player and player.Character
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA("BasePart")
end

local function arePlayersNear(playerA, playerB)
    local rootA = getRootPart(playerA)
    local rootB = getRootPart(playerB)
    if not rootA or not rootB then
        return false
    end

    local maxDistance = tonumber(TradeConfig.MaxInviteDistance) or 18
    return (rootA.Position - rootB.Position).Magnitude <= maxDistance
end

local function normalizeMutationLevel(mutationLevel)
    mutationLevel = math.floor(tonumber(mutationLevel) or 1)
    if mutationLevel < 1 then
        return 1
    end
    return mutationLevel
end

local function normalizeQuantity(quantity)
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity < 0 then
        quantity = 0
    end

    return math.min(quantity, tonumber(TradeConfig.MaxQuantityPerEntry) or 999)
end

local function getOfferKey(plantId, mutationLevel)
    return tostring(plantId) .. "_" .. tostring(normalizeMutationLevel(mutationLevel))
end

local function getPlantCount(data, plantId, mutationLevel)
    if type(data) ~= "table" or type(data.Inventory) ~= "table" or type(data.Inventory.Plants) ~= "table" then
        return 0
    end

    mutationLevel = normalizeMutationLevel(mutationLevel)
    local count = 0
    for _, plantData in ipairs(data.Inventory.Plants) do
        if plantData.ID == plantId and normalizeMutationLevel(plantData.Mutation or 1) == mutationLevel then
            count += math.max(0, math.floor(tonumber(plantData.Quantity) or 0))
        end
    end

    return count
end

local function isPlayerBusy(player)
    if not player then
        return true
    end

    return playerToInviteId[player.UserId] ~= nil or playerToSessionId[player.UserId] ~= nil
end

local function clearInvite(inviteId)
    local invite = pendingInvites[inviteId]
    if not invite then
        return nil
    end

    pendingInvites[inviteId] = nil
    if invite.Requester then
        playerToInviteId[invite.Requester.UserId] = nil
    end
    if invite.Target then
        playerToInviteId[invite.Target.UserId] = nil
    end

    return invite
end

local function offerToList(offer)
    local list = {}
    for _, entry in pairs(offer or {}) do
        table.insert(list, {
            PlantId = entry.PlantId,
            Mutation = normalizeMutationLevel(entry.Mutation),
            Quantity = math.max(1, math.floor(tonumber(entry.Quantity) or 1)),
        })
    end

    table.sort(list, function(a, b)
        if a.PlantId == b.PlantId then
            return (a.Mutation or 1) < (b.Mutation or 1)
        end
        return tostring(a.PlantId) < tostring(b.PlantId)
    end)

    return list
end

local function getPlayerInfo(player)
    return {
        UserId = player.UserId,
        Name = player.Name,
        DisplayName = player.DisplayName,
    }
end

local function buildSessionState(session)
    local playerA = session.PlayerA
    local playerB = session.PlayerB
    local userA = tostring(playerA.UserId)
    local userB = tostring(playerB.UserId)

    return {
        SessionId = session.Id,
        Players = {
            [userA] = getPlayerInfo(playerA),
            [userB] = getPlayerInfo(playerB),
        },
        PlayerOrder = { playerA.UserId, playerB.UserId },
        Offers = {
            [userA] = offerToList(session.Offers[playerA.UserId]),
            [userB] = offerToList(session.Offers[playerB.UserId]),
        },
        Ready = {
            [userA] = session.Ready[playerA.UserId] == true,
            [userB] = session.Ready[playerB.UserId] == true,
        },
        LastEmoji = cloneValue(session.LastEmoji or {}),
    }
end

local function broadcastSessionState(session)
    if not session or session.Closed then
        return
    end

    local state = buildSessionState(session)
    fireClient(session.PlayerA, "SessionState", state)
    fireClient(session.PlayerB, "SessionState", state)
end

local function resetReady(session)
    if not session then
        return
    end

    session.Ready[session.PlayerA.UserId] = false
    session.Ready[session.PlayerB.UserId] = false
end

local function clearSession(session)
    if not session then
        return
    end

    tradeSessions[session.Id] = nil
    if session.PlayerA then
        playerToSessionId[session.PlayerA.UserId] = nil
    end
    if session.PlayerB then
        playerToSessionId[session.PlayerB.UserId] = nil
    end
end

local function closeSession(session, reason)
    if not session or session.Closed then
        return
    end

    session.Closed = true
    clearSession(session)

    local payload = {
        SessionId = session.Id,
        Reason = reason or "Trade cancelled.",
    }
    fireClient(session.PlayerA, "SessionClosed", payload)
    fireClient(session.PlayerB, "SessionClosed", payload)
end

local function getSessionForPlayer(player)
    local sessionId = player and playerToSessionId[player.UserId]
    return sessionId and tradeSessions[sessionId] or nil
end

local function getTradePartner(session, player)
    if session.PlayerA == player then
        return session.PlayerB
    end
    if session.PlayerB == player then
        return session.PlayerA
    end
    return nil
end

local function validateOfferAgainstData(player, offer, data)
    local totalEntries = 0
    local totalQuantity = 0

    for _, entry in pairs(offer or {}) do
        totalEntries += 1
        if totalEntries > (tonumber(TradeConfig.MaxOfferEntries) or 60) then
            return false, "Too many trade items."
        end

        local plantId = tostring(entry.PlantId or "")
        local mutationLevel = normalizeMutationLevel(entry.Mutation)
        local quantity = normalizeQuantity(entry.Quantity)
        if plantId == "" or not ItemConfig.Plants[plantId] then
            return false, "Trade contains an unknown plant."
        end
        if quantity <= 0 then
            return false, "Trade contains an invalid quantity."
        end

        totalQuantity += quantity
        if getPlantCount(data, plantId, mutationLevel) < quantity then
            return false, tostring(player.Name) .. " no longer has enough " .. plantId .. "."
        end
    end

    return true, nil, totalEntries, totalQuantity
end

local function consumeOffer(player, offer)
    for _, entry in pairs(offer or {}) do
        local success = PlayerDataManager.ConsumePlant(
            player,
            entry.PlantId,
            normalizeQuantity(entry.Quantity),
            normalizeMutationLevel(entry.Mutation)
        )

        if not success then
            return false
        end
    end

    return true
end

local function grantOffer(player, offer)
    for _, entry in pairs(offer or {}) do
        PlayerDataManager.GivePlant(
            player,
            entry.PlantId,
            normalizeQuantity(entry.Quantity),
            normalizeMutationLevel(entry.Mutation),
            true
        )
    end
end

local function failExecutionWithRollback(session, dataA, dataB, snapshotA, snapshotB, reason)
    restoreTradeData(dataA, snapshotA)
    restoreTradeData(dataB, snapshotB)

    fireInventoryUpdate(session.PlayerA)
    fireInventoryUpdate(session.PlayerB)
    saveTradePlayer(session.PlayerA, "trade rollback player A")
    saveTradePlayer(session.PlayerB, "trade rollback player B")

    closeSession(session, reason or "Trade failed. Please try again.")
end

local function executeTrade(session)
    if not session or session.Executing or session.Closed then
        return
    end
    session.Executing = true

    local playerA = session.PlayerA
    local playerB = session.PlayerB
    if not (playerA and playerA.Parent == Players and playerB and playerB.Parent == Players) then
        closeSession(session, "Trade cancelled: player left.")
        return
    end

    if not PlayerDataManager.IsDataSafeToSave(playerA) or not PlayerDataManager.IsDataSafeToSave(playerB) then
        closeSession(session, "Trade failed: data is saving. Please try again.")
        return
    end

    local dataA = PlayerDataManager.GetPlayerData(playerA)
    local dataB = PlayerDataManager.GetPlayerData(playerB)
    if not dataA or not dataB then
        closeSession(session, "Trade failed: player data is still loading.")
        return
    end

    local offerA = session.Offers[playerA.UserId] or {}
    local offerB = session.Offers[playerB.UserId] or {}
    local okA, messageA, _, quantityA = validateOfferAgainstData(playerA, offerA, dataA)
    local okB, messageB, _, quantityB = validateOfferAgainstData(playerB, offerB, dataB)
    if not okA or not okB then
        session.Executing = false
        resetReady(session)
        fireError(playerA, messageA or messageB or "Trade offer is no longer valid.")
        fireError(playerB, messageA or messageB or "Trade offer is no longer valid.")
        broadcastSessionState(session)
        return
    end

    if (quantityA or 0) <= 0 and (quantityB or 0) <= 0 then
        session.Executing = false
        resetReady(session)
        fireError(playerA, "Add at least one plant to trade.")
        fireError(playerB, "Add at least one plant to trade.")
        broadcastSessionState(session)
        return
    end

    local snapshotA = snapshotTradeData(dataA)
    local snapshotB = snapshotTradeData(dataB)

    if not consumeOffer(playerA, offerA) then
        failExecutionWithRollback(session, dataA, dataB, snapshotA, snapshotB, "Trade failed: item is not available.")
        return
    end

    if not consumeOffer(playerB, offerB) then
        failExecutionWithRollback(session, dataA, dataB, snapshotA, snapshotB, "Trade failed: item is not available.")
        return
    end

    grantOffer(playerB, offerA)
    grantOffer(playerA, offerB)

    local savedA, saveErrA = saveTradePlayer(playerA, "trade complete player A")
    local savedB, saveErrB = saveTradePlayer(playerB, "trade complete player B")
    if not (savedA and savedB) then
        warn("[TradeService] Trade save failed for session " .. tostring(session.Id)
            .. ": savedA=" .. tostring(savedA)
            .. ", errA=" .. tostring(saveErrA)
            .. ", savedB=" .. tostring(savedB)
            .. ", errB=" .. tostring(saveErrB))
        failExecutionWithRollback(session, dataA, dataB, snapshotA, snapshotB, "Trade failed: save failed. Please try again.")
        return
    end

    session.Closed = true
    clearSession(session)

    fireClient(playerA, "TradeComplete", {
        SessionId = session.Id,
        Message = "Trade complete.",
    })
    fireClient(playerB, "TradeComplete", {
        SessionId = session.Id,
        Message = "Trade complete.",
    })
end

local function startSessionFromInvite(invite)
    if not invite or not invite.Requester or not invite.Target then
        return
    end

    if isPlayerBusy(invite.Requester) or isPlayerBusy(invite.Target) then
        fireClient(invite.Requester, "InviteClosed", { Message = "Player is busy." })
        fireClient(invite.Target, "InviteClosed", { Message = "Player is busy." })
        return
    end

    nextSessionId += 1
    local sessionId = "Trade_" .. tostring(nextSessionId)
    local session = {
        Id = sessionId,
        PlayerA = invite.Requester,
        PlayerB = invite.Target,
        Offers = {
            [invite.Requester.UserId] = {},
            [invite.Target.UserId] = {},
        },
        Ready = {
            [invite.Requester.UserId] = false,
            [invite.Target.UserId] = false,
        },
        LastEmoji = {},
        EmojiSeq = 0,
        CreatedAt = os.time(),
    }

    tradeSessions[sessionId] = session
    playerToSessionId[invite.Requester.UserId] = sessionId
    playerToSessionId[invite.Target.UserId] = sessionId

    local state = buildSessionState(session)
    fireClient(invite.Requester, "SessionStarted", state)
    fireClient(invite.Target, "SessionStarted", state)
end

local function requestInvite(player, targetPlayer)
    if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
        return
    end
    if player == targetPlayer then
        return
    end
    if player.Parent ~= Players or targetPlayer.Parent ~= Players then
        return
    end
    if isPlayerBusy(player) or isPlayerBusy(targetPlayer) then
        fireError(player, "Player is busy.")
        return
    end
    if not arePlayersNear(player, targetPlayer) then
        fireError(player, "Move closer to trade.")
        return
    end
    if not PlayerDataManager.GetPlayerData(player) or not PlayerDataManager.GetPlayerData(targetPlayer) then
        fireError(player, "Player data is still loading.")
        return
    end

    nextInviteId += 1
    local inviteId = "Invite_" .. tostring(nextInviteId)
    local invite = {
        Id = inviteId,
        Requester = player,
        Target = targetPlayer,
        CreatedAt = os.time(),
    }

    pendingInvites[inviteId] = invite
    playerToInviteId[player.UserId] = inviteId
    playerToInviteId[targetPlayer.UserId] = inviteId

    fireClient(player, "InvitePending", {
        InviteId = inviteId,
        TargetUserId = targetPlayer.UserId,
        TargetName = targetPlayer.DisplayName,
    })
    fireClient(targetPlayer, "InviteReceived", {
        InviteId = inviteId,
        FromUserId = player.UserId,
        FromName = player.DisplayName,
    })

    task.delay(tonumber(TradeConfig.InviteTimeoutSeconds) or 20, function()
        local pending = pendingInvites[inviteId]
        if not pending then
            return
        end

        clearInvite(inviteId)
        fireClient(pending.Requester, "InviteClosed", { Message = "Trade invite expired." })
        fireClient(pending.Target, "InviteClosed", { Message = "Trade invite expired." })
    end)
end

local function cancelInvite(player, inviteId)
    inviteId = tostring(inviteId or "")
    local invite = pendingInvites[inviteId]
    if not invite or (invite.Requester ~= player and invite.Target ~= player) then
        return
    end

    clearInvite(inviteId)
    fireClient(invite.Requester, "InviteClosed", { Message = "Trade invite cancelled." })
    fireClient(invite.Target, "InviteClosed", { Message = "Trade invite cancelled." })
end

local function respondInvite(player, inviteId, accepted)
    inviteId = tostring(inviteId or "")
    local invite = pendingInvites[inviteId]
    if not invite or invite.Target ~= player then
        return
    end

    clearInvite(inviteId)
    if accepted ~= true then
        fireClient(invite.Requester, "InviteClosed", { Message = player.DisplayName .. " declined the trade." })
        fireClient(invite.Target, "InviteClosed", { Message = "Trade declined." })
        return
    end

    if not arePlayersNear(invite.Requester, invite.Target) then
        fireClient(invite.Requester, "InviteClosed", { Message = "Trade failed: players moved too far away." })
        fireClient(invite.Target, "InviteClosed", { Message = "Trade failed: players moved too far away." })
        return
    end

    startSessionFromInvite(invite)
end

local function setOfferItem(player, payload)
    local session = getSessionForPlayer(player)
    if not session or session.Closed then
        return
    end

    if type(payload) ~= "table" then
        return
    end

    local plantId = tostring(payload.PlantId or "")
    local mutationLevel = normalizeMutationLevel(payload.Mutation)
    local quantity = normalizeQuantity(payload.Quantity)
    if plantId == "" or not ItemConfig.Plants[plantId] then
        fireError(player, "Unknown plant.")
        return
    end

    local data = PlayerDataManager.GetPlayerData(player)
    if not data then
        fireError(player, "Player data is still loading.")
        return
    end

    local offer = session.Offers[player.UserId]
    if not offer then
        return
    end

    local key = getOfferKey(plantId, mutationLevel)
    if quantity <= 0 then
        offer[key] = nil
        resetReady(session)
        broadcastSessionState(session)
        return
    end

    local owned = getPlantCount(data, plantId, mutationLevel)
    if owned <= 0 then
        fireError(player, "You do not have this plant.")
        return
    end

    quantity = math.min(quantity, owned)
    if not offer[key] then
        local entries = 0
        for _ in pairs(offer) do
            entries += 1
        end
        if entries >= (tonumber(TradeConfig.MaxOfferEntries) or 60) then
            fireError(player, "Too many trade items.")
            return
        end
    end

    offer[key] = {
        PlantId = plantId,
        Mutation = mutationLevel,
        Quantity = quantity,
    }

    resetReady(session)
    broadcastSessionState(session)
end

local function setReady(player, isReady)
    local session = getSessionForPlayer(player)
    if not session or session.Closed or session.Executing then
        return
    end

    session.Ready[player.UserId] = isReady == true
    broadcastSessionState(session)

    if session.Ready[session.PlayerA.UserId] and session.Ready[session.PlayerB.UserId] then
        executeTrade(session)
    end
end

-- 同步交易表情，并给每次点击生成递增序号，方便客户端重复播放反馈动画。
local function sendEmoji(player, emojiKey)
    local session = getSessionForPlayer(player)
    if not session or session.Closed then
        return
    end

    emojiKey = tostring(emojiKey or "")
    if emojiKey ~= "OK" and emojiKey ~= "NO" then
        return
    end

    session.EmojiSeq = (tonumber(session.EmojiSeq) or 0) + 1
    session.LastEmoji[tostring(player.UserId)] = {
        Kind = emojiKey,
        SentAt = os.time(),
        Seq = session.EmojiSeq,
    }
    broadcastSessionState(session)
end

local function cancelSessionByPlayer(player)
    local session = getSessionForPlayer(player)
    if not session then
        return
    end

    local partner = getTradePartner(session, player)
    local reason = "Trade cancelled."
    if partner then
        reason = player.DisplayName .. " cancelled the trade."
    end
    closeSession(session, reason)
end

local function cancelAnyByPlayer(player)
    local inviteId = player and playerToInviteId[player.UserId]
    if inviteId then
        local invite = clearInvite(inviteId)
        if invite then
            fireClient(invite.Requester, "InviteClosed", { Message = "Trade invite cancelled." })
            fireClient(invite.Target, "InviteClosed", { Message = "Trade invite cancelled." })
        end
        return
    end

    cancelSessionByPlayer(player)
end

local function cleanupPlayer(player)
    local inviteId = playerToInviteId[player.UserId]
    if inviteId then
        local invite = clearInvite(inviteId)
        if invite then
            local other = invite.Requester == player and invite.Target or invite.Requester
            fireClient(other, "InviteClosed", { Message = "Trade invite cancelled: player left." })
        end
    end

    local session = getSessionForPlayer(player)
    if session then
        closeSession(session, "Trade cancelled: player left.")
    end
end

function TradeService.Init()
    remoteEvent = getOrCreateRemoteEvent()
    if not remoteEvent then
        return
    end

    remoteEvent.OnServerEvent:Connect(function(player, action, payload, payload2)
        action = tostring(action or "")

        if action == "RequestInvite" then
            requestInvite(player, payload)
        elseif action == "CancelInvite" then
            cancelInvite(player, payload)
        elseif action == "RespondInvite" then
            respondInvite(player, payload, payload2)
        elseif action == "SetOfferItem" then
            setOfferItem(player, payload)
        elseif action == "RemoveOfferItem" then
            if type(payload) == "table" then
                payload.Quantity = 0
                setOfferItem(player, payload)
            end
        elseif action == "SetReady" then
            setReady(player, payload == true)
        elseif action == "CancelSession" then
            cancelSessionByPlayer(player)
        elseif action == "CancelAny" then
            cancelAnyByPlayer(player)
        elseif action == "Emoji" then
            sendEmoji(player, payload)
        end
    end)

    Players.PlayerRemoving:Connect(cleanupPlayer)
end

return TradeService

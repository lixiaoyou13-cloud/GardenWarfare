local PassQuestConfig = {}

PassQuestConfig.StateRemoteName = "GetPassQuestStateRF"
PassQuestConfig.ClaimRemoteName = "ClaimPassQuestRF"
PassQuestConfig.UpdateRemoteName = "UpdatePassQuestStateRE"

PassQuestConfig.RefreshIntervalSeconds = 24 * 60 * 60

PassQuestConfig.TaskIds = {
    EnterGame = "EnterGame",
    OnlineDuration = "OnlineDuration",
    DefeatZombies = "DefeatZombies",
    HarvestPlants = "HarvestPlants",
    OpenAirdrop = "OpenAirdrop",
}

PassQuestConfig.Tasks = {
    {
        Slot = 1,
        Id = PassQuestConfig.TaskIds.EnterGame,
        DisplayName = "Enter Game",
        Target = 1,
        RewardExp = 100,
    },
    {
        Slot = 2,
        Id = PassQuestConfig.TaskIds.OnlineDuration,
        DisplayName = "OnlineDuration",
        Target = 15,
        RewardExp = 50,
    },
    {
        Slot = 3,
        Id = PassQuestConfig.TaskIds.DefeatZombies,
        DisplayName = "Defeat Zombies",
        Target = 200,
        RewardExp = 50,
    },
    {
        Slot = 4,
        Id = PassQuestConfig.TaskIds.HarvestPlants,
        DisplayName = "Harvest Plants",
        Target = 3,
        RewardExp = 50,
    },
    {
        Slot = 5,
        Id = PassQuestConfig.TaskIds.OpenAirdrop,
        DisplayName = "Open an Airdrop Once",
        Target = 1,
        RewardExp = 50,
    },
}

PassQuestConfig.TasksById = {}
PassQuestConfig.TasksBySlot = {}

for _, taskConfig in ipairs(PassQuestConfig.Tasks) do
    PassQuestConfig.TasksById[taskConfig.Id] = taskConfig
    PassQuestConfig.TasksBySlot[taskConfig.Slot] = taskConfig
end

function PassQuestConfig.NormalizeTaskId(taskId)
    if type(taskId) == "number" then
        local taskConfig = PassQuestConfig.TasksBySlot[math.floor(taskId)]
        return taskConfig and taskConfig.Id or nil
    end

    taskId = tostring(taskId or "")
    local slot = tonumber(taskId)
    if slot then
        local taskConfig = PassQuestConfig.TasksBySlot[math.floor(slot)]
        return taskConfig and taskConfig.Id or nil
    end

    if PassQuestConfig.TasksById[taskId] then
        return taskId
    end

    return nil
end

function PassQuestConfig.GetTaskById(taskId)
    taskId = PassQuestConfig.NormalizeTaskId(taskId)
    return taskId and PassQuestConfig.TasksById[taskId] or nil
end

function PassQuestConfig.GetTaskBySlot(slot)
    slot = math.floor(tonumber(slot) or 0)
    return PassQuestConfig.TasksBySlot[slot]
end

function PassQuestConfig.GetUtcDayKey(timestamp)
    local utc = os.date("!*t", timestamp or os.time())
    return string.format("%04d-%02d-%02d", utc.year, utc.month, utc.day)
end

function PassQuestConfig.GetNextUtcMidnight(timestamp)
    timestamp = math.floor(tonumber(timestamp) or os.time())
    local utc = os.date("!*t", timestamp)
    local secondsIntoDay = (utc.hour * 60 * 60) + (utc.min * 60) + utc.sec
    return timestamp - secondsIntoDay + PassQuestConfig.RefreshIntervalSeconds
end

return PassQuestConfig

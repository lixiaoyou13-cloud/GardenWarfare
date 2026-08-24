local ChestConfig = {}

ChestConfig.Chests = {
    Chest1 = {
        Name = "Chest I",
        Price = 320000,
        ImageId = "rbxassetid://114584466817458",
        Rewards = {
            { PlantId = "PotatoMine", Weight = 75 },
            { PlantId = "FumeShroom", Weight = 20 },
            { PlantId = "Magnetshroom", Weight = 5 },
        },
    },
    Chest2 = {
        Name = "Chest II",
        Price = 1500000,
        ImageId = "rbxassetid://95395831296302",
        Rewards = {
            { PlantId = "Jalapeno", Weight = 75 },
            { PlantId = "Cactus", Weight = 20 },
            { PlantId = "Sunflower", Weight = 5 },
        },
    },
    Chest3 = {
        Name = "Chest III",
        Price = 8000000,
        ImageId = "rbxassetid://109754446279651",
        Rewards = {
            { PlantId = "TwinSunflower", Weight = 75 },
            { PlantId = "Melonpult", Weight = 20 },
            { PlantId = "Threepeater", Weight = 5 },
        },
    },
    Chest4 = {
        Name = "Chest IV",
        Price = 55000000,
        ImageId = "rbxassetid://127341979114740",
        Rewards = {
            { PlantId = "IceMelonpult", Weight = 75 },
            { PlantId = "CobCannon", Weight = 20 },
            { PlantId = "MusicIcePeashooter", Weight = 5 },
        },
    },
}

function ChestConfig.GetChest(chestId)
    return ChestConfig.Chests[chestId]
end

function ChestConfig.GetTotalWeight(chestId)
    local chest = ChestConfig.GetChest(chestId)
    if not chest then
        return 0
    end

    local totalWeight = 0
    for _, reward in ipairs(chest.Rewards or {}) do
        totalWeight += math.max(0, tonumber(reward.Weight) or 0)
    end

    return totalWeight
end

function ChestConfig.RollReward(chestId, rng)
    local chest = ChestConfig.GetChest(chestId)
    if not chest then
        return nil
    end

    local totalWeight = ChestConfig.GetTotalWeight(chestId)
    if totalWeight <= 0 then
        return nil
    end

    local roll = rng and rng:NextNumber(0, totalWeight) or math.random() * totalWeight
    local runningWeight = 0

    for _, reward in ipairs(chest.Rewards or {}) do
        local weight = math.max(0, tonumber(reward.Weight) or 0)
        runningWeight += weight
        if roll <= runningWeight then
            return reward.PlantId, reward.MutationLevel or 1, reward
        end
    end

    local fallbackReward = chest.Rewards and chest.Rewards[#chest.Rewards]
    if fallbackReward then
        return fallbackReward.PlantId, fallbackReward.MutationLevel or 1, fallbackReward
    end

    return nil
end

return ChestConfig

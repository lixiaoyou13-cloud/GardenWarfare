local ExclusiveRollConfig = {
    ResultEventName = "ExclusiveRollResultRE",
    RewardShowEventName = "ExclusiveRollRewardShowRE",
    TicketRollRemoteName = "UseExclusiveRollTicketRF",

    OutcomesPath = { "Store", "StoreFrame", "Container", "Exclusive", "Outcomes" },
    RewardShow = {
        ShowPath = { "Show" },
        IconName = "Icon",
        Duration = 1.5,
        MoveDuration = 0.45,
        TargetPosition = UDim2.new(0.5, 0, 0.82, 0),
    },
    OutcomeOrder = {
        "FumeShroom",
        "Magnetshroom",
        "IceMelonpult",
        "CobCannon",
        "AppleMortar",
        "Rotobaga",
    },

    Animation = {
        SelectedGradientColor = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
        PreAnimationDelay = 1,
        DurationByProductKey = {
            OneRoll = 1.8,
            TicketRoll = 1.8,
            ThreeRolls = 0.75,
            TenRolls = 0.75,
            Exclusive1OneRoll = 1.8,
            Exclusive1TenRolls = 0.75,
            Exclusive2FreeRoll = 1.8,
            Exclusive2OneRoll = 1.8,
        },
        ResultHoldDuration = 1,
        GrantDelayPadding = 0.15,
    },

    Products = {
        OneRoll = {
            ProductId = 3606332838,
            RollCount = 1,
            ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive", "BuyButtons", "Buttons1" },
        },
        ThreeRolls = {
            ProductId = 0,
            RollCount = 3,
            ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive", "BuyButtons", "Buttons2" },
            Hidden = true,
        },
        TenRolls = {
            ProductId = 3606333008,
            RollCount = 10,
            ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive", "BuyButtons", "Buttons3" },
        },
    },

    TicketRoll = {
        RollCount = 1,
        DataKey = "ExclusiveRollTickets",
        ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive", "BuyButtons", "Buttons0" },
        PriceTextPath = { "Info", "Price" },
        CountsAsPurchase = false,
    },

    ShopRolls = {
        Exclusive1 = {
            OutcomesPath = { "Store", "StoreFrame", "Container", "Exclusive1", "Outcomes" },
            OutcomeOrder = {
                "SnowPea",
                "Jalapeno",
                "Melonpult",
                "IceMelonpult",
                "CobCannon",
                "MusicIcePeashooter",
            },
            Pool = {
                { PlantId = "SnowPea", Weight = 34 },
                { PlantId = "Jalapeno", Weight = 30 },
                { PlantId = "Melonpult", Weight = 20 },
                { PlantId = "IceMelonpult", Weight = 10 },
                { PlantId = "CobCannon", Weight = 4 },
                { PlantId = "MusicIcePeashooter", Weight = 2 },
            },
            Products = {
                Exclusive1OneRoll = {
                    ProductId = 3599579545,
                    RollCount = 1,
                    ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive1", "BuyButtons", "Buttons1" },
                    RollGroup = "Exclusive1",
                    CountsAsPurchase = false,
                    CountsTotalRolls = false,
                },
                Exclusive1TenRolls = {
                    ProductId = 3606332965,
                    RollCount = 10,
                    ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive1", "BuyButtons", "Buttons2" },
                    RollGroup = "Exclusive1",
                    CountsAsPurchase = false,
                    CountsTotalRolls = false,
                },
            },
            Reward = {
                Amount = 1,
                Mutation = 1,
            },
        },
        Exclusive2 = {
            OutcomesPath = { "Store", "StoreFrame", "Container", "Exclusive2", "Outcomes" },
            OutcomeOrder = {
                "KernelPult",
                "RadishShooter",
                "PotatoMine",
                "Cactus",
                "Sunflower",
                "IceMelonpult",
            },
            Pool = {
                { PlantId = "KernelPult", Weight = 35 },
                { PlantId = "RadishShooter", Weight = 25 },
                { PlantId = "PotatoMine", Weight = 20 },
                { PlantId = "Cactus", Weight = 13 },
                { PlantId = "Sunflower", Weight = 6 },
                { PlantId = "IceMelonpult", Weight = 1 },
            },
            FreeRoll = {
                RemoteName = "UseExclusive2FreeRollRF",
                UseSessionTimer = true,
                CooldownSeconds = 300,
                RollCount = 1,
                ProductKey = "Exclusive2FreeRoll",
                ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive2", "BuyButtons", "Buttons1" },
                PriceTextPath = { "Info", "Price" },
                ReadyText = "Claim",
            },
            Products = {
                Exclusive2OneRoll = {
                    ProductId = 3607170575,
                    RollCount = 1,
                    ButtonPath = { "Store", "StoreFrame", "Container", "Exclusive2", "BuyButtons", "Buttons2" },
                    RollGroup = "Exclusive2",
                    CountsAsPurchase = false,
                    CountsTotalRolls = false,
                },
            },
            Reward = {
                Amount = 1,
                Mutation = 1,
            },
        },
    },

    HiddenButtonPaths = {
        { "Store", "StoreFrame", "Container", "Exclusive", "BuyButtons", "Buttons2" },
    },

    Pool = {
        { PlantId = "FumeShroom", Weight = 40 },
        { PlantId = "Magnetshroom", Weight = 30 },
        { PlantId = "IceMelonpult", Weight = 12.5 },
        { PlantId = "CobCannon", Weight = 10 },
        { PlantId = "AppleMortar", Weight = 5 },
        { PlantId = "Rotobaga", Weight = 2.5 },
    },

    Pity = {
        TargetPlantId = "Rotobaga",
        GuaranteeAt = 50,
        DataKey = "ExclusiveRollPity_Rotobaga",
        TextPath = { "Store", "StoreFrame", "Container", "Exclusive", "Pity" },
        ResetWhenHitTarget = true,
    },

    Reward = {
        Amount = 1,
        Mutation = 1,
    },
}

function ExclusiveRollConfig.GetRollGroupConfig(rollGroup)
    if type(rollGroup) == "string" then
        local shopRolls = ExclusiveRollConfig.ShopRolls or {}
        local groupConfig = shopRolls[rollGroup]
        if type(groupConfig) == "table" then
            return groupConfig, rollGroup
        end
    end

    return ExclusiveRollConfig, "Exclusive"
end

function ExclusiveRollConfig.GetProductRollConfig(productConfig)
    if type(productConfig) == "table" then
        return ExclusiveRollConfig.GetRollGroupConfig(productConfig.RollGroup)
    end

    return ExclusiveRollConfig, "Exclusive"
end

function ExclusiveRollConfig.GetProductById(productId)
    productId = tonumber(productId)
    if not productId then
        return nil, nil
    end

    for groupKey, groupConfig in pairs(ExclusiveRollConfig.ShopRolls or {}) do
        for productKey, productConfig in pairs(groupConfig.Products or {}) do
            if tonumber(productConfig.ProductId) == productId then
                return productConfig, productKey, groupConfig, groupKey
            end
        end
    end

    for productKey, productConfig in pairs(ExclusiveRollConfig.Products) do
        if tonumber(productConfig.ProductId) == productId then
            return productConfig, productKey, ExclusiveRollConfig, "Exclusive"
        end
    end

    return nil, nil
end

function ExclusiveRollConfig.GetOutcomeIndex(plantId, rollGroup)
    local rollConfig = ExclusiveRollConfig.GetRollGroupConfig(rollGroup)
    for index, outcomePlantId in ipairs(rollConfig.OutcomeOrder or {}) do
        if outcomePlantId == plantId then
            return index
        end
    end

    return nil
end

function ExclusiveRollConfig.GetRollAnimationDuration(productKey)
    local animation = ExclusiveRollConfig.Animation or {}
    local durationByProductKey = animation.DurationByProductKey or {}
    return math.max(0, tonumber(durationByProductKey[productKey]) or 0.5)
end

function ExclusiveRollConfig.GetResultHoldDuration()
    local animation = ExclusiveRollConfig.Animation or {}
    return math.max(0, tonumber(animation.ResultHoldDuration) or 0)
end

function ExclusiveRollConfig.GetGrantDelayPadding()
    local animation = ExclusiveRollConfig.Animation or {}
    return math.max(0, tonumber(animation.GrantDelayPadding) or 0)
end

function ExclusiveRollConfig.GetAnimationDuration(productKey, rollCount)
    local perRollDuration = ExclusiveRollConfig.GetRollAnimationDuration(productKey)
    local resultHoldDuration = ExclusiveRollConfig.GetResultHoldDuration()
    local padding = ExclusiveRollConfig.GetGrantDelayPadding()
    local count = math.max(1, tonumber(rollCount) or 1)

    return math.max(0, (perRollDuration + resultHoldDuration) * count + padding)
end

return ExclusiveRollConfig

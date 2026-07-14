-- src/shared/BossZombieConfig.luau
local BossZombieConfig = {
    ["ZomBoss1"] = {
        Id = "ZomBoss1",
        Name = "ZomBoss 1",
        BossType = "EventBoss",
        ModelName = "ZomBoss1",
        ModelPath = "ReplicatedStorage.ItemModels.ZomBoss1",
        HP = 50000,
        Attack = 2000,
        Speed = 1,
        AttackRange = 4,
        AttackInterval = 2,
        AttackDamageDelay = 1,
        Anims = {
            Walk = "rbxassetid://112248466737071",
            Eat = "rbxassetid://139034719168782",
            ScratchHead = "rbxassetid://139034719168782",
            Fire = "rbxassetid://96109126082604",
            Jump = "rbxassetid://122118226905874",
            Explosion = "rbxassetid://71244623034472",
            Death = "rbxassetid://71244623034472",
        },
    },
}

return BossZombieConfig

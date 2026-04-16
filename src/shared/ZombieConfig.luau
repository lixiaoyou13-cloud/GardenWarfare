-- src/shared/ZombieConfig.luau

local ZombieConfig = {
    ["Zombie"] = {
        Id = "Zombie",
        Name = "普通僵尸",         
        
        -- ==================================
        -- [核心战斗属性：1:1 还原 PvZ 原版比例]
        -- ==================================
        HP = 270,                 -- 【完美契合】你的豌豆射手攻击力是20，200血刚好需要10发打死！
        Attack = 100,             -- 【原版伤害】原版僵尸 DPS 是100。你的植物是300血，僵尸3秒吃完一个！
        Speed = 1.6,                -- 【移速放缓】Roblox 正常人速度是 16。设为 3 完美还原僵尸缓慢压迫的步伐。
        AttackRange = 3,          -- 【触发距离】走到距离植物 3 格（Studs）的距离停下开吃。
        AttackInterval = 1,       -- 【攻击频率】每 1 秒造成一次伤害（播放一次 Eat 动画）。
        
        -- 动作动画 ID 组
        Anims = {
            Idle = "rbxassetid://103252167598562",   
            Walk = "rbxassetid://110893261547291",   
            Bend = "rbxassetid://131459040784217",   
            Eat =  "rbxassetid://119641402238824",   
            Rise = "rbxassetid://116948729939997",   
        }
    },
    -- ==================================
    -- [🌟 新增：路障僵尸]
    -- ==================================
    ["ConeheadZombie"] = {
        Id = "ConeheadZombie",
        Name = "路障僵尸",         
        
        -- 【血量剧增】普通本体(270) + 路障防具(370) = 640
        -- 豌豆射手(每次20伤害)需要命中 32 发才能打死！
        HP = 640,             
        Attack = 100,             
        Speed = 1.6,                
        AttackRange = 3,          
        AttackInterval = 1,     
        
        -- 动画与普通僵尸共用（它们走路和啃植物的姿势是一样的）
        Anims = {
            Idle = "rbxassetid://103252167598562",   
            Walk = "rbxassetid://110893261547291",   
            Bend = "rbxassetid://131459040784217",   
            Eat  = "rbxassetid://119641402238824",   
            Rise = "rbxassetid://116948729939997",   
        }
    },

    -- ==================================
    -- [🌟 新增：铁桶僵尸]
    -- ==================================
    ["BucketheadZombie"] = {
        Id = "BucketheadZombie",
        Name = "铁桶僵尸",         
        
        -- 【叹息之墙】普通本体(270) + 铁桶防具(1100) = 1370
        -- 极其坚硬！非常需要土豆地雷（1800伤害）直接秒杀！
        HP = 1370,             
        Attack = 100,             
        Speed = 1.6,                
        AttackRange = 3,          
        AttackInterval = 1,     
        
        Anims = {
            Idle = "rbxassetid://103252167598562",   
            Walk = "rbxassetid://110893261547291",   
            Bend = "rbxassetid://131459040784217",   
            Eat  = "rbxassetid://119641402238824",   
            Rise = "rbxassetid://116948729939997",   
        },
    },
    
    ["ScreenDoorZombie"] = {
        Id = "ScreenDoorZombie",
        Name = "铁门僵尸",         
        
        -- 【叹息之墙】普通本体(270) + 铁桶防具(1100) = 1370
        -- 极其坚硬！非常需要土豆地雷（1800伤害）直接秒杀！
        HP = 2700,             
        Attack = 100,             
        Speed = 1.6,                
        AttackRange = 3,          
        AttackInterval = 1,     
        
        Anims = {
            Idle = "rbxassetid://103252167598562",   
            Walk = "rbxassetid://110893261547291",   
            Bend = "rbxassetid://131459040784217",   
            Eat  = "rbxassetid://119641402238824",   
            Rise = "rbxassetid://116948729939997",   
        },
    }
}
return ZombieConfig

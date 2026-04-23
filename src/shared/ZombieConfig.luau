-- src/shared/ZombieConfig.luau
local ZombieConfig = {
    ["Zombie"] = {
        Id = "Zombie",
        Name = "普通僵尸",         
        HP = 200,             
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
        }
    },
    ["ConeheadZombie"] = {
        Id = "ConeheadZombie",
        Name = "路障僵尸",         
        HP = 500,             
        Attack = 150,             
        Speed = 1.6,                
        AttackRange = 3,          
        AttackInterval = 1,     
        Anims = {
           Idle = "rbxassetid://103252167598562",   
            Walk = "rbxassetid://110893261547291",   
            Bend = "rbxassetid://131459040784217",   
            Eat  = "rbxassetid://119641402238824",   
            Rise = "rbxassetid://116948729939997",   
        }
    },
    ["BucketheadZombie"] = {
        Id = "BucketheadZombie",
        Name = "铁桶僵尸",         
        HP = 1200,             
        Attack = 300,             
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
        HP = 2500,             
        Attack = 500,             
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
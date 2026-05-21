-- src/shared/BaseItemConfig.luau
-- 专门管理系统工具和基础 UI 资源的配置表
local BaseItemConfig = {
    -- 工具类（对应前缀 Tool_）
    Tools = {
        ["Shovel"] = {
            Name = "Shovel",
            IconId = "rbxthumb://type=Asset&id=129146573433376&w=150&h=150", -- 请替换真实的铲子图片ID
        },
        ["WeaponBlock"] = {
            Id = "WeaponBlock",
            Name = "Cube Weapon",
            IconId = "rbxassetid://28316993" -- 换成你的武器图标ID
        }
    },
    
    -- 系统类（对应前缀 System_）
    System = {
        ["Backpack"] = {
            Name = "Backpack",
            IconId = "rbxassetid://126862599177625", -- 请替换真实的背包图片ID
        }
    },
    --道具背景类
    Item = {
        [1] = {
            Name = "Common",
            IconId = "rbxassetid://0", -- [请替换真实的随机种子图片ID]
        },
        [2] = {
            Name = "Special",
            IconId = "rbxassetid://1", -- [请替换真实的随机种子图片ID]
        },
       ["WeaponBlock"] = {
            Id = "WeaponBlock",
            Name = "Cube Weapon",
            IconId = "rbxassetid://28316993" -- 换成实际图标
    }
    }
}

return BaseItemConfig
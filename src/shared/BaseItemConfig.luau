-- src/shared/BaseItemConfig.luau
-- 专门管理系统工具和基础 UI 资源的配置表
local BaseItemConfig = {
    -- 工具类（对应前缀 Tool_）
    Tools = {
        ["Shovel"] = {
            Name = "铲子",
            IconId = "rbxassetid://126862599177625", -- 请替换真实的铲子图片ID
        }
    },
    
    -- 系统类（对应前缀 System_）
    System = {
        ["Backpack"] = {
            Name = "背包",
            IconId = "rbxassetid://126862599177625", -- 请替换真实的背包图片ID
        }
    }
}

return BaseItemConfig
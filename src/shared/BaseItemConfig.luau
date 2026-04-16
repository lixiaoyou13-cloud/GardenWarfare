-- src/shared/BaseItemConfig.luau
-- 专门管理系统工具和基础 UI 资源的配置表
local BaseItemConfig = {
    -- 工具类（对应前缀 Tool_）
    Tools = {
        ["Shovel"] = {
            Name = "铲子",
            Icon = "rbxassetid://你的铲子图片ID", -- 请替换真实ID
        }
    },
    
    -- 系统类（对应前缀 System_）
    System = {
        ["Backpack"] = {
            Name = "背包",
            Icon = "rbxassetid://你的背包图片ID", -- 请替换真实ID
        }
    }
}

return BaseItemConfig
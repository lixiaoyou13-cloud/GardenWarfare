-- src/shared/NumberFormatUtil.luau
-- 客户端/服务端通用数字显示格式化工具
local NumberFormatUtil = {}

function NumberFormatUtil.FormatNumber(num)
    num = tonumber(num) or 0

    if num >= 1000000000 then
        local str = string.format("%.1fB", num / 1000000000)
        return string.gsub(str, "%.0B", "B")
    elseif num >= 1000000 then
        local str = string.format("%.1fM", num / 1000000)
        return string.gsub(str, "%.0M", "M")
    elseif num >= 1000 then
        local str = string.format("%.1fK", num / 1000)
        return string.gsub(str, "%.0K", "K")
    end

    return tostring(math.floor(num))
end

return NumberFormatUtil
local TitleConfig = {}

TitleConfig.EquippedMoveSpeedBoostPercent = 30

TitleConfig.Titles = {
    CreatorPlayer = {
        Id = "CreatorPlayer",
        Name = "Creator player",
        ImageId = "rbxassetid://131903351693320",
        Quality = 6,
        Order = 1,
        Trail = "Orange",
        MoveSpeedBoostPercent = TitleConfig.EquippedMoveSpeedBoostPercent,
    },
    CreatorPlayerNo1 = {
        Id = "CreatorPlayerNo1",
        Name = "Creator player No.1",
        ImageId = "rbxassetid://125691500716649",
        Quality = 6,
        Order = 2,
        Trail = "Rainbow",
        MoveSpeedBoostPercent = TitleConfig.EquippedMoveSpeedBoostPercent,
    },
}

TitleConfig.IdToTitleKey = {
    "CreatorPlayer",
    "CreatorPlayerNo1",
}

function TitleConfig.GetTitle(titleId)
    if type(titleId) ~= "string" then
        return nil
    end

    return TitleConfig.Titles[titleId]
end

function TitleConfig.GetSortedTitles()
    local sortedTitles = {}

    for _, titleId in ipairs(TitleConfig.IdToTitleKey) do
        local titleConfig = TitleConfig.Titles[titleId]
        if titleConfig then
            table.insert(sortedTitles, titleConfig)
        end
    end

    table.sort(sortedTitles, function(a, b)
        local aOrder = tonumber(a.Order) or 9999
        local bOrder = tonumber(b.Order) or 9999
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end

        return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
    end)

    return sortedTitles
end

return TitleConfig

local TradeConfig = {}

-- 交易系统 RemoteEvent 名称，服务端会按这个名字创建/查找通信事件。
TradeConfig.RemoteName = "TradeRE"

-- 靠近其他玩家时显示交易 Prompt 的距离。
TradeConfig.PromptDistance = 12

-- 交易 Prompt 触发需要按住的时间，0 表示点击即可触发。
TradeConfig.PromptHoldDuration = 0

-- 本地玩家装备这些物品时隐藏交易 Prompt，避免战斗操作时误触交易。
TradeConfig.PromptBlockedEquippedIds = {
    Tool_WeaponBlock = true,
}

-- 服务端校验发起/接受交易时，双方允许的最大距离。
TradeConfig.MaxInviteDistance = 18

-- 交易邀请等待时间，超时后自动取消邀请。
TradeConfig.InviteTimeoutSeconds = 20

-- 单次交易中，一名玩家最多可放入多少种植物条目。
TradeConfig.MaxOfferEntries = 60

-- 每个植物条目单次最多可上传的数量。
TradeConfig.MaxQuantityPerEntry = 999

-- 交易界面 OK/NO 表情图片资源；可填数字 ID、rbxassetid 或 rbxthumb，客户端会兼容 Decal 缩略图。
TradeConfig.EmojiImageIds = {
    OK = "rbxassetid://123066753305619",
    NO = "rbxassetid://93585837695699",
}

-- 头像兜底图；Studio 本地多人测试的 Player1/Player2 可能是负数 UserId，无法获取真实头像。
TradeConfig.DefaultPortraitImageId = "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150"

return TradeConfig

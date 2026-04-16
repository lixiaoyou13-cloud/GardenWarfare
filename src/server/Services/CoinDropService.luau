-- src/server/Services/CoinDropService.luau
local CoinDropService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

function CoinDropService.Init()
    -- 1. 创建发报机：让服务器通知客户端爆金币
    local playDropRE = Instance.new("RemoteEvent")
    playDropRE.Name = "PlayCoinDropRE"
    playDropRE.Parent = ReplicatedStorage

    -- 2. 创建收报机：听取客户端“我捡到了”的汇报
    local pickupRE = Instance.new("RemoteEvent")
    pickupRE.Name = "PickupCoinRE"
    pickupRE.Parent = ReplicatedStorage

    -- 当客户端汇报捡到钱时，服务器负责加钱！
    pickupRE.OnServerEvent:Connect(function(player, amount)
        -- [简单防作弊] 确保 amount 是数字且不能一次要太多钱
        if type(amount) == "number" and amount > 0 and amount <= 100 then
            PlayerDataManager.GiveCoins(player, amount)
        end
    end)

    print("服务端：CoinDropService (网络桥接版) 加载完毕！所有物理移交客户端！")
end

function CoinDropService.DropCoins(player, dropPosition, coinCount, totalValue)
    if not player then return end
    
    local playDropRE = ReplicatedStorage:FindFirstChild("PlayCoinDropRE")
    if playDropRE then
        -- 服务器不负责生成任何东西，只发一条指令给这个玩家的客户端！
        playDropRE:FireClient(player, dropPosition, coinCount, totalValue)
    end
end

return CoinDropService
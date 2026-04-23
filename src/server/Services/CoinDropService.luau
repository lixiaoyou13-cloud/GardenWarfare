-- src/server/Services/CoinDropService.luau
local CoinDropService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerDataManager = require(script.Parent.Parent.PlayerDataManager)

function CoinDropService.Init()
    local playDropRE = Instance.new("RemoteEvent")
    playDropRE.Name = "PlayCoinDropRE"
    playDropRE.Parent = ReplicatedStorage

    local pickupRE = Instance.new("RemoteEvent")
    pickupRE.Name = "PickupCoinRE"
    pickupRE.Parent = ReplicatedStorage

    -- [🌟 核心修改：接收布尔值，判断是向日葵收集的还是玩家收集的]
    pickupRE.OnServerEvent:Connect(function(player, amount, isSunflowerCollect)
        if type(amount) == "number" and amount > 0 and amount <= 100 then
            if isSunflowerCollect then
                -- 如果是向日葵自动吸纳的，增加阳光总量
                PlayerDataManager.AddTotalSun(player, amount)
            else
                -- 玩家手动捡起的，加金币
                PlayerDataManager.GiveCoins(player, amount)
            end
        end
    end)

    print("服务端：CoinDropService 加载完毕！阳光吸纳与金币区分已实装！")
end

function CoinDropService.DropCoins(player, dropPosition, coinCount, totalValue)
    if not player then return end
    
    local playDropRE = ReplicatedStorage:FindFirstChild("PlayCoinDropRE")
    if playDropRE then
        playDropRE:FireClient(player, dropPosition, coinCount, totalValue)
    end
end

return CoinDropService
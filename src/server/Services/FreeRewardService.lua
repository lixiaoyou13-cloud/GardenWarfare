-- src/server/Services/FreeRewardService.lua
local FreeRewardService = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ==========================================
-- 🎁 奖励与群组配置区
-- ==========================================
local REWARD_PLANT = "Threepeater" 
local REWARD_AMOUNT = 1              
local GROUP_ID = 229662289        -- ⚠️⚠️⚠️ 请把这里换成你真正的 Roblox 群组 ID！

function FreeRewardService.Init()
    local claimRE = Instance.new("RemoteEvent")
    claimRE.Name = "ClaimFreeRewardRE"
    claimRE.Parent = ReplicatedStorage

    local PDManager = require(script.Parent.Parent.PlayerDataManager)

    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            local data = nil
            while not data do
                data = PDManager.GetPlayerData(player)
                if not data then task.wait(0.5) end
            end
            
            if data.FreeRewardClaimed then
                player:SetAttribute("HasClaimedFreeReward", true)
            else
                player:SetAttribute("HasClaimedFreeReward", false)
            end
        end)
    end)

    claimRE.OnServerEvent:Connect(function(player)
        local data = PDManager.GetPlayerData(player)
        if not data then return end
        
        -- 防作弊 1：如果已经领取过，直接拦截
        if data.FreeRewardClaimed then return end
        
        -- 🛡️ 防作弊 2：真实验证玩家是否在群组中 (核心安全锁)
        if not player:IsInGroup(GROUP_ID) then
            -- 如果玩家用外挂强行发包，但在网页上没加群，服务端会直接拒绝给奖励
            return 
        end
        
        -- 发放奖励
        PDManager.GivePlant(player, REWARD_PLANT, REWARD_AMOUNT, 1)
        
        data.FreeRewardClaimed = true
        player:SetAttribute("HasClaimedFreeReward", true)
        
        claimRE:FireClient(player, true)
    end)
end

return FreeRewardService
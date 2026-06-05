-- src/client/Services/FreeRewardClientController.luau
local FreeRewardClientController = {}
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REWARD_ITEM_NAME = "Threepeater" 
local GROUP_ID = 229662289 -- ⚠️⚠️⚠️ 保持与服务端一致，填入你的群组 ID！

function FreeRewardClientController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    local eventPage = basicGui:WaitForChild("EventPage")
    
    local freeRewardUI = eventPage:WaitForChild("FreeRewardUI")
    local closeBtn = freeRewardUI:WaitForChild("CloseButton")
    local claimBtn = freeRewardUI:WaitForChild("ClaimBattle")
    local claimBtnText = claimBtn:WaitForChild("TextLabel")
    local node1 = freeRewardUI:WaitForChild("Node_1")
    local node2 = freeRewardUI:WaitForChild("Node_2")
    
    local viewportFrame = freeRewardUI:WaitForChild("ViewportFrame") 
    
    local rewardPart = Workspace:WaitForChild("FreeReward")
    local claimRE = ReplicatedStorage:WaitForChild("ClaimFreeRewardRE")
    local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)

    local hasLiked = true -- 点赞依然是假验证
    local isDebounce = false

    freeRewardUI.Visible = false
    local rotateConnection = nil

    local function SetupViewportModel()
        viewportFrame:ClearAllChildren()
        local plantsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
        local modelName = REWARD_ITEM_NAME .. "_Plant"
        local modelTemplate = plantsFolder and plantsFolder:FindFirstChild(modelName)
        
        if not modelTemplate then
            warn("[FreeReward] Reward model not found: " .. tostring(modelName))
            return
        end

        local displayModel = modelTemplate:Clone()
        displayModel.Parent = viewportFrame

        -- 背包同款摄像机参数
        local camera = Instance.new("Camera")
        camera.FieldOfView = 40 
        camera.Parent = viewportFrame
        viewportFrame.CurrentCamera = camera

        local cframe, size = displayModel:GetBoundingBox()
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim == 0 then maxDim = 2 end 
        
        displayModel:PivotTo(CFrame.new(0, 0, 0))
        
        camera.CFrame = CFrame.lookAt(
           Vector3.new(0, 0, maxDim * 1.5 + 1),
            Vector3.new(0, size.Y / 3, 0)
        )

        if rotateConnection then
            rotateConnection:Disconnect()
            rotateConnection = nil
        end

        local currentAngle = 0
        rotateConnection = RunService.RenderStepped:Connect(function(dt)
            if freeRewardUI.Visible then
                currentAngle = currentAngle + math.rad(60 * dt) 
                displayModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, currentAngle, 0))
            end
        end)
    end

    rewardPart.Touched:Connect(function(hit)
        if isDebounce then return end
        local character = player.Character
        if character and hit:IsDescendantOf(character) then
            isDebounce = true
            
            -- 🌟 核心修改：真实向 Roblox 请求玩家是否在群组中
            local inGroup = false
            pcall(function()
                inGroup = player:IsInGroup(GROUP_ID)
            end)

            -- 更新文本状态：根据群组状态切换 1/1 或 0/1
            node1.Text = hasLiked and "1/1" or "0/1"
            node2.Text = inGroup and "1/1" or "0/1"
            
            if player:GetAttribute("HasClaimedFreeReward") then
                claimBtnText.Text = "Claimed"
                claimBtn.BackgroundColor3 = Color3.fromRGB(128, 128, 128)
                claimBtn.Interactable = false
            else
                claimBtnText.Text = "Claim"
                claimBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                claimBtn.Interactable = true
            end
            
            if eventPage:IsA("ScreenGui") then eventPage.Enabled = true end
            SetupViewportModel()
            freeRewardUI.Visible = true
            
            task.wait(1)
            isDebounce = false
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        freeRewardUI.Visible = false
        if rotateConnection then
            rotateConnection:Disconnect()
            rotateConnection = nil
        end
        viewportFrame:ClearAllChildren()
    end)

    claimBtn.MouseButton1Click:Connect(function()
        if player:GetAttribute("HasClaimedFreeReward") then return end
        
        if node1.Text == "1/1" and node2.Text == "1/1" then
            claimRE:FireServer()
        else
            -- 🌟 修改了提示文字
            UIEffectUtil.ShowTip("Please Like and Join our Group first!")
        end
    end)

    claimRE.OnClientEvent:Connect(function(success)
        if success then
            claimBtnText.Text = "Claimed"
            claimBtn.BackgroundColor3 = Color3.fromRGB(128, 128, 128)
            claimBtn.Interactable = false
            UIEffectUtil.ShowTip("Successfully claimed " .. REWARD_ITEM_NAME .. " x1!")
        end
    end)
end

return FreeRewardClientController
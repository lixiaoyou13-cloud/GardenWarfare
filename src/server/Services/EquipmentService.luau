-- src/server/Services/EquipmentService.luau
local EquipmentService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function EquipmentService.Init()
    local holdItemRE = Instance.new("RemoteEvent")
    holdItemRE.Name = "HoldItemRE"
    holdItemRE.Parent = ReplicatedStorage

    holdItemRE.OnServerEvent:Connect(function(player, compositeId)
        EquipmentService.UpdateHoldItem(player, compositeId)

    end)
    
end

-- [🌟 核心接口] 统一处理装备、卸下、物理锁定
function EquipmentService.UpdateHoldItem(player, compositeId)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid

    -- 1. 清理旧模型和动画
    local oldItem = character:FindFirstChild("HeldItem_Custom")
    if oldItem then oldItem:Destroy() end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Name == "CustomHoldAnim" then track:Stop() end
    end

    if not compositeId then 
        character:SetAttribute("EquippedSeed", nil)
        return 
    end

    -- 2. 播放动画
    local holdAnim = Instance.new("Animation")
    holdAnim.AnimationId = (humanoid.RigType == Enum.HumanoidRigType.R15) and "rbxassetid://507768375" or "rbxassetid://128428514"
    local track = animator:LoadAnimation(holdAnim)
    track.Name = "CustomHoldAnim"
    track.Priority = Enum.AnimationPriority.Action 
    track:Play()

    -- 3. [🌟 核心原理：根据标签寻找对应模型]
    local parts = string.split(compositeId, "_")
    local itemType = parts[1]
    local realId = parts[2]

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local realModel = nil

    if itemType == "Seed" then
        local itemDetail = ItemConfig.Seeds[realId]
        if itemDetail then
            local modelName = itemDetail.ModelId or realId
            realModel = itemModelsFolder and itemModelsFolder:FindFirstChild(modelName)
        end
    elseif itemType == "Plant" then
        local itemDetail = ItemConfig.Plants[realId]
        if itemDetail then
            realModel = itemModelsFolder and (itemModelsFolder:FindFirstChild(realId .. "_Plant") or itemModelsFolder:FindFirstChild(realId))
        end
    -- [🌟 新增这段：如果是工具，直接去 ItemModels 里找对应的模型（比如 Shovel）]
    elseif itemType == "Tool" then
        realModel = itemModelsFolder and itemModelsFolder:FindFirstChild(realId)
    end

    if realModel then
        local heldModel = realModel:Clone()
        heldModel.Name = "HeldItem_Custom"

        -- [🌟 获取根节点]
        local modelRoot = heldModel
        if heldModel:IsA("Model") then
            modelRoot = heldModel.PrimaryPart or heldModel:FindFirstChildWhichIsA("BasePart")
        end
        
        if not modelRoot or not modelRoot:IsA("BasePart") then return end

        -- ==========================================
        -- [🌟 终极物理安全锁：防瘫痪 + 防碎裂]
        -- ==========================================
        for _, part in pairs(heldModel:GetDescendants()) do
            if part:IsA("BasePart") then
                -- 1. 变成无碰撞的幽灵，防止卡住人物
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.Massless = true 
                
                -- 2. 🌟 绝对不能锚定！(修复五体投地 Bug 的关键)
                part.Anchored = false 
                
                -- 3. 🌟 自动焊接内部零件！(防止铲子解除锚定后散架)
                if part ~= modelRoot then
                    local internalWeld = Instance.new("WeldConstraint")
                    internalWeld.Part0 = modelRoot
                    internalWeld.Part1 = part
                    internalWeld.Parent = modelRoot
                end
            end
        end

        heldModel.Parent = character
        character:SetAttribute("EquippedSeed", compositeId) 

        -- 焊接至右手
        local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
        if rightHand then
            local rotationOffset = CFrame.new() 
            if itemType == "Plant" then
                rotationOffset = CFrame.Angles(-90, 0, 0) 
            end
            
            heldModel:PivotTo(rightHand.CFrame * rotationOffset)
            
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = rightHand
            weld.Part1 = modelRoot
            weld.Parent = heldModel
        end
    end
end

return EquipmentService
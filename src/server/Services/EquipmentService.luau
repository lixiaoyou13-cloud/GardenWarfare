-- src/server/Services/EquipmentService.luau
local EquipmentService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- [🌟 终极特效控制系统：支持 Attachment 容器穿透]
local function ApplyMutationEffects(model, mutationLevel)
    mutationLevel = mutationLevel or 1
    local effectMap = { [2] = "Glow", [3] = "Lightning", [4] = "HolyLight" }
    
    for lvl, fxName in pairs(effectMap) do
        local shouldEnable = (mutationLevel == lvl)
        
        -- 遍历模型中所有元件
        for _, node in ipairs(model:GetDescendants()) do
            -- 如果找到了对应名字的元件（比如 Glow 附件）
            if node.Name == fxName then
                
         

                -- 2. [🌟 核心修复] 如果这个节点是附件(Attachment)或文件夹，遍历并开关它【里面】的所有特效！
                for _, child in ipairs(node:GetDescendants()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                        child.Enabled = shouldEnable
                    end
                end
                
            end
        end
    end
end
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

    -- 3. [🌟 核心原理：根据标签寻找对应模型，并解析变异等级]
    local parts = string.split(compositeId, "_")
    local itemType = parts[1]
    local realId = parts[2]
    local mutationLevel = tonumber(parts[3]) or 1 -- [🌟 提取变异等级]

    local itemModelsFolder = ReplicatedStorage:FindFirstChild("ItemModels")
    local realModel = nil

    if itemType == "Seed" then
        
        realModel = itemModelsFolder:FindFirstChild(realId .. "_Seed") or itemModelsFolder:FindFirstChild("Seed")

    elseif itemType == "Plant" then
        local itemDetail = ItemConfig.Plants[realId]
        if itemDetail then
            realModel = itemModelsFolder and (itemModelsFolder:FindFirstChild(realId .. "_Plant") or itemModelsFolder:FindFirstChild(realId))
        end
    elseif itemType == "Tool" then
        realModel = itemModelsFolder and itemModelsFolder:FindFirstChild(realId)
    end

    if realModel then
        local heldModel = realModel:Clone()
        heldModel.Name = "HeldItem_Custom"

        -- [🌟 核心新增：在手里拿着的时候，过滤掉多余的特效，只显示正确的变异光效]
        if itemType == "Plant" then
            ApplyMutationEffects(heldModel, mutationLevel)
        end

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
                
                -- 2. 绝对不能锚定！
                part.Anchored = false 
                
                -- 3. 自动焊接内部零件
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

            elseif itemType == "Seed" then
                -- 修改这里的 3 个数字 (X, Y, Z轴的旋转度数)
                -- 比如现在是 X轴转90度，如果你觉得不对，可以尝试改成 (0, math.rad(90), 0) 等等
                rotationOffset = CFrame.Angles(math.rad(-90), math.rad(0), math.rad(0))
            elseif itemType == "Tool" and realId == "WeaponBlock" then
                -- 如果角度不对，可以修改下面这三个数字 (X轴, Y轴, Z轴 的旋转度数)
                rotationOffset = CFrame.Angles(math.rad(-90), 0, 0)
                
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
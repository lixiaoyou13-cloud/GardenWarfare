-- src/shared/EffectUtil.luau
local EffectUtil = {}

-- 定义所有变异特效的标签名称
local MUTATION_TAGS = { "Glow", "Lightning", "HolyLight" }

-- [🌟 核心修复：精准开关逻辑]
function EffectUtil.ApplyMutationEffects(model, mutationLevel)
    if not model then return end
    mutationLevel = mutationLevel or 1
    
    -- 等级与标签的映射表
    local effectMap = {
        [2] = "Glow",
        [3] = "Lightning",
        [4] = "HolyLight"
    }
    
    local targetName = effectMap[mutationLevel] -- 当前应该显示的特效名
    local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)

    -- 只进行一次全量搜索，确保性能和准确性
    for _, node in ipairs(model:GetDescendants()) do
        local isMutationNode = false
        for _, tag in ipairs(MUTATION_TAGS) do
            if node.Name == tag then
                isMutationNode = true
                break
            end
        end

        -- 如果这个节点是变异系统的一部分（名字是 Glow/Lightning/HolyLight）
        if isMutationNode then
            -- 判定：它是否属于当前植物等级对应的特效？
            local shouldBeActive = (node.Name == targetName)
            
            -- 1. 处理节点本身
            if node:IsA("BasePart") then
                node.Transparency = 1 -- 容器外壳永远保持透明，防止出现方块黑框
                node.CanCollide = false
                
                -- 自动焊接：解决 CombatService 取消锚定导致特效零件掉落的问题
                if not node.Anchored and primaryPart and node ~= primaryPart then
                    local weld = node:FindFirstChild("MutationWeld") or Instance.new("WeldConstraint")
                    weld.Name = "MutationWeld"
                    weld.Part0 = node
                    weld.Part1 = primaryPart
                    weld.Parent = node
                end
            elseif node:IsA("ParticleEmitter") or node:IsA("Light") or node:IsA("Beam") or node:IsA("Highlight") or node:IsA("Trail") then
                node.Enabled = shouldBeActive -- 如果不是目标，直接熄灭
            end

            -- 2. 处理该标签下的所有子节点 (解决残留的关键)
            for _, child in ipairs(node:GetDescendants()) do
                if child:IsA("BasePart") then
                    -- 内部真正的实体零件（如果有的话），只有匹配等级才显示
                    child.Transparency = shouldBeActive and 0 or 1
                elseif child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") or child:IsA("Highlight") or child:IsA("Trail") then
                    child.Enabled = shouldBeActive -- 非目标等级的所有子粒子、子灯光全部强制关闭
                end
            end
        end
    end
end

-- 保留这个函数名以兼容可能存在的其他调用，但逻辑直接指向 ApplyMutationEffects(model, 1)
function EffectUtil.HideAllMutations(model)
    EffectUtil.ApplyMutationEffects(model, 1)
end

return EffectUtil
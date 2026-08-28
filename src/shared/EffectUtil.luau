-- src/shared/EffectUtil.luau
local EffectUtil = {}
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SUNSHROOM_HEAL_VFX_DEBUG = false
local continuousAttackEmitterCache = setmetatable({}, { __mode = "k" })

-- 定义所有变异特效的标签名称
local MUTATION_TAGS = { "Glow", "Lightning", "HolyLight" }

-- 开关逻辑
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

    -- 只进行一次数全量搜索，确保性能和准确性
    for _, node in ipairs(model:GetDescendants()) do
        local isMutationNode = false
        for _, tag in ipairs(MUTATION_TAGS) do
            if node.Name == tag then
                isMutationNode = true
                break
            end
        end

        -- 如果这个节点击是变异系统的一部分（名字是 Glow/Lightning/HolyLight）
        if isMutationNode then
            -- 判定：它是否属于当前植物等级对应的特效？
            local shouldBeActive = (node.Name == targetName)

            -- 1. 处理节点击本身
            if node:IsA("BasePart") then
                node.Transparency = 1 -- 容器外壳永远保持透明，防止出现方块黑框
                node.CanCollide = false

                -- 自转动焊接：解决 CombatService 取消锚定导致特效零件掉落的问题
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

            -- 2. 处理该标签下的所有子节点击 (解决残留的)
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

-- 樱桃炸弹专属爆炸视觉特效
function EffectUtil.PlayExplosion(targetPos, radius)
    -- 1. 使用 Roblox 原生爆炸对象（提示供经典的烟雾火光和爆炸音效）
    local explosion = Instance.new("Explosion")
    explosion.Position = targetPos
    explosion.BlastRadius = radius
    -- 将物理冲击力设为 0，防止把场景里其他零件炸飞，伤害结算我们已经在 CombatService 里手写了
    explosion.BlastPressure = 0
    explosion.DestroyJointRadiusPercent = 0
    explosion.Parent = Workspace

    -- 2. 额外叠加一个巨大的能量冲击波光球，视觉冲击力拉满
    local shockwave = Instance.new("Part")
    shockwave.Shape = Enum.PartType.Ball
    shockwave.Material = Enum.Material.Neon
    shockwave.Color = Color3.fromRGB(255, 100, 50) -- 炽热的橙红点色
    shockwave.Anchored = true
    shockwave.CanCollide = false
    shockwave.CanQuery = false
    shockwave.Position = targetPos
    shockwave.Size = Vector3.new(2, 2, 2) -- 初始大小
    shockwave.Transparency = 0.2
    shockwave.Parent = Workspace

    -- 使用 TweenService 让光球瞬间膨胀并消失
    local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(shockwave, tweenInfo, {
        Size = Vector3.new(radius * 2, radius * 2, radius * 2), -- 膨胀到爆炸半径大小
        Transparency = 1 -- 逐渐变透明
    })

    tween:Play()

    -- 动画后清理光球
    tween.Completed:Connect(function()
        shockwave:Destroy()
    end)
end

-- 这个函数名以兼容可能存在的其他调用
function EffectUtil.HideAllMutations(model)
    EffectUtil.ApplyMutationEffects(model, 1)
end

-- 播放模型内名为 VFX/vfx 的一次性粒子特效。
function EffectUtil.PlayAttackVFX(model)
    if not model then return end
    local isSunShroom = model.Name == "SunShroom" or model:GetAttribute("PlantId") == "SunShroom"
    local vfxNodeCount = 0
    local emittedCount = 0

    -- 1. 遍历模型内的所有节点击（解决有多个 VFX 节点击的问题，比如双持武器）
    for _, node in ipairs(model:GetDescendants()) do

        -- 2. 忽略大小写判定（VFX, vfx, Vfx 都能识别）
        if string.upper(node.Name) == "VFX" then
            vfxNodeCount += 1

            -- 3. 把当前 VFX 节点击自转身，以及它内部的所有子代，放进一个列表里统一检查
            -- 解决你直接把 ParticleEmitter 命名为 VFX 的情况
            local nodesToCheck = node:GetDescendants()
            table.insert(nodesToCheck, node)


            for _, child in ipairs(nodesToCheck) do
                if child:IsA("ParticleEmitter") then

                    -- 4. 获取 EmitCount
                    local emitCount = child:GetAttribute("EmitCount")

                    if not emitCount then
                        local countValueNode = child:FindFirstChild("EmitCount")
                        if countValueNode and (countValueNode:IsA("IntValue") or countValueNode:IsA("NumberValue")) then
                            emitCount = countValueNode.Value
                        end
                    end

                    -- 5. 强转为数字，防止你在属性里错建成了 String (文本) 类型
                    emitCount = tonumber(emitCount)

                    -- 如果还是没有配置 EmitCount，给一个明显的默认值(15)，方便你肉眼确认特效触发了
                    if not emitCount or emitCount <= 0 then
                        emitCount = 15
                    end



                    -- 6. 瞬间发射粒子
                    child:Emit(emitCount)
                    emittedCount += 1
                end
            end
        end
    end

    if isSunShroom and SUNSHROOM_HEAL_VFX_DEBUG then
        print(("[SunShroomHealVFX][EffectUtil] scanned model=%s vfxNodes=%d emitters=%d"):format(
            model:GetFullName(),
            vfxNodeCount,
            emittedCount
        ))
    end
end

local function getContinuousAttackEmitters(model)
    local cached = continuousAttackEmitterCache[model]
    if cached then
        local validEmitters = {}
        for _, emitter in ipairs(cached) do
            if emitter and emitter.Parent and emitter:IsDescendantOf(model) then
                table.insert(validEmitters, emitter)
            end
        end
        if #validEmitters > 0 then
            continuousAttackEmitterCache[model] = validEmitters
            return validEmitters
        end
    end

    local emitters = {}
    local seen = {}
    for _, node in ipairs(model:GetDescendants()) do
        if string.upper(node.Name) == "VFX" then
            if node:IsA("ParticleEmitter") and not seen[node] then
                seen[node] = true
                table.insert(emitters, node)
            end
            for _, descendant in ipairs(node:GetDescendants()) do
                if descendant:IsA("ParticleEmitter") and not seen[descendant] then
                    seen[descendant] = true
                    table.insert(emitters, descendant)
                end
            end
        end
    end

    continuousAttackEmitterCache[model] = emitters
    return emitters
end

-- 持续启停模型 VFX 节点内的粒子；关闭时保留现有粒子自然结束。
function EffectUtil.SetAttackVFXContinuous(model, enabled)
    if not model then
        return 0
    end

    local changedCount = 0
    for _, emitter in ipairs(getContinuousAttackEmitters(model)) do
        if emitter and emitter.Parent and emitter:IsDescendantOf(model) then
            emitter.Enabled = enabled == true
            changedCount += 1
        end
    end
    return changedCount
end

return EffectUtil

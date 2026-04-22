-- src/client/Services/ToolController.luau
local ToolController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local activeShovelPrompts = {} -- 保存对 Prompt 的引用，方便随时清理

function ToolController.Init()
    local player = Players.LocalPlayer
    local shovelRE = ReplicatedStorage:WaitForChild("ShovelActionRE")

    local function clearAllPrompts()
        for plant, prompt in pairs(activeShovelPrompts) do
            if prompt and prompt.Parent then prompt:Destroy() end
        end
        table.clear(activeShovelPrompts)
    end

    local function checkAndAddPrompt(plant)
        -- 排除已经生成回收提示的植物
        if activeShovelPrompts[plant] then return end

        local isCombat = plant:GetAttribute("IsCombatPlant")
        local isFarm = plant:GetAttribute("PlantedOn")
        local isMature = plant:GetAttribute("IsMature")
        
        -- [🌟 核心判定：战斗植物可回收，农田植物必须【未成熟】]
        if isCombat or (isFarm and not isMature) then
            local prompt = Instance.new("ProximityPrompt")
            prompt.ActionText = "回收进背包"
            prompt.ObjectText = plant.Name or "植物"
            prompt.KeyboardKeyCode = Enum.KeyCode.F
            prompt.HoldDuration = 0.2 -- 稍微加一点长按时间，防止误触
            prompt.MaxActivationDistance = 12
            prompt.RequiresLineOfSight = false
            
            -- 挂载在植物的根部件上
            local attachPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart", true)
            if attachPart then
                prompt.Parent = attachPart
                activeShovelPrompts[plant] = prompt
                
                prompt.Triggered:Connect(function()
                    -- 向服务端发送回收请求
                    shovelRE:FireServer(plant)
                    
                    -- [🌟 核心修复：先隐藏，防闪烁]
                    if activeShovelPrompts[plant] then
                        local currentPrompt = activeShovelPrompts[plant]
                        
                        -- 1. 瞬间关闭交互，UI 会优雅消失，不会失去坐标而乱闪
                        currentPrompt.Enabled = false 
                        
                        -- 2. 从记录表中移除
                        activeShovelPrompts[plant] = nil
                        
                        -- 3. 延迟 0.1 秒后再彻底销毁，给底层渲染引擎一个缓冲时间
                        task.delay(0.1, function()
                            if currentPrompt and currentPrompt.Parent then 
                                currentPrompt:Destroy() 
                            end
                        end)
                    end
                end)
            end
        end
    end

    local function updateShovelState()
        local char = player.Character
        if not char or char:GetAttribute("EquippedSeed") ~= "Tool_Shovel" then
            -- 如果玩家放下铲子，立刻清理所有 F 回收提示
            clearAllPrompts()
            return
        end

        -- 如果拿起了铲子，扫描全图，给所有合法植物装上 F 回收提示
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and (obj:GetAttribute("IsCombatPlant") or obj:GetAttribute("PlantedOn")) then
                checkAndAddPrompt(obj)
            end
        end
    end

    -- 绑定装备切换监听
    local function bindCharacter(char)
        char:GetAttributeChangedSignal("EquippedSeed"):Connect(updateShovelState)
        updateShovelState()
    end

    if player.Character then bindCharacter(player.Character) end
    player.CharacterAdded:Connect(bindCharacter)

    -- 监听中途新生成的植物（比如手里拿着铲子时新种下的植物）
    Workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("Model") then
            task.delay(0.1, function() -- 延迟一点点等待属性赋值完毕
                local char = player.Character
                if char and char:GetAttribute("EquippedSeed") == "Tool_Shovel" then
                    if desc:GetAttribute("IsCombatPlant") or desc:GetAttribute("PlantedOn") then
                        checkAndAddPrompt(desc)
                    end
                end
            end)
        end
    end)
    
    -- 循环检查防 Bug：如果玩家一直举着铲子时，农田植物突然成熟了，自动去掉回收提示避免冲突
    task.spawn(function()
        while task.wait(1) do
            for plant, prompt in pairs(activeShovelPrompts) do
                if not plant or not plant.Parent or plant:GetAttribute("IsMature") then
                    if prompt then prompt:Destroy() end
                    activeShovelPrompts[plant] = nil
                end
            end
        end
    end)
    
    print("客户端：ToolController (F键回收逻辑) 加载完毕！")
end

return ToolController
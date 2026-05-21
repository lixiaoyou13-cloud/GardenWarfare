-- src/client/Services/ToolController.luau
local ToolController = {
    _okConn = nil,      -- 提前声明，消除 Luau 类型检查警告
    _cancelConn = nil   -- 提前声明，消除 Luau 类型检查警告
}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local weaponAttackRE = ReplicatedStorage:WaitForChild("WeaponAttackRE", 5)


local activePrompts = {} -- 保存对 Prompt 的引用，方便随时清理

function ToolController.Init()
    local player = Players.LocalPlayer
    local shovelRE = ReplicatedStorage:WaitForChild("ShovelActionRE")
    
    -- 🌟 注册交换植物的远程事件
    local swapRE = ReplicatedStorage:WaitForChild("SwapCombatPlantRE", 5) 
    if not swapRE then
        -- 本地伪造一个防止报错，等待服务端真正创建
        swapRE = Instance.new("RemoteEvent")
        swapRE.Name = "SwapCombatPlantRE"
        swapRE.Parent = ReplicatedStorage
    end

    local function clearAllPrompts()
        for plant, prompt in pairs(activePrompts) do
            if prompt and prompt.Parent then prompt:Destroy() end
        end
        table.clear(activePrompts)
    end

    local function checkAndAddPrompt(plant, equippedItem)
        -- 排除已经生成提示的植物
        if activePrompts[plant] then return end

        local isCombat = plant:GetAttribute("IsCombatPlant")
        local isFarm = plant:GetAttribute("PlantedOn")
        local isMature = plant:GetAttribute("IsMature")
        
        local actionName = nil
        
        -- [🌟 核心判定：手里拿的是铲子 还是 植物？]
        if equippedItem == "Tool_Shovel" then
            -- 铲子逻辑：战斗植物可回收，农田植物必须【未成熟】
            if isCombat or (isFarm and not isMature) then
                actionName = "Recycle to Backpack"
            end
        elseif type(equippedItem) == "string" and string.match(equippedItem, "^Plant_") then
            -- 拿着植物！开启交换逻辑，只能交换阵地上的战斗植物
            if isCombat then
                actionName = "Swap Plant"
            end
        end
        
        if actionName then
            local prompt = Instance.new("ProximityPrompt")
            prompt.ActionText = actionName
            prompt.ObjectText = plant.Name or "Plant"
            prompt.KeyboardKeyCode = Enum.KeyCode.F
            prompt.HoldDuration = 0.2 -- 稍微加一点长按时间，防止误触
            prompt.MaxActivationDistance = 12
            prompt.RequiresLineOfSight = false
            
            local attachPart = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart", true)
            if attachPart then
                prompt.Parent = attachPart
                activePrompts[plant] = prompt
                
                prompt.Triggered:Connect(function()
                    if isCombat then
                        local lawnPart = plant.Parent
                        local plot = lawnPart and lawnPart.Parent and lawnPart.Parent.Parent
                        if plot and plot:GetAttribute("IsLevelActive") then
                            
                            -- 👇 [🌟 修复后：正确的战斗状态拦截与弹窗逻辑]
                            if actionName == "Swap Plant" or actionName == "Recycle to Backpack" then
                                local playerGui = player:WaitForChild("PlayerGui")
                                local basicGui = playerGui:FindFirstChild("BasicGui")
                                local popup = basicGui and basicGui:FindFirstChild("Popup")
                                
                                if popup then
                                    local popupFrame = popup:FindFirstChild("PopupFrame")
                                    if popupFrame then
                                        local detail = popupFrame:FindFirstChild("Detail")
                                        local btnOk = popupFrame:FindFirstChild("OK")
                                        local btnCancel = popupFrame:FindFirstChild("Cancel")
                                        
                                        if detail and btnOk and btnCancel then
                                            -- 动态设置英文确认文本
                                            if actionName == "Swap Plant" then
                                                detail.Text = "Swapping plants during combat costs 1K Sun."
                                            else
                                                detail.Text = "Removing plants during combat costs 1K Sun."
                                            end
                                            popup.Enabled = true
                                            
                                            -- 清理之前的绑定，防止多重触发
                                            if ToolController._okConn then ToolController._okConn:Disconnect() end
                                            if ToolController._cancelConn then ToolController._cancelConn:Disconnect() end
                                            
                                            -- 确认扣费并发送请求
                                            ToolController._okConn = btnOk.MouseButton1Click:Connect(function()
                                                popup.Enabled = false
                                                ToolController._okConn:Disconnect()
                                                ToolController._cancelConn:Disconnect()
                                                
                                                -- 传入 true 代表这是战斗中的操作
                                                if actionName == "Swap Plant" then
                                                    swapRE:FireServer(plant, equippedItem, true)
                                                else
                                                    shovelRE:FireServer(plant, true)
                                                end
                                            end)
                                            
                                            -- 取消操作
                                            ToolController._cancelConn = btnCancel.MouseButton1Click:Connect(function()
                                                popup.Enabled = false
                                                ToolController._okConn:Disconnect()
                                                ToolController._cancelConn:Disconnect()
                                            end)
                                        end
                                    end
                                end
                                return -- 拦截到底，不往下执行默认操作
                            else
                                UIEffectUtil.ShowTip("Cannot interact with plants during battle")
                                return
                            end
                        end
                    end

                    -- [🌟 根据动作发送给不同的服务端接口 (非战斗状态走这里)]
                    if actionName == "Swap Plant" then
                        swapRE:FireServer(plant, equippedItem, false)
                    else
                        shovelRE:FireServer(plant, false)
                    end
                    
                    -- 先隐藏，防闪烁
                    if activePrompts[plant] then
                        local currentPrompt = activePrompts[plant]
                        currentPrompt.Enabled = false 
                        activePrompts[plant] = nil
                        
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

    local function updateToolState()
        local char = player.Character
        if not char then return end
        
        local equippedItem = char:GetAttribute("EquippedSeed")
        
        -- 每次切换装备，先清理旧的提示框
        clearAllPrompts()
        
        -- 如果拿起了铲子，或者举起了成熟的植物(Plant_开头)
        if equippedItem == "Tool_Shovel" or (type(equippedItem) == "string" and string.match(equippedItem, "^Plant_")) then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("Model") and (obj:GetAttribute("IsCombatPlant") or obj:GetAttribute("PlantedOn")) then
                    checkAndAddPrompt(obj, equippedItem)
                end
            end
        end
    end

    local function bindCharacter(char)
        char:GetAttributeChangedSignal("EquippedSeed"):Connect(updateToolState)
        updateToolState()
    end

    if player.Character then bindCharacter(player.Character) end
    player.CharacterAdded:Connect(bindCharacter)

    Workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("Model") then
            task.delay(0.1, function() 
                local char = player.Character
                if char then
                    local equippedItem = char:GetAttribute("EquippedSeed")
                    if equippedItem == "Tool_Shovel" or (type(equippedItem) == "string" and string.match(equippedItem, "^Plant_")) then
                        if desc:GetAttribute("IsCombatPlant") or desc:GetAttribute("PlantedOn") then
                            checkAndAddPrompt(desc, equippedItem)
                        end
                    end
                end
            end)
        end
    end)
    
    task.spawn(function()
        while task.wait(1) do
            for plant, prompt in pairs(activePrompts) do
                if not plant or not plant.Parent or plant:GetAttribute("IsMature") then
                    -- 仅铲子状态下才清理农田成熟的 Bug（交换只能对草坪使用，不受农田成熟影响）
                    if prompt and prompt.ActionText == "Recycle to Backpack" then
                        prompt:Destroy()
                        activePrompts[plant] = nil
                    end
                end
            end
        end
    end)
    
    -- ==========================================
    -- [武器点击挥舞逻辑]
    -- ==========================================
    local attackAnim = Instance.new("Animation")
    attackAnim.AnimationId = "rbxassetid://135432663541165" 
    local isAttacking = false 

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end 

        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local char = player.Character
            if not char then return end

            if char:GetAttribute("EquippedSeed") == "Tool_WeaponBlock" then
                if isAttacking then return end
                isAttacking = true

                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
                    local track = animator:LoadAnimation(attackAnim)
                    track.Priority = Enum.AnimationPriority.Action3 
                    track:Play(0.05)

                    task.spawn(function()
                        local hitTargets = {}
                        local processed = {}
                        local checkDuration = 0.35 
                        local startTime = tick()

                        while tick() - startTime < checkDuration and isAttacking do
                            local rootPart = char:FindFirstChild("HumanoidRootPart")
                            if not rootPart then break end

                            local checkCFrame = rootPart.CFrame * CFrame.new(0, 0, -3.5)
                            local checkSize = Vector3.new(6.5, 6, 7.5) 
                            local overlapParams = OverlapParams.new()

                            local hitParts = Workspace:GetPartBoundsInBox(checkCFrame, checkSize, overlapParams)

                            for _, part in ipairs(hitParts) do
                                local targetModel = part:FindFirstAncestorOfClass("Model")
                                if targetModel and targetModel ~= char and not processed[targetModel] then
                                    local hum = targetModel:FindFirstChildOfClass("Humanoid")
                                    if hum and hum.Health > 0 then
                                        processed[targetModel] = true
                                        table.insert(hitTargets, targetModel)
                                    end
                                end
                            end

                            if #hitTargets > 0 and weaponAttackRE then
                                 weaponAttackRE:FireServer(hitTargets)
                                 table.clear(hitTargets) 
                            end
                            task.wait(0.05) 
                         end
                    end)

                    task.delay(0.5, function()
                        isAttacking = false
                    end)
                else
                    isAttacking = false
                end
            end
        end
    end)
    
    print("客户端：ToolController (F键交换与回收联动) 加载完毕！")
end

return ToolController
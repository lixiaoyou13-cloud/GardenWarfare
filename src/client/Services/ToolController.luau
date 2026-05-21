-- src/client/Services/ToolController.luau
local ToolController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local UIEffectUtil = require(script.Parent.Parent.Utils.UIEffectUtil)
local PopupUtil = require(script.Parent.Parent.Utils.PopupUtil)
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local weaponAttackRE = ReplicatedStorage:WaitForChild("WeaponAttackRE", 5)


local activePrompts = {} -- 保存对 Prompt 的引用，方便随时清理
local activeGiftPopup = nil
local activeGiftRequestId = nil

function ToolController.Init()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()
    local shovelRE = ReplicatedStorage:WaitForChild("ShovelActionRE")
    local giftItemRE = ReplicatedStorage:WaitForChild("GiftItemRE")
    
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
                            
                            -- 👇 [🌟 战斗中的置换/回收确认弹窗交给独立模块处理]
                            if actionName == "Swap Plant" or actionName == "Recycle to Backpack" then
                                local detailText = if actionName == "Swap Plant"
                                    then "Swapping plants during combat costs 1K Sun."
                                    else "Removing plants during combat costs 1K Sun."

                                local shown = PopupUtil.ShowConfirm(detailText, function()
                                    -- 传入 true 代表这是战斗中的操作
                                    if actionName == "Swap Plant" then
                                        swapRE:FireServer(plant, equippedItem, true)
                                    else
                                        shovelRE:FireServer(plant, true)
                                    end
                                end)

                                if not shown then
                                    UIEffectUtil.ShowTip("Popup is unavailable right now")
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

    local function getGiftItemDisplayName(compositeId)
        local parts = string.split(compositeId, "_")
        local itemType = parts[1]
        local realId = parts[2]

        if itemType == "Seed" then
            local seedConfig = ItemConfig.Seeds[realId]
            return (seedConfig and seedConfig.Name) or realId
        elseif itemType == "Plant" then
            local plantConfig = ItemConfig.Plants[realId]
            return (plantConfig and plantConfig.Name) or realId
        end

        return nil
    end

    local function tryGiftEquippedItem(targetPlayer)
        if not targetPlayer or targetPlayer == player then return false end

        local char = player.Character
        if not char then return false end

        local equippedItem = char:GetAttribute("EquippedSeed")
        if type(equippedItem) ~= "string" then return false end
        if not string.match(equippedItem, "^Seed_") and not string.match(equippedItem, "^Plant_") then
            return false
        end

        local itemName = getGiftItemDisplayName(equippedItem)
        if not itemName then return false end

        local confirmText = string.format("Do you want to gift %s to %s?", itemName, targetPlayer.Name)
        local popupHandle = PopupUtil.ShowManaged(confirmText, {
            closeOnConfirm = false,
            closeOnCancel = true,
            onConfirm = function(handle)
                handle.SetWaiting("Waiting for the other player to confirm ...")
                activeGiftPopup = handle
                activeGiftRequestId = "PENDING"
                UIEffectUtil.ShowTip("Waiting...")
                giftItemRE:FireServer("CreateRequest", targetPlayer, equippedItem)
            end,
            onCancel = function()
                activeGiftPopup = nil
                activeGiftRequestId = nil
            end,
        })

        if not popupHandle then
            UIEffectUtil.ShowTip("Popup is unavailable right now")
            return true
        end

        return true
    end

    giftItemRE.OnClientEvent:Connect(function(action, ...)
        local args = { ... }

        if action == "RequesterWaiting" then
            local requestId = args[1]
            activeGiftRequestId = requestId

            if activeGiftPopup then
                activeGiftPopup.SetWaiting("Waiting for the other player to confirm ...")
                activeGiftPopup.SetButtons({
                    onCancel = function()
                        giftItemRE:FireServer("CancelRequest", requestId)
                        activeGiftPopup = nil
                        activeGiftRequestId = nil
                    end,
                    closeOnCancel = true,
                })
            end
        elseif action == "ReceiveRequest" then
            local requestId = args[1]
            local fromPlayerName = args[2]
            local itemName = args[3]

            activeGiftRequestId = requestId
            activeGiftPopup = PopupUtil.ShowManaged(
                string.format("Player %s gifts %s to you. Do you accept?", fromPlayerName, itemName),
                {
                    closeOnConfirm = true,
                    closeOnCancel = true,
                    onConfirm = function()
                        giftItemRE:FireServer("RespondRequest", requestId, true)
                        activeGiftPopup = nil
                        activeGiftRequestId = nil
                    end,
                    onCancel = function()
                        giftItemRE:FireServer("RespondRequest", requestId, false)
                        activeGiftPopup = nil
                        activeGiftRequestId = nil
                    end,
                }
            )

            if not activeGiftPopup then
                giftItemRE:FireServer("RespondRequest", requestId, false)
                UIEffectUtil.ShowTip("Popup is unavailable right now")
            end
        elseif action == "ClosePopup" then
            local requestId = args[1]
            local tipText = args[2]

            if activeGiftRequestId == requestId or requestId == nil then
                PopupUtil.Hide()
                activeGiftPopup = nil
                activeGiftRequestId = nil
            end

            if tipText and tipText ~= "" then
                UIEffectUtil.ShowTip(tipText)
            end
        end
    end)

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

            local target = mouse.Target
            if target then
                local targetModel = target:FindFirstAncestorOfClass("Model")
                local targetPlayer = targetModel and Players:GetPlayerFromCharacter(targetModel)
                if tryGiftEquippedItem(targetPlayer) then
                    return
                end
            end

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
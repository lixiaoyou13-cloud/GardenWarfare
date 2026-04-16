-- src/client/UI/EncyclopediaController.luau
local EncyclopediaController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

function EncyclopediaController.Init()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local basicGui = playerGui:WaitForChild("BasicGui")
    
    local playProperty = basicGui:WaitForChild("PlayProperty")
    local openCodexBtn = playProperty:WaitForChild("Codex")
    
    local codexGui = basicGui:WaitForChild("Codex")
    local plantPage = codexGui:WaitForChild("Plant")
    
    local scrollingFrames = {}
    local categoryBtns = {}
    
    for i = 1, 4 do
        scrollingFrames[i] = plantPage:WaitForChild("ScrollingFrame" .. i)
        categoryBtns[i] = plantPage:WaitForChild("Category" .. i)
    end
    
    local uiTemplates = ReplicatedStorage:WaitForChild("UITemplates")
    local itemTemplate = uiTemplates:WaitForChild("ItemTemplate")

    -- ==========================================
    -- [🌟 核心：获取真实后端数据并渲染]
    -- ==========================================
    local function LoadCodexItems(tabIndex)
        local currentScroll = scrollingFrames[tabIndex]
        if not currentScroll then return end

        for _, child in pairs(currentScroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        local mutationLabel = ItemConfig.MutationName and ItemConfig.MutationName[tabIndex] or "未知"
        
        local getPlayerDataRF = ReplicatedStorage:WaitForChild("GetPlayerDataRF", 5)
        local playerData = getPlayerDataRF and getPlayerDataRF:InvokeServer() or {}
        local unlockedMutations = playerData.UnlockedMutations or {}

        for plantId, plantDetail in pairs(ItemConfig.Plants) do
            local slot = itemTemplate:Clone()
            slot.Name = plantId
            slot.Visible = true
            
            if slot:FindFirstChild("ItemName") then
                slot.ItemName.Text = plantDetail.Name or plantId
            end
            
            if slot:FindFirstChild("Icom") then
                slot.Icom.Image = plantDetail.IconId or ""
                
                -- 判断变异解锁状态
                local isOwned = false
                if unlockedMutations[plantId] and unlockedMutations[plantId][tabIndex] then
                    isOwned = true
                end
                
                if isOwned then
                    slot.Icom.ImageColor3 = Color3.fromRGB(255, 255, 255)
                else
                    slot.Icom.ImageColor3 = Color3.fromRGB(0, 0, 0)
                end
            end
            
            if slot:FindFirstChild("Quantity") then
                slot.Quantity.Text = mutationLabel
                slot.Quantity.Visible = true
                
                if tabIndex == 1 then slot.Quantity.TextColor3 = Color3.fromRGB(255, 255, 255)
                elseif tabIndex == 2 then slot.Quantity.TextColor3 = Color3.fromRGB(85, 170, 255)
                elseif tabIndex == 3 then slot.Quantity.TextColor3 = Color3.fromRGB(170, 85, 255)
                elseif tabIndex == 4 then slot.Quantity.TextColor3 = Color3.fromRGB(255, 170, 0)
                end
            end
            
            if slot:FindFirstChild("Index") then
                slot.Index.Visible = false
            end
            
            slot.Parent = currentScroll
        end
    end

    local function SwitchTab(tabIndex)
        for i = 1, 4 do
            scrollingFrames[i].Visible = (i == tabIndex)
            if i == tabIndex then
                categoryBtns[i].BackgroundColor3 = Color3.fromRGB(200, 255, 200) 
            else
                categoryBtns[i].BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
            end
        end

        LoadCodexItems(tabIndex)
    end

    for i = 1, 4 do
        categoryBtns[i].MouseButton1Click:Connect(function()
            SwitchTab(i)
        end)
    end

    openCodexBtn.MouseButton1Click:Connect(function()
        -- [🌟 修复：完全按照你的要求使用 Enabled]
        codexGui.Enabled = true
        plantPage.Visible = true
        SwitchTab(1) 
    end)
    
    local updateInventoryRE = ReplicatedStorage:WaitForChild("UpdateInventoryRE", 5)
    if updateInventoryRE then
        updateInventoryRE.OnClientEvent:Connect(function()
            -- [🌟 修复：检测是否开启图鉴时同样使用 Enabled]
            if codexGui.Enabled then
                for i = 1, 4 do
                    if scrollingFrames[i].Visible then
                        LoadCodexItems(i)
                        break
                    end
                end
            end
        end)
    end

    local closeBtn = codexGui:FindFirstChild("Close", true) or codexGui:FindFirstChild("CloseBtn", true)
    if closeBtn and (closeBtn:IsA("GuiButton") or closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
        closeBtn.MouseButton1Click:Connect(function()
            -- [🌟 修复：关闭时使用 Enabled = false]
            codexGui.Enabled = false
        end)
    end 
    
    print("客户端：EncyclopediaController 加载完毕！（已改回 Enabled）")
end

return EncyclopediaController
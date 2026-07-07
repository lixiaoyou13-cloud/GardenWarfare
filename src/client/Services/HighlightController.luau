-- src/client/Services/HighlightController.luau
local HighlightController = {}

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 逻辑：为本地玩家专属地块添加半透明覆盖层
local function applyPlotOwnershipHighlight(plot)
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return end

    -- 1. 清理该地块上可能存在的旧特效（包含自己和其他人的）
    for _, obj in ipairs(plot:GetDescendants()) do
        if obj:IsA("SelectionBox") and obj.Name == "MyPlotOverlay" then
            obj:Destroy()
        end
    end

    local ownerId = plot:GetAttribute("OwnerId")

    -- 2. 判断该地块当前的归属者是否为客户端本地玩家
    if ownerId == localPlayer.UserId then
        -- print("地块高亮 识别到本地玩家的地块: " .. plot.Name .. "，开始铺设黄色高亮...")

        local areasToHighlight = {}

        -- 点击：直接移除了收集 Soils(泥土) 的代码，现在仅收集 Lawn(草坪)

        -- 收集草坪
        local lawn = plot:FindFirstChild("Lawn")
        if lawn then
            for _, part in ipairs(lawn:GetChildren()) do
                if part:IsA("BasePart") then
                    table.insert(areasToHighlight, part)
                end
            end
        end

        -- print("地块高亮 共找到 " .. #areasToHighlight .. " 个草坪零件，正在上色...")

        -- 3. 强化版 SelectionBox 附加颜色
        for _, part in ipairs(areasToHighlight) do
            local overlay = Instance.new("SelectionBox")
            overlay.Name = "MyPlotOverlay"

            -- 表面填充：明亮的黄色
            overlay.SurfaceColor3 = Color3.fromRGB(85, 255, 127)
            -- 将透明度保持为 0.5（50%透明）
            overlay.SurfaceTransparency = 0.65

            -- 加入微弱的边框，防止纯表面在特定材质下被渲染引擎吞掉
            overlay.Color3 = Color3.fromRGB(85, 255, 127)
            overlay.Transparency = 0.25 -- 正确的属性名
            overlay.LineThickness = 0.045

            overlay.Adornee = part
            overlay.Parent = part
        end
    end
end

function HighlightController.Init()

    -- 全局监听玩家眼前的交互提示框
    ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
        local targetPart = prompt.Parent

        if targetPart and (targetPart:IsA("BasePart") or targetPart:IsA("Model")) then
            local existingHighlight = targetPart:FindFirstChild("InteractFocusHighlight")
            if not existingHighlight then
                local hl = Instance.new("Highlight")
                hl.Name = "InteractFocusHighlight"
                hl.FillColor = Color3.fromRGB(85, 255, 127)
                hl.FillTransparency = 0.95
                hl.OutlineColor = Color3.fromRGB(85, 255, 127)
                hl.OutlineTransparency = 0.3
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = targetPart
                hl.Parent = targetPart
            end
        end
    end)

    ProximityPromptService.PromptHidden:Connect(function(prompt, inputType)
        local targetPart = prompt.Parent
        if targetPart then
            local hl = targetPart:FindFirstChild("InteractFocusHighlight")
            if hl then hl:Destroy() end
        end
    end)

    -- 监听地块分配状态，生成专属地块识别颜色
    task.spawn(function()
        local plotsFolder = Workspace:WaitForChild("Plots")

        -- 1. 初始化当前场上已有的地块
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            if string.match(plot.Name, "Plot") then
                applyPlotOwnershipHighlight(plot)

                -- 监听属性变化
                plot:GetAttributeChangedSignal("OwnerId"):Connect(function()
                    applyPlotOwnershipHighlight(plot)
                end)
            end
        end

        -- 2. 监听未来动态加载的新地块
        plotsFolder.ChildAdded:Connect(function(plot)
            if string.match(plot.Name, "Plot") then
                -- 稍微避免延迟一点击点击，等待内部组件加载
                task.wait(0.5)
                applyPlotOwnershipHighlight(plot)

                plot:GetAttributeChangedSignal("OwnerId"):Connect(function()
                    applyPlotOwnershipHighlight(plot)
                end)
            end
        end)
    end)

    print("Client: HighlightController (smart focus highlight + local lawn territory color) loaded.")
end

return HighlightController

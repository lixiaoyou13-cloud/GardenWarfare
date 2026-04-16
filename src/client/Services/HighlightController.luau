-- src/client/Services/HighlightController.luau
local HighlightController = {}

local ProximityPromptService = game:GetService("ProximityPromptService")

function HighlightController.Init()
    -- ==========================================
    -- [🌟 核心逻辑：全局监听玩家眼前的提示框]
    -- 当玩家靠近并看准了一个可交互物体，F键提示弹出来的瞬间：
    -- ==========================================
    ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
        local targetPart = prompt.Parent
        
        -- 确保提示框是挂在某个模型或者零件上的
        if targetPart and (targetPart:IsA("BasePart") or targetPart:IsA("Model")) then
            
            -- 防止重复创建，先找找有没有
            local existingHighlight = targetPart:FindFirstChild("InteractFocusHighlight")
            if not existingHighlight then
                local hl = Instance.new("Highlight")
                hl.Name = "InteractFocusHighlight"
                ---6666666
                
                -- ==========================================
                -- [🎨 视觉调优：更柔和、更暗的护眼高亮]
                -- ==========================================
                -- 1. 填充颜色也改成绿色，而不是刺眼的白色
                hl.FillColor = Color3.fromRGB(85, 255, 127)
                -- 2. 填充透明度拉高到 0.95（几乎看不见，只有极弱的一层光晕）
                hl.FillTransparency = 0.95 
                
                -- 3. 描边颜色保持绿色
                hl.OutlineColor = Color3.fromRGB(85, 255, 127) 
                -- 4. 给描边加上 30% 的透明度，不再那么生硬刺眼
                hl.OutlineTransparency = 0.3
                
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop 
                
                hl.Adornee = targetPart
                hl.Parent = targetPart
            end
        end
    end)

    -- ==========================================
    -- 当玩家移开视线走远，或者 F 键提示消失的瞬间：
    -- ==========================================
    ProximityPromptService.PromptHidden:Connect(function(prompt, inputType)
        local targetPart = prompt.Parent
        if targetPart then
            -- 找到刚才挂上去的高亮特效，销毁它！
            local hl = targetPart:FindFirstChild("InteractFocusHighlight")
            if hl then
                hl:Destroy()
            end
        end
    end)

    print("客户端：HighlightController (智能焦点高亮) 加载完毕！防误触系统上线！")
end

return HighlightController
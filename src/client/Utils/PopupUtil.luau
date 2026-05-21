local Players = game:GetService("Players")

local PopupUtil = {
	_okConn = nil,
	_cancelConn = nil,
}

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

function PopupUtil.Hide()
	disconnectConnection(PopupUtil._okConn)
	disconnectConnection(PopupUtil._cancelConn)
	PopupUtil._okConn = nil
	PopupUtil._cancelConn = nil

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local basicGui = playerGui and playerGui:FindFirstChild("BasicGui")
	local popup = basicGui and basicGui:FindFirstChild("Popup")
	if popup then
		popup.Enabled = false
	end
end

function PopupUtil.ShowConfirm(detailText: string, onConfirm: () -> ())
	PopupUtil.Hide()

	local player = Players.LocalPlayer
	if not player then
		warn("PopupUtil: LocalPlayer 不存在")
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
	local basicGui = playerGui:FindFirstChild("BasicGui")
	local popup = basicGui and basicGui:FindFirstChild("Popup")
	local popupFrame = popup and popup:FindFirstChild("PopupFrame")
	local detail = popupFrame and popupFrame:FindFirstChild("Detail")
	local btnOk = popupFrame and popupFrame:FindFirstChild("OK")
	local btnCancel = popupFrame and popupFrame:FindFirstChild("Cancel")

	if not (popup and popupFrame and detail and btnOk and btnCancel) then
		warn("PopupUtil: 找不到完整的 Popup UI 结构")
		return false
	end

	detail.Text = detailText
	popup.Enabled = true

	PopupUtil._okConn = btnOk.MouseButton1Click:Connect(function()
		PopupUtil.Hide()
		onConfirm()
	end)

	PopupUtil._cancelConn = btnCancel.MouseButton1Click:Connect(function()
		PopupUtil.Hide()
	end)

	return true
end

return PopupUtil
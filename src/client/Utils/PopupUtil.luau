local Players = game:GetService("Players")

local PopupUtil = {
	_okConn = nil,
	_cancelConn = nil,
	_popup = nil,
	_popupFrame = nil,
	_detail = nil,
	_btnOk = nil,
	_btnCancel = nil,
}

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function getButtonLabel(button)
	if not button then
		return nil
	end

	if button:IsA("TextButton") or button:IsA("TextLabel") or button:IsA("TextBox") then
		return button
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			return descendant
		end
	end

	return nil
end

local function getPopupRefs()
	local player = Players.LocalPlayer
	if not player then
		warn("PopupUtil: LocalPlayer 不存在")
		return nil
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
		return nil
	end

	PopupUtil._popup = popup
	PopupUtil._popupFrame = popupFrame
	PopupUtil._detail = detail
	PopupUtil._btnOk = btnOk
	PopupUtil._btnCancel = btnCancel

	return popup, popupFrame, detail, btnOk, btnCancel
end

local function setButtonEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.Selectable = enabled
	if button:IsA("GuiButton") then
		button.Modal = false
	end
	if button:IsA("GuiObject") then
		button.BackgroundTransparency = enabled and 0 or 0.35
	end

	local label = getButtonLabel(button)
	if label then
		label.TextTransparency = enabled and 0 or 0.25
	end
end

local function setButtonText(button, text)
	local label = getButtonLabel(button)
	if label and text ~= nil then
		label.Text = text
	end
end

function PopupUtil.Hide()
	disconnectConnection(PopupUtil._okConn)
	disconnectConnection(PopupUtil._cancelConn)
	PopupUtil._okConn = nil
	PopupUtil._cancelConn = nil

	local popup = PopupUtil._popup
	if not popup then
		popup = getPopupRefs()
	end

	if not popup then
		return
	end

	if popup then
		popup.Enabled = false
	end
end

function PopupUtil.ShowManaged(detailText: string, options)
	PopupUtil.Hide()

	local popup, _, detail, btnOk, btnCancel = getPopupRefs()
	if not popup then
		return false
	end

	options = options or {}
	detail.Text = detailText
	setButtonText(btnOk, options.okText or "OK")
	setButtonText(btnCancel, options.cancelText or "Cancel")
	btnOk.Visible = options.showOk ~= false
	btnCancel.Visible = options.showCancel ~= false
	setButtonEnabled(btnOk, options.okEnabled ~= false)
	setButtonEnabled(btnCancel, options.cancelEnabled ~= false)
	popup.Enabled = true

	local handle = {}

	PopupUtil._okConn = btnOk.MouseButton1Click:Connect(function()
		if options.closeOnConfirm ~= false then
			PopupUtil.Hide()
		end
		if options.onConfirm then
			options.onConfirm(handle)
		end
	end)

	PopupUtil._cancelConn = btnCancel.MouseButton1Click:Connect(function()
		if options.closeOnCancel ~= false then
			PopupUtil.Hide()
		end
		if options.onCancel then
			options.onCancel(handle)
		end
	end)

	function handle.Update(newDetailText: string)
		if PopupUtil._detail then
			PopupUtil._detail.Text = newDetailText
		end
	end

	function handle.SetButtons(newOptions)
		newOptions = newOptions or {}
		if PopupUtil._btnOk then
			if newOptions.okText ~= nil then setButtonText(PopupUtil._btnOk, newOptions.okText) end
			if newOptions.showOk ~= nil then PopupUtil._btnOk.Visible = newOptions.showOk end
			if newOptions.okEnabled ~= nil then setButtonEnabled(PopupUtil._btnOk, newOptions.okEnabled) end
		end
		if PopupUtil._btnCancel then
			if newOptions.cancelText ~= nil then setButtonText(PopupUtil._btnCancel, newOptions.cancelText) end
			if newOptions.showCancel ~= nil then PopupUtil._btnCancel.Visible = newOptions.showCancel end
			if newOptions.cancelEnabled ~= nil then setButtonEnabled(PopupUtil._btnCancel, newOptions.cancelEnabled) end
		end
		if newOptions.closeOnConfirm ~= nil then options.closeOnConfirm = newOptions.closeOnConfirm end
		if newOptions.closeOnCancel ~= nil then options.closeOnCancel = newOptions.closeOnCancel end
		if newOptions.onConfirm ~= nil then options.onConfirm = newOptions.onConfirm end
		if newOptions.onCancel ~= nil then options.onCancel = newOptions.onCancel end
		if newOptions.okText ~= nil or newOptions.cancelText ~= nil then
			-- no-op, handled above; keeps method symmetric
		end
	end

	function handle.SetWaiting(newDetailText: string)
		handle.Update(newDetailText)
		handle.SetButtons({
			showOk = true,
			okEnabled = false,
			cancelText = "Cancel",
			cancelEnabled = true,
			closeOnConfirm = false,
			closeOnCancel = true,
		})
	end

	function handle.Close()
		PopupUtil.Hide()
	end

	return handle
end

function PopupUtil.ShowConfirm(detailText: string, onConfirm: () -> ())
	return PopupUtil.ShowManaged(detailText, {
		onConfirm = function()
			onConfirm()
		end,
	}) ~= false
end

return PopupUtil
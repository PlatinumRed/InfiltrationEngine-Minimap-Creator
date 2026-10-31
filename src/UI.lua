-- UI module
-- This module handles the UI. Yup, that's it.
-- This was a lot more work than I expected going in though not gonna lie.

local State = require(script.Parent.State)

local UI = {}

local function getTheme(obj, objType)
	local theme = settings().Studio.Theme
	local themeColor = Enum.StudioStyleGuideColor
	if objType == "bg" then
		obj.BackgroundColor3 = theme:GetColor(themeColor.MainBackground)
	elseif objType == "panel" then
		obj.BackgroundColor3 = theme:GetColor(themeColor.InputFieldBackground)
		obj.BorderColor3 = theme:GetColor(themeColor.InputFieldBorder)
	elseif objType == "button" then
		obj.BackgroundColor3 = theme:GetColor(themeColor.Button)
		obj.TextColor3 = theme:GetColor(themeColor.ButtonText)
		obj.BorderColor3 = theme:GetColor(themeColor.ButtonBorder)
	elseif objType == "label" then
		obj.TextColor3 = theme:GetColor(themeColor.MainText)
	elseif objType == "sub" then
		obj.TextColor3 = theme:GetColor(themeColor.SubText)
	elseif objType == "input" then
		obj.BackgroundColor3 = theme:GetColor(themeColor.InputFieldBackground)
		obj.TextColor3 = theme:GetColor(themeColor.MainText)
		obj.BorderColor3 = theme:GetColor(themeColor.InputFieldBorder)
	end
end

local Elements = {}

local function reg(inst, objType)
	table.insert(Elements, { inst, objType })
	getTheme(inst, objType)
	return inst
end

function UI.applyTheme()
	for _, element in ipairs(Elements) do
		getTheme(element[1], element[2])
	end
end

UI.Theme = getTheme
UI.reg = reg
UI.updatingUI = false

function UI.makeButton(text, layoutOrder, parent, size)
	local button = reg(Instance.new("TextButton"), "button")
	button.Text = text
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 15
	button.Size = size or UDim2.new(1, 0, 0, 30)
	button.BorderSizePixel = 1
	button.LayoutOrder = layoutOrder
	button.Parent = parent or UI.content
	return button
end

function UI.numberRow(labelText, layoutOrder, step, onStep, onTyped)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = layoutOrder
	row.Parent = UI.content

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local nameLabel = reg(Instance.new("TextLabel"), "label")
	nameLabel.Text = labelText
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Size = UDim2.new(0, 70, 1, 0)
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = row

	local minusBtn = UI.makeButton("-", 2, row, UDim2.new(0, 28, 1, 0))

	local valueBox = reg(Instance.new("TextBox"), "input")
	valueBox.Font = Enum.Font.SourceSans
	valueBox.TextSize = 14
	valueBox.ClearTextOnFocus = false
	valueBox.BorderSizePixel = 1
	valueBox.Size = UDim2.new(1, -(70 + 28 + 28 + 18), 1, 0)
	valueBox.LayoutOrder = 3
	valueBox.Parent = row

	local plusBtn = UI.makeButton("+", 4, row, UDim2.new(0, 28, 1, 0))

	minusBtn.Activated:Connect(function() onStep(-step) end)
	plusBtn.Activated:Connect(function() onStep(step) end)
	valueBox:GetPropertyChangedSignal("Text"):Connect(function()
		if UI.updatingUI then return end
		local typedNumber = tonumber(valueBox.Text)
		if typedNumber then onTyped(typedNumber) end
	end)

	return valueBox
end

function UI.setStatus(message, isError)
	UI.statusLabel.Text = message
	if isError then
		UI.statusLabel.TextColor3 = Color3.fromRGB(230, 90, 90)
	else
		getTheme(UI.statusLabel, "sub")
	end
end

function UI.refreshNumbers()
	UI.updatingUI = true
	UI.rotationBox.Text = string.format("%.1f", State.rotation)
	UI.minSizeBox.Text = string.format("%g", State.minSize)
	UI.minSpanBox.Text = string.format("%g", State.minSpanPercent)
	UI.updatingUI = false
end

function UI.buildUI(plugin, widgetId)
	table.clear(Elements)

	local windowInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 360, 600, 360, 360)
	local widget = plugin:CreateDockWidgetPluginGuiAsync(widgetId, windowInfo)
	widget.Title = "Minimap Creator"
	UI.widget = widget

	local content = reg(Instance.new("ScrollingFrame"), "bg")
	content.Size = UDim2.fromScale(1, 1)
	content.BorderSizePixel = 0
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.ScrollBarThickness = 6
	content.Parent = widget
	UI.content = content
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 14)
		pad.Parent = content
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = content
	end

	local title = reg(Instance.new("TextLabel"), "label")
	title.Text = "Minimap Creator"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 18
	title.Parent = content

	local selectBtn = reg(Instance.new("TextButton"), "button")
	selectBtn.Text = "Select"
	selectBtn.Font = Enum.Font.SourceSansBold
	selectBtn.TextSize = 15
	selectBtn.Size = UDim2.new(1, 0, 0, 30)
	selectBtn.BorderSizePixel = 1
	selectBtn.LayoutOrder = 2
	selectBtn.Parent = content
	UI.selectBtn = selectBtn

	local dropdown = reg(Instance.new("ScrollingFrame"), "panel")
	dropdown.Size = UDim2.new(1, 0, 0, 100)
	dropdown.BorderSizePixel = 1
	dropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y
	dropdown.CanvasSize = UDim2.new()
	dropdown.ScrollBarThickness = 6
	dropdown.Visible = false
	dropdown.LayoutOrder = 3
	dropdown.Parent = content
	UI.dropdown = dropdown

	local dropdownPad = Instance.new("UIPadding")
	dropdownPad.PaddingTop, dropdownPad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	dropdownPad.PaddingLeft, dropdownPad.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
	dropdownPad.Parent = dropdown

	local dropdownList = Instance.new("UIListLayout")
	dropdownList.Padding = UDim.new(0, 2)
	dropdownList.SortOrder = Enum.SortOrder.LayoutOrder
	dropdownList.Parent = dropdown

	local infoLabel = reg(Instance.new("TextLabel"), "sub")
	infoLabel.Text = "No floor selected."
	infoLabel.BackgroundTransparency = 1
	infoLabel.Font = Enum.Font.SourceSans
	infoLabel.TextSize = 13
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextYAlignment = Enum.TextYAlignment.Top
	infoLabel.TextWrapped = true
	infoLabel.AutomaticSize = Enum.AutomaticSize.Y
	infoLabel.Size = UDim2.new(1, 0, 0, 0)
	infoLabel.LayoutOrder = 4
	infoLabel.Parent = content
	UI.infoLabel = infoLabel

	local createBtn = reg(Instance.new("TextButton"), "button")
	createBtn.Text = "Create"
	createBtn.Font = Enum.Font.SourceSansBold
	createBtn.TextSize = 15
	createBtn.Size = UDim2.new(1, 0, 0, 30)
	createBtn.BorderSizePixel = 1
	createBtn.LayoutOrder = 5
	createBtn.Parent = content
	UI.createBtn = createBtn

	local saveBtn = reg(Instance.new("TextButton"), "button")
	saveBtn.Text = "Save"
	saveBtn.Font = Enum.Font.SourceSansBold
	saveBtn.TextSize = 15
	saveBtn.Size = UDim2.new(1, 0, 0, 30)
	saveBtn.BorderSizePixel = 1
	saveBtn.LayoutOrder = 6
	saveBtn.Parent = content
	UI.saveBtn = saveBtn

	local styleRow = Instance.new("Frame")
	styleRow.BackgroundTransparency = 1
	styleRow.Size = UDim2.new(1, 0, 0, 28)
	styleRow.LayoutOrder = 7
	styleRow.Parent = content

	local styleLayout = Instance.new("UIListLayout")
	styleLayout.FillDirection = Enum.FillDirection.Horizontal
	styleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	styleLayout.Padding = UDim.new(0, 6)
	styleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	styleLayout.Parent = styleRow

	local defaultBtn = reg(Instance.new("TextButton"), "button")
	defaultBtn.Text = "Default"
	defaultBtn.Font = Enum.Font.SourceSansBold
	defaultBtn.TextSize = 15
	defaultBtn.Size = UDim2.new(0.5, -3, 1, 0)
	defaultBtn.BorderSizePixel = 1
	defaultBtn.LayoutOrder = 1
	defaultBtn.Parent = styleRow
	UI.defaultBtn = defaultBtn

	local outlineBtn = reg(Instance.new("TextButton"), "button")
	outlineBtn.Text = "Outline"
	outlineBtn.Font = Enum.Font.SourceSansBold
	outlineBtn.TextSize = 15
	outlineBtn.Size = UDim2.new(0.5, -3, 1, 0)
	outlineBtn.BorderSizePixel = 1
	outlineBtn.LayoutOrder = 2
	outlineBtn.Parent = styleRow
	UI.outlineBtn = outlineBtn

	local filterRow = Instance.new("Frame")
	filterRow.BackgroundTransparency = 1
	filterRow.Size = UDim2.new(1, 0, 0, 28)
	filterRow.LayoutOrder = 8
	filterRow.Parent = content

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	filterLayout.Padding = UDim.new(0, 6)
	filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filterLayout.Parent = filterRow

	local partsBtn = reg(Instance.new("TextButton"), "button")
	partsBtn.Text = "Parts Only"
	partsBtn.Font = Enum.Font.SourceSansBold
	partsBtn.TextScaled = true
	partsBtn.Size = UDim2.new(1 / 3, -4, 1, 0)
	partsBtn.BorderSizePixel = 1
	partsBtn.LayoutOrder = 1
	partsBtn.Parent = filterRow
	local partsLimit = Instance.new("UITextSizeConstraint")
	partsLimit.MaxTextSize, partsLimit.MinTextSize = 14, 8
	partsLimit.Parent = partsBtn
	UI.partsBtn = partsBtn

	local meshesBtn = reg(Instance.new("TextButton"), "button")
	meshesBtn.Text = "Parts + Meshes"
	meshesBtn.Font = Enum.Font.SourceSansBold
	meshesBtn.TextScaled = true
	meshesBtn.Size = UDim2.new(1 / 3, -4, 1, 0)
	meshesBtn.BorderSizePixel = 1
	meshesBtn.LayoutOrder = 2
	meshesBtn.Parent = filterRow
	local meshesLimit = Instance.new("UITextSizeConstraint")
	meshesLimit.MaxTextSize, meshesLimit.MinTextSize = 14, 8
	meshesLimit.Parent = meshesBtn
	UI.meshesBtn = meshesBtn

	local allBtn = reg(Instance.new("TextButton"), "button")
	allBtn.Text = "All"
	allBtn.Font = Enum.Font.SourceSansBold
	allBtn.TextScaled = true
	allBtn.Size = UDim2.new(1 / 3, -4, 1, 0)
	allBtn.BorderSizePixel = 1
	allBtn.LayoutOrder = 3
	allBtn.Parent = filterRow
	local allLimit = Instance.new("UITextSizeConstraint")
	allLimit.MaxTextSize, allLimit.MinTextSize = 14, 8
	allLimit.Parent = allBtn
	UI.allBtn = allBtn

	local thickenBtn = reg(Instance.new("TextButton"), "button")
	thickenBtn.Text = "Thicken thin walls to the average"
	thickenBtn.Font = Enum.Font.SourceSansBold
	thickenBtn.TextSize = 15
	thickenBtn.Size = UDim2.new(1, 0, 0, 30)
	thickenBtn.BorderSizePixel = 1
	thickenBtn.LayoutOrder = 9
	thickenBtn.Parent = content
	UI.thickenBtn = thickenBtn

	local statusLabel = reg(Instance.new("TextLabel"), "sub")
	statusLabel.Text = "Use Select to pick a floor."
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextWrapped = true
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.Size = UDim2.new(1, 0, 0, 0)
	statusLabel.LayoutOrder = 19
	statusLabel.Parent = content
	UI.statusLabel = statusLabel

	if UI.themeConnection then UI.themeConnection:Disconnect() end
	UI.themeConnection = settings().Studio.ThemeChanged:Connect(UI.applyTheme)
end

return UI

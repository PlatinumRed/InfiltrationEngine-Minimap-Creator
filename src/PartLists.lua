-- PartLists module
-- Finally a module that needs no explanation, I mean it's right there in the name
-- I'll say it anyway, this module handles the exceptions list and the blacklist
-- for the plugin.

local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Util = require(script.Parent.Util)

local MAX_ADD_AT_ONCE = 300

local PartLists = {}

local function getListFolder(createIfMissing, cfg)
	local folder = ReplicatedStorage:FindFirstChild(cfg.folderName)
	if not folder and createIfMissing then
		folder = Instance.new("Folder")
		folder.Name = cfg.folderName
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function allowed(part, roots)
	if not roots then return true end
	for _, folder in ipairs(roots) do
		if part:IsDescendantOf(folder) then return true end
	end
	return false
end

local function addSelectedParts(cfg, list)
	local candidates = {}
	for _, inst in ipairs(Selection:Get()) do
		if inst:IsA("BasePart") then
			table.insert(candidates, inst)
		elseif inst:IsA("Model") or inst:IsA("Folder") then
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(candidates, d) end
			end
		end
	end

	if #candidates == 0 then
		UI.setStatus("Select some parts first.", true)
		return
	end

	local roots = nil
	if cfg.allowedPaths then
		roots = {}
		for _, path in ipairs(cfg.allowedPaths) do
			local folder = Util.getFolder(path)
			if folder then table.insert(roots, folder) end
		end
	end

	local store = getListFolder(true, cfg)
	local existing = {}
	for _, obj in ipairs(store:GetChildren()) do
		if obj:IsA("ObjectValue") and obj.Value then
			existing[obj.Value] = true
		end
	end

	local added, rejected, outside, dupes = 0, 0, 0, 0
	local capped = false

	for _, part in ipairs(candidates) do
		if part:IsA("Terrain") or (cfg.rejectBalls and Util.isBall(part)) then
			rejected += 1
		elseif not allowed(part, roots) then
			outside += 1
		elseif existing[part] then
			dupes += 1
		elseif added >= MAX_ADD_AT_ONCE then
			capped = true
			break
		else
			local obj = Instance.new("ObjectValue")
			obj.Name = part.Name
			obj.Value = part
			obj:SetAttribute("Color", part.Color)
			obj:SetAttribute("Material", part.Material.Name)
			obj:SetAttribute("Size", part.Size)
			obj:SetAttribute("ApplyToMatchingParts", false)
			obj.Parent = store
			existing[part] = true
			added += 1
		end
	end

	list.refreshUI()

	local msg = ("Added %d part(s) to the %s."):format(added, cfg.noun)
	if dupes > 0 then msg ..= (" %d already in the list."):format(dupes) end
	if rejected > 0 then msg ..= cfg.rejectedNote:format(rejected) end
	if outside > 0 and cfg.outsideNote then msg ..= cfg.outsideNote:format(outside) end
	if capped then msg ..= (" Stopped at %d parts, use Match all for duplicates."):format(MAX_ADD_AT_ONCE) end
	UI.setStatus(msg, added == 0)

	if added > 0 and list.enabled then State.rebuildIfShowing() end
end

function PartLists.make(cfg)
	local list = {}

	local saved = State.plugin:GetSetting(cfg.setting)
	if saved == nil then
		list.enabled = cfg.defaultEnabled
	else
		list.enabled = (saved == true)
	end

	function list.read()
		local entries = {}
		local folder = getListFolder(false, cfg)
		if not folder then return entries end

		for _, obj in ipairs(folder:GetChildren()) do
			if obj:IsA("ObjectValue") then
				local color = obj:GetAttribute("Color")
				local material = obj:GetAttribute("Material")
				local size = obj:GetAttribute("Size")

				if typeof(color) == "Color3" and type(material) == "string" and typeof(size) == "Vector3" then
					table.insert(entries, {
						obj = obj,
						part = obj.Value,
						color = color,
						material = material,
						sortedSize = Util.sortedSize(size),
						matchAll = obj:GetAttribute("ApplyToMatchingParts") == true,
					})
				end
			end
		end
		return entries
	end

	local toggleBtn = UI.makeButton("", cfg.order)
	local addBtn = UI.makeButton(cfg.addLabel, cfg.order + 1)

	local listFrame = UI.reg(Instance.new("ScrollingFrame"), "panel")
	listFrame.LayoutOrder = cfg.order + 2
	listFrame.Size = UDim2.new(1, 0, 0, 90)
	listFrame.BorderSizePixel = 1
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.ScrollBarThickness = 6
	listFrame.Parent = UI.content

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop, listPad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	listPad.PaddingLeft, listPad.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
	listPad.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listFrame

	function list.refreshUI()
		toggleBtn.Text = cfg.title .. (list.enabled and ": ON" or ": OFF")

		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end

		local entries = list.read()
		if #entries == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Size = UDim2.new(1, -6, 0, 40)
			emptyLabel.Text = cfg.emptyText
			emptyLabel.TextWrapped = true
			emptyLabel.Font = Enum.Font.SourceSans
			emptyLabel.TextSize = 13
			emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
			emptyLabel.TextYAlignment = Enum.TextYAlignment.Top
			UI.Theme(emptyLabel, "sub")
			emptyLabel.Parent = listFrame
			return
		end

		for i, entry in ipairs(entries) do
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, -6, 0, 24)
			row.LayoutOrder = i
			row.Parent = listFrame

			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			rowLayout.Padding = UDim.new(0, 4)
			rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rowLayout.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.BackgroundTransparency = 1
			nameLabel.Size = UDim2.new(1, -(96 + 24 + 8), 1, 0)
			nameLabel.LayoutOrder = 1
			nameLabel.Text = entry.obj.Name .. (entry.part and "" or " (missing)")
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Font = Enum.Font.SourceSans
			nameLabel.TextSize = 14
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			UI.Theme(nameLabel, "label")
			nameLabel.Parent = row

			local matchBtn = Instance.new("TextButton")
			matchBtn.Size = UDim2.new(0, 96, 1, 0)
			matchBtn.LayoutOrder = 2
			matchBtn.Text = entry.matchAll and "Match all: ON" or "Match all: OFF"
			matchBtn.Font = Enum.Font.SourceSans
			matchBtn.TextSize = 13
			matchBtn.BorderSizePixel = 1
			UI.Theme(matchBtn, "button")
			matchBtn.Parent = row

			local delBtn = Instance.new("TextButton")
			delBtn.Size = UDim2.new(0, 24, 1, 0)
			delBtn.LayoutOrder = 3
			delBtn.Text = "X"
			delBtn.Font = Enum.Font.SourceSansBold
			delBtn.TextSize = 14
			delBtn.BorderSizePixel = 1
			UI.Theme(delBtn, "button")
			delBtn.Parent = row

			matchBtn.Activated:Connect(function()
				entry.obj:SetAttribute("ApplyToMatchingParts", not entry.matchAll)
				list.refreshUI()
				if list.enabled then State.rebuildIfShowing() end
			end)

			delBtn.Activated:Connect(function()
				entry.obj:Destroy()
				list.refreshUI()
				if list.enabled then State.rebuildIfShowing() end
			end)
		end
	end

	toggleBtn.Activated:Connect(function()
		list.enabled = not list.enabled
		State.plugin:SetSetting(cfg.setting, list.enabled)
		list.refreshUI()
		State.rebuildIfShowing()
	end)
	addBtn.Activated:Connect(function() addSelectedParts(cfg, list) end)

	list.refreshUI()
	return list
end

return PartLists
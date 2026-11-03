--[[
	Minimap Creator v1.11
	by: Red_Platinum
]]

local Selection = game:GetService("Selection")

local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Stage = require(script.Parent.Stage)
local PartLists = require(script.Parent.PartLists)
local MapData = require(script.Parent.MapData)
local Builder = require(script.Parent.Builder)

State.plugin = plugin

local savedFilter = plugin:GetSetting("PartFilter")
if savedFilter == "PartsOnly" or savedFilter == "PartsAndMeshes" or savedFilter == "All" then
	State.partFilter = savedFilter
else
	State.partFilter = "PartsOnly"
end

local savedStyle = plugin:GetSetting("MapStyle")
if savedStyle == "Default" or savedStyle == "Outline" then
	State.mapStyle = savedStyle
else
	State.mapStyle = "Default"
end

State.thickenWalls = (plugin:GetSetting("ThickenThinWalls") == true)

State.rebuildIfShowing = function()
	if State.stage and not State.busy then
		Builder.create()
	end
end

local toolbar = plugin:CreateToolbar("Minimap Creator")
local toolbarButton = toolbar:CreateButton("Minimap Creator", "Minimap Creator", "rbxassetid://88892478896646", "Minimap Creator")
toolbarButton.ClickableWhenViewportHidden = false

local currentWindow = nil
local windowCount = 0
local isOpening = false
local isClosing = false
local closeWindow

local function refreshSelectButton()
	if State.selectedFloorKey then
		UI.selectBtn.Text = "Select  (Floor " .. State.selectedFloorKey .. ")"
	else
		UI.selectBtn.Text = "Select"
	end
end

local function describeFloor(floorKey)
	local floor, err = MapData.resolveFloor(floorKey)
	if not floor then
		UI.infoLabel.Text = tostring(err)
		return nil
	end
	if floor.above then
		UI.infoLabel.Text = ("Floor %s: from '%s' (Y %.1f) up to '%s' (Y %.1f)."):format(
			floorKey, floor.part.Name, floor.lowY, floor.above.Name, floor.highY)
	else
		UI.infoLabel.Text = ("Floor %s: from '%s' (Y %.1f) up %d studs (no part above it)."):format(
			floorKey, floor.part.Name, floor.lowY, floor.highY - floor.lowY)
	end
	return floor
end

local function chooseFloor(floorKey)
	State.selectedFloorKey = floorKey
	UI.dropdown.Visible = false
	refreshSelectButton()

	local floor = describeFloor(floorKey)
	if not floor then return end
	Selection:Set(floor.above and { floor.part, floor.above } or { floor.part })

	if State.stage and not State.busy then
		Builder.create()
	else
		UI.setStatus("Floor " .. floorKey .. " selected. Press Create.")
	end
end

local function populateDropdown(floors)
	for _, child in ipairs(UI.dropdown:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	for index, floorEntry in ipairs(floors) do
		local floorButton = Instance.new("TextButton")
		floorButton.Text = "Floor " .. floorEntry.key
		floorButton.Font = Enum.Font.SourceSans
		floorButton.TextSize = 14
		floorButton.Size = UDim2.new(1, -6, 0, 24)
		floorButton.LayoutOrder = index
		floorButton.BorderSizePixel = 0
		UI.Theme(floorButton, "button")
		floorButton.Parent = UI.dropdown
		floorButton.Activated:Connect(function() chooseFloor(floorEntry.key) end)
	end
	UI.dropdown.Size = UDim2.new(1, 0, 0, math.min(#floors * 26 + 8, 170))
end

local function refreshStyleButtons()
	UI.defaultBtn.Text = (State.mapStyle == "Default") and "> Default <" or "Default"
	UI.outlineBtn.Text = (State.mapStyle == "Outline") and "> Outline <" or "Outline"
end

local function setMapStyle(name)
	State.mapStyle = name
	plugin:SetSetting("MapStyle", name)
	refreshStyleButtons()
	Stage.applyStyle()
end

local function refreshFilterButtons()
	UI.partsBtn.Text = (State.partFilter == "PartsOnly") and "● Parts Only" or "Parts Only"
	UI.meshesBtn.Text = (State.partFilter == "PartsAndMeshes") and "● Parts + Meshes" or "Parts + Meshes"
	UI.allBtn.Text = (State.partFilter == "All") and "● All" or "All"
end

local function setPartFilter(name)
	State.partFilter = name
	plugin:SetSetting("PartFilter", name)
	refreshFilterButtons()
	State.rebuildIfShowing()
end

local function refreshThickenButton()
	UI.thickenBtn.Text = "Thicken thin walls to the average: " .. (State.thickenWalls and "ON" or "OFF")
end

local function buildWindow()
	windowCount += 1

	-- This renames the window everytime so that it doesn't remember the size and location of the previous
	-- window. This allows us to have the plugin always open a new window with fixed size and location, and
	-- also allows us to have it as a floating window (cause I hate docking).
	local windowId = ("MissionMiniMapCreator_FloatingWindow_%d_%d"):format(os.time(), windowCount)

	UI.buildUI(plugin, windowId)
	Stage.buildPreview()
	local window = UI.widget

	UI.rotationBox = UI.numberRow("Rotation", 10, 15, function(step)
		Stage.applyRotation(State.rotation + step)
		UI.refreshNumbers()
	end, Stage.applyRotation)

	UI.minSizeBox = UI.numberRow("Min size", 11, 0.25, function(step)
		State.minSize = math.max(0, State.minSize + step)
		UI.refreshNumbers()
		State.rebuildIfShowing()
	end, function(typed)
		State.minSize = math.max(0, typed)
	end)

	UI.minSpanBox = UI.numberRow("Min span %", 12, 10, function(step)
		State.minSpanPercent = math.clamp(State.minSpanPercent + step, 0, 100)
		UI.refreshNumbers()
		State.rebuildIfShowing()
	end, function(typed)
		State.minSpanPercent = math.clamp(typed, 0, 100)
	end)

	UI.rotationBox.FocusLost:Connect(UI.refreshNumbers)
	UI.minSizeBox.FocusLost:Connect(function()
		UI.refreshNumbers()
		State.rebuildIfShowing()
	end)
	UI.minSpanBox.FocusLost:Connect(function()
		UI.refreshNumbers()
		State.rebuildIfShowing()
	end)

	State.exceptions = PartLists.make({
		title = "Exceptions", noun = "exception list", order = 13, defaultEnabled = false,
		folderName = "MissionMiniMapExceptions", setting = "ExceptionsEnabled", rejectBalls = true,
		allowedPaths = { State.geometryPath, State.glassPath },
		addLabel = "Add selected parts to exceptions",
		emptyText = "No exceptions yet. Select parts in Geometry or Glass and press the button above.",
		rejectedNote = " %d ball(s) skipped.",
		outsideNote = " %d part(s) skipped (not in Geometry or Glass).",
	})
	State.blacklist = PartLists.make({
		title = "Blacklist", noun = "blacklist", order = 16, defaultEnabled = true,
		folderName = "MissionMiniMapBlacklist", setting = "BlacklistEnabled", rejectBalls = false,
		addLabel = "Add selected parts to blacklist",
		emptyText = "Blacklist is empty. Select parts and press the button above.",
		rejectedNote = " %d item(s) skipped.",
	})

	UI.refreshNumbers()

	UI.selectBtn.Activated:Connect(function()
		if UI.dropdown.Visible then
			UI.dropdown.Visible = false
			return
		end
		local floors, err = MapData.scanFloors()
		if not floors then
			UI.setStatus(tostring(err), true)
			return
		end
		if #floors == 0 then
			UI.setStatus("No floors found in " .. table.concat(State.mapDataPath, "."), true)
			return
		end
		populateDropdown(floors)
		UI.dropdown.Visible = true
		UI.setStatus("Choose a floor from the list.")
	end)

	UI.defaultBtn.Activated:Connect(function() setMapStyle("Default") end)
	UI.outlineBtn.Activated:Connect(function() setMapStyle("Outline") end)

	UI.partsBtn.Activated:Connect(function() setPartFilter("PartsOnly") end)
	UI.meshesBtn.Activated:Connect(function() setPartFilter("PartsAndMeshes") end)
	UI.allBtn.Activated:Connect(function() setPartFilter("All") end)

	UI.thickenBtn.Activated:Connect(function()
		State.thickenWalls = not State.thickenWalls
		plugin:SetSetting("ThickenThinWalls", State.thickenWalls)
		refreshThickenButton()
		State.rebuildIfShowing()
	end)

	UI.createBtn.Activated:Connect(function() Builder.create() end)
	UI.saveBtn.Activated:Connect(Builder.save)

	window:GetPropertyChangedSignal("Enabled"):Connect(function()
		if window.Enabled then
			State.exceptions.refreshUI()
			State.blacklist.refreshUI()
		elseif currentWindow == window then
			closeWindow()
		end
	end)

	local resizeCount = 0
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		resizeCount += 1
		local thisResize = resizeCount

		task.delay(0.15, function()
			if thisResize == resizeCount and State.stage and not State.busy then
				Stage.updateCamera()
			end
		end)
	end)

	refreshStyleButtons()
	refreshFilterButtons()
	refreshThickenButton()
	refreshSelectButton()
	if State.selectedFloorKey then
		describeFloor(State.selectedFloorKey)
	end
	return window
end

local function openWindow()
	if currentWindow or isOpening or isClosing then return end

	isOpening = true
	currentWindow = buildWindow()
	isOpening = false
	currentWindow.Enabled = true
	toolbarButton:SetActive(true)

	-- We want the window active until manually closed for convenience so we end it here
end

function closeWindow()
	local windowToClose = currentWindow
	if not windowToClose then return end

	currentWindow = nil
	isClosing = true
	toolbarButton:SetActive(false)

	task.spawn(function()
		while State.busy do
			task.wait(0.1)
		end
		Stage.clear()
		windowToClose:Destroy()
		isClosing = false
	end)
end

toolbarButton.Click:Connect(function()
	if currentWindow then
		closeWindow()
	else
		openWindow()
	end
end)

plugin.Unloading:Connect(function()
	Stage.clear()
end)

toolbarButton:SetActive(false)
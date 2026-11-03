-- Builder module
-- Builds the minimap in some corner of the workspace so that it doesn't get in the way of regular studio stuff

local Selection = game:GetService("Selection")
local Lighting = game:GetService("Lighting")
local AssetService = game:GetService("AssetService")
local CaptureService = game:GetService("CaptureService")

local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Util = require(script.Parent.Util)
local MapData = require(script.Parent.MapData)
local Stage = require(script.Parent.Stage)

local Builder = {}

local TILE_SIZE = 2048
local TILE_COUNT = 2
local EXPORT_FOLDER = "MapExport"
local EXPORT_PART = "ExportThisPartAsObj"

local function createBackground(stage, minY)
	local center = State.stageCenter
	local tileCount, tileSize = TILE_COUNT, TILE_SIZE

	for i = 0, tileCount - 1 do
		for j = 0, tileCount - 1 do
			local tile = Instance.new("Part")
			tile.Name = "MinimapFloor"
			tile.Anchored = true
			tile.CanCollide = false
			tile.CastShadow = false
			tile.Material = Enum.Material.SmoothPlastic
			tile.Reflectance = 0
			tile.Size = Vector3.new(tileSize, 1, tileSize)
			tile.Position = Vector3.new(
				center.X + (i - (tileCount - 1) / 2) * tileSize,
				minY - 0.5,
				center.Z + (j - (tileCount - 1) / 2) * tileSize
			)
			tile:SetAttribute("MiniMapFloor", true)
			tile.Color = Stage.styleColor(tile)
			tile.Parent = stage
		end
	end
end

local function createCameraPart(stage)
	local cp = Instance.new("Part")
	cp.Name = "MinimapCamera"
	cp.Size = Vector3.one
	cp.Transparency = 1
	cp.Anchored = true
	cp.CanCollide, cp.CanQuery, cp.CanTouch, cp.CastShadow = false, false, false, false
	cp.Parent = stage
	return cp
end

local function isAboveDoor(part, doorBoxes)
	if #doorBoxes == 0 then return false end

	local pLow, pHigh = Util.partBounds(part)
	for _, doorBox in ipairs(doorBoxes) do
		local ox = math.min(pHigh.X, doorBox.high.X) - math.max(pLow.X, doorBox.low.X)
		local oz = math.min(pHigh.Z, doorBox.high.Z) - math.max(pLow.Z, doorBox.low.Z)
		if ox > 0.1 and oz > 0.1 and pLow.Y >= doorBox.high.Y - 1.5 then
			return true
		end
	end
	return false
end

-- Original here is used for when glass parts are copied over to the minimap from PartCollection(s)
local function consider(
	part, isGlass, original, seen, frame, selLow, selHigh, considered, blackEntries, excEntries,
	floorHeight, floorY, doorBoxes, stairParts, glassRegions, spanRange, toStage, newStage, copies
)
	local listPart = original or part
	if seen[part] then return considered end
	seen[part] = true

	if not part:IsA("BasePart") or part:IsA("Terrain") or Util.isBall(part) then return considered end

	local pLow, pHigh = Util.boundsInFrame(part, frame)
	local inside = pLow.X <= selHigh.X and pHigh.X >= selLow.X
		and pLow.Y <= selHigh.Y and pHigh.Y >= selLow.Y
		and pLow.Z <= selHigh.Z and pHigh.Z >= selLow.Z
	if not inside then return considered end
	considered += 1

	if #blackEntries > 0 and Util.matchesList(listPart, blackEntries) then return considered end

	local isException = #excEntries > 0 and Util.matchesList(listPart, excEntries)

	if floorHeight and not isException and pHigh.Y <= floorY + 0.25 then return considered end
	if not isException and isAboveDoor(part, doorBoxes) then return considered end

	if not (isGlass or isException) then
		if stairParts[part] then return considered end
		if not Util.isVisible(part) then return considered end

		local bsize = pHigh - pLow
		local flatSlab = bsize.Y < bsize.X and bsize.Y < bsize.Z

		local beside = not flatSlab and #glassRegions > 0 and Util.isBesideGlass(part, glassRegions)
		if not beside then
			local size = part.Size
			local span = (math.min(pHigh.Y, selHigh.Y) - math.max(pLow.Y, floorY)) / spanRange * 100

			if flatSlab
				or not Util.passesFilter(part)
				or not Util.isUpright(part)
				or math.min(size.X, size.Y, size.Z) < State.minSize
				or span < State.minSpanPercent then
				return considered
			end
		end
	end

	local copy = part:Clone()
	if not copy then return considered end

	Stage.styleWall(copy)
	copy.Color = Stage.styleColor(copy)
	copy.CFrame = toStage * copy.CFrame
	copy.Parent = newStage
	table.insert(copies, copy)

	if isGlass then
		local region = Util.glassRegion(part)
		if region then table.insert(glassRegions, region) end
	end

	return considered
end

function Builder.create()
	if State.busy then return end

	if not State.selectedFloorKey then
		UI.setStatus("Select a floor first.", true)
		return
	end

	local geometry = Util.getFolder(State.geometryPath)
	if not geometry then
		UI.setStatus("Workspace not found: " .. table.concat(State.geometryPath, "."), true)
		return
	end

	local floor, err = MapData.resolveFloor(State.selectedFloorKey)
	if not floor then
		UI.setStatus(tostring(err), true)
		return
	end

	local frame, areaSize = floor.frame, floor.size
	local selLow = Vector3.new(-areaSize.X / 2, floor.lowY - frame.Position.Y, -areaSize.Y / 2)
	local selHigh = Vector3.new(areaSize.X / 2, floor.highY - frame.Position.Y, areaSize.Y / 2)
	local toStage = CFrame.new(State.stageCenter) * frame:Inverse()

	Stage.clear()

	local newStage = Instance.new("Folder")
	newStage.Name = State.stageFolderName
	newStage.Archivable = false

	local excEntries = State.exceptions.enabled and State.exceptions.read() or {}
	local blackEntries = State.blacklist.enabled and State.blacklist.read() or {}
	local glassFolder = Util.getFolder(State.glassPath)
	local propsFolder = Util.getFolder(State.propsPath)

	-- Assume that the floor is a little above the MapData part. This is because official missions actually
	-- do it this way, and the parts of the floor underneath it sometimes get selected because of this

	-- This should work with any mission as long as the MapData part is not ABOVE the floor for some reason
	local floorHeight = MapData.findFloorHeight(geometry, frame, selLow, selHigh, areaSize, blackEntries)
	local floorY = (floorHeight or floor.lowY) - frame.Position.Y
	local spanRange = math.max(selHigh.Y - floorY, 1e-3)

	local doorBoxes = {}
	local windowPlacements = {}
	if propsFolder then
		local doorList
		doorList, windowPlacements = MapData.placements(propsFolder)

		for _, pl in ipairs(doorList) do
			local dSize = pl.part.Size
			local dLow, dHigh = Util.boundsOfCFrame(pl.cf, dSize, frame)
			local midY = (dLow.Y + dHigh.Y) / 2

			local onThisFloor = midY >= selLow.Y and midY <= selHigh.Y
				and dLow.X <= selHigh.X and dHigh.X >= selLow.X
				and dLow.Z <= selHigh.Z and dHigh.Z >= selLow.Z

			if onThisFloor then
				local wLow, wHigh = Util.boundsOfCFrame(pl.cf, dSize)
				table.insert(doorBoxes, { low = wLow, high = wHigh })
			end
		end
	end

	local stairParts = MapData.findStairs(geometry, frame, selLow, selHigh, blackEntries)

	local considered = 0
	local copies = {}
	local seen = {}
	local glassRegions = {}

	if glassFolder then
		for _, d in ipairs(glassFolder:GetDescendants()) do
			considered = consider(
				d, true, nil, seen, frame, selLow, selHigh, considered, blackEntries, excEntries,
				floorHeight, floorY, doorBoxes, stairParts, glassRegions, spanRange, toStage, newStage, copies
			)
		end
	end

	for _, pl in ipairs(windowPlacements) do
		if pl.moved then
			local moved = pl.part:Clone()
			if moved then
				moved.CFrame = pl.cf
				considered = consider(
					moved, true, pl.part, seen, frame, selLow, selHigh, considered, blackEntries, excEntries,
					floorHeight, floorY, doorBoxes, stairParts, glassRegions, spanRange, toStage, newStage, copies
				)
			end
		else
			considered = consider(
				pl.part, true, nil, seen, frame, selLow, selHigh, considered, blackEntries, excEntries,
				floorHeight, floorY, doorBoxes, stairParts, glassRegions, spanRange, toStage, newStage, copies
			)
		end
	end

	for _, d in ipairs(geometry:GetDescendants()) do
		if not Util.hasCondition(d, geometry) then
			considered = consider(
				d, false, nil, seen, frame, selLow, selHigh, considered, blackEntries, excEntries,
				floorHeight, floorY, doorBoxes, stairParts, glassRegions, spanRange, toStage, newStage, copies
			)
		end
	end

	if #copies == 0 then
		newStage:Destroy()
		UI.setStatus("No parts passed the filters.", true)
		return
	end

	local minY = math.huge
	for _, copy in ipairs(copies) do
		local copyLow = Util.partBounds(copy)
		minY = math.min(minY, copyLow.Y)
	end

	local planeY = minY + 1
	local flatParts = {}
	for _, copy in ipairs(copies) do
		if Stage.flattenPart(copy, planeY) then
			table.insert(flatParts, copy)
		end
	end

	if State.thickenWalls then
		Util.thicken(flatParts)
	end

	for _, copy in ipairs(copies) do
		table.insert(State.copiedParts, { part = copy, baseCFrame = copy.CFrame })
		State.copiedPartSet[copy] = true
	end

	createBackground(newStage, minY)
	local cp = createCameraPart(newStage)

	local center = State.stageCenter
	State.stageOrigin = Vector3.new(center.X, minY, center.Z)
	State.stage, State.cameraPart = newStage, cp
	newStage.Parent = workspace

	State.mapArea = areaSize
	Stage.rotateCopies(-State.rotation)
	Stage.updateCamera()
	Stage.rebuildPreview()

	UI.setStatus(("Minimap created out of %d parts. %d parts filtered."):format(#copies, considered - #copies))
end

local PIXELS_PER_PAUSE = 1000000

local FLAT_LIGHTING = {
	GlobalShadows = false,
	Brightness = 0,
	Ambient = Color3.new(1, 1, 1),
	OutdoorAmbient = Color3.new(1, 1, 1),
	ColorShift_Top = Color3.new(0, 0, 0),
	ColorShift_Bottom = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = 1,
	FogEnd = 1e6,
	FogStart = 1e6 - 1,
}

local function applyFlatLighting()
	local saved = { props = {}, effects = {} }

	for name, flatValue in pairs(FLAT_LIGHTING) do
		saved.props[name] = Lighting[name]
		Lighting[name] = flatValue
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") then
			saved.effects[child] = { property = "Enabled", value = child.Enabled }
			child.Enabled = false
		elseif child:IsA("Atmosphere") then
			saved.effects[child] = { property = "Density", value = child.Density }
			child.Density = 0
		end
	end
	return saved
end

local function restoreLighting(saved)
	for name, value in pairs(saved.props) do
		Lighting[name] = value
	end
	for effect, old in pairs(saved.effects) do
		effect[old.property] = old.value
	end
end

local function takeScreenshot()
	local id = nil
	CaptureService:CaptureScreenshot(function(contentId) id = contentId end)

	local startTime = os.clock()
	while not id and os.clock() - startTime < 8 do
		task.wait(0.05)
	end
	return id
end

local function createExportPart(cropped, mapW, mapH, transparent)
	local oldFolder = workspace:FindFirstChild(EXPORT_FOLDER)
	if oldFolder then oldFolder:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = EXPORT_FOLDER

	local part = Instance.new("Part")
	part.Name = EXPORT_PART
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic

	local scale = 10 / math.max(mapW, mapH)
	part.Size = Vector3.new(mapW * scale, mapH * scale, 0.2)

	part.Color = transparent and Color3.fromRGB(60, 60, 60) or Color3.new(1, 1, 1)

	part:SetAttribute("FloorId", State.selectedFloorKey)
	part:SetAttribute("MapWidthStuds", mapW)
	part:SetAttribute("MapHeightStuds", mapH)
	part:SetAttribute("MinSize", State.minSize)
	part:SetAttribute("MinSpanPercent", State.minSpanPercent)
	part:SetAttribute("Rotation", State.rotation)
	part:SetAttribute("MapStyle", State.mapStyle)
	part:SetAttribute("ThickenThinWalls", State.thickenWalls)

	local cam = workspace.CurrentCamera
	local camPos = cam.CFrame.Position
	part.CFrame = CFrame.lookAt(camPos + cam.CFrame.LookVector * 20, camPos)

	local decal = Instance.new("Decal")
	decal.Name = "MapImage"
	decal.Face = Enum.NormalId.Front
	decal.TextureContent = cropped
	decal.Parent = part

	part.Parent = folder
	folder.Parent = workspace
	return part
end

local function makeBlackTransparent(image)
	local size = image.Size
	local total = size.X * size.Y
	local pixels = image:ReadPixelsBuffer(Vector2.zero, size)

	local darkest, lightest = 255, 0
	for i = 0, total - 1 do
		local value = buffer.readu8(pixels, i * 4)
		if value < darkest then darkest = value end
		if value > lightest then lightest = value end
		if i % PIXELS_PER_PAUSE == 0 and i > 0 then task.wait() end
	end

	local range = lightest - darkest
	for i = 0, total - 1 do
		local opacity
		if range >= 32 then
			opacity = math.floor((buffer.readu8(pixels, i * 4) - darkest) / range * 255 + 0.5)
		else
			opacity = (lightest >= 128) and 255 or 0
		end

		buffer.writeu32(pixels, i * 4, 0x00FFFFFF + opacity * 0x1000000)
		if i % PIXELS_PER_PAUSE == 0 and i > 0 then task.wait() end
	end

	image:WritePixelsBuffer(Vector2.zero, size, pixels)
end

local function cropScreenshot(shotId, fracW, fracH, makeTransparent)
	local shot = AssetService:CreateEditableImageAsync(Content.fromUri(shotId))
	local w, h = shot.Size.X, shot.Size.Y

	local cropW = math.clamp(math.floor(w * math.min(fracW, 1) + 0.5), 1, w)
	local cropH = math.clamp(math.floor(h * math.min(fracH, 1) + 0.5), 1, h)
	local offsetX = math.floor((w - cropW) / 2)
	local offsetY = math.floor((h - cropH) / 2)

	local cropped = AssetService:CreateEditableImage({ Size = Vector2.new(cropW, cropH) })
	cropped:DrawImage(Vector2.new(-offsetX, -offsetY), shot, Enum.ImageCombineType.Overwrite)

	if makeTransparent then makeBlackTransparent(cropped) end
	return Content.fromObject(cropped)
end

function Builder.save()
	if State.busy then return end

	if not State.selectedFloorKey then
		UI.setStatus("Select a floor first.", true)
		return
	end

	Builder.create()
	if not (State.stage and State.cameraPart) then return end

	State.busy = true
	UI.setStatus("Capturing...")

	local cam = workspace.CurrentCamera
	local savedCam = { cf = cam.CFrame, focus = cam.Focus, fov = cam.FieldOfView, mode = cam.FieldOfViewMode }
	local oldSelection = Selection:Get()
	local savedLighting = applyFlatLighting()

	local viewport = cam.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local dist, fov, mapW, mapH = Stage.fitView(aspect)
	local visibleH = 2 * dist * math.tan(math.rad(fov / 2))
	local fracW = mapW / (visibleH * aspect)
	local fracH = mapH / visibleH

	local shotId = nil
	local ok, err = pcall(function()
		Selection:Set({})
		cam.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		cam.FieldOfView = fov
		cam.CFrame = Stage.cameraCFrame(dist)
		cam.Focus = CFrame.new(State.stageOrigin)
		task.wait(0.8)

		-- Studio trolls us and spins the camera for some reason when we take a screenshot
		-- so we turn the minimap itself back by the same amount to line it up
		local right = cam.CFrame.RightVector
		local turn = math.deg(math.atan2(-right.Z, right.X))
		if math.abs(turn) > 0.5 then
			Stage.rotateCopies(-State.rotation + turn)
			task.wait(0.5)
		end

		shotId = takeScreenshot()
	end)

	restoreLighting(savedLighting)
	cam.CFrame = savedCam.cf
	cam.Focus = savedCam.focus
	cam.FieldOfView = savedCam.fov
	cam.FieldOfViewMode = savedCam.mode
	State.busy = false

	if not shotId then
		Selection:Set(oldSelection)
		UI.setStatus("Screenshot failed: " .. (ok and "timed out" or tostring(err)), true)
		return
	end
	Stage.clear()

	local transparent = State.mapStyle == "Default"
	local cropped = cropScreenshot(shotId, fracW, fracH, transparent)
	local exportPart = createExportPart(cropped, mapW, mapH, transparent)

	Selection:Set({ exportPart })
	UI.setStatus("Minimap screenshot saved under " .. EXPORT_PART .. " part (currently selected). "
		.. "Right click the part and export as obj to save the screenshot to your device next to the .obj file "
		.. "(Try it again if it raises an error, it should work within like 3 attempts).")
end

return Builder
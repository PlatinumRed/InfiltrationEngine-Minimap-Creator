-- Stage module
-- This is what I call the copy of the minimap that we see in the preview
-- It is also what we take a screenshot of for the final minimap image

local State = require(script.Parent.State)
local Util = require(script.Parent.Util)
local UI = require(script.Parent.UI)

local Stage = {}

local FLAT_THICKNESS = 0.5
local FOV = 5
local MAX_CAMERA_DISTANCE = 8000
local PREVIEW_SIZE = 270
local MAX_PREVIEW_SIZE = 900
local MIN_LINE_PX = 1.5

function Stage.clear()
	if State.stage then State.stage:Destroy() end

	local leftover = workspace:FindFirstChild(State.stageFolderName)
	if leftover then leftover:Destroy() end

	State.stage, State.cameraPart = nil, nil
	State.copiedParts, State.copiedPartSet = {}, {}
	State.previewCopies, State.previewSizes = {}, {}
	Stage.world:ClearAllChildren()
	Stage.setPreviewVisible(false)
end

function Stage.styleColor(part)
	local isBg = part:GetAttribute("MiniMapFloor")
	if State.mapStyle == "Default" then
		return isBg and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
	end
	return isBg and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
end

function Stage.styleWall(copy)
	for _, child in ipairs(copy:GetChildren()) do
		if not child:IsA("SpecialMesh") then child:Destroy() end
	end

	copy.Anchored = true
	copy.CanCollide = false
	copy.CastShadow = false
	copy.Transparency = 0
	copy.Reflectance = 0
	copy.Material = Enum.Material.SmoothPlastic
	if copy:IsA("UnionOperation") then copy.UsePartColor = true end
	if copy:IsA("MeshPart") then copy.TextureID = "" end
end

-- Flatten the part alongside whichever side is pointing up or down (and ignore tilted parts)
function Stage.flattenPart(part, planeY)
	if not Util.isUpright(part) then return false end

	local side = Util.verticalSide(part)
	local size = part.Size
	part.Size = Vector3.new(
		side == 1 and FLAT_THICKNESS or size.X,
		side == 2 and FLAT_THICKNESS or size.Y,
		side == 3 and FLAT_THICKNESS or size.Z
	)

	local pos = part.Position
	part.CFrame = part.CFrame.Rotation + Vector3.new(pos.X, planeY, pos.Z)
	return true
end

function Stage.rotateCopies(degrees)
	local center = State.stageCenter
	local rotation = CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(-center.X, 0, -center.Z)

	for _, entry in ipairs(State.copiedParts) do
		local rotated = rotation * entry.baseCFrame
		entry.part.CFrame = rotated

		local twin = State.previewCopies[entry.part]
		if twin then twin.CFrame = rotated + State.previewOffset end
	end
end

function Stage.applyRotation(degrees)
	State.rotation = degrees % 360
	Stage.rotateCopies(-State.rotation)
	Stage.updateCamera()
end

function Stage.applyStyle()
	if not State.stage then return end

	for _, child in ipairs(State.stage:GetChildren()) do
		if child:IsA("BasePart") and child ~= State.cameraPart then
			child.Color = Stage.styleColor(child)
		end
	end
	Stage.rebuildPreview()
end

function Stage.buildPreview()
	local container = UI.reg(Instance.new("Frame"), "bg")
	container.LayoutOrder = 20
	container.Size = UDim2.new(1, 0, 0, PREVIEW_SIZE + 6)
	container.BorderSizePixel = 0
	container.Parent = UI.content
	Stage.container = container

	local hint = UI.reg(Instance.new("TextLabel"), "sub")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, 0, 0, 40)
	hint.Text = "Preview shows up after Create."
	hint.TextWrapped = true
	hint.Font = Enum.Font.SourceSans
	hint.TextSize = 14
	hint.Parent = container
	Stage.hint = hint

	local vpf = Instance.new("ViewportFrame")
	vpf.AnchorPoint = Vector2.new(0.5, 0)
	vpf.Position = UDim2.new(0.5, 0, 0, 3)
	vpf.Size = UDim2.fromOffset(PREVIEW_SIZE, PREVIEW_SIZE)
	vpf.BackgroundColor3 = Color3.new(0, 0, 0)
	vpf.BorderSizePixel = 0
	vpf.Ambient = Color3.new(1, 1, 1)
	vpf.LightColor = Color3.new(0, 0, 0)
	vpf.Visible = false
	vpf.Parent = container
	Stage.vpf = vpf

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	Stage.cam = cam

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = vpf
	Stage.world = world
end

function Stage.setPreviewVisible(visible)
	Stage.vpf.Visible = visible
	Stage.hint.Visible = not visible
end

function Stage.rotatedBounds()
	local rad = math.rad(State.rotation)
	local cos, sin = math.abs(math.cos(rad)), math.abs(math.sin(rad))
	local w = State.mapArea.X * cos + State.mapArea.Y * sin
	local h = State.mapArea.X * sin + State.mapArea.Y * cos
	return w, h
end

-- Math for the camera distance needed to fit the map area (boring stuff)
function Stage.fitView(aspect)
	local bw, bh = Stage.rotatedBounds()
	local fov = FOV
	local tan = math.tan(math.rad(fov / 2))

	local dist = math.max(bh / (2 * tan), bw / (aspect * 2 * tan))
	if dist > MAX_CAMERA_DISTANCE then
		dist = MAX_CAMERA_DISTANCE
		fov = math.deg(2 * math.atan(math.max(bh / 2, bw / (aspect * 2)) / dist))
	end
	return dist, fov, bw, bh
end

function Stage.cameraCFrame(dist)
	local origin = State.stageOrigin
	local pos = Vector3.new(origin.X, origin.Y + dist, origin.Z)
	return CFrame.lookAt(pos, origin, Vector3.new(0, 0, -1))
end

local function getPreviewSize()
	return math.clamp(UI.widget.AbsoluteSize.X - 30, 200, MAX_PREVIEW_SIZE)
end

function Stage.layoutPreview()
	local bw, bh = Stage.rotatedBounds()
	local box = getPreviewSize()
	local ratio = bw / bh

	local w, h = box, box
	if ratio >= 1 then
		h = box / ratio
	else
		w = box * ratio
	end

	Stage.vpf.Size = UDim2.fromOffset(w, h)
	Stage.container.Size = UDim2.new(1, 0, 0, box + 6)
	State.previewPxPerStud = h / bh
	return w / h
end

-- Some parts are too thin to be visible in the preview so we thicken it a bit
function Stage.thickenPreview()
	local minW = MIN_LINE_PX / math.max(State.previewPxPerStud, 1e-6)

	for twin, info in pairs(State.previewSizes) do
		local sizes = { info.size.X, info.size.Y, info.size.Z }
		for _, side in ipairs(info.flatSides) do
			if sizes[side] < minW then sizes[side] = minW end
		end

		local want = Vector3.new(sizes[1], sizes[2], sizes[3])
		if (twin.Size - want).Magnitude > 1e-4 then
			twin.Size = want
		end
	end
end

function Stage.updateCamera()
	if not (State.stage and State.cameraPart) then return end

	local aspect = Stage.layoutPreview()
	local dist, fov = Stage.fitView(aspect)
	State.previewDist = dist

	Stage.cam.FieldOfView = fov
	State.cameraPart.CFrame = Stage.cameraCFrame(dist)
	Stage.cam.CFrame = State.cameraPart.CFrame + State.previewOffset
	Stage.thickenPreview()
end

function Stage.rebuildPreview()
	Stage.world:ClearAllChildren()
	State.previewCopies, State.previewSizes = {}, {}
	if not (State.stage and State.cameraPart) then return end

	local drop = Vector3.new(0, -math.clamp(State.previewDist * 0.01, 5, 80), 0)

	for _, child in ipairs(State.stage:GetChildren()) do
		local twin = child:Clone()
		if twin then
			if twin:IsA("BasePart") then
				twin.CFrame = twin.CFrame + State.previewOffset
				if twin:GetAttribute("MiniMapFloor") then
					twin.CFrame = twin.CFrame + drop
				end
			end

			if State.copiedPartSet[child] then
				State.previewCopies[child] = twin
				State.previewSizes[twin] = { size = twin.Size, flatSides = Util.horizontalAxes(twin) }
			end
			twin.Parent = Stage.world
		end
	end

	Stage.cam.CFrame = State.cameraPart.CFrame + State.previewOffset
	Stage.thickenPreview()
	Stage.setPreviewVisible(true)
end

return Stage

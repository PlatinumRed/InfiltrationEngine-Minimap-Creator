-- Util(ity) module
-- Helper functions for various modules such as MapData and PartLists.

local State = require(script.Parent.State)

local Util = {}

function Util.isBall(part)
	return part:IsA("Part") and part.Shape == Enum.PartType.Ball
end

function Util.isVisible(part)
	return part.Transparency < 0.95
end

function Util.sortedSize(size)
	local sizes = { size.X, size.Y, size.Z }
	table.sort(sizes)
	return sizes
end

function Util.colorsClose(c1, c2)
	return math.abs(c1.R - c2.R) < 0.004 and math.abs(c1.G - c2.G) < 0.004 and math.abs(c1.B - c2.B) < 0.004
end

function Util.matchesList(part, entries)
	local size = nil
	for _, entry in ipairs(entries) do
		if entry.part == part then return true end

		if entry.matchAll and part.Material.Name == entry.material and Util.colorsClose(part.Color, entry.color) then
			size = size or Util.sortedSize(part.Size)
			if math.abs(size[1] - entry.sortedSize[1]) < 0.01
				and math.abs(size[2] - entry.sortedSize[2]) < 0.01
				and math.abs(size[3] - entry.sortedSize[3]) < 0.01 then
				return true
			end
		end
	end
	return false
end

function Util.boundsOfCFrame(cf, size, frame)
	if frame then cf = frame:ToObjectSpace(cf) end
	local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
	local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
	local ext = Vector3.new(
		math.abs(right.X) * halfX + math.abs(up.X) * halfY + math.abs(look.X) * halfZ,
		math.abs(right.Y) * halfX + math.abs(up.Y) * halfY + math.abs(look.Y) * halfZ,
		math.abs(right.Z) * halfX + math.abs(up.Z) * halfY + math.abs(look.Z) * halfZ
	)
	return cf.Position - ext, cf.Position + ext
end

function Util.partBounds(part)
	return Util.boundsOfCFrame(part.CFrame, part.Size)
end

function Util.boundsInFrame(part, frame)
	return Util.boundsOfCFrame(part.CFrame, part.Size, frame)
end

function Util.hasCondition(inst, rootFolder)
	while inst and inst ~= rootFolder do
		if inst:GetAttribute("Condition") ~= nil then return true end
		inst = inst.Parent
	end
	return false
end

function Util.getFolder(path)
	local folder = workspace
	for _, name in ipairs(path) do
		folder = folder and folder:FindFirstChild(name)
	end
	return folder
end

function Util.verticalSide(part)
	local cf = part.CFrame
	local tilt = { math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y) }
	local side = 1
	if tilt[2] > tilt[side] then side = 2 end
	if tilt[3] > tilt[side] then side = 3 end
	return side, tilt[side]
end

function Util.isUpright(part)
	local _, alignment = Util.verticalSide(part)
	return alignment >= math.cos(math.rad(2))
end

function Util.horizontalAxes(part)
	local vertical = Util.verticalSide(part)
	local flat = {}
	for side = 1, 3 do
		if side ~= vertical then table.insert(flat, side) end
	end
	return flat
end

function Util.passesFilter(part)
	if Util.isBall(part) then return false end
	local filter = State.partFilter
	if filter == "All" then return true end
	if part:IsA("MeshPart") then return filter == "PartsAndMeshes" end
	if part:IsA("PartOperation") then return false end
	return part:IsA("Part") or part:IsA("WedgePart") or part:IsA("CornerWedgePart")
end

local function sideDirection(part, side)
	local cf = part.CFrame
	if side == 1 then return cf.RightVector end
	if side == 2 then return cf.UpVector end
	return cf.LookVector
end

local function sideLength(part, side)
	local size = part.Size
	if side == 1 then return size.X end
	if side == 2 then return size.Y end
	return size.Z
end

local function sideways(direction)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-4 then return nil end
	return flat.Unit
end

function Util.describeFlatSides(part, anyTilt)
	if not anyTilt and not Util.isUpright(part) then return nil end

	local flat = Util.horizontalAxes(part)
	local thinSide, longSide = flat[1], flat[2]
	if sideLength(part, thinSide) > sideLength(part, longSide) then
		thinSide, longSide = longSide, thinSide
	end

	local thinDir = sideways(sideDirection(part, thinSide))
	local longDir = sideways(sideDirection(part, longSide))
	if not (thinDir and longDir) then return nil end

	local pos = part.Position
	return {
		thinSide = thinSide,
		thin = sideLength(part, thinSide),
		thinDir = thinDir,
		long = sideLength(part, longSide),
		longDir = longDir,
		position = Vector3.new(pos.X, 0, pos.Z),
	}
end

function Util.glassRegion(glass)
	local region = Util.describeFlatSides(glass, true)
	if not region then return nil end

	local low, high = Util.partBounds(glass)
	region.frame = CFrame.fromMatrix(region.position, region.longDir, Vector3.yAxis)
	region.lowY = low.Y
	region.highY = high.Y
	return region
end

function Util.isBesideGlass(part, glassRegions)
	for _, region in ipairs(glassRegions) do
		local low, high = Util.boundsInFrame(part, region.frame)
		local gapAlong = math.max(low.X - region.long / 2, -region.long / 2 - high.X, 0)
		local gapAcross = math.max(low.Z - region.thin / 2, -region.thin / 2 - high.Z, 0)
		local sharedHeight = math.min(high.Y, region.highY) - math.max(low.Y, region.lowY)

		if gapAlong <= 0.5 and gapAcross <= 0.5 and sharedHeight > -0.5 then
			return true
		end
	end
	return false
end

-- Gotta exclude pillars and very thick walls so that they don't count as normal walls
local function wallInfo(part)
	if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then return nil end
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") or part:IsA("TrussPart") then return nil end

	local info = Util.describeFlatSides(part)
	if not info then return nil end
	if info.long < info.thin * 2.5 then return nil end
	if info.thin > 4 then return nil end
	return info
end

-- Thicken only the walls that are thinner than the average
function Util.thicken(parts)
	local walls = {}
	local total = 0

	for _, part in ipairs(parts) do
		local info = wallInfo(part)
		if info then
			table.insert(walls, { part = part, info = info })
			total += info.thin
		end
	end
	if #walls == 0 then return end

	local mean = total / #walls
	for _, wall in ipairs(walls) do
		if wall.info.thin < mean - 0.01 then
			local size = wall.part.Size
			local side = wall.info.thinSide
			wall.part.Size = Vector3.new(
				side == 1 and mean or size.X,
				side == 2 and mean or size.Y,
				side == 3 and mean or size.Z
			)
		end
	end
end

return Util

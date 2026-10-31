-- MapData module
-- Wait let me guess! This has to do with the MapData folder from DebugMission!
-- Lol no, this module has multiple filters that are used to sort parts for the
-- minimap. Also uses helper functions from the util module for the filters.

local State = require(script.Parent.State)
local Util = require(script.Parent.Util)

local MapData = {}

local FLOOR_PIECE_MIN_SIDE = 40
local FLOOR_SEARCH_BELOW = 1
local FLOOR_SEARCH_ABOVE = 10
local FLOOR_LEVEL_TOLERANCE = 0.25
local FLOOR_MIN_COVERAGE = 0.1

local STAIR_NAMES = { "stair", "step" }
local STAIR_MIN_STEPS = 3
local STAIR_RISE_MIN, STAIR_RISE_MAX = 0.2, 2.5
local STAIR_RUN_MIN, STAIR_RUN_MAX = 0.2, 6
local STAIR_TOLERANCE = 0.15

function MapData.scanFloors()
	local mapDataFolder = Util.getFolder(State.mapDataPath)
	if not mapDataFolder then
		return nil, "Workspace not found: " .. table.concat(State.mapDataPath, ".")
	end

	local floors = {}
	local seen = {}
	for _, obj in ipairs(mapDataFolder:GetDescendants()) do
		if obj:IsA("BasePart") then
			local floorId = obj:GetAttribute("Id")
			if floorId ~= nil then
				local floorKey = tostring(floorId)
				if not seen[floorKey] then
					seen[floorKey] = true
					table.insert(floors, { key = floorKey, part = obj })
				end
			end
		end
	end

	table.sort(floors, function(firstFloor, secondFloor)
		local firstNumber, secondNumber = tonumber(firstFloor.key), tonumber(secondFloor.key)
		if (firstNumber ~= nil) ~= (secondNumber ~= nil) then return firstNumber ~= nil end
		if firstNumber and secondNumber and firstNumber ~= secondNumber then return firstNumber < secondNumber end
		return firstFloor.key < secondFloor.key
	end)

	return floors, mapDataFolder
end

function MapData.findPartAbove(mapDataFolder, floorPart)
	local floorLow, floorHigh = Util.partBounds(floorPart)
	local closestPart, closestY = nil, nil

	for _, obj in ipairs(mapDataFolder:GetDescendants()) do
		if obj:IsA("BasePart") and obj ~= floorPart then
			local low, high = Util.partBounds(obj)
			local ox = math.min(floorHigh.X, high.X) - math.max(floorLow.X, low.X)
			local oz = math.min(floorHigh.Z, high.Z) - math.max(floorLow.Z, low.Z)
			local height = obj.Position.Y
			if ox > 0 and oz > 0 and height > floorHigh.Y and (closestY == nil or height < closestY) then
				closestPart, closestY = obj, height
			end
		end
	end
	return closestPart
end

function MapData.computeRegion(floorPart, partAbove)
	local floorLow = Util.partBounds(floorPart)
	local lowY = floorLow.Y
	local highY
	if partAbove then
		local aboveLow = Util.partBounds(partAbove)
		highY = aboveLow.Y
	else
		highY = lowY + 15
	end
	highY = math.max(highY, lowY + 1)

	local look = floorPart.CFrame.LookVector
	local turnAngle = math.atan2(-look.X, -look.Z)
	local position = floorPart.Position
	local frame = CFrame.new(position.X, (lowY + highY) / 2, position.Z) * CFrame.Angles(0, turnAngle, 0)

	local areaLow, areaHigh = Util.boundsInFrame(floorPart, frame)
	local areaSize = Vector2.new(areaHigh.X - areaLow.X, areaHigh.Z - areaLow.Z)
	return frame, areaSize, lowY, highY
end

function MapData.resolveFloor(floorKey)
	local floors, mapDataFolder = MapData.scanFloors()
	if not floors then return nil, mapDataFolder end

	for _, floor in ipairs(floors) do
		if floor.key == floorKey then
			local partAbove = MapData.findPartAbove(mapDataFolder, floor.part)
			local frame, areaSize, lowY, highY = MapData.computeRegion(floor.part, partAbove)
			return {
				part = floor.part,
				above = partAbove,
				frame = frame,
				size = areaSize,
				lowY = lowY,
				highY = highY,
			}
		end
	end
	return nil, "Floor " .. floorKey .. " not found, try using Select again."
end

-- Finds the real floor height from the big flat parts near the MapData part
function MapData.findFloorHeight(geometry, frame, selLow, selHigh, areaSize, blackEntries)
	local minSide = math.min(FLOOR_PIECE_MIN_SIDE, math.min(areaSize.X, areaSize.Y) * 0.5)
	local lowTop = selLow.Y - FLOOR_SEARCH_BELOW
	local highTop = math.min(selLow.Y + FLOOR_SEARCH_ABOVE, selHigh.Y)
	local totalArea = math.max(areaSize.X * areaSize.Y, 1e-3)

	local floorPieces = {}
	for _, obj in ipairs(geometry:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsA("Terrain") and not Util.isBall(obj)
			and Util.isVisible(obj) and Util.isUpright(obj)
			and not Util.hasCondition(obj, geometry)
			and not (#blackEntries > 0 and Util.matchesList(obj, blackEntries)) then

			local low, high = Util.boundsInFrame(obj, frame)
			local sx, sy, sz = high.X - low.X, high.Y - low.Y, high.Z - low.Z

			if sy < sx and sy < sz and sx >= minSide and sz >= minSide
				and high.Y >= lowTop and high.Y <= highTop then

				local ox = math.min(high.X, selHigh.X) - math.max(low.X, selLow.X)
				local oz = math.min(high.Z, selHigh.Z) - math.max(low.Z, selLow.Z)
				if ox > 0 and oz > 0 then
					table.insert(floorPieces, { top = high.Y, area = ox * oz })
				end
			end
		end
	end
	if #floorPieces == 0 then return nil end

	table.sort(floorPieces, function(firstPiece, secondPiece) return firstPiece.top < secondPiece.top end)

	-- This groups pieces with the same top height so we can use it to find the real floor
	local floorLevels = {}
	for _, piece in ipairs(floorPieces) do
		local level = floorLevels[#floorLevels]
		if level and piece.top - level.lastTop <= FLOOR_LEVEL_TOLERANCE then
			level.lastTop = piece.top
			level.area += piece.area
			level.weightedTop += piece.top * piece.area
			level.pieceCount += 1
		else
			table.insert(floorLevels, {
				lastTop = piece.top,
				area = piece.area,
				weightedTop = piece.top * piece.area,
				pieceCount = 1,
			})
		end
	end

	-- Finds the lowest group of parts that covers enough of the map (which should be the real floor)
	for _, level in ipairs(floorLevels) do
		if level.area / totalArea >= FLOOR_MIN_COVERAGE then
			return frame.Position.Y + level.weightedTop / level.area, level.pieceCount
		end
	end
	return nil
end

local function getCellKey(cellX, cellZ, cellTop)
	return cellX .. "," .. cellZ .. "," .. cellTop
end

local function findStepAt(grid, x, z, top)
	local tolerance = STAIR_TOLERANCE
	local cellSize = tolerance * 2
	local cellX, cellZ, cellTop = math.floor(x / cellSize), math.floor(z / cellSize), math.floor(top / cellSize)

	for offsetX = -1, 1 do
		for offsetZ = -1, 1 do
			for offsetTop = -1, 1 do
				local cell = grid[getCellKey(cellX + offsetX, cellZ + offsetZ, cellTop + offsetTop)]
				if cell then
					for _, step in ipairs(cell) do
						if math.abs(step.x - x) <= tolerance and math.abs(step.z - z) <= tolerance and math.abs(step.top - top) <= tolerance then
							return step
						end
					end
				end
			end
		end
	end
	return nil
end

local function detectStairs(candidates, stairParts)
	local cellSize = STAIR_TOLERANCE * 2

	local groups = {}
	for _, candidate in ipairs(candidates) do
		local sizeKey = math.floor(candidate.width * 10 + 0.5) .. "_" .. math.floor(candidate.depth * 10 + 0.5)
		groups[sizeKey] = groups[sizeKey] or {}
		table.insert(groups[sizeKey], candidate)
	end

	for _, group in pairs(groups) do
		if #group >= STAIR_MIN_STEPS then
			table.sort(group, function(a, b) return a.top < b.top end)

			local grid = {}
			for _, step in ipairs(group) do
				local cellKey = getCellKey(math.floor(step.x / cellSize), math.floor(step.z / cellSize), math.floor(step.top / cellSize))
				grid[cellKey] = grid[cellKey] or {}
				table.insert(grid[cellKey], step)
			end

			local start = 1
			for _, lower in ipairs(group) do
				while start <= #group and group[start].top < lower.top + STAIR_RISE_MIN do
					start += 1
				end

				local j = start
				while j <= #group and group[j].top <= lower.top + STAIR_RISE_MAX do
					local upper = group[j]
					local dx, dz = upper.x - lower.x, upper.z - lower.z
					local run = math.sqrt(dx * dx + dz * dz)

					if run >= STAIR_RUN_MIN and run <= STAIR_RUN_MAX then
						local rise = upper.top - lower.top
						local chain = { lower, upper }
						local last = upper
						while #chain < 500 do
							local nextStep = findStepAt(grid, last.x + dx, last.z + dz, last.top + rise)
							if not nextStep then break end
							table.insert(chain, nextStep)
							last = nextStep
						end

						if #chain >= STAIR_MIN_STEPS then
							for _, step in ipairs(chain) do
								stairParts[step.part] = true
							end
						end
					end
					j += 1
				end
			end
		end
	end
end

function MapData.findStairs(geometry, frame, selLow, selHigh, blackEntries)
	local stairParts = {}
	local stairNames = {}
	for _, name in ipairs(STAIR_NAMES) do
		table.insert(stairNames, string.lower(name))
	end

	local candidates = {}
	for _, obj in ipairs(geometry:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsA("Terrain") and not Util.isBall(obj) and not Util.hasCondition(obj, geometry) then
			local low, high = Util.boundsInFrame(obj, frame)
			local inside = low.X <= selHigh.X and high.X >= selLow.X
				and low.Y <= selHigh.Y and high.Y >= selLow.Y
				and low.Z <= selHigh.Z and high.Z >= selLow.Z

			if inside and Util.passesFilter(obj) and Util.isVisible(obj)
				and not (#blackEntries > 0 and Util.matchesList(obj, blackEntries)) then

				local named = false
				local inst = obj
				while #stairNames > 0 and inst and inst ~= geometry and not named do
					local lname = string.lower(inst.Name)
					for _, stairName in ipairs(stairNames) do
						if string.find(lname, stairName, 1, true) then
							named = true
							break
						end
					end
					inst = inst.Parent
				end

				if named then
					stairParts[obj] = true
				else
					local rel = frame:ToObjectSpace(obj.CFrame)
					table.insert(candidates, {
						part = obj,
						x = rel.Position.X,
						z = rel.Position.Z,
						top = high.Y,
						width = high.X - low.X,
						depth = high.Z - low.Z,
					})
				end
			end
		end
	end

	detectStairs(candidates, stairParts)
	return stairParts
end

local function getBox(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end

	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	return nil
end

-- PartCollection has a ShuffleTarget attribute, ShuffleTargets have a matching ShuffleTag.
-- A collection can end up at any target with the same tag.
-- So we use this function to find out which PartCollections are linked to which ShuffleTags.
local function findCollections(propsFolder)
	local collections = {}
	local targetsByTag = {}

	for _, inst in ipairs(propsFolder:GetDescendants()) do
		if inst:IsA("BasePart") or inst:IsA("Model") then
			local key = inst:GetAttribute("ShuffleTarget")
			local targetTag = inst:GetAttribute("ShuffleTag")

			if key ~= nil or targetTag ~= nil then
				local cf, size = getBox(inst)
				if cf then
					if key ~= nil then
						table.insert(collections, { cf = cf, size = size, key = tostring(key) })
					end
					if targetTag ~= nil then
						local tag = tostring(targetTag)
						targetsByTag[tag] = targetsByTag[tag] or {}
						table.insert(targetsByTag[tag], { cf = cf })
					end
				end
			end
		end
	end

	return collections, targetsByTag
end

local function isInsideCollection(collection, part)
	local rel = collection.cf:PointToObjectSpace(part.Position)
	local tolerance = 0.5
	return math.abs(rel.X) <= collection.size.X / 2 + tolerance
		and math.abs(rel.Y) <= collection.size.Y / 2 + tolerance
		and math.abs(rel.Z) <= collection.size.Z / 2 + tolerance
end

-- You know how sometimes we have doors and windows inside of PartCollections?
-- This handles that. Parts inside a collection get one position per target.
-- And then the door / window gets duplicated to a would-be location inside the
-- ShuffleTarget so we can leave spaces or draw walls indicating their presence
-- in the minimap.
function MapData.placements(propsFolder)
	local doors, windows = {}, {}
	local doorKey, windowKey = "door", "window"
	local collections, targetsByTag = findCollections(propsFolder)

	for _, part in ipairs(propsFolder:GetDescendants()) do
		if part:IsA("BasePart") then
			local lowerName = string.lower(part.Name)
			local list = nil
			if lowerName == windowKey then
				list = windows
			elseif string.find(lowerName, doorKey, 1, true) then
				list = doors
			end

			if list then
				local placed = false
				for _, collection in ipairs(collections) do
					if isInsideCollection(collection, part) then
						for _, target in ipairs(targetsByTag[collection.key] or {}) do
							local newCf = target.cf * collection.cf:Inverse() * part.CFrame
							table.insert(list, { part = part, cf = newCf, moved = true })
							placed = true
						end
					end
				end

				if not placed then
					table.insert(list, { part = part, cf = part.CFrame, moved = false })
				end
			end
		end
	end

	return doors, windows
end

return MapData

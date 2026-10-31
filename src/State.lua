-- State module
-- This is used to store variables shared across modules that are often changed during use of plugin

local State = {
	plugin = nil,
	exceptions = nil,
	blacklist = nil,
	rebuildIfShowing = function() end,

	geometryPath = { "DebugMission", "Geometry" },
	glassPath = { "DebugMission", "Glass" },
	propsPath = { "DebugMission", "Props" },
	mapDataPath = { "DebugMission", "MapData" },
	stageFolderName = "MissionMiniMapCreator_Stage",
	stageCenter = Vector3.new(-30000, 500, -30000),

	rotation = 0,
	minSize = 0.5,
	minSpanPercent = 30,

	partFilter = "All",
	mapStyle = "Default",
	thickenWalls = false,

	selectedFloorKey = nil,
	stage = nil,
	cameraPart = nil,
	stageOrigin = Vector3.zero,
	mapArea = Vector2.new(100, 100),
	busy = false,

	copiedParts = {},
	copiedPartSet = {},
	previewCopies = {},
	previewSizes = {},
	previewPxPerStud = 1,
	previewDist = 1000,
}

State.previewOffset = -State.stageCenter

return State
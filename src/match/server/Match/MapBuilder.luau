--!strict
--[[
	Builds a playable map out of a MapConfig (ARCHITECTURE.md D7).

	Maps are Luau modules rather than .rbxmx models so they stay diffable,
	reviewable and editable by an agent. The cost is this file: someone has to
	turn the data into parts. That cost is paid once, here.

	What it produces:
	  * a ground plane
	  * a walkway drawn along each lane's waypoints, purely visual
	  * buildable pads, tagged and attributed so placement validation can find
	    them by CollectionService query rather than by walking the model
	  * decor
	  * a base marker

	What it deliberately does NOT produce: anything the simulation reads back.
	The authoritative path is the Path object returned alongside the folder;
	the walkway parts are scenery. If those two ever disagree, the parts are
	wrong by definition.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Footprint = require(ReplicatedStorage.Shared.Footprint)
local Pads = require(ReplicatedStorage.Shared.Config.Maps.Pads)
local Path = require(ReplicatedStorage.Shared.Path)
local Types = require(ReplicatedStorage.Shared.Types)

local MapBuilder = {}

export type BuiltMap = {
	config: Types.MapConfig,
	folder: Folder,
	--- One Path per lane, index-aligned with config.paths. This is the
	--- authority for where enemies are.
	paths: { Path.Path },
}

local PATH_WIDTH = 16
local PATH_THICKNESS = 1
--- Walkway sits a hair above the BUILDABLE APRON, not above the ground
--- plane.
---
--- Every map lays one broad ground pad over its whole play area with its
--- top at Pads.GROUND_TOP, and every lane falls inside it. Measured from
--- y = 0 the walkway topped out at 0.15, which is 0.85 studs UNDER that
--- apron - so the lane was drawn, buried, and invisible, and the map read
--- as one featureless slab with no path on it.
---
--- Derived from Pads rather than hardcoded, so raising the apron cannot
--- bury the walkway again - and shared with the rig fitting, so enemies
--- stand ON this surface rather than on the y = 0 path plane beneath it.
local PATH_TOP_Y = Pads.WALKWAY_TOP

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function buildGround(config: Types.MapConfig, parent: Instance)
	local size = config.groundSize
	newPart(
		"Ground",
		size,
		-- Positioned so the slab's TOP sits at y = 0, which is the plane every
		-- other y in a map config is measured against.
		CFrame.new(0, -size.Y / 2, 0),
		config.groundColor,
		parent
	)
end

local function buildWalkway(lane: Types.MapPath, laneIndex: number, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = `Lane{laneIndex}`
	folder.Parent = parent

	local surface = Color3.fromRGB(122, 112, 96)
	local waypoints = lane.waypoints

	for i = 1, #waypoints - 1 do
		local from = waypoints[i]
		local to = waypoints[i + 1]
		local delta = to - from
		local length = delta.Magnitude
		local midpoint = from:Lerp(to, 0.5) + Vector3.new(0, PATH_TOP_Y - PATH_THICKNESS / 2, 0)

		-- CFrame.lookAt orients -Z toward the target, and a part's Size.Z runs
		-- along its local Z, so a part of this length spans exactly from->to.
		local segment = newPart(
			`Segment{i}`,
			Vector3.new(PATH_WIDTH, PATH_THICKNESS, length),
			CFrame.lookAt(midpoint, midpoint + delta),
			surface,
			folder
		)
		segment.CanCollide = false
	end

	-- Square patches at the interior corners. Without these, two segments
	-- meeting at a right angle leave a visible notch on the outside of the
	-- turn.
	for i = 2, #waypoints - 1 do
		local corner = newPart(
			`Corner{i}`,
			Vector3.new(PATH_WIDTH, PATH_THICKNESS, PATH_WIDTH),
			CFrame.new(waypoints[i] + Vector3.new(0, PATH_TOP_Y - PATH_THICKNESS / 2, 0)),
			surface,
			folder
		)
		corner.CanCollide = false
	end
end

local function buildSurfaces(config: Types.MapConfig, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Buildable"
	folder.Parent = parent

	for index, surface in config.buildableSurfaces do
		local isElevated = surface.surfaceType == "Elevated"

		local pad = newPart(
			`Pad{index}`,
			surface.size,
			CFrame.new(surface.position),
			if isElevated then Color3.fromRGB(120, 116, 104) else Color3.fromRGB(96, 108, 86),
			folder
		)

		-- Tag plus attribute, rather than encoding the type in the name.
		-- Placement validation reads these; a name-based scheme breaks the
		-- moment someone renames a part in Studio.
		pad:SetAttribute(Constants.ATTR_SURFACE_TYPE, surface.surfaceType)
		CollectionService:AddTag(pad, Constants.BUILDABLE_TAG)
	end
end

local function buildDecor(config: Types.MapConfig, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = parent

	for index, piece in config.decor do
		local part = newPart(`Decor{index}`, piece.size, CFrame.new(piece.position), piece.color, folder)

		if piece.material ~= nil then
			part.Material = piece.material
		end

		if piece.transparency ~= nil then
			part.Transparency = piece.transparency
		end
	end
end

local function buildBaseMarker(config: Types.MapConfig, parent: Instance)
	local marker = newPart(
		"Base",
		Vector3.new(20, 24, 20),
		CFrame.new(config.basePosition + Vector3.new(0, 12, 0)),
		Color3.fromRGB(72, 130, 180),
		parent
	)
	marker.CanCollide = false
	marker.Transparency = 0.35
end

--- Removes any previously built map. Safe to call when none exists.
function MapBuilder.clear()
	local existing = workspace:FindFirstChild(Constants.MAP_FOLDER)

	if existing ~= nil then
		existing:Destroy()
	end
end

--- Builds `config` into workspace and returns the handle the match needs.
--- Replaces any map already present.
--- Minimum studs a spawn must sit from every lane. Comfortably wider than
--- the walkway, so a spawning player is never standing in traffic.
local SPAWN_CLEARANCE = 24

--- Picks somewhere off the lanes to put players.
---
--- Without an explicit SpawnLocation, Roblox drops characters at the origin -
--- which on a map whose lane crosses the middle means spawning inside the
--- enemy path. Rather than hand-authoring a spawn per map and having it rot
--- when waypoints move, this searches the map's own edges for the candidate
--- furthest from every lane, reusing the same distance function placement
--- validation uses.
local function findSpawnPosition(config: Types.MapConfig): Vector3
	local halfX = config.groundSize.X / 2 - SPAWN_CLEARANCE
	local halfZ = config.groundSize.Z / 2 - SPAWN_CLEARANCE

	local candidates: { Vector3 } = {
		Vector3.new(-halfX, 0, -halfZ),
		Vector3.new(halfX, 0, -halfZ),
		Vector3.new(-halfX, 0, halfZ),
		Vector3.new(halfX, 0, halfZ),
		Vector3.new(0, 0, -halfZ),
		Vector3.new(0, 0, halfZ),
		Vector3.new(-halfX, 0, 0),
		Vector3.new(halfX, 0, 0),
	}

	local best = candidates[1]
	local bestDistance = -1

	for _, candidate in candidates do
		local nearest = math.huge

		for _, lane in config.paths do
			nearest = math.min(nearest, Footprint.distanceToPath(candidate, lane.waypoints))
		end

		-- Furthest-from-any-lane rather than first-acceptable, so a cramped
		-- map still gets the best available spot instead of an arbitrary one.
		if nearest > bestDistance then
			bestDistance = nearest
			best = candidate
		end
	end

	return best
end

local function buildSpawn(config: Types.MapConfig, parent: Instance): SpawnLocation
	local position = findSpawnPosition(config)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MatchSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	-- Rests on the ground apron, whose top is at y = 1.
	spawn.CFrame = CFrame.new(position.X, 1.5, position.Z)
	spawn.Color = Color3.fromRGB(120, 160, 200)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = parent

	return spawn
end

--- Draggable markers for each waypoint, so a map can be reshaped in Studio
--- and read back by MapExtract.
---
--- Visible only in Studio. In a live server these are invisible and inert -
--- they exist so the tree MapBuilder produces is the same tree MapExtract
--- consumes, which is what makes the round trip lossless. A player never sees
--- them; the walkway drawn from the same waypoints is the visible thing.
---
--- The Order attribute rather than relying on the name: an author renumbering
--- a lane should not have to rename anything.
local function buildWaypointMarkers(config: Types.MapConfig, parent: Instance)
	local lanes = Instance.new("Folder")
	lanes.Name = "Lanes"
	lanes.Parent = parent

	local visible = RunService:IsStudio()

	for laneIndex, lane in config.paths do
		local folder = Instance.new("Folder")
		folder.Name = `Lane{laneIndex}`
		folder.Parent = lanes

		for index, point in lane.waypoints do
			local marker = newPart(
				`Waypoint{index}`,
				Vector3.new(3, 3, 3),
				CFrame.new(point),
				Color3.fromRGB(240, 200, 90),
				folder
			)

			marker.Shape = Enum.PartType.Ball
			marker.Material = Enum.Material.Neon
			marker.Transparency = if visible then 0.45 else 1
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.CastShadow = false
			marker:SetAttribute("Order", index)
		end
	end
end

function MapBuilder.build(config: Types.MapConfig): BuiltMap
	MapBuilder.clear()

	local folder = Instance.new("Folder")
	folder.Name = Constants.MAP_FOLDER

	buildGround(config, folder)
	buildWaypointMarkers(config, folder)
	buildSurfaces(config, folder)
	buildDecor(config, folder)
	buildBaseMarker(config, folder)
	buildSpawn(config, folder)

	local walkways = Instance.new("Folder")
	walkways.Name = "Walkways"
	walkways.Parent = folder

	local paths: { Path.Path } = {}

	for index, lane in config.paths do
		buildWalkway(lane, index, walkways)
		paths[index] = Path.new(lane.waypoints)
	end

	folder.Parent = workspace

	return {
		config = config,
		folder = folder,
		paths = paths,
	}
end

return MapBuilder

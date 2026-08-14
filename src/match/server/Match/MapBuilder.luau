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

local Constants = require(ReplicatedStorage.Shared.Constants)
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
--- Walkway sits a hair above y = 0 so it does not z-fight the ground plane.
local PATH_TOP_Y = 0.15

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
function MapBuilder.build(config: Types.MapConfig): BuiltMap
	MapBuilder.clear()

	local folder = Instance.new("Folder")
	folder.Name = Constants.MAP_FOLDER

	buildGround(config, folder)
	buildSurfaces(config, folder)
	buildDecor(config, folder)
	buildBaseMarker(config, folder)

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

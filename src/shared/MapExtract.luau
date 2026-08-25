--!strict
--[[
	Reads a map back out of a Studio tree, and writes it as a config module.

	The inverse of MapBuilder. MapBuilder turns `Config/Maps/<Name>.luau` into
	parts in workspace; this turns those parts back into the same config, so a
	map can be dragged around in Studio and then committed as diffable data.

	WHY NOT JUST SAVE AN .rbxm. Because the config is not scenery - it is what
	the simulation runs on. `Path.new(lane.waypoints)` is the authority for
	where enemies walk, `Placement.validate` reads buildableSurfaces and the
	ground extents, and three spec files exercise all of that as plain tables
	with no Instance anywhere near them (ARCHITECTURE.md D7). Keeping the
	runtime on data is what lets 44 tests cover placement and pathing at all.
	Authoring in Studio and EXTRACTING gets the editing experience without
	giving that up.

	THE CONVENTION, which is exactly what MapBuilder emits:

	    TDMap/
	      Ground          a Part; its Size and Color are the ground plane
	      Base            a Part; its position is basePosition
	      Lanes/
	        Lane1/        one folder per lane, ordered by trailing number
	          <parts>     waypoints, ordered by an `Order` attribute if
	                      present, otherwise by a trailing number in the name
	      Buildable/      parts tagged TDBuildable, each with a SurfaceType
	      Decor/          everything else that should be rebuilt as scenery
	      Walkways/       IGNORED - generated from the waypoints, not authored

	Anything unreadable is reported rather than guessed at. A map that extracts
	with problems is a map that would have shipped wrong.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

local MapExtract = {}

export type Extraction = {
	config: Types.MapConfig?,
	--- Everything that could not be read. Empty means the config is complete.
	problems: { string },
}

--- Waypoints and the base marker are flattened onto the path plane.
---
--- Every y in a map config is measured against the ground plane's top, and
--- the walkway is drawn from the waypoints rather than the other way round.
--- Letting an author's drag introduce a stray y would tilt the lane without
--- any visible cause.
local PATH_PLANE_Y = 0

--- Where a part sits in the running order of its lane.
---
--- An explicit `Order` attribute wins, so an author can renumber without
--- renaming. Falling back to a trailing number means the parts MapBuilder
--- emits - Waypoint1, Waypoint2 - sort correctly with no extra work.
local function orderOf(part: BasePart): number?
	local attribute = part:GetAttribute("Order")

	if type(attribute) == "number" then
		return attribute
	end

	local suffix = string.match(part.Name, "(%d+)$")

	return if suffix ~= nil then tonumber(suffix) else nil
end

local function sortedByOrder(folder: Instance, problems: { string }): { BasePart }
	local parts: { BasePart } = {}

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			if orderOf(child) == nil then
				table.insert(
					problems,
					`{child:GetFullName()}: no Order attribute and no trailing number in the name, so its position in the lane is undefined`
				)
			else
				table.insert(parts, child)
			end
		end
	end

	table.sort(parts, function(a: BasePart, b: BasePart): boolean
		return (orderOf(a) or 0) < (orderOf(b) or 0)
	end)

	return parts
end

--- Lane folders, ordered the same way waypoints are.
local function laneFolders(lanes: Instance, problems: { string }): { Instance }
	local folders: { Instance } = {}

	for _, child in lanes:GetChildren() do
		if child:IsA("Folder") then
			if string.match(child.Name, "(%d+)$") == nil then
				table.insert(problems, `{child:GetFullName()}: lane folder name must end in a number, e.g. Lane1`)
			else
				table.insert(folders, child)
			end
		end
	end

	table.sort(folders, function(a: Instance, b: Instance): boolean
		local an = tonumber(string.match(a.Name, "(%d+)$")) or 0
		local bn = tonumber(string.match(b.Name, "(%d+)$")) or 0
		return an < bn
	end)

	return folders
end

local function readPaths(root: Instance, problems: { string }): { Types.MapPath }
	local lanes = root:FindFirstChild("Lanes")

	if lanes == nil then
		table.insert(problems, "no Lanes folder - the map has no path for enemies to walk")
		return {}
	end

	local paths: { Types.MapPath } = {}

	for _, folder in laneFolders(lanes, problems) do
		local parts = sortedByOrder(folder, problems)

		if #parts < 2 then
			table.insert(problems, `{folder:GetFullName()}: a lane needs at least two waypoints, found {#parts}`)
			continue
		end

		local waypoints: { Vector3 } = {}

		for _, part in parts do
			table.insert(waypoints, Vector3.new(part.Position.X, PATH_PLANE_Y, part.Position.Z))
		end

		table.insert(paths, { waypoints = waypoints })
	end

	if #paths == 0 then
		table.insert(problems, "Lanes folder contains no usable lane")
	end

	return paths
end

local function readSurfaces(root: Instance, problems: { string }): { Types.BuildableSurface }
	local container = root:FindFirstChild("Buildable")

	if container == nil then
		table.insert(problems, "no Buildable folder - nothing could be built on this map")
		return {}
	end

	local surfaces: { Types.BuildableSurface } = {}

	for _, child in container:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end

		if not CollectionService:HasTag(child, Constants.BUILDABLE_TAG) then
			table.insert(
				problems,
				`{child:GetFullName()}: in Buildable but not tagged {Constants.BUILDABLE_TAG}, so placement would never find it`
			)
			continue
		end

		local surfaceType = child:GetAttribute(Constants.ATTR_SURFACE_TYPE)

		if surfaceType ~= "Ground" and surfaceType ~= "Elevated" then
			table.insert(
				problems,
				`{child:GetFullName()}: {Constants.ATTR_SURFACE_TYPE} is {tostring(surfaceType)}, expected "Ground" or "Elevated"`
			)
			continue
		end

		table.insert(surfaces, {
			position = child.Position,
			size = child.Size,
			surfaceType = surfaceType :: Types.SurfaceType,
		})
	end

	return surfaces
end

local function readDecor(root: Instance): { Types.DecorPart }
	local container = root:FindFirstChild("Decor")

	if container == nil then
		return {}
	end

	local decor: { Types.DecorPart } = {}

	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(decor, {
				position = child.Position,
				size = child.Size,
				color = child.Color,
			})
		end
	end

	return decor
end

--- Reads `root` - normally workspace.TDMap - into a config.
---
--- `id` and `displayName` cannot be recovered from geometry, so they are
--- passed in rather than invented.
function MapExtract.fromFolder(root: Instance, id: string, displayName: string): Extraction
	local problems: { string } = {}

	local ground = root:FindFirstChild("Ground")
	local base = root:FindFirstChild("Base")

	if ground == nil or not ground:IsA("BasePart") then
		table.insert(problems, "no Ground part - the ground plane's size and colour come from it")
	end

	if base == nil or not base:IsA("BasePart") then
		table.insert(problems, "no Base part - basePosition comes from it")
	end

	-- The ground's POSITION is derived, never read: MapBuilder places the slab
	-- so its top sits at y = 0, which is the plane every other y in a config is
	-- measured against. Dragging the ground therefore does nothing except
	-- detach the play area from the lane - so say so, rather than snapping it
	-- back in silence and letting an author think the move took.
	if ground ~= nil and ground:IsA("BasePart") then
		local expected = -ground.Size.Y / 2

		if math.abs(ground.Position.Y - expected) > 0.01 then
			table.insert(
				problems,
				`{ground:GetFullName()}: y is {ground.Position.Y}, but the ground's top defines y = 0, so it must sit at {expected}. Move it back, or move everything else instead.`
			)
		end

		if math.abs(ground.Position.X) > 0.01 or math.abs(ground.Position.Z) > 0.01 then
			table.insert(
				problems,
				`{ground:GetFullName()}: is off-centre at ({ground.Position.X}, {ground.Position.Z}); the ground plane is always centred on the origin`
			)
		end
	end

	local paths = readPaths(root, problems)
	local surfaces = readSurfaces(root, problems)
	local decor = readDecor(root)

	if ground == nil or not ground:IsA("BasePart") or base == nil or not base:IsA("BasePart") then
		return { config = nil, problems = problems }
	end

	local config: Types.MapConfig = {
		id = id,
		displayName = displayName,
		paths = paths,
		basePosition = Vector3.new(base.Position.X, PATH_PLANE_Y, base.Position.Z),
		buildableSurfaces = surfaces,
		decor = decor,
		groundSize = ground.Size,
		groundColor = ground.Color,
	}

	return { config = config, problems = problems }
end

-- ---------------------------------------------------------------------------
-- Serialisation
-- ---------------------------------------------------------------------------

--- Trims float noise off a dragged position.
---
--- Studio hands back values like 139.99998474121094. Writing that verbatim
--- makes every re-extraction a diff even when nothing moved, which is the
--- whole benefit of keeping maps as text.
local function num(value: number): string
	local rounded = math.floor(value * 100 + 0.5) / 100

	if rounded == math.floor(rounded) then
		return string.format("%d", rounded)
	end

	return (string.gsub(string.format("%.2f", rounded), "0$", ""))
end

local function vec(value: Vector3): string
	return `Vector3.new({num(value.X)}, {num(value.Y)}, {num(value.Z)})`
end

local function col(value: Color3): string
	return `Color3.fromRGB({math.round(value.R * 255)}, {math.round(value.G * 255)}, {math.round(value.B * 255)})`
end

--- Renders a config as the source of a Config/Maps module.
---
--- Emitted rather than hand-maintained, so what is committed is exactly what
--- was in Studio. The header says so, because a file that looks hand-written
--- but is regenerated is a file someone will edit and lose.
function MapExtract.toSource(config: Types.MapConfig): string
	local out: { string } = {}

	local function line(text: string)
		table.insert(out, text)
	end

	line("--!strict")
	line("--[[")
	line(`\tGenerated from Studio by MapExtract. Edit the map in Studio and`)
	line(`\tre-extract; hand edits here are overwritten on the next extraction.`)
	line("")
	line(`\tCoordinate conventions are unchanged: waypoints sit at y = 0, a`)
	line(`\tbuildable surface's position is the CENTRE of its slab, and the`)
	line(`\tground plane's top is y = 0.`)
	line("]]")
	line("")
	line("local Types = require(script.Parent.Parent.Parent.Types)")
	line("")
	line("local map: Types.MapConfig = {")
	line(`\tid = "{config.id}",`)
	line(`\tdisplayName = "{config.displayName}",`)
	line("")
	line("\tpaths = {")

	for _, lane in config.paths do
		line("\t\t{")
		line("\t\t\twaypoints = {")

		for _, point in lane.waypoints do
			line(`\t\t\t\t{vec(point)},`)
		end

		line("\t\t\t},")
		line("\t\t},")
	end

	line("\t},")
	line("")
	line(`\tbasePosition = {vec(config.basePosition)},`)
	line("")
	line("\tbuildableSurfaces = {")

	for _, surface in config.buildableSurfaces do
		line("\t\t{")
		line(`\t\t\tposition = {vec(surface.position)},`)
		line(`\t\t\tsize = {vec(surface.size)},`)
		line(`\t\t\tsurfaceType = "{surface.surfaceType}" :: Types.SurfaceType,`)
		line("\t\t},")
	end

	line("\t},")
	line("")
	line("\tdecor = {")

	for _, piece in config.decor do
		line("\t\t{")
		line(`\t\t\tposition = {vec(piece.position)},`)
		line(`\t\t\tsize = {vec(piece.size)},`)
		line(`\t\t\tcolor = {col(piece.color)},`)
		line("\t\t},")
	end

	line("\t},")
	line("")
	line(`\tgroundSize = {vec(config.groundSize)},`)
	line(`\tgroundColor = {col(config.groundColor)},`)
	line("}")
	line("")
	line("return map")
	line("")

	return table.concat(out, "\n")
end

return MapExtract

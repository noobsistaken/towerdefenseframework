--!strict
--[[
	Crossroads - the introductory map.

	One lane, 610 studs long, folded into an S so that a tower placed in the
	middle can cover several passes. That overlap is what makes placement an
	interesting decision rather than "put it anywhere near the path".

	Coordinate conventions used by every map:
	  * Path waypoints sit at y = 0. MapBuilder draws the visible walkway just
	    above that, and enemies are lifted by their own hoverHeight.
	  * A buildable surface's `position` is the CENTRE of its slab, so its
	    walkable top is position.Y + size.Y / 2.
	  * Ground pads top out at y = 1, elevated pads at y = 12. Hillside towers
	    are exactly the ones restricted to the latter.

	This is placeholder geometry. Everything here is parts and colours, and
	every slot appears in the asset manifest.
]]

local Types = require(script.Parent.Parent.Parent.Types)

--- Slab thickness shared by every buildable pad, so the y arithmetic above
--- holds uniformly.
local PAD_THICKNESS = 4

local function groundPad(x: number, z: number, sizeX: number, sizeZ: number): Types.BuildableSurface
	return {
		position = Vector3.new(x, 1 - PAD_THICKNESS / 2, z),
		size = Vector3.new(sizeX, PAD_THICKNESS, sizeZ),
		surfaceType = "Ground" :: Types.SurfaceType,
	}
end

local function elevatedPad(x: number, z: number, sizeX: number, sizeZ: number): Types.BuildableSurface
	return {
		position = Vector3.new(x, 12 - PAD_THICKNESS / 2, z),
		size = Vector3.new(sizeX, PAD_THICKNESS, sizeZ),
		surfaceType = "Elevated" :: Types.SurfaceType,
	}
end

local map: Types.MapConfig = {
	id = "Crossroads",
	displayName = "Crossroads",

	paths = {
		{
			waypoints = {
				Vector3.new(-140, 0, -80),
				Vector3.new(-60, 0, -80),
				Vector3.new(-60, 0, 40),
				Vector3.new(20, 0, 40),
				Vector3.new(20, 0, -40),
				Vector3.new(90, 0, -40),
				Vector3.new(90, 0, 90),
				Vector3.new(140, 0, 90),
			},
		},
	},

	basePosition = Vector3.new(140, 0, 90),

	buildableSurfaces = {
		-- One broad apron covering the play area, NOT a set of pockets.
		--
		-- The lane is carved out of it by PATH_CLEARANCE during validation
		-- rather than by holes in the geometry. Doing it that way is what
		-- makes placement free-form: the rule a player learns is "anywhere
		-- except on the path", which they can see, instead of "only on the
		-- pads", which they cannot.
		groundPad(0, 0, 320, 280),

		-- Elevated: two plateaus, each overlooking a different pair of
		-- passes. These are the only legal Hillside placements on this map.
		--
		-- They sit ON TOP of the apron, so both surfaces contain any point on
		-- a plateau. surfaceUnder resolves that by height, which is why these
		-- being listed after the apron does not matter.
		elevatedPad(-105, -110, 60, 50),
		elevatedPad(55, -95, 70, 40),
	},

	decor = {
		-- Ramps implied by geometry only - they are visual, not walkable.
		{
			position = Vector3.new(-105, 6, -75),
			size = Vector3.new(60, 12, 12),
			color = Color3.fromRGB(96, 88, 78),
		},
		{
			position = Vector3.new(55, 6, -70),
			size = Vector3.new(70, 12, 12),
			color = Color3.fromRGB(96, 88, 78),
		},
		-- Spawn marker.
		{
			position = Vector3.new(-148, 6, -80),
			size = Vector3.new(6, 12, 26),
			color = Color3.fromRGB(150, 60, 60),
		},
	},

	groundSize = Vector3.new(340, 4, 300),
	groundColor = Color3.fromRGB(72, 88, 64),
}

return map

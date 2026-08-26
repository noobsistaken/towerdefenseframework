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

local Pads = require(script.Parent.Pads)

local groundPad = Pads.ground
local elevatedPad = Pads.elevated

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
		-- Meadow dressing: oaks and boulders in the lane-free pockets,
		-- flower plates flat on the apron. Every piece sits 14+ studs off
		-- the lane centreline, so nothing reads as blocking the walkway.
		{
			position = Vector3.new(-130, 4.0, 20),
			size = Vector3.new(2.5, 8.0, 2.5),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-130, 11.2, 20),
			size = Vector3.new(9.0, 7.0, 9.0),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-115, 3.4, 62),
			size = Vector3.new(2.1, 6.8, 2.1),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-115, 9.5, 62),
			size = Vector3.new(7.6, 6.0, 7.6),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-140, 4.4, 118),
			size = Vector3.new(2.8, 8.8, 2.8),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-140, 12.3, 118),
			size = Vector3.new(9.9, 7.7, 9.9),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(60, 4.0, 120),
			size = Vector3.new(2.5, 8.0, 2.5),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(60, 11.2, 120),
			size = Vector3.new(9.0, 7.0, 9.0),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(150, 3.6, -20),
			size = Vector3.new(2.2, 7.2, 2.2),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(150, 10.1, -20),
			size = Vector3.new(8.1, 6.3, 8.1),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-20, 4.2, -130),
			size = Vector3.new(2.6, 8.4, 2.6),
			color = Color3.fromRGB(92, 66, 46),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-20, 11.8, -130),
			size = Vector3.new(9.5, 7.4, 9.5),
			color = Color3.fromRGB(64, 118, 58),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(120, 1.75, 24),
			size = Vector3.new(6, 3.5, 7),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-40, 2.0, 92),
			size = Vector3.new(7, 4, 5),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-88, 1.25, 130),
			size = Vector3.new(4, 2.5, 5),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-100, 1.2, 90),
			size = Vector3.new(14, 0.4, 14),
			color = Color3.fromRGB(150, 170, 90),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(50, 1.2, 90),
			size = Vector3.new(12, 0.4, 12),
			color = Color3.fromRGB(176, 156, 96),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-15, 1.2, -125),
			size = Vector3.new(12, 0.4, 12),
			color = Color3.fromRGB(150, 170, 90),
			material = Enum.Material.Grass,
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

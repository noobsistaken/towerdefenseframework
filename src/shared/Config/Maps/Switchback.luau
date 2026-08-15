--!strict
--[[
	Switchback - the long map.

	One lane, ~820 studs, folded into a serpentine that doubles back on itself
	three times. The extra length is not a difficulty knob in itself: a longer
	lane means MORE time to shoot, so this map is easier per enemy than
	Crossroads and compensates by being stingy about where you can shoot from.

	What makes it distinct is the plateau. There is exactly ONE, sitting in the
	middle where the lane passes it on three sides, so it covers far more of
	the route than either Crossroads plateau does. Anti-air is therefore
	concentrated in a single spot rather than split across two, and losing that
	spot to badly-placed ground towers is a real mistake a player can make.

	Coordinate conventions are the ones in Pads.luau: waypoints at y = 0,
	ground apron top at y = 1, plateau top at y = 12.
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pads = require(script.Parent.Pads)

local map: Types.MapConfig = {
	id = "Switchback",
	displayName = "Switchback",

	paths = {
		{
			-- West edge, then three folds east-west before running out east.
			waypoints = {
				Vector3.new(-150, 0, -70),
				Vector3.new(90, 0, -70),
				Vector3.new(90, 0, 10),
				Vector3.new(-90, 0, 10),
				Vector3.new(-90, 0, 90),
				Vector3.new(150, 0, 90),
			},
		},
	},

	basePosition = Vector3.new(150, 0, 90),

	buildableSurfaces = {
		Pads.ground(0, 10, 320, 280),

		-- The single plateau, in the pocket the first two folds create. The
		-- lane runs past it north, west and south.
		Pads.elevated(-10, -30, 70, 50),
	},

	decor = {
		-- Ramp implied by geometry only - visual, not walkable.
		{
			position = Vector3.new(-10, 6, -62),
			size = Vector3.new(70, 12, 10),
			color = Color3.fromRGB(96, 88, 78),
		},
		-- Spawn marker.
		{
			position = Vector3.new(-152, 6, -70),
			size = Vector3.new(6, 12, 26),
			color = Color3.fromRGB(150, 60, 60),
		},
	},

	groundSize = Vector3.new(340, 4, 320),
	groundColor = Color3.fromRGB(68, 80, 72),
}

return map

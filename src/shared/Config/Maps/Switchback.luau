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
		-- Moor dressing: pines on the outer edges and a ring of standing
		-- stones in the northwest corner, well clear of every fold.
		{
			position = Vector3.new(-140, 3.5, 50),
			size = Vector3.new(2.0, 7.0, 2.0),
			color = Color3.fromRGB(78, 58, 42),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-140, 9.5, 50),
			size = Vector3.new(7.0, 5.0, 7.0),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-140, 13.5, 50),
			size = Vector3.new(4.5, 3.5, 4.5),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(140, 4.2, -120),
			size = Vector3.new(2.4, 8.4, 2.4),
			color = Color3.fromRGB(78, 58, 42),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(140, 11.4, -120),
			size = Vector3.new(8.4, 6.0, 8.4),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(140, 16.2, -120),
			size = Vector3.new(5.4, 4.2, 5.4),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(150, 3.15, 40),
			size = Vector3.new(1.8, 6.3, 1.8),
			color = Color3.fromRGB(78, 58, 42),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(150, 8.6, 40),
			size = Vector3.new(6.3, 4.5, 6.3),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(150, 12.2, 40),
			size = Vector3.new(4.0, 3.1, 4.0),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-120, 3.85, 140),
			size = Vector3.new(2.2, 7.7, 2.2),
			color = Color3.fromRGB(78, 58, 42),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-120, 10.4, 140),
			size = Vector3.new(7.7, 5.5, 7.7),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-120, 14.9, 140),
			size = Vector3.new(5.0, 3.9, 5.0),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(60, 3.3, -130),
			size = Vector3.new(1.9, 6.6, 1.9),
			color = Color3.fromRGB(78, 58, 42),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(60, 9.0, -130),
			size = Vector3.new(6.6, 4.8, 6.6),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(60, 12.8, -130),
			size = Vector3.new(4.3, 3.3, 4.3),
			color = Color3.fromRGB(46, 88, 60),
			material = Enum.Material.Grass,
		},
		{
			position = Vector3.new(-130, 5, -120),
			size = Vector3.new(4, 10, 3),
			color = Color3.fromRGB(106, 110, 118),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-110, 4.5, -135),
			size = Vector3.new(3.5, 9, 3),
			color = Color3.fromRGB(106, 110, 118),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-147, 4, -100),
			size = Vector3.new(3.5, 8, 3),
			color = Color3.fromRGB(106, 110, 118),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-128, 0.8, -118),
			size = Vector3.new(22, 0.4, 22),
			color = Color3.fromRGB(88, 96, 92),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(30, 2.0, 132),
			size = Vector3.new(8, 4, 6),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-40, 1.5, -130),
			size = Vector3.new(6, 3, 7),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
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

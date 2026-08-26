--!strict
--[[
	Gauntlet - the short one.

	A single 320-stud lane with one dogleg. Where Fork stretches a defence
	across two fronts and Switchback buys you time, this map refuses to: the
	walk from spawn to base is the shortest in the registry, so every wave
	arrives before the last one's bounty is spent. The map for players who
	think the game is too slow, and the map that makes Nightmare mean it.

	The arena is deliberately slim - two long plateaus flank the lane at
	whisker distance, so Hillside towers cover almost all of it and the real
	decision is ground placement in the narrow margins.
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pads = require(script.Parent.Pads)

local map: Types.MapConfig = {
	id = "Gauntlet",
	displayName = "Gauntlet",

	paths = {
		{
			-- 180 + 40 + 100 = 320 studs, the shortest lane in the game.
			waypoints = {
				Vector3.new(-140, 0, -20),
				Vector3.new(40, 0, -20),
				Vector3.new(40, 0, 20),
				Vector3.new(140, 0, 20),
			},
		},
	},

	basePosition = Vector3.new(145, 0, 20),

	buildableSurfaces = {
		Pads.ground(0, 0, 300, 180),

		-- Flanking plateaus, close enough that between them almost the whole
		-- lane is covered. The pressure here is money, not geometry.
		Pads.elevated(-50, -70, 70, 40),
		Pads.elevated(50, 70, 70, 40),
	},

	decor = {
		-- Canyon walls, so the slim arena reads as a place rather than a
		-- clipped rectangle.
		{
			position = Vector3.new(0, 8, -95),
			size = Vector3.new(300, 16, 10),
			color = Color3.fromRGB(108, 88, 68),
		},
		{
			position = Vector3.new(0, 8, 95),
			size = Vector3.new(300, 16, 10),
			color = Color3.fromRGB(108, 88, 68),
		},
		-- Canyon dressing: mesas and cacti in the narrow margins the slim
		-- arena leaves. Nothing within 14 studs of the lane.
		{
			position = Vector3.new(-130, 5, 60),
			size = Vector3.new(40, 10, 25),
			color = Color3.fromRGB(134, 112, 86),
			material = Enum.Material.Sandstone,
		},
		{
			position = Vector3.new(-130, 11.5, 60),
			size = Vector3.new(30, 3, 18),
			color = Color3.fromRGB(148, 126, 96),
			material = Enum.Material.Sandstone,
		},
		{
			position = Vector3.new(130, 6, -60),
			size = Vector3.new(35, 12, 22),
			color = Color3.fromRGB(134, 112, 86),
			material = Enum.Material.Sandstone,
		},
		{
			position = Vector3.new(130, 13.5, -60),
			size = Vector3.new(26, 3, 16),
			color = Color3.fromRGB(148, 126, 96),
			material = Enum.Material.Sandstone,
		},
		{
			position = Vector3.new(-60, 4, 50),
			size = Vector3.new(1.6, 6, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(-58.4, 5, 50),
			size = Vector3.new(1.6, 2.2, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(0, 4, 60),
			size = Vector3.new(1.6, 6, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(1.6, 5, 60),
			size = Vector3.new(1.6, 2.2, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(90, 4, -60),
			size = Vector3.new(1.6, 6, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(91.6, 5, -60),
			size = Vector3.new(1.6, 2.2, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(-100, 4, -55),
			size = Vector3.new(1.6, 6, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(-98.4, 5, -55),
			size = Vector3.new(1.6, 2.2, 1.6),
			color = Color3.fromRGB(96, 142, 74),
		},
		{
			position = Vector3.new(10, 1.6, -80),
			size = Vector3.new(30, 1.2, 14),
			color = Color3.fromRGB(168, 146, 108),
			material = Enum.Material.Sand,
		},
		{
			position = Vector3.new(-40, 1.6, 75),
			size = Vector3.new(26, 1.2, 12),
			color = Color3.fromRGB(168, 146, 108),
			material = Enum.Material.Sand,
		},
		{
			position = Vector3.new(60, 1.5, 55),
			size = Vector3.new(5, 3, 4),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		-- Spawn marker.
		{
			position = Vector3.new(-146, 6, -20),
			size = Vector3.new(6, 12, 26),
			color = Color3.fromRGB(150, 60, 60),
		},
	},

	groundSize = Vector3.new(320, 4, 200),
	groundColor = Color3.fromRGB(118, 100, 80),
}

return map

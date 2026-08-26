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

--!strict
--[[
	Fork - the two-lane map.

	Two independent lanes from two spawns, converging on one base. This is the
	map that exercises the multi-lane machinery: WaveGenerator round-robins
	spawns across lanes, and every enemy is assigned one lane at spawn and
	never changes.

	The lanes are DIFFERENT LENGTHS on purpose - 370 studs north, 450 south.
	That is the shape that distinguishes correct First/Last targeting from the
	naive version: ordering enemies by raw distance walked would rank a south-
	lane enemy ahead of a north-lane one that is actually closer to the base.
	Ordering by distance REMAINING is what makes it come out right, which is
	ARCHITECTURE.md D8, and this map is where that stops being theoretical.

	Both lanes are short, so a defence split across two fronts is under real
	pressure. Each lane gets its own plateau, and they are far enough apart
	that one cannot cover both.
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pads = require(script.Parent.Pads)

local map: Types.MapConfig = {
	id = "Fork",
	displayName = "Fork",

	paths = {
		{
			-- North lane. 180 + 80 + 110 = 370 studs.
			waypoints = {
				Vector3.new(-150, 0, -90),
				Vector3.new(30, 0, -90),
				Vector3.new(30, 0, -10),
				Vector3.new(140, 0, -10),
			},
		},
		{
			-- South lane, deliberately longer at 90 + 40 + 120 + 120 + 80 =
			-- 450 studs, so the two lanes never stay in step.
			waypoints = {
				Vector3.new(-150, 0, 90),
				Vector3.new(-60, 0, 90),
				Vector3.new(-60, 0, 130),
				Vector3.new(60, 0, 130),
				Vector3.new(60, 0, 10),
				Vector3.new(140, 0, 10),
			},
		},
	},

	basePosition = Vector3.new(145, 0, 0),

	buildableSurfaces = {
		Pads.ground(0, 0, 320, 300),

		-- One plateau per lane, far enough apart that neither covers both.
		Pads.elevated(-60, -40, 60, 50),
		Pads.elevated(0, 70, 60, 40),
	},

	decor = {
		{
			position = Vector3.new(-60, 6, -8),
			size = Vector3.new(60, 12, 10),
			color = Color3.fromRGB(96, 88, 78),
		},
		{
			position = Vector3.new(0, 6, 44),
			size = Vector3.new(60, 12, 10),
			color = Color3.fromRGB(96, 88, 78),
		},
		-- Graveyard dressing, in the lane-free centre-west pocket: the
		-- zombies walk home through their own churchyard. The crypt and
		-- every stone sit clear of both lanes and both plateaus.
		{
			position = Vector3.new(-120, 4.5, 0),
			size = Vector3.new(2, 9, 2),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-120, 8, 1.5),
			size = Vector3.new(1.2, 1.2, 4),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-90, 4.5, -40),
			size = Vector3.new(2, 9, 2),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-90, 8, -38.5),
			size = Vector3.new(1.2, 1.2, 4),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-130, 4.5, 50),
			size = Vector3.new(2, 9, 2),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-130, 8, 51.5),
			size = Vector3.new(1.2, 1.2, 4),
			color = Color3.fromRGB(66, 56, 48),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-100, 2.2, 20),
			size = Vector3.new(3, 4, 0.8),
			color = Color3.fromRGB(130, 132, 140),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-85, 2.2, 45),
			size = Vector3.new(3, 4, 0.8),
			color = Color3.fromRGB(130, 132, 140),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-115, 2.2, -25),
			size = Vector3.new(3, 4, 0.8),
			color = Color3.fromRGB(130, 132, 140),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-70, 2.2, 10),
			size = Vector3.new(3, 4, 0.8),
			color = Color3.fromRGB(130, 132, 140),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-102, 2.2, -8),
			size = Vector3.new(3, 4, 0.8),
			color = Color3.fromRGB(130, 132, 140),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-10, 4, 60),
			size = Vector3.new(12, 8, 10),
			color = Color3.fromRGB(84, 84, 96),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-10, 8.6, 60),
			size = Vector3.new(14, 1.2, 12),
			color = Color3.fromRGB(70, 70, 82),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(120, 2.0, -60),
			size = Vector3.new(7, 4, 6),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(118, 1.5, 66),
			size = Vector3.new(5, 3, 5),
			color = Color3.fromRGB(118, 120, 124),
			material = Enum.Material.Slate,
		},
		{
			position = Vector3.new(-40, 2.4, -140),
			size = Vector3.new(22, 3, 0.6),
			color = Color3.fromRGB(96, 90, 84),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(0, 2.4, -140),
			size = Vector3.new(22, 3, 0.6),
			color = Color3.fromRGB(96, 90, 84),
			material = Enum.Material.Wood,
		},
		-- Two spawn markers, one per lane.
		{
			position = Vector3.new(-152, 6, -90),
			size = Vector3.new(6, 12, 26),
			color = Color3.fromRGB(150, 60, 60),
		},
		{
			position = Vector3.new(-152, 6, 90),
			size = Vector3.new(6, 12, 26),
			color = Color3.fromRGB(150, 60, 60),
		},
	},

	groundSize = Vector3.new(340, 4, 320),
	groundColor = Color3.fromRGB(76, 76, 88),
}

return map

--!strict
--[[
	Bastion - the surrounded one.

	The base sits in the CENTRE, and two lanes close on it from opposite
	edges like a pincer. Fork also runs two lanes, but both arrive from the
	same side; here the two fronts face away from each other, so no single
	killzone covers both and rotating attention is the whole game.

	Lane lengths differ - 350 north, 415 south - for the same reason Fork's
	do (ARCHITECTURE.md D8): distance REMAINING is what orders targeting,
	and unequal lanes are what keep that honest rather than theoretical.

	The two plateaus sit just inside each approach, close enough to the
	centre that a Hillside tower on one can lean across to help the other
	front - at its longest range, and only just. That overlap is the entire
	economy of the map.
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pads = require(script.Parent.Pads)

local map: Types.MapConfig = {
	id = "Bastion",
	displayName = "Bastion",

	paths = {
		{
			-- North pincer: 70 + 160 + 60 + 60 = 350 studs.
			waypoints = {
				Vector3.new(-100, 0, -140),
				Vector3.new(-100, 0, -70),
				Vector3.new(60, 0, -70),
				Vector3.new(60, 0, -10),
				Vector3.new(0, 0, -10),
			},
		},
		{
			-- South pincer, longer at 60 + 190 + 75 + 90 = 415 studs.
			waypoints = {
				Vector3.new(100, 0, 150),
				Vector3.new(100, 0, 90),
				Vector3.new(-90, 0, 90),
				Vector3.new(-90, 0, 15),
				Vector3.new(0, 0, 15),
			},
		},
	},

	basePosition = Vector3.new(0, 0, 0),

	buildableSurfaces = {
		Pads.ground(0, 0, 320, 320),

		-- One plateau per approach, just inside the elbow. Their edges sit a
		-- stud outside PATH_CLEARANCE of the horizontal runs, so the far row
		-- of a plateau is legal and the near row is a tease.
		Pads.elevated(0, -45, 50, 30),
		Pads.elevated(0, 45, 50, 30),
	},

	decor = {
		-- Corner watchtowers, so the fortress premise is visible from spawn.
		-- At +/-160 with a 12-stud footprint they clear the +/-146 corner
		-- candidates MapBuilder's spawn derivation picks from - at +/-150
		-- the northeast one swallowed the spawn pad whole.
		{
			position = Vector3.new(-160, 10, -160),
			size = Vector3.new(12, 20, 12),
			color = Color3.fromRGB(84, 92, 84),
		},
		{
			position = Vector3.new(160, 10, -160),
			size = Vector3.new(12, 20, 12),
			color = Color3.fromRGB(84, 92, 84),
		},
		{
			position = Vector3.new(-160, 10, 160),
			size = Vector3.new(12, 20, 12),
			color = Color3.fromRGB(84, 92, 84),
		},
		{
			position = Vector3.new(160, 10, 160),
			size = Vector3.new(12, 20, 12),
			color = Color3.fromRGB(84, 92, 84),
		},
		-- Spawn markers, one per pincer.
		{
			position = Vector3.new(-100, 6, -144),
			size = Vector3.new(26, 12, 6),
			color = Color3.fromRGB(150, 60, 60),
		},
		{
			position = Vector3.new(100, 6, 154),
			size = Vector3.new(26, 12, 6),
			color = Color3.fromRGB(150, 60, 60),
		},
	},

	groundSize = Vector3.new(340, 4, 340),
	groundColor = Color3.fromRGB(72, 88, 76),
}

return map

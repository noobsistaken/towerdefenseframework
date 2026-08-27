--!strict
--[[
	Bastion - the surrounded one.

	The base sits in the CENTRE, and two lanes close on it from opposite
	edges like a pincer, facing away from each other - so no single killzone
	covers both fronts and rotating attention is the whole game. That is the
	half of the design space Crossroads does not occupy: there a single
	folded lane rewards one well-chosen overlap, here nothing covers
	everything and the question is what you leave uncovered.

	Lane lengths differ deliberately - 350 north, 415 south (ARCHITECTURE.md
	D8): distance REMAINING is what orders targeting, and unequal lanes are
	what keep that honest rather than theoretical.

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
		-- Fortress dressing: curtain walls run the edges between the
		-- watchtowers (the lanes START inside them, so no gate is needed),
		-- banners flank the two plateaus, braziers burn at the keep.
		{
			position = Vector3.new(164, 6, 0),
			size = Vector3.new(5, 12, 120),
			color = Color3.fromRGB(84, 92, 84),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-164, 6, 0),
			size = Vector3.new(5, 12, 120),
			color = Color3.fromRGB(84, 92, 84),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(0, 6, -164),
			size = Vector3.new(120, 12, 5),
			color = Color3.fromRGB(84, 92, 84),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(0, 6, 164),
			size = Vector3.new(120, 12, 5),
			color = Color3.fromRGB(84, 92, 84),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(35, 4.5, -45),
			size = Vector3.new(0.8, 9, 0.8),
			color = Color3.fromRGB(70, 62, 54),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(35, 6.5, -43.4),
			size = Vector3.new(0.4, 5, 2.6),
			color = Color3.fromRGB(168, 62, 62),
		},
		{
			position = Vector3.new(-35, 4.5, 45),
			size = Vector3.new(0.8, 9, 0.8),
			color = Color3.fromRGB(70, 62, 54),
			material = Enum.Material.Wood,
		},
		{
			position = Vector3.new(-35, 6.5, 46.6),
			size = Vector3.new(0.4, 5, 2.6),
			color = Color3.fromRGB(168, 62, 62),
		},
		{
			position = Vector3.new(16, 1.5, 16),
			size = Vector3.new(2.2, 3, 2.2),
			color = Color3.fromRGB(62, 58, 54),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(16, 3.6, 16),
			size = Vector3.new(1.6, 1.6, 1.6),
			color = Color3.fromRGB(236, 140, 58),
			material = Enum.Material.Neon,
		},
		{
			position = Vector3.new(-16, 1.5, -16),
			size = Vector3.new(2.2, 3, 2.2),
			color = Color3.fromRGB(62, 58, 54),
			material = Enum.Material.Concrete,
		},
		{
			position = Vector3.new(-16, 3.6, -16),
			size = Vector3.new(1.6, 1.6, 1.6),
			color = Color3.fromRGB(236, 140, 58),
			material = Enum.Material.Neon,
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

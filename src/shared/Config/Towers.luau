--!strict
--[[
	Tower roster.

	Adding a tower means adding an entry here. It needs a behaviour module
	under src/match/server/Entities/Towers/ only if it does something
	BaseTower cannot express - which, of the six below, is true of exactly
	two: Mortar and Flak need splash, and Lacerator needs to apply an effect.
	The other three are pure config.

	`levels[i].cost` is the cost to REACH level i, not a running total. Index 1
	is therefore the purchase price and later indices are upgrade prices. The
	sell refund is computed from the sum of what was actually paid, so a
	fully upgraded tower refunds against its true investment rather than its
	base price.

	Placement categories map onto surface tags:
	    Ground   -> surfaces tagged Ground
	    Hillside -> surfaces tagged Elevated
	    Hybrid   -> either
	Hillside towers are the ones that can hit air, which is what makes an
	elevated plateau worth holding.
]]

local Types = require(script.Parent.Parent.Types)

local Towers = {}

local DEFINITIONS: { [string]: Types.TowerDefinition } = {
	-- -----------------------------------------------------------------------
	-- Ground
	-- -----------------------------------------------------------------------

	Rifleman = {
		id = "Rifleman",
		displayName = "Rifleman",
		description = "Cheap, reliable single-target fire. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 150,
				damage = 8,
				fireRate = 1.6,
				range = 42,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(4, 6, 4),
				color = Color3.fromRGB(120, 132, 148),
			},
			{
				cost = 120,
				damage = 14,
				fireRate = 1.8,
				range = 46,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(4, 7, 4),
				color = Color3.fromRGB(134, 148, 166),
			},
			{
				cost = 220,
				damage = 24,
				fireRate = 2,
				range = 50,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(4.5, 8, 4.5),
				color = Color3.fromRGB(150, 166, 186),
			},
			{
				cost = 400,
				damage = 40,
				fireRate = 2.2,
				range = 54,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5, 9, 5),
				color = Color3.fromRGB(168, 186, 208),
			},
			{
				cost = 750,
				damage = 68,
				fireRate = 2.5,
				range = 60,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5.5, 10, 5.5),
				color = Color3.fromRGB(196, 214, 236),
			},
		},
	},

	Mortar = {
		id = "Mortar",
		displayName = "Mortar",
		description = "Slow, heavy splash that concusses what survives. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(9, 9),
		-- Splash wants the densest part of the lane, and the enemy furthest
		-- along is usually leading the pack rather than sitting in it.
		defaultTargeting = "Last" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 400,
				damage = 30,
				fireRate = 0.5,
				range = 70,
				splashRadius = 14,
				applies = { { effectId = "Slow", duration = 1.5, power = 0 } },
				modelSize = Vector3.new(7, 5, 7),
				color = Color3.fromRGB(96, 104, 88),
			},
			{
				cost = 550,
				damage = 55,
				fireRate = 0.55,
				range = 76,
				splashRadius = 16,
				applies = { { effectId = "Slow", duration = 2, power = 0 } },
				modelSize = Vector3.new(7.5, 5.5, 7.5),
				color = Color3.fromRGB(110, 120, 100),
			},
			{
				cost = 1000,
				damage = 105,
				fireRate = 0.6,
				range = 82,
				splashRadius = 19,
				applies = { { effectId = "Slow", duration = 2.5, power = 0 } },
				modelSize = Vector3.new(8, 6, 8),
				color = Color3.fromRGB(126, 138, 114),
			},
		},
	},

	-- -----------------------------------------------------------------------
	-- Hillside - elevated placement only, and the answer to air
	-- -----------------------------------------------------------------------

	Marksman = {
		id = "Marksman",
		displayName = "Marksman",
		description = "Extreme range, heavy single hits. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 350,
				damage = 45,
				fireRate = 0.6,
				range = 95,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5, 9, 5),
				color = Color3.fromRGB(84, 96, 120),
			},
			{
				cost = 300,
				damage = 80,
				fireRate = 0.7,
				range = 105,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5, 10, 5),
				color = Color3.fromRGB(96, 112, 142),
			},
			{
				cost = 600,
				damage = 145,
				fireRate = 0.8,
				range = 115,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5.5, 11, 5.5),
				color = Color3.fromRGB(110, 130, 166),
			},
			{
				cost = 1200,
				damage = 260,
				fireRate = 0.9,
				range = 130,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(6, 12.5, 6),
				color = Color3.fromRGB(128, 152, 194),
			},
		},
	},

	Flak = {
		id = "Flak",
		displayName = "Flak",
		description = "Rapid bursting splash, built for swarms and air. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(8, 8),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 300,
				damage = 18,
				fireRate = 1.2,
				range = 60,
				splashRadius = 10,
				applies = {},
				modelSize = Vector3.new(6, 6, 6),
				color = Color3.fromRGB(150, 120, 72),
			},
			{
				cost = 400,
				damage = 32,
				fireRate = 1.4,
				range = 66,
				splashRadius = 12,
				applies = {},
				modelSize = Vector3.new(6.5, 7, 6.5),
				color = Color3.fromRGB(170, 138, 84),
			},
			{
				cost = 800,
				damage = 58,
				fireRate = 1.6,
				range = 72,
				splashRadius = 14,
				applies = {},
				modelSize = Vector3.new(7, 8, 7),
				color = Color3.fromRGB(194, 158, 98),
			},
		},
	},

	-- -----------------------------------------------------------------------
	-- Hybrid - place anywhere, hit anything, excel at nothing
	-- -----------------------------------------------------------------------

	Ranger = {
		id = "Ranger",
		displayName = "Ranger",
		description = "Balanced all-rounder. Places anywhere, hits anything.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 250,
				damage = 16,
				fireRate = 1.1,
				range = 55,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(4.5, 7, 4.5),
				color = Color3.fromRGB(88, 140, 104),
			},
			{
				cost = 220,
				damage = 28,
				fireRate = 1.2,
				range = 60,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(4.5, 8, 4.5),
				color = Color3.fromRGB(100, 158, 118),
			},
			{
				cost = 450,
				damage = 50,
				fireRate = 1.35,
				range = 66,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5, 9, 5),
				color = Color3.fromRGB(114, 178, 134),
			},
			{
				cost = 900,
				damage = 90,
				fireRate = 1.5,
				range = 72,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.new(5.5, 10, 5.5),
				color = Color3.fromRGB(132, 200, 152),
			},
		},
	},

	Lacerator = {
		id = "Lacerator",
		displayName = "Lacerator",
		description = "Light hits that stack a bleed. Damage arrives late but ignores armour of any kind.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		-- First, so its stacks land on whatever is closest to leaking and get
		-- the most time to tick before that happens.
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			{
				cost = 275,
				damage = 10,
				fireRate = 1.3,
				range = 50,
				splashRadius = 0,
				applies = { { effectId = "Bleed", duration = 4, power = 3 } },
				modelSize = Vector3.new(4.5, 7, 4.5),
				color = Color3.fromRGB(150, 72, 88),
			},
			{
				cost = 250,
				damage = 16,
				fireRate = 1.4,
				range = 54,
				splashRadius = 0,
				applies = { { effectId = "Bleed", duration = 4.5, power = 5 } },
				modelSize = Vector3.new(4.5, 8, 4.5),
				color = Color3.fromRGB(168, 82, 100),
			},
			{
				cost = 500,
				damage = 26,
				fireRate = 1.5,
				range = 58,
				splashRadius = 0,
				applies = { { effectId = "Bleed", duration = 5, power = 8 } },
				modelSize = Vector3.new(5, 9, 5),
				color = Color3.fromRGB(190, 94, 114),
			},
			{
				cost = 950,
				damage = 44,
				fireRate = 1.6,
				range = 64,
				splashRadius = 0,
				applies = { { effectId = "Bleed", duration = 6, power = 13 } },
				modelSize = Vector3.new(5.5, 10, 5.5),
				color = Color3.fromRGB(212, 108, 130),
			},
		},
	},
}

Towers.DEFINITIONS = DEFINITIONS

--- Sorted, so shop order is stable across servers. A pairs() order is not.
local sortedIds: { string } = {}

for id in DEFINITIONS do
	table.insert(sortedIds, id)
end

table.sort(sortedIds)

Towers.IDS = table.freeze(sortedIds)

--- Non-throwing lookup. Tower ids arrive from clients, so the placement path
--- uses this and rejects nil rather than erroring on a forged id.
function Towers.find(id: string): Types.TowerDefinition?
	return DEFINITIONS[id]
end

function Towers.get(id: string): Types.TowerDefinition
	local definition = DEFINITIONS[id]

	if definition == nil then
		error(`Towers.get: no tower definition with id "{id}"`)
	end

	return definition
end

--- Level data, or nil if `level` is out of range for this tower.
function Towers.levelAt(definition: Types.TowerDefinition, level: number): Types.TowerLevel?
	return definition.levels[level]
end

function Towers.maxLevel(definition: Types.TowerDefinition): number
	return #definition.levels
end

--- Whether this tower may stand on a surface with the given tag.
function Towers.acceptsSurface(definition: Types.TowerDefinition, surface: Types.SurfaceType): boolean
	if definition.category == "Hybrid" then
		return true
	end

	if definition.category == "Ground" then
		return surface == "Ground"
	end

	return surface == "Elevated"
end

--- Whether this tower may shoot the given enemy class.
function Towers.canTarget(definition: Types.TowerDefinition, enemy: Types.EnemyCategory): boolean
	if definition.targets == "Both" then
		return true
	end

	return definition.targets == enemy
end

return Towers

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

--- Compact level constructor for the expanded roster. The first six
--- towers predate it and stay verbatim; everything after uses this,
--- because twenty towers of hand-written level tables is how a typo
--- ships. Argument order mirrors the field order the verbatim tables use.
local function makeLevel(
	cost: number,
	damage: number,
	fireRate: number,
	range: number,
	splashRadius: number,
	applies: { Types.StatusApplication },
	modelSize: Vector3,
	color: Color3
): Types.TowerLevel
	return {
		cost = cost,
		damage = damage,
		fireRate = fireRate,
		range = range,
		splashRadius = splashRadius,
		applies = applies,
		modelSize = modelSize,
		color = color,
	}
end

local DEFINITIONS: { [string]: Types.TowerDefinition } = {
	-- -----------------------------------------------------------------------
	-- Ground
	-- -----------------------------------------------------------------------

	Rifleman = {
		id = "Rifleman",
		displayName = "Rifleman",
		rarity = "Common",
		description = "Cheap, reliable single-target fire. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		ability = {
			id = "RapidFire",
			displayName = "Rapid Fire",
			description = "Double fire rate for six seconds.",
			kind = "Overcharge" :: Types.TowerAbilityKind,
			cooldownSeconds = 30,
			power = 2,
			strikes = 0,
			durationSeconds = 6,
		},
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
		rarity = "Uncommon",
		description = "Slow, heavy splash that concusses what survives. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(9, 9),
		-- Splash wants the densest part of the lane, and the enemy furthest
		-- along is usually leading the pack rather than sitting in it.
		defaultTargeting = "Last" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "SwatSoldier",
		ability = {
			id = "ShellStorm",
			displayName = "Shell Storm",
			description = "Five instant shells on the closest enemies.",
			kind = "Barrage" :: Types.TowerAbilityKind,
			cooldownSeconds = 45,
			power = 60,
			strikes = 5,
			durationSeconds = 0,
		},
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
		rarity = "Legendary",
		description = "Extreme range, heavy single hits. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "VDVSoldier",
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
		rarity = "Epic",
		description = "Rapid bursting splash, built for swarms and air. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(8, 8),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "WinterSoldier",
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
		rarity = "Common",
		description = "Balanced all-rounder. Places anywhere, hits anything.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmySoldier2",
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
		rarity = "Rare",
		description = "Light hits that stack a bleed. Damage arrives late but ignores armour of any kind.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		-- First, so its stacks land on whatever is closest to leaking and get
		-- the most time to tick before that happens.
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ToySoldier",
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
	-- -----------------------------------------------------------------------
	-- The expanded roster. Twenty towers, distributed pyramid-style across
	-- the rarity ladder; every one is pure config - splash and status
	-- behaviour derive from the numbers below, never from new code.
	-- -----------------------------------------------------------------------

	-- Commons: one clear job each, cheaply.

	Scout = {
		id = "Scout",
		displayName = "Scout",
		rarity = "Common",
		description = "Fast, cheap chip damage anywhere. The first thing worth placing.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(5, 5),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			makeLevel(100, 4, 2.2, 38, 0, {}, Vector3.new(3.5, 5.5, 3.5), Color3.fromRGB(186, 172, 138)),
			makeLevel(90, 7, 2.4, 41, 0, {}, Vector3.new(4, 6, 4), Color3.fromRGB(198, 186, 152)),
			makeLevel(170, 12, 2.6, 44, 0, {}, Vector3.new(4, 6.5, 4), Color3.fromRGB(212, 202, 170)),
		},
	},
	Shotgunner = {
		id = "Shotgunner",
		displayName = "Shotgunner",
		rarity = "Common",
		description = "Brutal up close, useless at distance. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "Closest" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmySoldier2",
		levels = {
			makeLevel(200, 22, 0.9, 28, 0, {}, Vector3.new(4, 6, 4), Color3.fromRGB(158, 122, 92)),
			makeLevel(180, 38, 1.0, 30, 0, {}, Vector3.new(4.5, 7, 4.5), Color3.fromRGB(172, 134, 100)),
			makeLevel(340, 68, 1.1, 33, 0, {}, Vector3.new(5, 8, 5), Color3.fromRGB(188, 148, 110)),
		},
	},
	Slinger = {
		id = "Slinger",
		displayName = "Slinger",
		rarity = "Common",
		description = "The budget answer to air. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(5, 5),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ToySoldier",
		levels = {
			makeLevel(180, 9, 1.5, 55, 0, {}, Vector3.new(4, 6, 4), Color3.fromRGB(122, 148, 170)),
			makeLevel(160, 15, 1.6, 60, 0, {}, Vector3.new(4, 6.5, 4), Color3.fromRGB(134, 162, 186)),
			makeLevel(300, 27, 1.8, 66, 0, {}, Vector3.new(4.5, 7, 4.5), Color3.fromRGB(148, 178, 204)),
		},
	},
	Watchman = {
		id = "Watchman",
		displayName = "Watchman",
		rarity = "Common",
		description = "Sees far, hits light. Buys reach before you can afford real range.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "VDVSoldier",
		ability = {
			id = "BountyMark",
			displayName = "Bounty Mark",
			description = "Calls in cash, worth more the deeper the run.",
			kind = "Payday" :: Types.TowerAbilityKind,
			cooldownSeconds = 60,
			power = 60,
			strikes = 0,
			durationSeconds = 0,
		},
		levels = {
			makeLevel(220, 12, 1.1, 70, 0, {}, Vector3.new(4, 7, 4), Color3.fromRGB(128, 138, 128)),
			makeLevel(200, 20, 1.2, 76, 0, {}, Vector3.new(4.5, 8, 4.5), Color3.fromRGB(140, 152, 140)),
			makeLevel(380, 34, 1.3, 84, 0, {}, Vector3.new(5, 9, 5), Color3.fromRGB(154, 168, 154)),
		},
	},
	Grenadier = {
		id = "Grenadier",
		displayName = "Grenadier",
		rarity = "Common",
		description = "Small, honest splash on a small, honest budget. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "Last" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "SwatSoldier",
		levels = {
			makeLevel(250, 14, 0.8, 48, 8, {}, Vector3.new(5, 5.5, 5), Color3.fromRGB(130, 122, 96)),
			makeLevel(220, 24, 0.85, 52, 9, {}, Vector3.new(5.5, 6, 5.5), Color3.fromRGB(142, 134, 104)),
			makeLevel(420, 42, 0.9, 56, 11, {}, Vector3.new(6, 6.5, 6), Color3.fromRGB(156, 148, 114)),
		},
	},

	-- Uncommons: a real specialisation each.

	Gunner = {
		id = "Gunner",
		displayName = "Gunner",
		rarity = "Uncommon",
		description = "Sustained automatic fire. Ground only, and never stops.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmyNoobSoldier",
		levels = {
			makeLevel(450, 12, 3.2, 44, 0, {}, Vector3.new(4.5, 6, 4.5), Color3.fromRGB(110, 116, 130)),
			makeLevel(380, 20, 3.5, 48, 0, {}, Vector3.new(5, 6.5, 5), Color3.fromRGB(122, 130, 146)),
			makeLevel(700, 34, 3.8, 52, 0, {}, Vector3.new(5, 7, 5), Color3.fromRGB(136, 146, 164)),
			makeLevel(1200, 58, 4.0, 56, 0, {}, Vector3.new(5.5, 8, 5.5), Color3.fromRGB(152, 164, 184)),
		},
	},
	Frostcaster = {
		id = "Frostcaster",
		displayName = "Frostcaster",
		rarity = "Uncommon",
		description = "Light hits that chill everything they touch. The damage is the excuse.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 6,
		rig = "WinterSoldier",
		ability = {
			id = "DeepFreeze",
			displayName = "Deep Freeze",
			description = "Stuns everything in range for a moment.",
			kind = "FreezeBurst" :: Types.TowerAbilityKind,
			cooldownSeconds = 40,
			power = 0,
			strikes = 0,
			durationSeconds = 1.2,
			effectId = "Concuss",
		},
		levels = {
			makeLevel(
				400,
				8,
				1.0,
				55,
				0,
				{ { effectId = "Slow", duration = 2, power = 0 } },
				Vector3.new(4.5, 7, 4.5),
				Color3.fromRGB(152, 196, 220)
			),
			makeLevel(
				350,
				13,
				1.1,
				60,
				0,
				{ { effectId = "Slow", duration = 2.5, power = 0 } },
				Vector3.new(5, 8, 5),
				Color3.fromRGB(166, 208, 230)
			),
			makeLevel(
				650,
				22,
				1.2,
				66,
				0,
				{ { effectId = "Slow", duration = 3, power = 0 } },
				Vector3.new(5.5, 9, 5.5),
				Color3.fromRGB(182, 220, 240)
			),
		},
	},
	Skirmisher = {
		id = "Skirmisher",
		displayName = "Skirmisher",
		rarity = "Uncommon",
		description = "A Ranger that traded its air coverage for a harder punch.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "ArmySoldier2",
		levels = {
			makeLevel(350, 18, 1.7, 50, 0, {}, Vector3.new(4.5, 7, 4.5), Color3.fromRGB(104, 132, 96)),
			makeLevel(300, 30, 1.8, 54, 0, {}, Vector3.new(5, 8, 5), Color3.fromRGB(114, 146, 106)),
			makeLevel(560, 52, 2.0, 58, 0, {}, Vector3.new(5.5, 9, 5.5), Color3.fromRGB(126, 162, 118)),
		},
	},
	Flaresman = {
		id = "Flaresman",
		displayName = "Flaresman",
		rarity = "Uncommon",
		description = "Shoots ONLY air, and punishes it for existing. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Air" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "VDVSoldier",
		levels = {
			makeLevel(300, 26, 1.3, 65, 0, {}, Vector3.new(4.5, 8, 4.5), Color3.fromRGB(190, 110, 90)),
			makeLevel(260, 42, 1.4, 70, 0, {}, Vector3.new(5, 9, 5), Color3.fromRGB(204, 122, 100)),
			makeLevel(500, 74, 1.5, 76, 0, {}, Vector3.new(5.5, 10, 5.5), Color3.fromRGB(220, 136, 112)),
		},
	},

	-- Rares: the mid-game backbone.

	Autocannon = {
		id = "Autocannon",
		displayName = "Autocannon",
		rarity = "Rare",
		description = "Rapid bursting shells. What Flak grows up wanting to be. Elevated only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "Cat6Heavy",
		levels = {
			makeLevel(700, 20, 1.8, 58, 8, {}, Vector3.new(6, 6, 6), Color3.fromRGB(96, 108, 122)),
			makeLevel(600, 33, 2.0, 62, 9, {}, Vector3.new(6.5, 6.5, 6.5), Color3.fromRGB(106, 120, 136)),
			makeLevel(1100, 56, 2.2, 68, 11, {}, Vector3.new(7, 7, 7), Color3.fromRGB(118, 134, 152)),
		},
	},
	Hexer = {
		id = "Hexer",
		displayName = "Hexer",
		rarity = "Rare",
		description = "Marks the strongest enemy to take extra damage from EVERYTHING.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 6,
		rig = "ToySoldier",
		levels = {
			makeLevel(
				500,
				10,
				1.2,
				52,
				0,
				{ { effectId = "Sunder", duration = 3, power = 0 } },
				Vector3.new(4.5, 7.5, 4.5),
				Color3.fromRGB(148, 104, 178)
			),
			makeLevel(
				450,
				16,
				1.3,
				56,
				0,
				{ { effectId = "Sunder", duration = 3.5, power = 0 } },
				Vector3.new(5, 8.5, 5),
				Color3.fromRGB(160, 116, 190)
			),
			makeLevel(
				850,
				27,
				1.4,
				62,
				0,
				{ { effectId = "Sunder", duration = 4, power = 0 } },
				Vector3.new(5.5, 9.5, 5.5),
				Color3.fromRGB(174, 130, 204)
			),
		},
	},
	Marauder = {
		id = "Marauder",
		displayName = "Marauder",
		rarity = "Rare",
		description = "Heavy rounds for heavy targets. Hunts the strongest thing it can see.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 0,
		rig = "InsurgentRaider",
		levels = {
			makeLevel(600, 34, 1.6, 48, 0, {}, Vector3.new(5, 7, 5), Color3.fromRGB(132, 106, 84)),
			makeLevel(500, 55, 1.7, 52, 0, {}, Vector3.new(5.5, 8, 5.5), Color3.fromRGB(146, 116, 92)),
			makeLevel(950, 92, 1.8, 56, 0, {}, Vector3.new(6, 9, 6), Color3.fromRGB(160, 128, 100)),
			makeLevel(1700, 170, 1.9, 60, 0, {}, Vector3.new(6.5, 10, 6.5), Color3.fromRGB(176, 142, 110)),
		},
	},
	Longbow = {
		id = "Longbow",
		displayName = "Longbow",
		rarity = "Rare",
		description = "Marksman range on a working budget. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 8,
		rig = "ToySoldier",
		levels = {
			makeLevel(550, 48, 0.9, 100, 0, {}, Vector3.new(4.5, 8.5, 4.5), Color3.fromRGB(96, 124, 112)),
			makeLevel(480, 78, 0.95, 108, 0, {}, Vector3.new(5, 9.5, 5), Color3.fromRGB(106, 138, 124)),
			makeLevel(900, 130, 1.0, 116, 0, {}, Vector3.new(5.5, 10.5, 5.5), Color3.fromRGB(118, 154, 138)),
		},
	},

	-- Epics: build-defining.

	Pyromancer = {
		id = "Pyromancer",
		displayName = "Pyromancer",
		rarity = "Epic",
		description = "Sets the lane on fire and lets the fire do the arguing. Ground targets.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 6,
		rig = "SwatSoldier",
		levels = {
			makeLevel(
				800,
				16,
				1.4,
				50,
				0,
				{ { effectId = "Burn", duration = 3, power = 6 } },
				Vector3.new(5, 8, 5),
				Color3.fromRGB(216, 118, 62)
			),
			makeLevel(
				700,
				26,
				1.5,
				54,
				0,
				{ { effectId = "Burn", duration = 3.5, power = 10 } },
				Vector3.new(5.5, 9, 5.5),
				Color3.fromRGB(228, 132, 72)
			),
			makeLevel(
				1300,
				44,
				1.6,
				60,
				0,
				{ { effectId = "Burn", duration = 4, power = 16 } },
				Vector3.new(6, 10, 6),
				Color3.fromRGB(240, 148, 84)
			),
		},
	},
	Railgunner = {
		id = "Railgunner",
		displayName = "Railgunner",
		rarity = "Epic",
		description = "One enormous hit at a time, from very far away. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 6,
		rig = "Cat6Sniper",
		ability = {
			id = "CoilSurge",
			displayName = "Coil Surge",
			description = "Two-and-a-half times fire rate for five seconds.",
			kind = "Overcharge" :: Types.TowerAbilityKind,
			cooldownSeconds = 45,
			power = 2.5,
			strikes = 0,
			durationSeconds = 5,
		},
		levels = {
			makeLevel(1000, 130, 0.75, 90, 0, {}, Vector3.new(6, 8, 6), Color3.fromRGB(84, 110, 140)),
			makeLevel(850, 210, 0.8, 98, 0, {}, Vector3.new(6.5, 9, 6.5), Color3.fromRGB(94, 124, 158)),
			makeLevel(1600, 380, 0.85, 106, 0, {}, Vector3.new(7, 10, 7), Color3.fromRGB(106, 140, 178)),
		},
	},
	Warden = {
		id = "Warden",
		displayName = "Warden",
		rarity = "Epic",
		description = "Hits hard enough to stop things mid-step. Briefly. Ground only.",
		category = "Ground" :: Types.TowerCategory,
		targets = "Ground" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 4,
		rig = "SwatSoldier",
		levels = {
			-- Stun durations sit under the FASTEST reload any trait can buy
			-- (fireRate x1.3 Godslayer), so a permanent freeze is impossible
			-- by arithmetic - TowerBalance.spec enforces the inequality.
			makeLevel(
				900,
				28,
				1.1,
				46,
				0,
				{ { effectId = "Concuss", duration = 0.35, power = 0 } },
				Vector3.new(5.5, 7.5, 5.5),
				Color3.fromRGB(196, 186, 120)
			),
			makeLevel(
				800,
				46,
				1.15,
				50,
				0,
				{ { effectId = "Concuss", duration = 0.4, power = 0 } },
				Vector3.new(6, 8.5, 6),
				Color3.fromRGB(208, 198, 132)
			),
			makeLevel(
				1500,
				78,
				1.2,
				54,
				0,
				{ { effectId = "Concuss", duration = 0.45, power = 0 } },
				Vector3.new(6.5, 9.5, 6.5),
				Color3.fromRGB(222, 212, 146)
			),
		},
	},

	-- Legendaries: the ones a lobby notices.

	Stormcaller = {
		id = "Stormcaller",
		displayName = "Stormcaller",
		rarity = "Legendary",
		description = "Wide, freezing detonations across half the lane. Elevated ground only.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(8, 8),
		defaultTargeting = "Last" :: Types.TargetingMode,
		perPlayerCap = 4,
		rig = "WinterSoldier",
		ability = {
			id = "Whiteout",
			displayName = "Whiteout",
			description = "A deep slow on everything in range.",
			kind = "FreezeBurst" :: Types.TowerAbilityKind,
			cooldownSeconds = 40,
			power = 0,
			strikes = 0,
			durationSeconds = 4,
			effectId = "Slow",
		},
		levels = {
			makeLevel(
				1400,
				60,
				0.9,
				72,
				16,
				{ { effectId = "Slow", duration = 1.5, power = 0 } },
				Vector3.new(6.5, 9, 6.5),
				Color3.fromRGB(110, 150, 200)
			),
			makeLevel(
				1200,
				100,
				0.95,
				78,
				18,
				{ { effectId = "Slow", duration = 2, power = 0 } },
				Vector3.new(7, 10, 7),
				Color3.fromRGB(124, 164, 214)
			),
			makeLevel(
				2200,
				170,
				1.0,
				84,
				20,
				{ { effectId = "Slow", duration = 2.5, power = 0 } },
				Vector3.new(7.5, 11, 7.5),
				Color3.fromRGB(140, 180, 228)
			),
		},
	},
	Executioner = {
		id = "Executioner",
		displayName = "Executioner",
		rarity = "Legendary",
		description = "Finds the strongest thing on the map and deletes it. Anywhere, anything.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 4,
		rig = "VDVSoldier",
		levels = {
			makeLevel(1200, 150, 0.8, 60, 0, {}, Vector3.new(5, 9, 5), Color3.fromRGB(90, 84, 96)),
			makeLevel(1000, 240, 0.85, 65, 0, {}, Vector3.new(5.5, 10, 5.5), Color3.fromRGB(102, 96, 110)),
			makeLevel(1900, 430, 0.9, 70, 0, {}, Vector3.new(6, 11, 6), Color3.fromRGB(116, 108, 124)),
			makeLevel(3200, 700, 1.0, 76, 0, {}, Vector3.new(6.5, 12, 6.5), Color3.fromRGB(132, 122, 140)),
		},
	},

	-- Mythic: the reason to keep rolling.

	Annihilator = {
		id = "Annihilator",
		displayName = "Annihilator",
		rarity = "Mythic",
		description = "Burning shells the size of rooms. Elevated ground only, mercifully.",
		category = "Hillside" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(9, 9),
		defaultTargeting = "Last" :: Types.TargetingMode,
		perPlayerCap = 4,
		rig = "Cat6Specialist",
		levels = {
			makeLevel(
				2200,
				120,
				1.1,
				66,
				14,
				{ { effectId = "Burn", duration = 2.5, power = 8 } },
				Vector3.new(7, 8, 7),
				Color3.fromRGB(180, 84, 64)
			),
			makeLevel(
				1800,
				190,
				1.2,
				72,
				16,
				{ { effectId = "Burn", duration = 3, power = 12 } },
				Vector3.new(7.5, 9, 7.5),
				Color3.fromRGB(196, 96, 72)
			),
			makeLevel(
				3400,
				320,
				1.3,
				78,
				18,
				{ { effectId = "Burn", duration = 3.5, power = 18 } },
				Vector3.new(8, 10, 8),
				Color3.fromRGB(214, 110, 82)
			),
		},
	},

	-- Secret: the chase.

	Godhand = {
		id = "Godhand",
		displayName = "Godhand",
		rarity = "Secret",
		description = "There is a 0.7% chance the toy soldier was the strongest one all along.",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(7, 7),
		defaultTargeting = "Strongest" :: Types.TargetingMode,
		perPlayerCap = 2,
		rig = "ToySoldier",
		ability = {
			id = "DivineJudgment",
			displayName = "Divine Judgment",
			description = "Ten instant strikes on the closest enemies.",
			kind = "Barrage" :: Types.TowerAbilityKind,
			cooldownSeconds = 60,
			power = 200,
			strikes = 10,
			durationSeconds = 0,
		},
		levels = {
			makeLevel(2500, 210, 1.5, 80, 0, {}, Vector3.new(5.5, 10, 5.5), Color3.fromRGB(236, 200, 96)),
			makeLevel(2000, 330, 1.6, 86, 0, {}, Vector3.new(6, 11, 6), Color3.fromRGB(242, 210, 110)),
			makeLevel(3800, 560, 1.7, 92, 0, {}, Vector3.new(6.5, 12, 6.5), Color3.fromRGB(248, 222, 126)),
			makeLevel(6000, 950, 1.8, 100, 0, {}, Vector3.new(7, 13, 7), Color3.fromRGB(252, 232, 146)),
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

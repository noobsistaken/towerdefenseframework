--!strict
--[[
	Enemy roster.

	Adding an enemy means adding an entry here. Nothing else is required
	unless it needs behaviour the base simulation cannot express, in which
	case it also gets a behaviour table under
	src/match/server/Entities/Enemies/.

	All numbers here are WAVE-1 baselines. Scaling applies the wave curve on
	top, so tuning early-game difficulty means editing these and tuning
	late-game difficulty means editing Scaling. Keeping those two knobs
	separate is deliberate - a single combined number makes it impossible to
	fix wave 40 without breaking wave 2.
]]

local Types = require(script.Parent.Parent.Types)

local Enemies = {}

--- Keyed by id. The id is also what wave compositions and save data refer to,
--- so renaming one is a breaking change.
Enemies.DEFINITIONS = {
	Zombie = {
		id = "Zombie",
		displayName = "Zombie",
		category = "Ground" :: Types.EnemyCategory,
		baseHealth = 100,
		baseSpeed = 12,
		baseBounty = 10,
		leakDamage = 1,
		isBoss = false,
		introducesAtWave = 1,
		hitboxSize = Vector3.new(2, 4, 2),
		color = Color3.fromRGB(106, 140, 88),
		hoverHeight = 2,
		resistances = {},
	},

	Runner = {
		id = "Runner",
		displayName = "Runner",
		category = "Ground" :: Types.EnemyCategory,
		baseHealth = 55,
		baseSpeed = 26,
		baseBounty = 8,
		leakDamage = 1,
		isBoss = false,
		introducesAtWave = 4,
		hitboxSize = Vector3.new(1.6, 3.4, 1.6),
		color = Color3.fromRGB(214, 178, 76),
		hoverHeight = 1.7,
		-- Fast and fragile. Bleed is disproportionately strong against it,
		-- so it shrugs off a little of the duration.
		resistances = {
			Bleed = 0.6,
		},
	},

	Tank = {
		id = "Tank",
		displayName = "Tank",
		category = "Ground" :: Types.EnemyCategory,
		baseHealth = 480,
		baseSpeed = 6.5,
		baseBounty = 30,
		leakDamage = 3,
		isBoss = false,
		introducesAtWave = 7,
		hitboxSize = Vector3.new(3.4, 4.6, 3.4),
		color = Color3.fromRGB(88, 96, 112),
		hoverHeight = 2.3,
		resistances = {},
	},

	Titan = {
		id = "Titan",
		displayName = "Titan",
		category = "Ground" :: Types.EnemyCategory,
		baseHealth = 6000,
		baseSpeed = 9,
		baseBounty = 250,
		-- A leaked Titan should be close to a run-ending event, not a scratch.
		leakDamage = 20,
		isBoss = true,
		introducesAtWave = 10,
		hitboxSize = Vector3.new(7, 11, 7),
		color = Color3.fromRGB(150, 52, 52),
		hoverHeight = 5.5,
		-- Bosses resist crowd control rather than being immune to it, so a
		-- slow tower is still worth building without trivialising them.
		resistances = {
			Bleed = 0.5,
			Slow = 0.4,
			Stun = 0,
		},
	},
} :: { [string]: Types.EnemyDefinition }

--- Every enemy id, sorted, so iteration order is stable across runs.
--- A hash-table pairs() order is not stable in Luau, and an unstable order
--- would make wave generation unreproducible from the same seed.
local sortedIds: { string } = {}

for id in Enemies.DEFINITIONS do
	table.insert(sortedIds, id)
end

table.sort(sortedIds)

Enemies.IDS = table.freeze(sortedIds)

--- Throws on an unknown id rather than returning nil. Every caller has a
--- definition it believes exists; a nil here would surface much later as an
--- arithmetic error on a nil field.
function Enemies.get(id: string): Types.EnemyDefinition
	local definition = Enemies.DEFINITIONS[id]

	if definition == nil then
		error(`Enemies.get: no enemy definition with id "{id}"`)
	end

	return definition
end

return Enemies

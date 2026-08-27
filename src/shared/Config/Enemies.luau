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
		rig = "FastZombie",
		hoverHeight = 2,
		resistances = {},
	},

	Runner = {
		id = "Runner",
		displayName = "Runner",
		rig = "RusherZombie",
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

	Drifter = {
		id = "Drifter",
		displayName = "Drifter",
		-- The FIRST air enemy, and the reason anti-air towers exist.
		-- Ground-only towers cannot touch it, so a player who built nothing
		-- but Riflemen has to react. Wisp and Zeppelin follow it.
		category = "Air" :: Types.EnemyCategory,
		baseHealth = 70,
		baseSpeed = 16,
		-- Priced above its health suggests, because the towers that can
		-- answer it are more expensive than the ones that cannot.
		baseBounty = 14,
		leakDamage = 2,
		isBoss = false,
		-- Late enough that Marksman and Flak are affordable, early enough to
		-- punish having ignored them.
		introducesAtWave = 8,
		hitboxSize = Vector3.new(2.6, 2.6, 2.6),
		color = Color3.fromRGB(126, 196, 214),
		-- Well clear of the ground so it reads as flying at a glance.
		hoverHeight = 14,
		resistances = {},
	},

	-- Air, fast and fragile: the flying answer to Runner. Where Drifter
	-- asks whether you own any anti-air at all, Wisp asks whether you own
	-- enough of it - a single slow-firing Marksman cannot clear a flock
	-- before it crosses. Cheap to kill, punishing to ignore.
	Wisp = {
		id = "Wisp",
		displayName = "Wisp",
		category = "Air" :: Types.EnemyCategory,
		baseHealth = 40,
		baseSpeed = 27,
		baseBounty = 9,
		leakDamage = 1,
		isBoss = false,
		-- Four waves after Drifter: long enough to have bought anti-air,
		-- short enough that one token turret is not yet enough.
		introducesAtWave = 12,
		hitboxSize = Vector3.new(1.8, 1.8, 1.8),
		color = Color3.fromRGB(198, 236, 246),
		-- Below Drifter, so the two read as different altitudes rather than
		-- as one flock.
		hoverHeight = 10,
		resistances = {
			-- Small and quick, the same reason Runner shrugs off bleed.
			Bleed = 0.6,
		},
	},

	-- Air, slow and armoured: the flying Tank. Sustained anti-air DPS is
	-- the only answer - a burst tower that clears Wisps will not finish
	-- this before it crosses, and it takes the most base health of any
	-- non-boss when it leaks.
	Zeppelin = {
		id = "Zeppelin",
		displayName = "Zeppelin",
		category = "Air" :: Types.EnemyCategory,
		baseHealth = 340,
		baseSpeed = 7,
		-- Priced like Tank for the same reason Drifter is priced above its
		-- health: the towers that answer it cost more.
		baseBounty = 34,
		leakDamage = 4,
		isBoss = false,
		introducesAtWave = 18,
		hitboxSize = Vector3.new(4.2, 3.2, 4.2),
		color = Color3.fromRGB(120, 138, 170),
		-- The highest thing in the game, and deliberately: it should be
		-- obvious from the ground that only real anti-air reaches it.
		hoverHeight = 19,
		resistances = {
			-- Envelope rather than plating, but there is a lot of it.
			Concuss = 0.5,
		},
	},

	Tank = {
		id = "Tank",
		displayName = "Tank",
		rig = "SciFiRobot",
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
		resistances = {
			-- Heavy plating halves how long a concussion sticks.
			Concuss = 0.5,
		},
	},

	Titan = {
		id = "Titan",
		displayName = "Titan",
		-- FastZombie rather than noobsv8: the boss shares the zombie rig at
		-- 11 studs tall. noobsv8 lives only in the original place file and
		-- cannot follow the match into its own place until rig templates are
		-- exported into the repo - the standing assets/ follow-up. Scaled to
		-- nearly triple the trash zombie's height it still reads as a boss.
		rig = "FastZombie",
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
		-- Only ids that exist in Config/StatusEffects.luau belong here; a
		-- resistance naming an effect that does not exist is silently dead.
		resistances = {
			Bleed = 0.5,
			Slow = 0.4,
			-- Stun-immune, as bosses are: a chain-stunnable boss is a DPS
			-- check with the check removed.
			Concuss = 0,
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

--- Non-throwing lookup, mirroring Towers.find. Used where an id comes from
--- authored config that may name an enemy that has since been removed: that
--- is a content mistake worth skipping over, not a reason to abort a wave.
function Enemies.find(id: string): Types.EnemyDefinition?
	return Enemies.DEFINITIONS[id]
end

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

--!strict
--[[
	Wave composition.

	Two sources, in priority order:

	  1. AUTHORED - an explicit roster for the opening waves, where the exact
	     order things are introduced matters more than any formula. Hand
	     authoring the ramp is the only way to guarantee a player meets one new
	     idea at a time.

	  2. The rules below - counts derived from BASE_COUNTS and each enemy's
	     introducesAtWave. This covers everything past the authored range and
	     is what endless mode runs on forever.

	Counts in BASE_COUNTS are "how many appear in the first wave this type is
	eligible for". Scaling.enemyCount grows them from there. Counts in
	AUTHORED are literal and are not scaled, which is the point of authoring
	them.

	Note the shape: Luau permits a type annotation on a `local` declaration
	but not on a table-field assignment, so each table is declared as an
	annotated local and then attached.
]]

local Waves = {}

--- Per-type wave-1-eligible counts. An enemy absent from this table never
--- spawns from the rules path, which is a useful way to bench a type without
--- deleting it.
local BASE_COUNTS: { [string]: number } = {
	Zombie = 6,
	Runner = 4,
	Tank = 2,
	Drifter = 3,
	Wisp = 4,
	Zeppelin = 2,
	Titan = 1,
}

--- Runners arrive in tight bursts rather than evenly spaced, which is what
--- makes them threatening: a spread-out Runner is just a weak Zombie.
local BURST_TYPES: { [string]: boolean } = {
	Runner = true,
}

--- One entry of an authored wave.
export type AuthoredEntry = {
	id: string,
	count: number,
}

--- Hand-authored opening waves. Every new enemy gets a wave where it is the
--- only new thing, and the wave after it goes back down in volume so the
--- introduction is legible rather than lost in a crowd.
---
---   1-3   Zombies only. Learn placement and the economy.
---   4     Runners. First thing that punishes a shallow defence.
---   7     Tanks. First thing that punishes low DPS.
---   8     Drifters. First thing ground-only towers cannot touch at all.
---   10    Titan. Boss, on the boss-wave interval.
---   12    Wisps. Air again, but fast and in numbers - one turret is no
---         longer enough. Volume of everything else drops to make room.
---   18    Zeppelins, from the rules path. Slow, armoured air.
---
--- Past the last entry the rules path takes over, so extending this table is
--- always optional and never load-bearing.
local AUTHORED: { [number]: { AuthoredEntry } } = {
	[1] = { { id = "Zombie", count = 6 } },
	[2] = { { id = "Zombie", count = 9 } },
	[3] = { { id = "Zombie", count = 12 } },

	[4] = { { id = "Zombie", count = 10 }, { id = "Runner", count = 4 } },
	[5] = { { id = "Zombie", count = 14 }, { id = "Runner", count = 5 } },
	[6] = { { id = "Zombie", count = 16 }, { id = "Runner", count = 7 } },

	[7] = { { id = "Zombie", count = 14 }, { id = "Runner", count = 6 }, { id = "Tank", count = 2 } },
	[8] = {
		{ id = "Zombie", count = 16 },
		{ id = "Runner", count = 8 },
		{ id = "Tank", count = 2 },
		{ id = "Drifter", count = 3 },
	},
	[9] = {
		{ id = "Zombie", count = 18 },
		{ id = "Runner", count = 10 },
		{ id = "Tank", count = 3 },
		{ id = "Drifter", count = 4 },
	},

	-- Boss wave. Volume drops so the Titan is the story rather than noise.
	[10] = {
		{ id = "Zombie", count = 12 },
		{ id = "Runner", count = 6 },
		{ id = "Tank", count = 3 },
		{ id = "Drifter", count = 3 },
		{ id = "Titan", count = 1 },
	},

	[11] = {
		{ id = "Zombie", count = 20 },
		{ id = "Runner", count = 10 },
		{ id = "Tank", count = 4 },
		{ id = "Drifter", count = 5 },
	},
	-- Wisps arrive. Ground volume drops so the new thing is the story, the
	-- same shape as the Titan's wave.
	[12] = {
		{ id = "Zombie", count = 14 },
		{ id = "Runner", count = 8 },
		{ id = "Tank", count = 3 },
		{ id = "Drifter", count = 4 },
		{ id = "Wisp", count = 6 },
	},
	[13] = {
		{ id = "Zombie", count = 20 },
		{ id = "Runner", count = 11 },
		{ id = "Tank", count = 4 },
		{ id = "Drifter", count = 5 },
		{ id = "Wisp", count = 8 },
	},
}

Waves.BASE_COUNTS = BASE_COUNTS
Waves.BURST_TYPES = BURST_TYPES
Waves.AUTHORED = AUTHORED

--- Seconds between consecutive spawns within a wave.
Waves.SPAWN_INTERVAL = 0.8
Waves.BURST_INTERVAL = 0.25

--- Bosses are held back so they arrive behind the wave's chaff rather than
--- leading it.
Waves.BOSS_LEAD_IN = 3

--- Bosses only appear on boss waves; everything else is gated purely by its
--- own introducesAtWave. Applies to the RULES path only - an authored wave is
--- taken at its word, because overriding the author is what makes an override
--- table useless.
Waves.BOSS_ONLY_ON_BOSS_WAVES = true

--- Highest wave with an authored roster. Computed rather than written down,
--- so adding an entry above cannot leave a stale constant behind.
local highestAuthored = 0

for wave in AUTHORED do
	if wave > highestAuthored then
		highestAuthored = wave
	end
end

Waves.HIGHEST_AUTHORED_WAVE = highestAuthored

return Waves

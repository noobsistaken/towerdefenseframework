--!strict
--[[
	Wave composition rules.

	Phase 1 ships the rule-driven generator only. Phase 3 adds the authored
	override table for waves 1-N on top of it; the generator stays the
	fallback and becomes the endless-mode source. Both read from here.

	Counts below are "how many of this type appear in the first wave it is
	eligible for". Scaling.enemyCount grows them from there.

	Note the shape: Luau permits a type annotation on a `local` declaration
	but not on a table-field assignment, so each table is declared as an
	annotated local and then attached.
]]

local Waves = {}

--- Per-type wave-1-eligible counts. An enemy absent from this table never
--- spawns, which is a useful way to bench a type without deleting it.
local BASE_COUNTS: { [string]: number } = {
	Zombie = 6,
	Runner = 4,
	Tank = 2,
	Titan = 1,
}

--- Runners arrive in tight bursts rather than evenly spaced, which is what
--- makes them threatening: a spread-out Runner is just a weak Zombie.
local BURST_TYPES: { [string]: boolean } = {
	Runner = true,
}

Waves.BASE_COUNTS = BASE_COUNTS
Waves.BURST_TYPES = BURST_TYPES

--- Seconds between consecutive spawns within a wave.
Waves.SPAWN_INTERVAL = 0.8
Waves.BURST_INTERVAL = 0.25

--- Bosses are held back so they arrive behind the wave's chaff rather than
--- leading it.
Waves.BOSS_LEAD_IN = 3

--- Bosses only appear on boss waves; everything else is gated purely by its
--- own introducesAtWave.
Waves.BOSS_ONLY_ON_BOSS_WAVES = true

return Waves

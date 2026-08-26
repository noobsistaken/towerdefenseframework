--!strict
--[[
	Status effect roster.

	The brief asked for a bleed built on a generic system so that poison, burn
	and slow are trivial to add later. Two effects ship, deliberately covering
	two different KINDS - a damage-over-time and a movement multiplier - so
	that "generic" is demonstrated by working code rather than claimed.

	Adding burn or poison from here is one entry: copy Bleed, change the id,
	the tick interval and the colour. Adding a vulnerability debuff is one
	entry with kind = "DamageTakenMultiplier". No new code in either case.

	Resistances live on the enemy (Config/Enemies.luau) and multiply incoming
	DURATION, so a resistance of 0.5 halves how long an effect lasts and 0
	makes the enemy immune.
]]

local Types = require(script.Parent.Parent.Types)

local StatusEffects = {}

local DEFINITIONS: { [string]: Types.StatusEffectDefinition } = {
	Bleed = {
		id = "Bleed",
		displayName = "Bleed",
		kind = "DamageOverTime" :: Types.StatusEffectKind,
		tickInterval = 0.5,
		-- Stacks, because a bleed that only refreshed would make a second
		-- Lacerator worth almost nothing against the same target.
		stacking = "Stack" :: Types.StatusStacking,
		maxStacks = 5,
		magnitude = 1,
		color = Color3.fromRGB(168, 36, 44),
	},

	Burn = {
		id = "Burn",
		displayName = "Burn",
		kind = "DamageOverTime" :: Types.StatusEffectKind,
		tickInterval = 0.4,
		-- Stacks shallower than Bleed: burn towers hit harder per
		-- application, so the cap is what keeps two of them honest.
		stacking = "Stack" :: Types.StatusStacking,
		maxStacks = 3,
		magnitude = 1,
		color = Color3.fromRGB(226, 124, 44),
	},

	Sunder = {
		id = "Sunder",
		displayName = "Sunder",
		kind = "DamageTakenMultiplier" :: Types.StatusEffectKind,
		tickInterval = 0,
		-- Refresh, like Slow and for the same reason: multiplicative
		-- vulnerability stacks are how one debuffer becomes a damage
		-- doubling nobody priced.
		stacking = "Refresh" :: Types.StatusStacking,
		maxStacks = 1,
		magnitude = 1.2,
		color = Color3.fromRGB(168, 96, 202),
	},

	-- Short on purpose, and Refresh: a stun that outlasted its tower's
	-- reload would be a permanent freeze with extra steps. The invariant
	-- that actually guarantees it: every applier's stun duration stays
	-- BELOW its fastest possible traited reload (fireRate times the
	-- largest fire-rate trait). TowerBalance.spec computes both sides
	-- from config, so a new stun tower cannot ship a permafreeze.
	Concuss = {
		id = "Concuss",
		displayName = "Concuss",
		kind = "Stun" :: Types.StatusEffectKind,
		tickInterval = 0,
		stacking = "Refresh" :: Types.StatusStacking,
		maxStacks = 1,
		-- Unused by Stun; speed is forced to zero regardless.
		magnitude = 0,
		color = Color3.fromRGB(232, 220, 120),
	},

	Slow = {
		id = "Slow",
		displayName = "Slow",
		kind = "SpeedMultiplier" :: Types.StatusEffectKind,
		-- Unused by this kind; multipliers are continuous, not periodic.
		tickInterval = 0,
		-- Refresh rather than stack: stacking multiplicative slows is how a
		-- handful of towers accidentally becomes a permanent freeze.
		stacking = "Refresh" :: Types.StatusStacking,
		maxStacks = 1,
		magnitude = 0.7,
		color = Color3.fromRGB(96, 168, 220),
	},
}

StatusEffects.DEFINITIONS = DEFINITIONS

--- Non-throwing lookup. Used on the hot path, where an unknown id should skip
--- the effect rather than kill the simulation step.
function StatusEffects.find(id: string): Types.StatusEffectDefinition?
	return DEFINITIONS[id]
end

--- Throwing lookup, for config validation and tests.
function StatusEffects.get(id: string): Types.StatusEffectDefinition
	local definition = DEFINITIONS[id]

	if definition == nil then
		error(`StatusEffects.get: no effect with id "{id}"`)
	end

	return definition
end

return StatusEffects

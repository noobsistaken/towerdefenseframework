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

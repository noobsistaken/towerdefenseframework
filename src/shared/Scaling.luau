--!strict
--[[
	Wave scaling curves.

	Pure functions, no state, no Instances - so the whole difficulty ramp is
	testable, which matters because balance is one of the things static
	analysis provably cannot check.

	The shape of the run, and why:

	  * Health grows geometrically at 11% a wave. By wave 40 an enemy has
	    ~63x its wave-1 health, which is what makes a 30-50 wave run feel like
	    it escalates rather than plateaus.

	  * Count grows much more slowly, at 5.5%. Health carries the difficulty;
	    count carries the texture. Scaling both aggressively produces a wave
	    40 that is simultaneously unkillable and a performance problem.

	  * Bounty grows SUB-LINEARLY against health - roughly health^0.55, so a
	    ~63x health enemy is worth only ~10x its wave-1 bounty. This is the
	    single most important curve in the file. Paying out proportionally to
	    health means late waves print money, every tower gets maxed, and the
	    difficulty collapses exactly when it should peak.

	Wave 1 is the fixed point of all three: at wave = 1 every function returns
	its base value untouched, so the numbers in Config/Enemies.luau mean
	literally what they say.
]]

local Scaling = {}

--- Per-wave geometric growth in enemy health.
Scaling.HEALTH_GROWTH = 0.11

--- Per-wave geometric growth in enemy count.
Scaling.COUNT_GROWTH = 0.055

--- Exponent applied to the health growth factor to get the bounty growth
--- factor. Below 1 means income falls behind threat over a run, on purpose.
Scaling.BOUNTY_EXPONENT = 0.55

--- Every Nth wave is a boss wave.
Scaling.BOSS_WAVE_INTERVAL = 10

--- Hard ceiling on enemies spawned in one wave, whatever the curve says.
--- This is a performance guard, not a balance knob: past this the server is
--- moving more parts than it can replicate comfortably.
Scaling.MAX_ENEMIES_PER_WAVE = 220

--- Separate, much tighter ceiling on bosses.
---
--- Boss counts run through the same geometric growth as everything else, and
--- 5.5% a wave compounds hard: an uncapped Titan count reaches the per-wave
--- ceiling deep into endless mode, which would both wreck performance and
--- starve the regular enemy budget to nothing. A boss wave is supposed to be
--- a boss and its escort, at any wave number.
Scaling.MAX_BOSSES_PER_WAVE = 6

--- Multiplier applied to a wave-1 value at `wave`. Exposed because several
--- callers want the raw factor rather than a scaled quantity.
function Scaling.healthFactor(wave: number): number
	return (1 + Scaling.HEALTH_GROWTH) ^ (wave - 1)
end

--- Scaled health for one enemy.
function Scaling.enemyHealth(baseHealth: number, wave: number, healthMultiplier: number): number
	-- Rounded to whole health so damage numbers stay legible and a kill is
	-- never one-hundredth of a point away.
	return math.max(1, math.floor(baseHealth * Scaling.healthFactor(wave) * healthMultiplier + 0.5))
end

--- Scaled count for one enemy type in one wave.
function Scaling.enemyCount(baseCount: number, wave: number): number
	local scaled = baseCount * ((1 + Scaling.COUNT_GROWTH) ^ (wave - 1))
	return math.clamp(math.floor(scaled + 0.5), 1, Scaling.MAX_ENEMIES_PER_WAVE)
end

--- Scaled kill bounty. Grows as healthFactor^BOUNTY_EXPONENT, so income
--- deliberately falls behind threat as the run goes on.
function Scaling.bounty(baseBounty: number, wave: number, rewardMultiplier: number): number
	local factor = Scaling.healthFactor(wave) ^ Scaling.BOUNTY_EXPONENT
	return math.max(1, math.floor(baseBounty * factor * rewardMultiplier + 0.5))
end

--- Cash granted for clearing a wave, before the difficulty multiplier.
--- Grows linearly: a predictable floor under the player's income that does
--- not depend on how efficiently they killed things.
function Scaling.waveBonus(wave: number, rewardMultiplier: number): number
	return math.max(1, math.floor((40 + 12 * wave) * rewardMultiplier + 0.5))
end

function Scaling.isBossWave(wave: number): boolean
	return wave > 0 and wave % Scaling.BOSS_WAVE_INTERVAL == 0
end

-- ===========================================================================
-- Endless mode
-- ===========================================================================

--- Additional per-wave health growth once the campaign is over, compounding
--- ON TOP of HEALTH_GROWTH. 11% + 6% means endless waves get roughly 17%
--- harder each time.
---
--- Steeper than the campaign on purpose. Endless is not meant to be survived
--- indefinitely; it is meant to find the point where a given defence breaks,
--- and a curve that only matched the campaign would take hundreds of waves to
--- do that.
Scaling.ENDLESS_EXTRA_GROWTH = 0.06

--- Extra multiplier for waves past `finalWave`. Exactly 1 up to and including
--- the final wave, so campaign balance is untouched by this existing.
function Scaling.endlessFactor(wave: number, finalWave: number): number
	if wave <= finalWave then
		return 1
	end

	return (1 + Scaling.ENDLESS_EXTRA_GROWTH) ^ (wave - finalWave)
end

--- True once the campaign has been cleared and the run is on borrowed time.
function Scaling.isEndlessWave(wave: number, finalWave: number): boolean
	return wave > finalWave
end

return Scaling

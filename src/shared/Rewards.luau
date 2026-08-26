--!strict
--[[
	Match rewards and the account level curve.

	Pure, so the numbers a player is paid can be asserted without running a
	match. That matters more here than in most modules: a bug in this file
	writes wrong values into persistent player data, and unlike a balance
	mistake there is no way to walk it back once it has shipped.

	Two deliberate shapes:

	  * Rewards are paid per WAVE CLEARED, not per kill or per match. A player
	    who reaches wave 30 and loses has done more than one who reaches wave 5
	    and loses, and paying flat per match makes a quick loss the efficient
	    way to farm.

	  * The level curve is QUADRATIC in cumulative XP, so each level costs
	    more than the last. A linear curve makes level a synonym for hours
	    played; a quadratic one keeps early levels quick and later ones
	    meaningful without ever stalling completely.
]]

local Types = require(script.Parent.Types)

local Rewards = {}

--- Coins per wave cleared, before the difficulty multiplier.
Rewards.COINS_PER_WAVE = 15

--- Flat bonus for clearing the campaign. Large enough to be the reason to
--- finish a run rather than farm the early waves.
Rewards.COINS_FOR_WIN = 250

Rewards.XP_PER_WAVE = 10
Rewards.XP_FOR_WIN = 150

--- RerollTokens per payout: one for playing, one more for winning. Flat
--- and difficulty-blind on purpose - tokens gate rerolls, and a currency
--- that farms exponentially would make the reroll button a formality.
Rewards.TOKENS_PER_PAYOUT = 1
Rewards.TOKENS_FOR_WIN = 1

--- Scales the whole level curve. Level L requires this times L(L-1)/2
--- cumulative XP, so the gap between consecutive levels grows linearly.
Rewards.XP_CURVE = 200

export type Payout = {
	coins: number,
	xp: number,
	tokens: number,
}

--- What a finished match pays.
---
--- `wavesCleared` is waves fully cleared, so the wave a player died on does
--- not count. `won` means the campaign's final wave was reached, which under
--- endless mode can be true of a run that later ends in defeat - deliberately,
--- because clearing the campaign happened regardless of what came after.
function Rewards.forMatch(wavesCleared: number, won: boolean, difficulty: Types.DifficultyConfig): Payout
	local waves = math.max(0, math.floor(wavesCleared))

	local coins = waves * Rewards.COINS_PER_WAVE
	local xp = waves * Rewards.XP_PER_WAVE

	if won then
		coins += Rewards.COINS_FOR_WIN
		xp += Rewards.XP_FOR_WIN
	end

	-- Harder difficulties pay more through the same multiplier that makes
	-- their in-match bounties richer, so there is one number to tune.
	return {
		coins = math.max(0, math.floor(coins * difficulty.rewardMultiplier + 0.5)),
		xp = math.max(0, math.floor(xp * difficulty.rewardMultiplier + 0.5)),
		tokens = Rewards.TOKENS_PER_PAYOUT + (if won then Rewards.TOKENS_FOR_WIN else 0),
	}
end

--- Cumulative XP required to REACH `level`. Level 1 is free.
function Rewards.xpForLevel(level: number): number
	if level <= 1 then
		return 0
	end

	return Rewards.XP_CURVE * (level - 1) * level / 2
end

--- The level `xp` buys. Always at least 1.
---
--- A loop rather than solving the quadratic: it is exact, it is obviously
--- correct against xpForLevel, and it runs once at the end of a match.
--- Inverting the formula in floating point risks landing one XP short of a
--- level boundary and telling a player they did not level up when they did.
function Rewards.levelFor(xp: number): number
	local level = 1

	while Rewards.xpForLevel(level + 1) <= xp do
		level += 1
	end

	return level
end

--- Progress through the current level, as XP earned and XP needed. Used by
--- the results screen's progress bar.
function Rewards.levelProgress(xp: number): (number, number)
	local level = Rewards.levelFor(xp)
	local floor = Rewards.xpForLevel(level)
	local ceiling = Rewards.xpForLevel(level + 1)

	return xp - floor, ceiling - floor
end

return Rewards

--!strict
--[[
	Tests for match payouts and the level curve.

	These matter more than most: a bug here writes wrong values into
	persistent player data, and unlike a balance mistake there is no way to
	walk it back once real accounts hold the numbers.

	The level round-trip is the load-bearing one. levelFor and xpForLevel are
	two descriptions of the same curve, and if they ever disagree a player is
	told they did not level up when they did.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function difficulty(rewardMultiplier: number): Types.DifficultyConfig
	return {
		id = "Test",
		displayName = "Test",
		startingCash = 500,
		baseHealth = 100,
		healthMultiplier = 1,
		rewardMultiplier = rewardMultiplier,
		finalWave = 40,
	}
end

local NORMAL = difficulty(1)

describe("Rewards.forMatch", function()
	it("pays nothing for a run that cleared nothing", function()
		local payout = Rewards.forMatch(0, false, NORMAL)

		expect(payout.coins).toBe(0)
		expect(payout.xp).toBe(0)
	end)

	it("pays more the further you got", function()
		-- The shape that stops a quick loss being the efficient way to farm.
		local previous = -1

		for waves = 0, 50 do
			local payout = Rewards.forMatch(waves, false, NORMAL)
			expect(payout.coins > previous).toBe(true)
			previous = payout.coins
		end
	end)

	it("pays a bonus for clearing the campaign", function()
		local lost = Rewards.forMatch(40, false, NORMAL)
		local won = Rewards.forMatch(40, true, NORMAL)

		expect(won.coins > lost.coins).toBe(true)
		expect(won.xp > lost.xp).toBe(true)
	end)

	it("pays tokens flat: one for the payout, one more for the win", function()
		-- Difficulty-blind on purpose: tokens gate rerolls, and a currency
		-- that farms exponentially makes the reroll button a formality.
		expect(Rewards.forMatch(5, false, NORMAL).tokens).toBe(Rewards.TOKENS_PER_PAYOUT)
		expect(Rewards.forMatch(40, true, NORMAL).tokens).toBe(Rewards.TOKENS_PER_PAYOUT + Rewards.TOKENS_FOR_WIN)
		expect(Rewards.forMatch(5, false, difficulty(1.25)).tokens).toBe(Rewards.forMatch(5, false, NORMAL).tokens)
	end)

	it("scales with the difficulty multiplier", function()
		local casual = Rewards.forMatch(20, false, difficulty(0.8))
		local nightmare = Rewards.forMatch(20, false, difficulty(1.25))

		expect(nightmare.coins > casual.coins).toBe(true)
	end)

	it("never pays a negative or fractional amount", function()
		-- Coins and XP are persisted as whole numbers. A fraction would round
		-- differently on the next read and drift.
		for _, waves in { -5, 0, 1, 37 } do
			local payout = Rewards.forMatch(waves, true, difficulty(0.33))

			expect(payout.coins >= 0).toBe(true)
			expect(payout.xp >= 0).toBe(true)
			expect(payout.coins % 1).toBe(0)
			expect(payout.xp % 1).toBe(0)
		end
	end)

	it("ignores a fractional wave count", function()
		expect(Rewards.forMatch(10.9, false, NORMAL).coins).toBe(Rewards.forMatch(10, false, NORMAL).coins)
	end)
end)

describe("Rewards level curve", function()
	it("makes level 1 free", function()
		expect(Rewards.xpForLevel(1)).toBe(0)
		expect(Rewards.levelFor(0)).toBe(1)
	end)

	it("never drops below level 1", function()
		expect(Rewards.levelFor(-100)).toBe(1)
	end)

	it("costs more for each successive level", function()
		-- A linear curve makes level a synonym for hours played.
		local previousGap = -1

		for level = 1, 40 do
			local gap = Rewards.xpForLevel(level + 1) - Rewards.xpForLevel(level)
			expect(gap > previousGap).toBe(true)
			previousGap = gap
		end
	end)

	it("round-trips against xpForLevel", function()
		-- THE assertion in this file. Exactly the XP required must award the
		-- level, and one short of it must not.
		for level = 1, 40 do
			local required = Rewards.xpForLevel(level)

			expect(Rewards.levelFor(required)).toBe(level)

			if level > 1 then
				expect(Rewards.levelFor(required - 1)).toBe(level - 1)
			end
		end
	end)

	it("never goes backwards as XP grows", function()
		local previous = 0

		for xp = 0, 20000, 137 do
			local level = Rewards.levelFor(xp)
			expect(level >= previous).toBe(true)
			previous = level
		end
	end)
end)

describe("Rewards.levelProgress", function()
	it("reads zero at exactly a level boundary", function()
		for level = 1, 20 do
			local earned, needed = Rewards.levelProgress(Rewards.xpForLevel(level))

			expect(earned).toBe(0)
			expect(needed > 0).toBe(true)
		end
	end)

	it("never exceeds what the level needs", function()
		-- A progress bar past 100% is the symptom of levelFor and xpForLevel
		-- disagreeing, so this is the round-trip test seen from the UI's side.
		for xp = 0, 20000, 97 do
			local earned, needed = Rewards.levelProgress(xp)

			expect(earned >= 0).toBe(true)
			expect(earned < needed).toBe(true)
		end
	end)
end)

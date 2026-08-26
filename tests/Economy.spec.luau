--!strict
--[[
	Tests for match economy arithmetic.

	The bounty split is the part worth the most scrutiny. It is the one piece
	of arithmetic that can silently create or destroy currency, and in a co-op
	game an unfair split is invisible to the person it is unfair to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

--- Three levels costing 100, 200 and 400. Everything else is filler; only
--- `cost` is read by this module.
local function definition(): Types.TowerDefinition
	local function level(cost: number): Types.TowerLevel
		return {
			cost = cost,
			damage = 1,
			fireRate = 1,
			range = 10,
			splashRadius = 0,
			applies = {},
			modelSize = Vector3.one,
			color = Color3.new(),
		}
	end

	return {
		id = "Fixture",
		displayName = "Fixture",
		rarity = "Common",
		description = "",
		category = "Hybrid" :: Types.TowerCategory,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(6, 6),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = 0,
		levels = { level(100), level(200), level(400) },
	}
end

describe("Economy.totalInvested", function()
	it("sums the steps actually paid, not the last price", function()
		-- Costs are per-step, so a level 3 tower cost 700 in total. Reading
		-- only levels[3].cost would say 400 and under-refund by 300.
		expect(Economy.totalInvested(definition(), 1)).toBe(100)
		expect(Economy.totalInvested(definition(), 2)).toBe(300)
		expect(Economy.totalInvested(definition(), 3)).toBe(700)
	end)

	it("clamps above max level", function()
		expect(Economy.totalInvested(definition(), 99)).toBe(700)
	end)

	it("is zero below level 1", function()
		expect(Economy.totalInvested(definition(), 0)).toBe(0)
	end)
end)

describe("Economy.sellValue", function()
	it("refunds the configured fraction of real investment", function()
		local expected = math.floor(700 * Economy.SELL_REFUND_RATE)
		expect(Economy.sellValue(definition(), 3)).toBe(expected)
	end)

	it("never refunds more than was paid", function()
		for level = 1, 3 do
			local paid = Economy.totalInvested(definition(), level)
			expect(Economy.sellValue(definition(), level) <= paid).toBe(true)
		end
	end)
end)

describe("Economy.upgradeCost", function()
	it("is the next level's price", function()
		expect(Economy.upgradeCost(definition(), 1)).toBe(200)
		expect(Economy.upgradeCost(definition(), 2)).toBe(400)
	end)

	it("is nil at max level", function()
		expect(Economy.upgradeCost(definition(), 3)).toBe(nil)
	end)
end)

describe("Economy.earlyStartBonus", function()
	it("pays the flat amount with no time left", function()
		expect(Economy.earlyStartBonus(0, 1)).toBe(Economy.EARLY_START_FLAT)
	end)

	it("grows with the time skipped", function()
		local none = Economy.earlyStartBonus(0, 1)
		local some = Economy.earlyStartBonus(10, 1)
		expect(some > none).toBe(true)
	end)

	it("treats negative time as zero", function()
		-- The clock can go slightly past the deadline before the tick runs.
		expect(Economy.earlyStartBonus(-50, 1)).toBe(Economy.EARLY_START_FLAT)
	end)

	it("applies the difficulty reward multiplier", function()
		local base = Economy.earlyStartBonus(10, 1)
		local doubled = Economy.earlyStartBonus(10, 2)
		expect(doubled > base).toBe(true)
	end)
end)

describe("Economy.splitByContribution", function()
	it("splits in proportion to damage dealt", function()
		local shares = Economy.splitByContribution({ a = 75, b = 25 }, 100)
		expect(shares.a).toBe(75)
		expect(shares.b).toBe(25)
	end)

	it("conserves the total exactly", function()
		-- The property that matters: the system can neither mint nor destroy
		-- cash. Three-way splits of indivisible amounts are where naive
		-- flooring silently loses coins.
		-- Annotated: without it Luau infers the record shape from the first
		-- entry and then rejects the later ones for having different keys.
		local cases: { { contributions: { [string]: number }, total: number } } = {
			{ contributions = { a = 1, b = 1, c = 1 }, total = 100 },
			{ contributions = { a = 1, b = 2 }, total = 7 },
			{ contributions = { a = 3, b = 3, c = 3, d = 3 }, total = 10 },
			{ contributions = { a = 999, b = 1 }, total = 3 },
		}

		for _, case in cases do
			local shares = Economy.splitByContribution(case.contributions, case.total)
			local sum = 0

			for _, amount in shares do
				sum += amount
			end

			expect(sum).toBe(case.total)
		end
	end)

	it("gives everything to a lone contributor", function()
		local shares = Economy.splitByContribution({ solo = 42 }, 250)
		expect(shares.solo).toBe(250)
	end)

	it("hands the rounding remainder to the largest contributor", function()
		-- 10 split 2:1 floors to 6 and 3, leaving 1 over. It belongs to
		-- whoever did the most, not to whoever iterated first.
		local shares = Economy.splitByContribution({ big = 2, small = 1 }, 10)
		expect(shares.big).toBe(7)
		expect(shares.small).toBe(3)
	end)

	it("pays nobody when there is nothing to pay", function()
		local shares = Economy.splitByContribution({ a = 5 }, 0)
		expect(next(shares)).toBe(nil)
	end)

	it("pays nobody when nobody contributed", function()
		expect(next(Economy.splitByContribution({}, 100))).toBe(nil)
		expect(next(Economy.splitByContribution({ a = 0 }, 100))).toBe(nil)
	end)

	it("ignores non-positive contributions", function()
		local shares = Economy.splitByContribution({ real = 10, idle = 0 }, 50)
		expect(shares.real).toBe(50)
		expect(shares.idle).toBe(nil)
	end)
end)

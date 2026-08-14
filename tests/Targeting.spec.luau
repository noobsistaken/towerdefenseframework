--!strict
--[[
	Tests for target selection.

	Each mode gets a candidate set constructed so that the RIGHT answer and
	the answer a different mode would give are different candidates. A fixture
	where several modes agree proves nothing about which one ran.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function candidate(
	id: number,
	distanceToBase: number,
	maxHealth: number,
	distanceToTower: number
): Targeting.Candidate
	return {
		id = id,
		distanceToBase = distanceToBase,
		health = maxHealth,
		maxHealth = maxHealth,
		distanceToTower = distanceToTower,
	}
end

--- Deliberately built so all four modes pick a DIFFERENT candidate:
---   First      -> id 2 (closest to base, 10 studs out)
---   Last       -> id 3 (furthest from base, 300)
---   Strongest  -> id 4 (highest max health, 900)
---   Closest    -> id 1 (nearest the tower, 5)
local function mixedSet(): { Targeting.Candidate }
	return {
		candidate(1, 200, 100, 5),
		candidate(2, 10, 120, 40),
		candidate(3, 300, 150, 60),
		candidate(4, 150, 900, 30),
	}
end

describe("Targeting.select", function()
	it("returns nil when there is nothing to shoot", function()
		expect(Targeting.select("First", {})).toBe(nil)
		expect(Targeting.select("Last", {})).toBe(nil)
		expect(Targeting.select("Strongest", {})).toBe(nil)
		expect(Targeting.select("Closest", {})).toBe(nil)
	end)

	it("First picks the enemy nearest to leaking", function()
		local chosen = Targeting.select("First", mixedSet())
		expect(chosen).never.toBe(nil)
		expect((chosen :: Targeting.Candidate).id).toBe(2)
	end)

	it("Last picks the enemy furthest from the base", function()
		local chosen = Targeting.select("Last", mixedSet())
		expect((chosen :: Targeting.Candidate).id).toBe(3)
	end)

	it("Strongest picks the highest MAX health, not the highest current", function()
		-- The distinction matters: a chipped Tank should stay "strongest".
		local set = {
			candidate(1, 100, 500, 10),
			candidate(2, 110, 200, 20),
		}
		set[1].health = 5

		local chosen = Targeting.select("Strongest", set)
		expect((chosen :: Targeting.Candidate).id).toBe(1)
	end)

	it("Closest picks the enemy nearest the tower", function()
		local chosen = Targeting.select("Closest", mixedSet())
		expect((chosen :: Targeting.Candidate).id).toBe(1)
	end)

	it("uses a single candidate whatever the mode", function()
		local only = { candidate(7, 42, 42, 42) }

		for _, mode: Types.TargetingMode in Targeting.modes() do
			local chosen = Targeting.select(mode, only)
			expect((chosen :: Targeting.Candidate).id).toBe(7)
		end
	end)
end)

describe("Targeting tie-breaking", function()
	it("breaks every tie on the lowest id", function()
		-- Without an explicit tie-break the winner depends on table order and
		-- a tower visibly flickers between two equidistant targets.
		local tied = {
			candidate(9, 50, 100, 25),
			candidate(3, 50, 100, 25),
			candidate(6, 50, 100, 25),
		}

		for _, mode: Types.TargetingMode in Targeting.modes() do
			local chosen = Targeting.select(mode, tied)
			expect((chosen :: Targeting.Candidate).id).toBe(3)
		end
	end)

	it("is order-independent", function()
		local forwards = mixedSet()
		local backwards = mixedSet()
		table.sort(backwards, function(a, b)
			return a.id > b.id
		end)

		for _, mode: Types.TargetingMode in Targeting.modes() do
			local a = Targeting.select(mode, forwards)
			local b = Targeting.select(mode, backwards)
			expect((a :: Targeting.Candidate).id).toBe((b :: Targeting.Candidate).id)
		end
	end)
end)

describe("Targeting.cycle", function()
	it("walks every mode and returns to the start", function()
		-- Annotated: an unannotated local widens the union to `string`, which
		-- then cannot be passed back into cycle().
		local mode: Types.TargetingMode = Targeting.modes()[1]
		local seen = { mode }

		for _ = 1, #Targeting.modes() - 1 do
			mode = Targeting.cycle(mode)
			table.insert(seen, mode)
		end

		expect(#seen).toBe(#Targeting.modes())

		-- Every mode visited exactly once before wrapping.
		for _, expected: Types.TargetingMode in Targeting.modes() do
			expect(table.find(seen, expected)).never.toBe(nil)
		end

		expect(Targeting.cycle(mode)).toBe(Targeting.modes()[1])
	end)

	it("falls back to the first mode for an unrecognised one", function()
		-- A stale client value must never leave a tower with no valid mode.
		expect(Targeting.cycle("Nonsense" :: any)).toBe(Targeting.modes()[1])
	end)
end)

describe("Targeting.isValid", function()
	it("accepts every real mode", function()
		for _, mode: Types.TargetingMode in Targeting.modes() do
			expect(Targeting.isValid(mode)).toBe(true)
		end
	end)

	it("rejects anything else", function()
		expect(Targeting.isValid("")).toBe(false)
		expect(Targeting.isValid("first")).toBe(false)
		expect(Targeting.isValid("Strongest ")).toBe(false)
	end)
end)

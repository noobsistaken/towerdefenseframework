--!strict
--[[
	Tests for the trait -> multiplier bridge.

	Small on purpose: the module is three multiplications. What earns the
	spec is the degradation contract - trait ids come from PERSISTED data,
	so an id deleted from the roster must become "no effect", never an error
	in the placement path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local TraitEffects = require(ReplicatedStorage.Shared.TraitEffects)
local Traits = require(ReplicatedStorage.Shared.Config.Traits)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("TraitEffects.multipliers", function()
	it("is the identity for no traits", function()
		local none = TraitEffects.multipliers({})

		expect(none.damage).toBe(1)
		expect(none.range).toBe(1)
		expect(none.fireRate).toBe(1)
	end)

	it("returns exactly the trait's numbers for a single trait", function()
		for _, id in Traits.IDS do
			local definition = Traits.get(id)
			local multipliers = TraitEffects.multipliers({ id })

			expect(multipliers.damage).toBeCloseTo(definition.damage, 10)
			expect(multipliers.range).toBeCloseTo(definition.range, 10)
			expect(multipliers.fireRate).toBeCloseTo(definition.fireRate, 10)
		end
	end)

	it("multiplies traits together, ready for SLOTS > 1", function()
		local sturdy = Traits.get("Sturdy")
		local overclocked = Traits.get("Overclocked")
		local combined = TraitEffects.multipliers({ "Sturdy", "Overclocked" })

		expect(combined.damage).toBeCloseTo(sturdy.damage * overclocked.damage, 10)
		expect(combined.range).toBeCloseTo(sturdy.range * overclocked.range, 10)
		expect(combined.fireRate).toBeCloseTo(sturdy.fireRate * overclocked.fireRate, 10)
	end)

	it("treats an unknown id as no effect, because saved data outlives rosters", function()
		local ghosted = TraitEffects.multipliers({ "DeletedFromRoster" })

		expect(ghosted.damage).toBe(1)
		expect(ghosted.range).toBe(1)
		expect(ghosted.fireRate).toBe(1)

		-- And mixed with a real trait, the real one still applies alone.
		local mixed = TraitEffects.multipliers({ "DeletedFromRoster", "Brutal" })
		expect(mixed.damage).toBeCloseTo(Traits.get("Brutal").damage, 10)
	end)
end)

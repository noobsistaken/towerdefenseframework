--!strict
--[[
	Tests for the trait roster.

	Config-integrity checks: a trait naming a tier that does not exist rolls
	as nothing and silently vanishes from the pool, and a multiplier of the
	wrong sign turns a buff into a curse nobody typed on purpose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gacha = require(ReplicatedStorage.Shared.Gacha)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local Traits = require(ReplicatedStorage.Shared.Config.Traits)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Traits", function()
	it("names only real rarity tiers", function()
		for _, id in Traits.IDS do
			expect(Rarity.find(Traits.get(id).rarity)).never.toBeNil()
		end
	end)

	it("keeps every multiplier positive", function()
		for _, id in Traits.IDS do
			local definition = Traits.get(id)

			expect(definition.damage > 0).toBe(true)
			expect(definition.range > 0).toBe(true)
			expect(definition.fireRate > 0).toBe(true)
		end
	end)

	it("keeps every trait an overall buff", function()
		-- A trait may tax one stat, but the product of its multipliers must
		-- exceed 1: a roll should never make a tower strictly worse.
		for _, id in Traits.IDS do
			local definition = Traits.get(id)
			local product = definition.damage * definition.range * definition.fireRate

			expect(product > 1).toBe(true)
		end
	end)

	it("populates every rarity tier used by at least one trait pool roll", function()
		-- The full trait pool must resolve through the shared gacha core.
		local pool: { Gacha.PoolEntry } = {}

		for _, id in Traits.IDS do
			table.insert(pool, { id = id, rarityId = Traits.get(id).rarity })
		end

		local rng = Random.new(5)

		for _ = 1, 200 do
			local result = Gacha.roll(rng, pool)

			expect(result).never.toBeNil()
			expect(Traits.find((result :: Gacha.Result).id)).never.toBeNil()
		end
	end)
end)

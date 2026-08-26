--!strict
--[[
	Tests for the gacha's rolling core.

	Worth having because a gacha whose real odds drift from its advertised
	odds is the one bug players will never forgive - and because the roll is
	pure, every property here is checkable with a seeded Random and a loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gacha = require(ReplicatedStorage.Shared.Gacha)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

--- One tower per tier, the simplest full pool.
local function fullPool(): { Gacha.PoolEntry }
	local pool: { Gacha.PoolEntry } = {}

	for _, id in Rarity.IDS do
		table.insert(pool, { towerId = `Tower_{id}`, rarityId = id })
	end

	return pool
end

describe("Rarity ladder", function()
	it("keeps its advertised weights summing to 100", function()
		-- The number shown to a player IS the number the roll uses; a sum
		-- other than 100 means the display lies.
		expect(Gacha.totalWeight()).toBe(100)
	end)

	it("orders its tiers strictly", function()
		local last = 0

		for _, id in Rarity.IDS do
			local order = Rarity.get(id).order

			expect(order > last).toBe(true)
			last = order
		end
	end)
end)

describe("Gacha.roll", function()
	it("returns nil only for an empty pool", function()
		expect(Gacha.roll(Random.new(1), {})).toBeNil()
		expect(Gacha.roll(Random.new(1), fullPool())).never.toBeNil()
	end)

	it("is deterministic under a seeded Random", function()
		local a = Gacha.roll(Random.new(42), fullPool())
		local b = Gacha.roll(Random.new(42), fullPool())

		expect((a :: Gacha.Result).towerId).toBe((b :: Gacha.Result).towerId)
	end)

	it("tracks the ladder's weights over many rolls", function()
		local rng = Random.new(7)
		local pool = fullPool()
		local counts: { [string]: number } = {}
		local rolls = 20000

		for _ = 1, rolls do
			local result = Gacha.roll(rng, pool) :: Gacha.Result
			counts[result.rarityId] = (counts[result.rarityId] or 0) + 1
		end

		for _, id in Rarity.IDS do
			local expected = Rarity.get(id).gachaWeight / 100
			local observed = (counts[id] or 0) / rolls

			-- Loose band: this is a sanity check on the wiring, not a
			-- statistics exam. A broken weight table misses this by miles.
			expect(math.abs(observed - expected) < 0.02).toBe(true)
		end
	end)

	it("falls DOWN the ladder when the drawn tier is empty", function()
		-- Pool with only Commons: every roll must land Common, including the
		-- rolls whose drawn tier was Secret.
		local pool: { Gacha.PoolEntry } = {
			{ towerId = "A", rarityId = "Common" },
			{ towerId = "B", rarityId = "Common" },
		}

		local rng = Random.new(3)

		for _ = 1, 500 do
			local result = Gacha.roll(rng, pool) :: Gacha.Result
			expect(result.rarityId).toBe("Common")
		end
	end)

	it("walks UP when the pool holds only higher tiers", function()
		-- A pool of one Secret: rolls that drew Common cannot fall lower and
		-- must still resolve rather than returning nil.
		local pool: { Gacha.PoolEntry } = {
			{ towerId = "S", rarityId = "Secret" },
		}

		local rng = Random.new(9)

		for _ = 1, 200 do
			local result = Gacha.roll(rng, pool) :: Gacha.Result
			expect(result.towerId).toBe("S")
		end
	end)

	it("splits a tier's chance evenly across its towers", function()
		local pool: { Gacha.PoolEntry } = {
			{ towerId = "A", rarityId = "Common" },
			{ towerId = "B", rarityId = "Common" },
		}

		local rng = Random.new(11)
		local a = 0
		local rolls = 4000

		for _ = 1, rolls do
			local result = Gacha.roll(rng, pool) :: Gacha.Result

			if result.towerId == "A" then
				a += 1
			end
		end

		expect(math.abs(a / rolls - 0.5) < 0.05).toBe(true)
	end)
end)

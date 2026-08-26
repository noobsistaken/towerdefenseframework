--!strict
--[[
	Tests for the gacha's transaction rules.

	The invariants under test are the ones money-handling code actually
	breaks: a refused roll taking coins anyway, a duplicate refunding the
	wrong fraction, a reroll stacking traits past SLOTS, and conservation -
	coins may only ever move by exactly the amounts the config names.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local GachaFlow = require(ReplicatedStorage.Shared.GachaFlow)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Traits = require(ReplicatedStorage.Shared.Config.Traits)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function freshData(coins: number, tokens: number): Types.PlayerData
	return {
		Version = 3,
		Coins = coins,
		XP = 0,
		Level = 1,
		UnlockedTowers = { "Rifleman", "Ranger" },
		Traits = {},
		RerollTokens = tokens,
		Stats = { MatchesPlayed = 0, MatchesWon = 0, HighestWave = 0, EnemiesKilled = 0 },
		Settings = { MusicEnabled = true, SfxEnabled = true },
	}
end

describe("GachaFlow.towerPool", function()
	it("covers the whole roster with real rarities", function()
		local pool = GachaFlow.towerPool()

		expect(#pool).toBe(#Towers.IDS)

		for _, entry in pool do
			expect(Towers.get(entry.id).rarity).toBe(entry.rarityId)
		end
	end)
end)

describe("GachaFlow.rollTower", function()
	it("refuses without charging when the player cannot afford it", function()
		local data = freshData(Economy.GACHA_ROLL_COST - 1, 0)
		local result = GachaFlow.rollTower(data, Random.new(1))

		expect(result.outcome).toBe("CannotAfford")
		expect(data.Coins).toBe(Economy.GACHA_ROLL_COST - 1)
		expect(#data.UnlockedTowers).toBe(2)
	end)

	it("charges exactly the price and grants the tower on a fresh roll", function()
		-- Seeds are cheap: walk until a roll lands something unowned, then
		-- assert the exact ledger movement for that roll.
		for seed = 1, 100 do
			local data = freshData(Economy.GACHA_ROLL_COST, 0)
			local result = GachaFlow.rollTower(data, Random.new(seed))

			if result.outcome == "Rolled" then
				expect(data.Coins).toBe(0)
				expect(table.find(data.UnlockedTowers, result.towerId)).never.toBeNil()
				expect(Towers.get(result.towerId).rarity).toBe(result.rarityId)
				return
			end
		end

		error("no seed in 1..100 rolled an unowned tower")
	end)

	it("refunds the advertised fraction on a duplicate, and only that", function()
		for seed = 1, 200 do
			local data = freshData(Economy.GACHA_ROLL_COST, 0)
			local result = GachaFlow.rollTower(data, Random.new(seed))

			if result.outcome == "Duplicate" then
				local refund = math.floor(Economy.GACHA_ROLL_COST * Economy.GACHA_DUPLICATE_REFUND_RATE)

				expect(result.refunded).toBe(refund)
				expect(data.Coins).toBe(refund)
				-- The roster must not have grown: they already owned it.
				expect(#data.UnlockedTowers).toBe(2)
				return
			end
		end

		error("no seed in 1..200 rolled a duplicate")
	end)

	it("conserves coins across many rolls: every delta is a named amount", function()
		local data = freshData(100000, 0)
		local rng = Random.new(99)
		local refund = math.floor(Economy.GACHA_ROLL_COST * Economy.GACHA_DUPLICATE_REFUND_RATE)

		for _ = 1, 200 do
			local before = data.Coins
			local result = GachaFlow.rollTower(data, rng)

			if result.outcome == "Rolled" then
				expect(before - data.Coins).toBe(Economy.GACHA_ROLL_COST)
			elseif result.outcome == "Duplicate" then
				expect(before - data.Coins).toBe(Economy.GACHA_ROLL_COST - refund)
			else
				expect(data.Coins).toBe(before)
			end
		end

		-- 200 rolls at 400 a roll from 100k: the whole roster must be owned
		-- by now, and owned exactly once each.
		for _, id in Towers.IDS do
			local first = table.find(data.UnlockedTowers, id)

			expect(first).never.toBeNil()
			expect(table.find(data.UnlockedTowers, id, (first :: number) + 1)).toBeNil()
		end
	end)
end)

describe("GachaFlow.rerollTrait", function()
	it("refuses a tower the player does not own, free of charge", function()
		local data = freshData(0, 5)
		local result = GachaFlow.rerollTrait(data, "Marksman", Random.new(1))

		expect(result.outcome).toBe("UnknownTower")
		expect(data.RerollTokens).toBe(5)
	end)

	it("refuses a forged tower id the same way", function()
		local data = freshData(0, 5)
		table.insert(data.UnlockedTowers, "NotARealTower")

		expect(GachaFlow.rerollTrait(data, "NotARealTower", Random.new(1)).outcome).toBe("UnknownTower")
	end)

	it("refuses without spending when out of tokens", function()
		local data = freshData(0, 0)
		local result = GachaFlow.rerollTrait(data, "Rifleman", Random.new(1))

		expect(result.outcome).toBe("CannotAfford")
		expect(data.Traits.Rifleman).toBeNil()
	end)

	it("spends one token and writes exactly one trait", function()
		local data = freshData(0, 3)
		local result = GachaFlow.rerollTrait(data, "Rifleman", Random.new(7))

		expect(result.outcome).toBe("Rolled")
		expect(data.RerollTokens).toBe(3 - Economy.TRAIT_REROLL_TOKEN_COST)

		local rolled: { string }? = data.Traits.Rifleman

		expect(rolled).never.toBeNil()
		expect(#(rolled :: { string })).toBe(Traits.SLOTS)
		expect(Traits.find(result.traitId)).never.toBeNil()
	end)

	it("REPLACES on reroll, never stacks past SLOTS", function()
		local data = freshData(0, 10)

		for _ = 1, 5 do
			expect(GachaFlow.rerollTrait(data, "Ranger", Random.new(11)).outcome).toBe("Rolled")
		end

		local rolled: { string }? = data.Traits.Ranger

		expect(#(rolled :: { string })).toBe(Traits.SLOTS)
		expect(data.RerollTokens).toBe(5)
	end)
end)

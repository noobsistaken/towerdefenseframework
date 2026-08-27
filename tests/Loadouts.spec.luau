--!strict
--[[
	Tests for the loadout rules.

	The requests come from clients, so every rule here is an exploit test as
	much as a UX one: an oversized deck is extra shop buttons the design says
	you chose not to have, and a deck of unowned towers is theft.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Loadouts = require(ReplicatedStorage.Shared.Loadouts)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function freshData(): Types.PlayerData
	return {
		Version = 4,
		Coins = 0,
		XP = 0,
		Level = 1,
		UnlockedTowers = { "Rifleman", "Ranger", "Mortar", "Marksman", "Flak", "Lacerator", "Scout", "Gunner" },
		Loadout = { "Rifleman", "Ranger" },
		Traits = {},
		RerollTokens = 0,
		RollsSinceSecret = 0,
		Stats = { MatchesPlayed = 0, MatchesWon = 0, HighestWave = 0, EnemiesKilled = 0 },
		Settings = { MusicEnabled = true, SfxEnabled = true },
	}
end

describe("Loadouts.apply", function()
	it("accepts a legal deck and replaces the old one whole", function()
		local data = freshData()

		expect(Loadouts.apply(data, { "Scout", "Gunner", "Mortar" })).toBe(true)
		expect(#data.Loadout).toBe(3)
		expect(data.Loadout[1]).toBe("Scout")
	end)

	it("refuses an empty deck and an oversized one, writing nothing", function()
		local data = freshData()

		expect(Loadouts.apply(data, {})).toBe(false)
		expect(Loadouts.apply(data, { "Rifleman", "Ranger", "Mortar", "Marksman", "Flak", "Lacerator", "Scout" })).toBe(
			false
		)
		expect(#data.Loadout).toBe(2)
	end)

	it("refuses towers the player does not own", function()
		local data = freshData()

		expect(Loadouts.apply(data, { "Rifleman", "Godhand" })).toBe(false)
		expect(data.Loadout[1]).toBe("Rifleman")
		expect(#data.Loadout).toBe(2)
	end)

	it("refuses forged ids and duplicates", function()
		local data = freshData()

		expect(Loadouts.apply(data, { "NotATower" })).toBe(false)
		expect(Loadouts.apply(data, { "Rifleman", "Rifleman" })).toBe(false)
	end)

	it("does not alias the caller's table into persisted data", function()
		local data = freshData()
		local request = { "Scout" }

		Loadouts.apply(data, request)
		table.insert(request, "Gunner")

		expect(#data.Loadout).toBe(1)
	end)
end)

describe("Loadouts.resolve", function()
	it("returns the persisted deck when it is fully valid", function()
		local data = freshData()
		local deck = Loadouts.resolve(data)

		expect(#deck).toBe(2)
		expect(deck[1]).toBe("Rifleman")
	end)

	it("silently drops entries that stopped being owned or real", function()
		local data = freshData()
		data.Loadout = { "Rifleman", "DeletedFromRoster", "Godhand" }

		local deck = Loadouts.resolve(data)

		expect(#deck).toBe(1)
		expect(deck[1]).toBe("Rifleman")
	end)

	it("tops up from the owned roster rather than returning an empty shop", function()
		local data = freshData()
		data.Loadout = { "DeletedFromRoster" }

		local deck = Loadouts.resolve(data)

		expect(#deck).toBe(Loadouts.MAX)
		expect(deck[1]).toBe("Rifleman")
	end)
end)

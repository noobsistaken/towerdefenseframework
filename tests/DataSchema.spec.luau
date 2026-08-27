--!strict
--[[
	Tests for the player-data migration ladder.

	These are the tests worth having: data migration is the one subsystem
	where a bug is unrecoverable, because it corrupts data that already
	belongs to real players.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataSchema = require(ReplicatedStorage.Shared.DataSchema)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("DataSchema", function()
	it("ships a template stamped at the current version", function()
		expect(DataSchema.TEMPLATE.Version).toBe(DataSchema.CURRENT_VERSION)
	end)

	it("treats up-to-date data as a no-op", function()
		local data = table.clone(DataSchema.TEMPLATE)
		expect(DataSchema.migrate(data)).toBe(0)
		expect(data.Version).toBe(DataSchema.CURRENT_VERSION)
	end)

	it("refuses to guess when a migration step is missing", function()
		local data = table.clone(DataSchema.TEMPLATE)
		-- Version 0 has never existed and can never gain a ladder rung, so
		-- this stays a missing-step probe no matter how long the real ladder
		-- grows. The original form used CURRENT_VERSION - 1, which stopped
		-- being a missing step the day rung 1 was added.
		data.Version = 0

		expect(function()
			DataSchema.migrate(data)
		end).toThrow()
	end)

	it("walks v1 data the whole ladder to the current version", function()
		local data = table.clone(DataSchema.TEMPLATE)
		data.Version = 1
		-- What a real v1 profile holds: the original two starters, plus one
		-- extra to prove the union keeps unknown entries and cannot
		-- duplicate an existing one.
		data.UnlockedTowers = { "Rifleman", "Ranger", "Mortar" }

		-- One step per rung, all the way up - the count grows with the
		-- ladder, which is the point: a v1 profile can never get stranded.
		expect(DataSchema.migrate(data)).toBe(DataSchema.CURRENT_VERSION - 1)
		expect(data.Version).toBe(DataSchema.CURRENT_VERSION)

		-- v3's and v4's additions arrive on the way through.
		expect(type(data.Traits)).toBe("table")
		expect(data.RerollTokens).toBe(0)
		expect(#data.Loadout > 0).toBe(true)
		expect(#data.Loadout <= 6).toBe(true)

		for _, id in { "Rifleman", "Ranger", "Mortar", "Marksman", "Flak", "Lacerator" } do
			expect(table.find(data.UnlockedTowers, id) ~= nil).toBe(true)
		end

		-- Union, not append: Mortar was already owned and must appear once.
		local mortars = 0
		for _, id in data.UnlockedTowers do
			if id == "Mortar" then
				mortars += 1
			end
		end
		expect(mortars).toBe(1)
	end)

	it("gives a v2 profile its trait storage without touching its towers", function()
		local data = table.clone(DataSchema.TEMPLATE)
		data.Version = 2
		data.UnlockedTowers = { "Rifleman", "Flak" }

		expect(DataSchema.migrate(data)).toBe(DataSchema.CURRENT_VERSION - 2)
		expect(data.Version).toBe(DataSchema.CURRENT_VERSION)
		expect(type(data.Traits)).toBe("table")
		expect(data.RerollTokens).toBe(0)
		expect(#data.UnlockedTowers).toBe(2)
	end)

	it("deals a v3 profile its first deck from what it owns, in order", function()
		local data = table.clone(DataSchema.TEMPLATE)
		data.Version = 3
		-- Nine owned: the deck takes the first six exactly.
		data.UnlockedTowers =
			{ "Rifleman", "Ranger", "Mortar", "Marksman", "Flak", "Lacerator", "Scout", "Gunner", "Hexer" }

		-- Walks every remaining rung, not just the one under test: this
		-- assertion is about the DECK the v3 rung deals, so it is written
		-- against CURRENT_VERSION rather than against whatever the top of
		-- the ladder happened to be the day it was written.
		expect(DataSchema.migrate(data)).toBe(DataSchema.CURRENT_VERSION - 3)
		expect(data.Version).toBe(DataSchema.CURRENT_VERSION)
		expect(#data.Loadout).toBe(6)
		expect(data.Loadout[1]).toBe("Rifleman")
		expect(data.Loadout[6]).toBe("Lacerator")
		-- The collection itself is untouched.
		expect(#data.UnlockedTowers).toBe(9)
	end)

	it("never leaves data below the current version", function()
		local data = table.clone(DataSchema.TEMPLATE)
		DataSchema.migrate(data)
		expect(data.Version >= DataSchema.CURRENT_VERSION).toBe(true)
	end)
end)

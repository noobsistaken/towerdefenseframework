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
		data.Version = DataSchema.CURRENT_VERSION - 1

		expect(function()
			DataSchema.migrate(data)
		end).toThrow()
	end)

	it("never leaves data below the current version", function()
		local data = table.clone(DataSchema.TEMPLATE)
		DataSchema.migrate(data)
		expect(data.Version >= DataSchema.CURRENT_VERSION).toBe(true)
	end)
end)

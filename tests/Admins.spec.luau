--!strict
--[[
	Tests for the admin allowlist.

	Two lines of logic, but the failure modes are asymmetric: a false
	positive hands a stranger a money printer, a false negative only
	inconveniences one person. The spec pins both directions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Config.Admins)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Admins.isAdmin", function()
	it("admits a listed account in production", function()
		expect(Admins.isAdmin(289104678, false)).toBe(true)
	end)

	it("refuses everyone else in production", function()
		expect(Admins.isAdmin(1, false)).toBe(false)
		expect(Admins.isAdmin(0, false)).toBe(false)
		expect(Admins.isAdmin(-1, false)).toBe(false)
	end)

	it("admits anyone in Studio, where grants touch nothing live", function()
		expect(Admins.isAdmin(1, true)).toBe(true)
	end)
end)

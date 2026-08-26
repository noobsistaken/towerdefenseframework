--!strict
--[[
	Tests for the boot gate.

	Worth having because the failure it prevents is silent and production
	only: both entry scripts exist in every superset-synced tree, and a place
	that boots the wrong one - or both - ships a match running inside the
	live lobby. No Studio test can see production; this pure function is the
	next best thing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Places = require(ReplicatedStorage.Shared.Config.Places)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Places.shouldBoot", function()
	it("lets only STUDIO_ROLE boot in Studio, whatever the place id", function()
		-- Literal args, not a variable holding STUDIO_ROLE: the old solver
		-- widens the table field to string, which can't pass as PlaceRole.
		local lobbyWins = Places.STUDIO_ROLE == "Lobby"

		expect(Places.shouldBoot("Lobby", true, 0)).toBe(lobbyWins)
		expect(Places.shouldBoot("Match", true, 0)).toBe(not lobbyWins)
		-- The id must not matter in Studio: the test place's id is neither.
		expect(Places.shouldBoot("Lobby", true, 123456)).toBe(lobbyWins)
		expect(Places.shouldBoot("Match", true, 123456)).toBe(not lobbyWins)
	end)

	it("boots each role only in its own place outside Studio", function()
		expect(Places.shouldBoot("Lobby", false, Places.LOBBY_PLACE_ID)).toBe(true)
		expect(Places.shouldBoot("Match", false, Places.MATCH_PLACE_ID)).toBe(true)

		-- The cross cases are the entire point: a superset published to the
		-- wrong place must boot NEITHER wrong role.
		expect(Places.shouldBoot("Match", false, Places.LOBBY_PLACE_ID)).toBe(false)
		expect(Places.shouldBoot("Lobby", false, Places.MATCH_PLACE_ID)).toBe(false)
	end)

	it("boots nothing for an unknown place outside Studio", function()
		expect(Places.shouldBoot("Lobby", false, 999)).toBe(false)
		expect(Places.shouldBoot("Match", false, 999)).toBe(false)
	end)

	it("is configured, and the gate depends on it", function()
		-- The ids-unset fallback (entry presence decides) cannot be exercised
		-- here without mutating shared config, so instead pin the premise:
		-- this repo HAS real ids, which is what arms the id gate at all.
		expect(Places.isConfigured()).toBe(true)
		expect(Places.LOBBY_PLACE_ID ~= Places.MATCH_PLACE_ID).toBe(true)
	end)
end)

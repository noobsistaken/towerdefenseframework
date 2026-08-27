--!strict
--[[
	Tests for validating untrusted teleport data.

	This is the match place's trust boundary. TeleportData is not guaranteed
	tamper-proof, so every one of these is phrased as "what would a forged or
	malformed payload do", and the property being defended is simple enough to
	state in one line:

	    parse NEVER returns an id that is not in the registry, and NEVER raises.

	The second half matters as much as the first. This runs while a player is
	joining, and an error there is a player who never finishes loading.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArrivalGate = require(ServerScriptService.Server.Match.ArrivalGate)
local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

--- Every shape a malformed or hostile payload could plausibly take.
local MALFORMED: { any } = {
	nil,
	false,
	0,
	"",
	"mapId=Bastion",
	{},
	{ mapId = 42 },
	{ mapId = {} },
	{ mapId = false },
	{ difficultyId = 42 },
	{ mapId = "Bastion", difficultyId = 42 },
	{ mapId = "", difficultyId = "" },
	{ mapId = "NoSuchMap", difficultyId = "NoSuchDifficulty" },
	{ mapId = "crossroads" },
	{ nested = { mapId = "Bastion" } },
}

describe("ArrivalGate.parse: the security property", function()
	it("never returns an id outside the registry", function()
		-- Asserted over every malformed shape at once, because the property
		-- is about the function's whole range rather than any one input.
		for index = 1, 16 do
			local result = ArrivalGate.parse(MALFORMED[index])

			expect(MapRegistry.find(result.mapId) ~= nil).toBe(true)
			expect(Difficulty.find(result.difficultyId) ~= nil).toBe(true)
		end
	end)

	it("never raises", function()
		for index = 1, 16 do
			local ok = pcall(function()
				ArrivalGate.parse(MALFORMED[index])
			end)

			expect(ok).toBe(true)
		end
	end)
end)

describe("ArrivalGate.parse: defaults", function()
	it("falls back when there is no data at all", function()
		local result = ArrivalGate.parse(nil)

		expect(result.mapId).toBe(MapRegistry.DEFAULT_ID)
		expect(result.difficultyId).toBe(Difficulty.DEFAULT_ID)
	end)

	it("falls back when the payload is not a table", function()
		-- Indexing a string would raise, which is the failure this guards.
		expect(ArrivalGate.parse("Bastion").mapId).toBe(MapRegistry.DEFAULT_ID)
		expect(ArrivalGate.parse(7).mapId).toBe(MapRegistry.DEFAULT_ID)
	end)

	it("falls back on a field of the wrong type", function()
		expect(ArrivalGate.parse({ mapId = 42 }).mapId).toBe(MapRegistry.DEFAULT_ID)
	end)

	it("falls back on an id that does not exist", function()
		expect(ArrivalGate.parse({ mapId = "NoSuchMap" }).mapId).toBe(MapRegistry.DEFAULT_ID)
	end)

	it("is case sensitive", function()
		-- Ids are compared exactly. Accepting "crossroads" would mean the
		-- allowlist and the registry disagreed about what an id is.
		expect(ArrivalGate.parse({ mapId = "crossroads" }).mapId).toBe(MapRegistry.DEFAULT_ID)
	end)
end)

describe("ArrivalGate.parse: legitimate payloads", function()
	it("accepts every map the lobby could have voted for", function()
		-- If this ever fails, the lobby can send something the match refuses,
		-- and a vote would silently land on the default map instead.
		for _, id in MapRegistry.IDS do
			expect(ArrivalGate.parse({ mapId = id }).mapId).toBe(id)
		end
	end)

	it("accepts every difficulty the lobby could have voted for", function()
		for _, id in Difficulty.IDS do
			expect(ArrivalGate.parse({ difficultyId = id }).difficultyId).toBe(id)
		end
	end)

	it("takes both fields together", function()
		local result = ArrivalGate.parse({ mapId = "Bastion", difficultyId = "Nightmare" })

		expect(result.mapId).toBe("Bastion")
		expect(result.difficultyId).toBe("Nightmare")
	end)

	it("keeps a good field when the other is junk", function()
		-- Partial corruption should not throw away the half that was fine.
		local result = ArrivalGate.parse({ mapId = "Bastion", difficultyId = 999 })

		expect(result.mapId).toBe("Bastion")
		expect(result.difficultyId).toBe(Difficulty.DEFAULT_ID)
	end)
end)

--!strict
--[[
	Tests for the lobby's walk-in vote zones.

	Worth having because the zones ARE the vote: a resolver that mistakes one
	zone for another silently miscounts votes, and overlapping zones would
	make a player on the boundary flicker between maps every scan tick.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("LobbyZones.zones", function()
	it("grows one zone per registered map", function()
		local zones = LobbyZones.zones()

		expect(#zones).toBe(#MapRegistry.IDS)

		for index, zone in zones do
			expect(zone.mapId).toBe(MapRegistry.IDS[index])
		end
	end)

	it("grows one pad per difficulty inside every zone", function()
		for _, zone in LobbyZones.zones() do
			expect(#zone.pads).toBe(#Difficulty.IDS)

			for index, pad in zone.pads do
				expect(pad.difficultyId).toBe(Difficulty.IDS[index])
			end
		end
	end)

	it("never lets two zones touch", function()
		-- A shared boundary is a player flickering between votes every scan.
		local zones = LobbyZones.zones()

		for i = 1, #zones do
			for j = i + 1, #zones do
				local a, b = zones[i], zones[j]
				local gapX = math.abs(a.center.X - b.center.X) - (a.size.X + b.size.X) / 2
				local gapZ = math.abs(a.center.Z - b.center.Z) - (a.size.Z + b.size.Z) / 2

				expect(gapX > 0 or gapZ > 0).toBe(true)
			end
		end
	end)

	it("keeps every pad fully inside its zone", function()
		for _, zone in LobbyZones.zones() do
			for _, pad in zone.pads do
				expect(math.abs(pad.center.X - zone.center.X) + pad.size.X / 2 <= zone.size.X / 2).toBe(true)
				expect(math.abs(pad.center.Z - zone.center.Z) + pad.size.Z / 2 <= zone.size.Z / 2).toBe(true)
			end
		end
	end)
end)

describe("LobbyZones.stations", function()
	it("keeps stations clear of every vote zone and of each other", function()
		-- A footprint shared with a zone would make walking up to roll also
		-- cast a map vote, silently.
		local stations = LobbyZones.stations()

		expect(#stations).toBe(2)

		for i = 1, #stations do
			for _, zone in LobbyZones.zones() do
				local a = stations[i]
				local gapX = math.abs(a.center.X - zone.center.X) - (a.size.X + zone.size.X) / 2
				local gapZ = math.abs(a.center.Z - zone.center.Z) - (a.size.Z + zone.size.Z) / 2

				expect(gapX > 0 or gapZ > 0).toBe(true)
			end

			for j = i + 1, #stations do
				local a, b = stations[i], stations[j]
				local gapX = math.abs(a.center.X - b.center.X) - (a.size.X + b.size.X) / 2
				local gapZ = math.abs(a.center.Z - b.center.Z) - (a.size.Z + b.size.Z) / 2

				expect(gapX > 0 or gapZ > 0).toBe(true)
			end
		end
	end)

	it("resolves a station centre to its id and everywhere else to nil", function()
		for _, station in LobbyZones.stations() do
			expect(LobbyZones.resolveStation(station.center)).toBe(station.id)
		end

		expect(LobbyZones.resolveStation(Vector3.new(0, 0, 1000))).toBeNil()
		-- The spawn pad must never sit inside a station: standing where you
		-- appear should not open a shop.
		expect(LobbyZones.resolveStation(Vector3.new(0, 0, 30))).toBeNil()
	end)
end)

describe("LobbyZones.resolve", function()
	it("resolves a zone centre to its map and no difficulty", function()
		for _, zone in LobbyZones.zones() do
			-- The centre is off the pad row by construction.
			local mapId, difficultyId = LobbyZones.resolve(zone.center)

			expect(mapId).toBe(zone.mapId)
			expect(difficultyId).toBeNil()
		end
	end)

	it("resolves a pad centre to its map AND difficulty", function()
		for _, zone in LobbyZones.zones() do
			for _, pad in zone.pads do
				local mapId, difficultyId = LobbyZones.resolve(pad.center)

				expect(mapId).toBe(zone.mapId)
				expect(difficultyId).toBe(pad.difficultyId)
			end
		end
	end)

	it("resolves far outside to nothing", function()
		local mapId, difficultyId = LobbyZones.resolve(Vector3.new(0, 0, 1000))

		expect(mapId).toBeNil()
		expect(difficultyId).toBeNil()
	end)

	it("ignores height entirely", function()
		local zone = LobbyZones.zones()[1]
		local mapId = LobbyZones.resolve(zone.center + Vector3.new(0, 50, 0))

		expect(mapId).toBe(zone.mapId)
	end)
end)

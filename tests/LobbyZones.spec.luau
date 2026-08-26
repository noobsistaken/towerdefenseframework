--!strict
--[[
	Tests for the lobby hub's walk-in areas.

	Three readers share this one layout - the builder draws it, the server
	scans occupancy against it, the client opens panels from it - so a
	geometry mistake here is simultaneously a rendering, gameplay and UI
	bug. Overlaps are the killer: a footprint shared between two areas
	makes one pad open two panels and one launch take bystanders along.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("LobbyZones.AREAS", function()
	it("holds the three areas of the sketch, Game first", function()
		expect(#LobbyZones.AREAS).toBe(3)
		expect(LobbyZones.AREAS[1].id).toBe("Game")
		expect(LobbyZones.find("Gacha")).never.toBeNil()
		expect(LobbyZones.find("Reroll")).never.toBeNil()
		expect(LobbyZones.find("NotAnArea")).toBeNil()
	end)

	it("never lets two areas touch", function()
		for i = 1, #LobbyZones.AREAS do
			for j = i + 1, #LobbyZones.AREAS do
				local a, b = LobbyZones.AREAS[i], LobbyZones.AREAS[j]
				local gapX = math.abs(a.center.X - b.center.X) - (a.size.X + b.size.X) / 2
				local gapZ = math.abs(a.center.Z - b.center.Z) - (a.size.Z + b.size.Z) / 2

				expect(gapX > 0 or gapZ > 0).toBe(true)
			end
		end
	end)

	it("keeps every area clear of the spawn", function()
		-- Standing where you appear must not open a panel - and must never
		-- put a fresh spawn inside the GAME area, where someone else's
		-- START press would teleport them without a single step taken.
		expect(LobbyZones.resolveArea(Vector3.new(0, 0, 0))).toBeNil()

		-- The whole 12-stud spawn pad, corners included.
		for _, dx in { -6, 6 } do
			for _, dz in { -6, 6 } do
				expect(LobbyZones.resolveArea(Vector3.new(dx, 0, dz))).toBeNil()
			end
		end
	end)
end)

describe("LobbyZones.resolveArea", function()
	it("resolves every area's centre to its id", function()
		for _, area in LobbyZones.AREAS do
			expect(LobbyZones.resolveArea(area.center)).toBe(area.id)
		end
	end)

	it("resolves the open floor and the far distance to nil", function()
		expect(LobbyZones.resolveArea(Vector3.new(0, 0, 1000))).toBeNil()
	end)

	it("resolves edges inclusively and just-outside exclusively", function()
		local area = LobbyZones.AREAS[1]
		local edge = area.center + Vector3.new(area.size.X / 2, 0, 0)

		expect(LobbyZones.resolveArea(edge)).toBe(area.id)
		expect(LobbyZones.resolveArea(edge + Vector3.new(0.5, 0, 0))).toBeNil()
	end)

	it("ignores height entirely", function()
		local area = LobbyZones.AREAS[1]

		expect(LobbyZones.resolveArea(area.center + Vector3.new(0, 50, 0))).toBe(area.id)
	end)
end)

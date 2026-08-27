--!strict
--[[
	Registry-wide structural checks on every map config.

	A map with a diagonal segment, a waypoint off the ground slab, or a lane
	that ends nowhere near the base does not fail loudly - it builds, looks
	plausible from above, and then enemies walk through scenery or leak at a
	spot no tower was told about. These are the invariants every existing map
	satisfies and every new one must.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("MapRegistry", function()
	it("holds both maps and a real default", function()
		expect(#MapRegistry.IDS).toBe(2)
		expect(MapRegistry.find(MapRegistry.DEFAULT_ID)).never.toBeNil()
	end)

	it("keys every map by its own id", function()
		for id, map in MapRegistry.MAPS do
			expect(map.id).toBe(id)
			expect(#map.displayName > 0).toBe(true)
		end
	end)
end)

describe("Map structure", function()
	it("gives every lane at least two waypoints on the path plane", function()
		for _, id in MapRegistry.IDS do
			local map = MapRegistry.get(id)

			expect(#map.paths > 0).toBe(true)

			for _, path in map.paths do
				expect(#path.waypoints >= 2).toBe(true)

				for _, waypoint in path.waypoints do
					-- The simulation's path plane is y = 0; the walkway is
					-- drawn above it and feet are planted by WALKWAY_TOP.
					expect(waypoint.Y).toBe(0)
				end
			end
		end
	end)

	it("keeps every segment axis-aligned and longer than zero", function()
		-- MapBuilder draws walkways as axis-aligned slabs; a diagonal segment
		-- would still simulate but render as enemies walking on air.
		for _, id in MapRegistry.IDS do
			for _, path in MapRegistry.get(id).paths do
				for index = 2, #path.waypoints do
					local from = path.waypoints[index - 1]
					local to = path.waypoints[index]
					local dx = math.abs(to.X - from.X)
					local dz = math.abs(to.Z - from.Z)

					expect(dx == 0 or dz == 0).toBe(true)
					expect(dx + dz > 0).toBe(true)
				end
			end
		end
	end)

	it("keeps every waypoint on the ground slab", function()
		for _, id in MapRegistry.IDS do
			local map = MapRegistry.get(id)
			local halfX = map.groundSize.X / 2
			local halfZ = map.groundSize.Z / 2

			for _, path in map.paths do
				for _, waypoint in path.waypoints do
					expect(math.abs(waypoint.X) <= halfX).toBe(true)
					expect(math.abs(waypoint.Z) <= halfZ).toBe(true)
				end
			end
		end
	end)

	it("ends every lane near the base it damages", function()
		-- The leak test is reaching the path end; basePosition is the marker
		-- players watch. If they drift apart, damage appears to come from
		-- nowhere.
		for _, id in MapRegistry.IDS do
			local map = MapRegistry.get(id)

			for _, path in map.paths do
				local last = path.waypoints[#path.waypoints]
				local offset = last - map.basePosition

				expect(offset.Magnitude <= 30).toBe(true)
			end
		end
	end)

	it("offers both surface types on every map", function()
		-- A map with no Elevated surface silently deletes the entire Hillside
		-- category from the shop; one with no Ground does worse.
		for _, id in MapRegistry.IDS do
			local hasGround = false
			local hasElevated = false

			for _, surface in MapRegistry.get(id).buildableSurfaces do
				if surface.surfaceType == "Ground" then
					hasGround = true
				elseif surface.surfaceType == "Elevated" then
					hasElevated = true
				end
			end

			expect(hasGround).toBe(true)
			expect(hasElevated).toBe(true)
		end
	end)

	it("names distinct lane lengths within every multi-lane map", function()
		-- Equal lanes make distance-remaining ordering untestable in play
		-- (D8): if this ever regresses to equal lengths, the map stops
		-- exercising the machinery it exists to exercise.
		for _, id in MapRegistry.IDS do
			local map = MapRegistry.get(id)

			if #map.paths < 2 then
				continue
			end

			local lengths: { number } = {}

			for _, path in map.paths do
				local total = 0

				for index = 2, #path.waypoints do
					total += (path.waypoints[index] - path.waypoints[index - 1]).Magnitude
				end

				table.insert(lengths, total)
			end

			table.sort(lengths)

			for index = 2, #lengths do
				expect(lengths[index] > lengths[index - 1]).toBe(true)
			end
		end
	end)
end)

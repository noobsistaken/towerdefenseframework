--!strict
--[[
	Tests for placement geometry.

	The two assertions that matter most are the ones about the lane: a tower
	that can be placed across the path turns a tower defense into a maze game,
	and a clearance rule that is too greedy makes half the map unbuildable.
	Both failure modes are tested from both sides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Footprint = require(ReplicatedStorage.Shared.Footprint)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local EPSILON = 1e-4

local function expectClose(actual: number, expected: number)
	expect(math.abs(actual - expected) < EPSILON).toBe(true)
end

--- An L-shaped lane: 100 studs along +X, then 100 along +Z.
local function lane(): { Vector3 }
	return {
		Vector3.new(0, 0, 0),
		Vector3.new(100, 0, 0),
		Vector3.new(100, 0, 100),
	}
end

describe("Footprint.radius", function()
	it("is half the longest side", function()
		expectClose(Footprint.radius(Vector2.new(6, 6)), 3)
		expectClose(Footprint.radius(Vector2.new(9, 4)), 4.5)
		expectClose(Footprint.radius(Vector2.new(4, 9)), 4.5)
	end)
end)

describe("Footprint.overlaps", function()
	it("lets two footprints sit exactly flush", function()
		-- Two 6x6 towers have radius 3 each, so centres 6 apart are touching
		-- and must be legal. Rejecting this would leave unusable gaps between
		-- every pair of adjacent towers.
		local a = Vector3.new(0, 0, 0)
		local b = Vector3.new(6, 0, 0)

		expect(Footprint.overlaps(a, 3, b, 3)).toBe(false)
	end)

	it("rejects any actual intersection", function()
		local a = Vector3.new(0, 0, 0)

		expect(Footprint.overlaps(a, 3, Vector3.new(5.99, 0, 0), 3)).toBe(true)
		expect(Footprint.overlaps(a, 3, Vector3.new(0, 0, 0), 3)).toBe(true)
	end)

	it("ignores height entirely", function()
		-- A tower on an elevated pad must not be placeable directly above one
		-- on the ground: the footprints still collide in plan view.
		local low = Vector3.new(0, 0, 0)
		local high = Vector3.new(1, 500, 0)

		expect(Footprint.overlaps(low, 3, high, 3)).toBe(true)
	end)

	it("measures diagonally, not per axis", function()
		-- Centres 5 apart on each axis are ~7.07 apart, which two radius-3
		-- footprints clear. An axis-wise test would wrongly call this a hit.
		local a = Vector3.new(0, 0, 0)
		local b = Vector3.new(5, 0, 5)

		expect(Footprint.overlaps(a, 3, b, 3)).toBe(false)
	end)
end)

describe("Footprint.distanceToSegment", function()
	it("measures perpendicular distance inside the segment", function()
		local a = Vector3.new(0, 0, 0)
		local b = Vector3.new(100, 0, 0)

		expectClose(Footprint.distanceToSegment(Vector3.new(50, 0, 12), a, b), 12)
	end)

	it("clamps to the endpoints rather than the infinite line", function()
		-- Past the end of the segment the answer must be the distance to the
		-- endpoint. Using the infinite line would report 0 here and let a
		-- tower sit on the lane just past its final waypoint.
		local a = Vector3.new(0, 0, 0)
		local b = Vector3.new(100, 0, 0)

		expectClose(Footprint.distanceToSegment(Vector3.new(-30, 0, 0), a, b), 30)
		expectClose(Footprint.distanceToSegment(Vector3.new(130, 0, 0), a, b), 30)
	end)

	it("ignores height", function()
		local a = Vector3.new(0, 0, 0)
		local b = Vector3.new(100, 0, 0)

		expectClose(Footprint.distanceToSegment(Vector3.new(50, 400, 9), a, b), 9)
	end)

	it("handles a degenerate segment without dividing by zero", function()
		local a = Vector3.new(10, 0, 10)

		expectClose(Footprint.distanceToSegment(Vector3.new(10, 0, 15), a, a), 5)
	end)
end)

describe("Footprint.distanceToPath", function()
	it("takes the nearest segment, not the first", function()
		-- This point is 60 from the first leg and 5 from the second.
		expectClose(Footprint.distanceToPath(Vector3.new(95, 0, 60), lane()), 5)
	end)

	it("is zero on the line itself", function()
		expectClose(Footprint.distanceToPath(Vector3.new(50, 0, 0), lane()), 0)
		expectClose(Footprint.distanceToPath(Vector3.new(100, 0, 50), lane()), 0)
	end)
end)

describe("Footprint.blocksPath", function()
	it("refuses a tower overlapping the lane", function()
		expect(Footprint.blocksPath(Vector3.new(50, 0, 0), 3, lane(), 9)).toBe(true)
	end)

	it("refuses one whose footprint merely reaches the lane", function()
		-- Centre 11 studs out with radius 3 leaves 8 studs of gap, inside the
		-- 9-stud clearance. The check must use the footprint edge, not the
		-- centre - otherwise a wide tower can straddle the path.
		expect(Footprint.blocksPath(Vector3.new(50, 0, 11), 3, lane(), 9)).toBe(true)
	end)

	it("allows one that clears it", function()
		-- 13 out, radius 3, leaves 10 studs of gap against a 9-stud rule.
		expect(Footprint.blocksPath(Vector3.new(50, 0, 13), 3, lane(), 9)).toBe(false)
	end)

	it("checks the corner as well as the straights", function()
		-- Just inside the elbow, which a per-segment test that stopped at the
		-- first leg would miss.
		expect(Footprint.blocksPath(Vector3.new(95, 0, 95), 3, lane(), 9)).toBe(true)
	end)
end)

describe("Footprint.isInsideBounds", function()
	local ground = Vector3.new(200, 4, 100)

	it("accepts a footprint well inside", function()
		expect(Footprint.isInsideBounds(Vector3.new(0, 0, 0), 5, ground)).toBe(true)
	end)

	it("accepts one exactly flush with the edge", function()
		expect(Footprint.isInsideBounds(Vector3.new(95, 0, 45), 5, ground)).toBe(true)
	end)

	it("rejects one hanging over any edge", function()
		expect(Footprint.isInsideBounds(Vector3.new(96, 0, 0), 5, ground)).toBe(false)
		expect(Footprint.isInsideBounds(Vector3.new(0, 0, -46), 5, ground)).toBe(false)
	end)

	it("rejects a footprint larger than the map", function()
		expect(Footprint.isInsideBounds(Vector3.new(0, 0, 0), 500, ground)).toBe(false)
	end)
end)

describe("Footprint.isOnSurface", function()
	local padPosition = Vector3.new(50, 10, -20)
	local padSize = Vector3.new(40, 4, 30)

	it("accepts a footprint fully on the pad", function()
		expect(Footprint.isOnSurface(Vector3.new(50, 0, -20), 5, padPosition, padSize)).toBe(true)
	end)

	it("rejects one hanging off the edge", function()
		-- Pad spans x 30..70. Centre 68 with radius 5 reaches 73.
		expect(Footprint.isOnSurface(Vector3.new(68, 0, -20), 5, padPosition, padSize)).toBe(false)
	end)

	it("rejects a footprint wider than the pad", function()
		expect(Footprint.isOnSurface(Vector3.new(50, 0, -20), 40, padPosition, padSize)).toBe(false)
	end)

	it("ignores the pad's height", function()
		-- The caller supplies a flat XZ position; the pad's Y must not matter
		-- to whether the footprint fits on it.
		expect(Footprint.isOnSurface(Vector3.new(50, 999, -20), 5, padPosition, padSize)).toBe(true)
	end)
end)

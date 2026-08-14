--!strict
--[[
	Tests for arc-length path parameterisation.

	Path is the module the entire enemy simulation rests on: an enemy is one
	number, and this turns that number into a world position. If the
	parameterisation is wrong, every enemy moves at the wrong speed and no
	amount of downstream code is correct.

	The assertions below are deliberately built around paths with UNEVEN
	segment lengths, because that is the only shape that distinguishes true
	arc-length parameterisation from the naive "lerp each segment by a
	normalised t" mistake. On evenly spaced waypoints both implementations
	agree, and a test that only uses even spacing proves nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Path = require(ReplicatedStorage.Shared.Path)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local EPSILON = 1e-4

--- Explicit epsilon comparison rather than a float matcher, so the assertion
--- depends only on `toBe`, which is certain to exist in this Jest build.
local function expectClose(actual: number, expected: number)
	expect(math.abs(actual - expected) < EPSILON).toBe(true)
end

local function expectVectorClose(actual: Vector3, expected: Vector3)
	expectClose(actual.X, expected.X)
	expectClose(actual.Y, expected.Y)
	expectClose(actual.Z, expected.Z)
end

--- Straight along +X, but with deliberately uneven waypoint spacing:
--- segments of 1, 100 and 4 studs. On this path positionAt(d).X must equal d
--- exactly, which is the cleanest possible statement of arc-length.
local function unevenStraightPath(): Path.Path
	return Path.new({
		Vector3.new(0, 0, 0),
		Vector3.new(1, 0, 0),
		Vector3.new(101, 0, 0),
		Vector3.new(105, 0, 0),
	})
end

--- An L: 30 studs east, then 40 studs north. Total 70.
local function cornerPath(): Path.Path
	return Path.new({
		Vector3.new(0, 0, 0),
		Vector3.new(30, 0, 0),
		Vector3.new(30, 0, 40),
	})
end

describe("Path.new", function()
	it("rejects a path with fewer than two waypoints", function()
		expect(function()
			Path.new({ Vector3.new(0, 0, 0) })
		end).toThrow()
	end)

	it("rejects duplicate consecutive waypoints", function()
		-- A zero-length segment has no defined direction. Tolerating it would
		-- push an undefined orientation into every enemy on that lane.
		expect(function()
			Path.new({
				Vector3.new(0, 0, 0),
				Vector3.new(5, 0, 0),
				Vector3.new(5, 0, 0),
			})
		end).toThrow()
	end)

	it("measures total length as the sum of its segments", function()
		expectClose(unevenStraightPath().totalLength, 105)
		expectClose(cornerPath().totalLength, 70)
	end)

	it("does not alias the caller's waypoint table", function()
		local waypoints = { Vector3.new(0, 0, 0), Vector3.new(10, 0, 0) }
		local path = Path.new(waypoints)

		waypoints[2] = Vector3.new(999, 0, 0)

		expectClose(path.totalLength, 10)
	end)
end)

describe("Path.positionAt", function()
	it("returns the endpoints at 0 and at total length", function()
		local path = unevenStraightPath()

		expectVectorClose(path:positionAt(0), Vector3.new(0, 0, 0))
		expectVectorClose(path:positionAt(path.totalLength), Vector3.new(105, 0, 0))
	end)

	it("clamps outside the path rather than extrapolating", function()
		local path = unevenStraightPath()

		expectVectorClose(path:positionAt(-50), Vector3.new(0, 0, 0))
		expectVectorClose(path:positionAt(9999), Vector3.new(105, 0, 0))
	end)

	it("walks exactly d studs for a query of d", function()
		-- The core arc-length property. Under a naive per-segment lerp the
		-- 100-stud middle segment would be traversed in the same "time" as
		-- the 1-stud first segment and these would all fail.
		local path = unevenStraightPath()

		for _, d in { 0.5, 1, 1.5, 25, 50.5, 100, 101, 103, 105 } do
			expectClose(path:positionAt(d).X, d)
		end
	end)

	it("covers equal ground for equal steps", function()
		-- Constant speed in, constant speed out - stated without reference to
		-- the implementation, so it holds whatever the waypoint spacing is.
		local path = unevenStraightPath()
		local step = 3
		local previous = path:positionAt(0)

		for i = 1, 34 do
			local current = path:positionAt(i * step)
			expectClose((current - previous).Magnitude, step)
			previous = current
		end
	end)

	it("turns the corner at the right place", function()
		local path = cornerPath()

		expectVectorClose(path:positionAt(30), Vector3.new(30, 0, 0))
		expectVectorClose(path:positionAt(15), Vector3.new(15, 0, 0))
		expectVectorClose(path:positionAt(50), Vector3.new(30, 0, 20))
	end)
end)

describe("Path.directionAt", function()
	it("points along the segment the query falls in", function()
		local path = cornerPath()

		expectVectorClose(path:directionAt(10), Vector3.new(1, 0, 0))
		expectVectorClose(path:directionAt(50), Vector3.new(0, 0, 1))
	end)

	it("stays oriented at and beyond both endpoints", function()
		-- A spawning or leaking enemy must still face somewhere sensible.
		local path = cornerPath()

		expectVectorClose(path:directionAt(0), Vector3.new(1, 0, 0))
		expectVectorClose(path:directionAt(-10), Vector3.new(1, 0, 0))
		expectVectorClose(path:directionAt(path.totalLength), Vector3.new(0, 0, 1))
		expectVectorClose(path:directionAt(9999), Vector3.new(0, 0, 1))
	end)

	it("returns unit vectors", function()
		local path = cornerPath()

		for _, d in { 0, 5, 30, 45, 70 } do
			expectClose(path:directionAt(d).Magnitude, 1)
		end
	end)
end)

describe("Path.distanceToBase", function()
	it("is the universal ordering key (D8)", function()
		-- Two lanes of different length. An enemy 10 studs from the base on
		-- the long lane must order ahead of one 20 studs out on the short
		-- lane, even though it has walked much further. Ordering on raw
		-- progress would invert this, which is the bug D8 exists to prevent.
		local shortLane = Path.new({ Vector3.new(0, 0, 0), Vector3.new(50, 0, 0) })
		local longLane = unevenStraightPath()

		local leader = longLane:distanceToBase(95)
		local trailer = shortLane:distanceToBase(30)

		expectClose(leader, 10)
		expectClose(trailer, 20)
		expect(leader < trailer).toBe(true)
	end)

	it("decreases monotonically and never goes negative", function()
		local path = cornerPath()
		local previous = path:distanceToBase(0)

		for d = 5, 100, 5 do
			local current = path:distanceToBase(d)
			expect(current <= previous).toBe(true)
			expect(current >= 0).toBe(true)
			previous = current
		end

		expectClose(path:distanceToBase(9999), 0)
	end)
end)

describe("Path.hasReachedEnd", function()
	it("is false until the lane is fully walked", function()
		local path = cornerPath()

		expect(path:hasReachedEnd(0)).toBe(false)
		expect(path:hasReachedEnd(69.9)).toBe(false)
		expect(path:hasReachedEnd(70)).toBe(true)
		expect(path:hasReachedEnd(9999)).toBe(true)
	end)
end)

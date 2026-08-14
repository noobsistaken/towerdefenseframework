--!strict
--[[
	Arc-length parameterised waypoint path.

	This is the module the whole enemy simulation rests on. An enemy is stored
	as a single number - how far it has walked - and this converts that number
	into a world position on demand. Nothing else in the codebase needs to know
	where an enemy is.

	Two properties matter and both are load-bearing:

	  * Arc-length parameterisation. `positionAt(d)` walks exactly `d` studs
	    along the polyline, so an enemy moving at a constant speed covers
	    constant ground regardless of how the waypoints are spaced. Lerping
	    per-segment by a normalised t would make enemies speed up on long
	    segments and crawl on short ones.

	  * `distanceToBase` is the universal ordering key (ARCHITECTURE.md D8).
	    Ordering by distance REMAINING rather than distance travelled makes
	    First/Last targeting correct across lanes of different lengths without
	    any special casing.

	Pure: no Instances, no services, no globals. That is what makes it
	testable, and the test suite is the only runtime evidence this project
	can produce outside Studio.
]]

local Path = {}
Path.__index = Path

export type Path = typeof(setmetatable(
	{} :: {
		waypoints: { Vector3 },
		--- cumulative[i] is the distance from the start to waypoints[i].
		--- cumulative[1] is always 0, so this is always #waypoints long.
		cumulative: { number },
		totalLength: number,
	},
	Path
))

--- Builds a path from at least two waypoints.
---
--- Rejects duplicate consecutive waypoints rather than tolerating them: a
--- zero-length segment is a map authoring mistake, and silently accepting it
--- produces a path whose direction at that point is undefined.
function Path.new(waypoints: { Vector3 }): Path
	local count = #waypoints

	if count < 2 then
		error(`Path.new: need at least 2 waypoints, got {count}`)
	end

	local cumulative = table.create(count)
	cumulative[1] = 0

	local running = 0

	for i = 2, count do
		local segment = (waypoints[i] - waypoints[i - 1]).Magnitude

		if segment <= 0 then
			error(`Path.new: waypoints {i - 1} and {i} are identical`)
		end

		running += segment
		cumulative[i] = running
	end

	return setmetatable({
		waypoints = table.clone(waypoints),
		cumulative = cumulative,
		totalLength = running,
	}, Path)
end

--- Index of the segment containing `distance`, in [1, #waypoints - 1].
--- Segment i runs from waypoints[i] to waypoints[i + 1].
---
--- Binary search rather than a linear scan: this runs once per enemy per
--- simulation step, so at 200 enemies and 30Hz it is 6000 calls a second.
local function segmentIndexFor(self: Path, distance: number): number
	local lo = 1
	local hi = #self.waypoints - 1

	while lo < hi do
		-- Bias the midpoint upward so `lo` converges rather than sticking.
		local mid = (lo + hi + 1) // 2

		if self.cumulative[mid] <= distance then
			lo = mid
		else
			hi = mid - 1
		end
	end

	return lo
end

--- World position `distance` studs along the path.
--- Clamps: distances outside [0, totalLength] return the endpoints.
function Path.positionAt(self: Path, distance: number): Vector3
	if distance <= 0 then
		return self.waypoints[1]
	end

	if distance >= self.totalLength then
		return self.waypoints[#self.waypoints]
	end

	local i = segmentIndexFor(self, distance)
	local segmentStart = self.cumulative[i]
	local segmentLength = self.cumulative[i + 1] - segmentStart

	-- Guaranteed non-zero: Path.new rejects duplicate waypoints.
	local alpha = (distance - segmentStart) / segmentLength

	return self.waypoints[i]:Lerp(self.waypoints[i + 1], alpha)
end

--- Unit direction of travel at `distance`. Used to face the model forward.
--- At and beyond the endpoints this returns the first/last segment direction,
--- which keeps a spawning or leaking enemy correctly oriented.
function Path.directionAt(self: Path, distance: number): Vector3
	local i: number

	if distance <= 0 then
		i = 1
	elseif distance >= self.totalLength then
		i = #self.waypoints - 1
	else
		i = segmentIndexFor(self, distance)
	end

	return (self.waypoints[i + 1] - self.waypoints[i]).Unit
end

--- Studs still to walk before leaking. The universal ordering key (D8).
--- Never negative.
function Path.distanceToBase(self: Path, progress: number): number
	return math.max(0, self.totalLength - progress)
end

--- True once an enemy at `progress` has reached the end of the lane.
function Path.hasReachedEnd(self: Path, progress: number): boolean
	return progress >= self.totalLength
end

return Path

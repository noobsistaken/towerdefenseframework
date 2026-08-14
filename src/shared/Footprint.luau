--!strict
--[[
	Placement geometry.

	Pure 2D maths on the XZ plane. Y is ignored throughout: a tower's height
	never affects whether it fits, and towers on an elevated pad must still be
	prevented from hanging over the lane below them.

	Footprints are treated as CIRCLES of radius max(x, z) / 2 rather than as
	rotated rectangles. That is a deliberate simplification and worth stating,
	because the wire format carries a rotation:

	  * Every footprint in the roster is square, so the inscribed circle has
	    exactly the side length as its diameter - two 6x6 towers must be 6
	    studs apart, which is the same answer an axis-aligned box test gives.
	  * It is rotation-invariant. Rotation stays purely cosmetic, so a player
	    can never squeeze a tower into an illegal spot by spinning it, and the
	    server never has to trust a client-supplied angle for anything that
	    matters.
	  * Circle tests are cheap and have no orientation edge cases, where
	    box-vs-box needs a separating-axis test and gets fiddly at 45 degrees.

	If a non-square footprint is ever added, this is the module that has to
	grow a real oriented-box test - not the callers.
]]

local Footprint = {}

--- Collision radius of a footprint, in studs.
function Footprint.radius(footprint: Vector2): number
	return math.max(footprint.X, footprint.Y) / 2
end

--- True if two circular footprints intersect. Touching exactly is allowed:
--- adjacent towers should be able to sit flush.
function Footprint.overlaps(centerA: Vector3, radiusA: number, centerB: Vector3, radiusB: number): boolean
	local dx = centerA.X - centerB.X
	local dz = centerA.Z - centerB.Z
	local minimum = radiusA + radiusB

	-- Squared comparison: no square root on a path that runs against every
	-- placed tower on every placement request.
	return (dx * dx + dz * dz) < (minimum * minimum)
end

--- Shortest XZ distance from a point to the segment ab.
function Footprint.distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local abX = b.X - a.X
	local abZ = b.Z - a.Z
	local lengthSquared = abX * abX + abZ * abZ

	local apX = point.X - a.X
	local apZ = point.Z - a.Z

	if lengthSquared <= 0 then
		-- Degenerate segment. Path.new rejects these, but this function is
		-- also called on raw config during authoring, where they can exist.
		return math.sqrt(apX * apX + apZ * apZ)
	end

	-- Projection parameter, clamped so the nearest point stays on the segment
	-- rather than running off its infinite line.
	local t = math.clamp((apX * abX + apZ * abZ) / lengthSquared, 0, 1)

	local closestX = a.X + abX * t
	local closestZ = a.Z + abZ * t
	local dx = point.X - closestX
	local dz = point.Z - closestZ

	return math.sqrt(dx * dx + dz * dz)
end

--- Shortest XZ distance from a point to a whole polyline.
function Footprint.distanceToPath(point: Vector3, waypoints: { Vector3 }): number
	local best = math.huge

	for i = 1, #waypoints - 1 do
		local distance = Footprint.distanceToSegment(point, waypoints[i], waypoints[i + 1])

		if distance < best then
			best = distance
		end
	end

	return best
end

--- True if a tower here would intrude on the lane.
---
--- `clearance` is measured from the path centre line, so it must cover half
--- the walkway width plus whatever margin is wanted. This is the check that
--- stops a player walling the lane shut - the one placement bug that turns a
--- tower defense into a maze game.
function Footprint.blocksPath(center: Vector3, radius: number, waypoints: { Vector3 }, clearance: number): boolean
	return Footprint.distanceToPath(center, waypoints) < (radius + clearance)
end

--- True if the whole footprint sits inside the map's ground plane.
--- `groundSize` is the full extent, centred on the origin, matching
--- MapConfig.groundSize.
function Footprint.isInsideBounds(center: Vector3, radius: number, groundSize: Vector3): boolean
	local halfX = groundSize.X / 2 - radius
	local halfZ = groundSize.Z / 2 - radius

	if halfX <= 0 or halfZ <= 0 then
		return false
	end

	return math.abs(center.X) <= halfX and math.abs(center.Z) <= halfZ
end

--- True if the footprint rests entirely on a single axis-aligned pad.
--- Requiring ONE pad to contain it, rather than accepting coverage spread
--- across several, keeps the rule easy to state and prevents a tower
--- balancing across a gap between two pads.
function Footprint.isOnSurface(center: Vector3, radius: number, surfacePosition: Vector3, surfaceSize: Vector3): boolean
	local halfX = surfaceSize.X / 2 - radius
	local halfZ = surfaceSize.Z / 2 - radius

	if halfX < 0 or halfZ < 0 then
		return false
	end

	return math.abs(center.X - surfacePosition.X) <= halfX and math.abs(center.Z - surfacePosition.Z) <= halfZ
end

return Footprint

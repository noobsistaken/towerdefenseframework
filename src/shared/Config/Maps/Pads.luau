--!strict
--[[
	Buildable pad constructors, shared by every map.

	Extracted because the y arithmetic is subtle and easy to get wrong by a
	half-thickness. A pad's `position` is the CENTRE of its slab, but map
	authors think in terms of the surface a tower stands on, so every
	constructor here takes the TOP height and derives the centre.

	The two heights are the entire mechanism behind the Hillside category:
	nothing else in the codebase special-cases it. A Ground tower is one that
	requires a GROUND_TOP surface, a Hillside tower one that requires
	ELEVATED_TOP, and Placement.surfaceUnder resolves overlaps by picking the
	higher of the two.
]]

local Types = require(script.Parent.Parent.Parent.Types)

local Pads = {}

--- Slab thickness shared by every pad, so the y arithmetic holds uniformly.
Pads.THICKNESS = 4

--- Walkable height of a ground pad. One stud above the ground plane (whose
--- top is y = 0), enough to read as a distinct surface without becoming a
--- step the eye has to account for.
Pads.GROUND_TOP = 1

--- Top surface of the visible walkway: a hair above the apron so it cannot
--- z-fight it. This is where anything WALKING should plant its feet.
---
--- One constant shared by the walkway that draws at this height and the rig
--- fitting that stands enemies on it, because the two drifting apart is
--- exactly how the zombies ended up buried to the waist: the sim's path
--- plane is y = 0, the walkway surface is here, and feet aligned to the
--- hitbox bottom sat 1.15 studs under the boards.
Pads.WALKWAY_TOP = Pads.GROUND_TOP + 0.15

--- Walkable height of an elevated plateau. Far enough above the ground that
--- it is unmistakable at a glance, which matters because it is the only
--- visual cue for where Hillside towers are legal.
Pads.ELEVATED_TOP = 12

--- A ground-level buildable area, centred on (x, z).
---
--- Maps should use ONE broad apron rather than several small pockets. The
--- lane is carved out of it by PATH_CLEARANCE during validation, not by holes
--- in the geometry: the rule a player can learn is "anywhere except on the
--- path", which they can see, rather than "only on the pads", which they
--- cannot.
function Pads.ground(x: number, z: number, sizeX: number, sizeZ: number): Types.BuildableSurface
	return {
		position = Vector3.new(x, Pads.GROUND_TOP - Pads.THICKNESS / 2, z),
		size = Vector3.new(sizeX, Pads.THICKNESS, sizeZ),
		surfaceType = "Ground" :: Types.SurfaceType,
	}
end

--- An elevated plateau, the only legal Hillside placement.
---
--- These sit ON TOP of the apron, so both surfaces contain any point on a
--- plateau. That is fine and expected - surfaceUnder resolves it by height.
function Pads.elevated(x: number, z: number, sizeX: number, sizeZ: number): Types.BuildableSurface
	return {
		position = Vector3.new(x, Pads.ELEVATED_TOP - Pads.THICKNESS / 2, z),
		size = Vector3.new(sizeX, Pads.THICKNESS, sizeZ),
		surfaceType = "Elevated" :: Types.SurfaceType,
	}
end

return Pads

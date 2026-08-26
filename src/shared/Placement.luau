--!strict
--[[
	Tower placement rules.

	Pure, and deliberately in shared/ rather than on the server, so the
	client's ghost preview and the server's authoritative check run the SAME
	function. Two implementations of these rules would drift, and the symptom
	would be a preview showing green on a spot the server then rejects.

	The client's use is advisory only. It colours a ghost. The server calls
	this again on every request and its answer is the only one that counts -
	a client that skips the check entirely gains nothing.

	Validation is against the map CONFIG, not against Instances. No raycast,
	no CollectionService query, no workspace at all. That makes every rule
	here testable without a running game, and it removes a whole class of bug
	where a player nudges a pad in Studio and placement silently changes.

	The client's Y is ignored outright. The surface it lands on determines the
	height, so a client cannot float a tower, sink it into terrain, or claim
	to be standing on a pad it is nowhere near.
]]

local Constants = require(script.Parent.Constants)
local Economy = require(script.Parent.Config.Economy)
local Footprint = require(script.Parent.Footprint)
local Towers = require(script.Parent.Config.Towers)
local Types = require(script.Parent.Types)

local Placement = {}

--- Enough about an already-placed tower to test overlap against it.
export type ExistingTower = {
	position: Vector3,
	radius: number,
}

export type Request = {
	definition: Types.TowerDefinition,
	--- X and Z are used. Y is ignored - see the header.
	position: Vector3,
	map: Types.MapConfig,
	existing: { ExistingTower },
	--- Whether this player has unlocked the tower.
	unlocked: boolean,
	--- Whether the tower is in this player's LOADOUT - owning it is not
	--- bringing it. The server resolves this; the client mirrors it for the
	--- ghost, whose shop only offers the loadout anyway.
	inLoadout: boolean,
	cash: number,
	--- How many of this definition the player already owns, for the cap.
	ownedOfType: number,
	--- False outside the phases where building is allowed.
	canBuildNow: boolean,
}

export type Result = {
	ok: boolean,
	reason: Types.PlacementRejectReason?,
	--- Where the tower actually goes: the request's X and Z, with Y resting
	--- on the surface. Only present when ok.
	position: Vector3?,
}

local function reject(reason: Types.PlacementRejectReason): Result
	return { ok = false, reason = reason, position = nil }
end

--- The pad this footprint rests entirely on, or nil.
---
--- Requiring a single containing pad - rather than accepting coverage spread
--- across several - keeps the rule simple to state and stops a tower
--- balancing across the gap between two adjacent pads.
---
--- Where several pads contain the footprint, the HIGHEST one wins, because
--- that is the one a tower would physically rest on. This is load-bearing
--- rather than tidy: elevated plateaus sit on top of the ground apron, so
--- every Hillside placement is inside two surfaces at once. Returning the
--- first match instead would resolve a plateau to the apron underneath it,
--- which reads in game as "Ground towers can be built on the hills and
--- Hillside towers cannot" - the exact inversion of the category rule.
---
--- Exact ties in height fall to config order. Two buildable surfaces at the
--- same height overlapping in XZ is a map authoring mistake, not a case worth
--- paying for.
local function surfaceUnder(map: Types.MapConfig, center: Vector3, radius: number): Types.BuildableSurface?
	local best: Types.BuildableSurface? = nil
	local bestTop = -math.huge

	for _, surface in map.buildableSurfaces do
		if not Footprint.isOnSurface(center, radius, surface.position, surface.size) then
			continue
		end

		local top = surface.position.Y + surface.size.Y / 2

		if top > bestTop then
			bestTop = top
			best = surface
		end
	end

	return best
end

--- Full validation. Checks run cheapest-and-most-explanatory first, so the
--- reason a player sees is the most useful one rather than whichever
--- happened to be tested first.
function Placement.validate(request: Request): Result
	local definition = request.definition

	if not request.canBuildNow then
		return reject("WrongMatchState")
	end

	if not request.unlocked then
		return reject("NotUnlocked")
	end

	if not request.inLoadout then
		return reject("NotInLoadout")
	end

	local cost = definition.levels[1].cost

	if request.cash < cost then
		return reject("CannotAfford")
	end

	if definition.perPlayerCap > 0 and request.ownedOfType >= definition.perPlayerCap then
		return reject("TowerCapReached")
	end

	local radius = Footprint.radius(definition.footprint)
	local flat = Vector3.new(request.position.X, 0, request.position.Z)

	if not Footprint.isInsideBounds(flat, radius, request.map.groundSize) then
		return reject("OutOfBounds")
	end

	local surface = surfaceUnder(request.map, flat, radius)

	if surface == nil then
		return reject("NotBuildable")
	end

	-- Category against surface tag. This is the entire mechanism behind the
	-- Hillside category: nothing else in the codebase special-cases it.
	if not Towers.acceptsSurface(definition, surface.surfaceType) then
		return reject("WrongSurface")
	end

	for _, other in request.existing do
		if Footprint.overlaps(flat, radius, other.position, other.radius) then
			return reject("OverlapsTower")
		end
	end

	-- Lane clearance, checked against every lane. This is the rule that stops
	-- a player walling the path shut, which is the one placement bug that
	-- turns a tower defense into a maze game.
	for _, lane in request.map.paths do
		if Footprint.blocksPath(flat, radius, lane.waypoints, Constants.PATH_CLEARANCE) then
			return reject("BlocksPath")
		end
	end

	-- Height comes from the surface, never from the request.
	local restingY = surface.position.Y + surface.size.Y / 2

	return {
		ok = true,
		reason = nil,
		position = Vector3.new(request.position.X, restingY, request.position.Z),
	}
end

--- Whether a player may upgrade this tower right now, and what it costs.
--- Shared for the same reason as placement: the inspector button and the
--- server agree by construction.
function Placement.canUpgrade(
	definition: Types.TowerDefinition,
	level: number,
	cash: number,
	isOwner: boolean
): (boolean, number?)
	if not isOwner then
		return false, nil
	end

	local cost = Economy.upgradeCost(definition, level)

	if cost == nil then
		return false, nil
	end

	return cash >= cost, cost
end

return Placement

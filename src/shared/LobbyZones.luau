--!strict
--[[
	The lobby hub's walk-in areas, as data plus a pure resolver.

	The lobby is a PLACE now, not a menu with scenery: you spawn in the
	middle and nothing happens until you walk somewhere. Three areas, per
	the sketch that defined them - GAME to the northwest (step in and a
	map-and-difficulty chooser opens; START in that chooser is the only
	thing that ever launches a match), GACHA to the northeast, REROLL on
	the east side.

	This module owns where every area IS and answers "which area is this
	position in" - nothing else. The builder draws pads from this data, the
	server scans occupancy against it from character positions it owns, and
	the client opens the matching panel from the same table. Three readers,
	one layout: the floor you stand on and the UI you see can never
	disagree about where an area is.

	Resolution is on X and Z only. Y is deliberately ignored: a player
	jumping inside an area is still inside it, and the hub is one floor.
]]

local LobbyZones = {}

export type Area = {
	id: string,
	displayName: string,
	center: Vector3,
	size: Vector3,
}

--- The hub layout. Ids are load-bearing: the server's occupancy scan keys
--- on "Game", and the client opens the panel named by the id it resolves.
local AREAS: { Area } = {
	{
		id = "Game",
		displayName = "GAME",
		-- Northwest, and the largest: a party stands in it together, and
		-- everyone inside when START is pressed goes along.
		center = Vector3.new(-40, 0, -36),
		size = Vector3.new(36, 0, 30),
	},
	{
		id = "Gacha",
		displayName = "TROOP GACHA",
		center = Vector3.new(42, 0, -36),
		size = Vector3.new(20, 0, 16),
	},
	{
		id = "Reroll",
		displayName = "TRAIT REROLL",
		center = Vector3.new(46, 0, 12),
		size = Vector3.new(20, 0, 16),
	},
}

LobbyZones.AREAS = table.freeze(AREAS)

local function insideXZ(position: Vector3, center: Vector3, size: Vector3): boolean
	return math.abs(position.X - center.X) <= size.X / 2 and math.abs(position.Z - center.Z) <= size.Z / 2
end

--- Which area `position` stands in, or nil for the open floor.
function LobbyZones.resolveArea(position: Vector3): string?
	for _, area in AREAS do
		if insideXZ(position, area.center, area.size) then
			return area.id
		end
	end

	return nil
end

--- Lookup by id, for the builder and the panels.
function LobbyZones.find(id: string): Area?
	for _, area in AREAS do
		if area.id == id then
			return area
		end
	end

	return nil
end

return LobbyZones

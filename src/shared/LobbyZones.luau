--!strict
--[[
	The lobby's walk-in vote zones, as data plus a pure resolver.

	The lobby stopped being a menu: you vote for a map by STANDING in its
	zone, and for a difficulty by standing on one of the pads inside it.
	Occupancy is the vote. This module owns where every zone and pad IS and
	answers "which zone is this position in" - and nothing else, so the whole
	thing is testable as geometry with no Instance anywhere near it, the same
	split that makes the placement and pathing suites possible.

	THE LAYOUT IS DERIVED, NOT AUTHORED. Zones come from MapRegistry.IDS and
	pads from Difficulty.IDS at require time, so adding a fourth map or a
	fourth difficulty is one config entry and the lobby grows a zone for it
	with no change here. That is the same content-is-config rule the towers
	and enemies follow.

	Resolution is on X and Z only. Y is deliberately ignored: a player
	jumping inside a zone is still voting for it, and the zones sit on one
	floor - if the lobby ever grows a second storey, this is the line to
	revisit.
]]

local Difficulty = require(script.Parent.Config.Difficulty)
local MapRegistry = require(script.Parent.Config.MapRegistry)

local LobbyZones = {}

--- Zone row centre line, north half of the 120-stud lobby floor.
local ZONE_ROW_Z = -32

--- Footprint of one map zone.
LobbyZones.ZONE_SIZE = Vector3.new(28, 0, 24)

--- Gap between neighbouring zones. Zones must never touch: a player on the
--- boundary of two zones would flicker between votes.
local ZONE_GAP = 8

--- Difficulty pads sit in a row along the SOUTH edge of their zone - the
--- side you walk in from - so entering a zone votes the map first and the
--- difficulty is a deliberate second step deeper in.
LobbyZones.PAD_SIZE = Vector3.new(6, 0, 6)
local PAD_ROW_LOCAL_Z = 7
local PAD_GAP = 3

--- The walk-up service stations - gacha and trait reroll - on the SOUTH
--- half, opposite the vote zones, so rolling and voting never share floor.
--- Same contract as the zones: this module owns where they ARE, the builder
--- draws them from this data, and the client opens a panel when the local
--- character stands inside one - all three reading one layout.
LobbyZones.STATION_SIZE = Vector3.new(18, 0, 12)
local STATION_ROW_Z = 46
local STATION_X = 34

export type Station = {
	id: string,
	displayName: string,
	center: Vector3,
	size: Vector3,
}

export type Pad = {
	difficultyId: string,
	center: Vector3,
	size: Vector3,
}

export type Zone = {
	mapId: string,
	center: Vector3,
	size: Vector3,
	pads: { Pad },
}

--- The full zone layout. Computed fresh per call rather than cached: it is
--- cheap, and a frozen cache would hide a registry that changed under test.
function LobbyZones.zones(): { Zone }
	local mapIds = MapRegistry.IDS
	local zones: { Zone } = {}

	local pitch = LobbyZones.ZONE_SIZE.X + ZONE_GAP
	local startX = -((#mapIds - 1) * pitch) / 2

	for index, mapId in mapIds do
		local center = Vector3.new(startX + (index - 1) * pitch, 0, ZONE_ROW_Z)

		local pads: { Pad } = {}
		local padPitch = LobbyZones.PAD_SIZE.X + PAD_GAP
		local padStartX = -((#Difficulty.IDS - 1) * padPitch) / 2

		for padIndex, difficultyId in Difficulty.IDS do
			table.insert(pads, {
				difficultyId = difficultyId,
				center = center + Vector3.new(padStartX + (padIndex - 1) * padPitch, 0, PAD_ROW_LOCAL_Z),
				size = LobbyZones.PAD_SIZE,
			})
		end

		table.insert(zones, {
			mapId = mapId,
			center = center,
			size = LobbyZones.ZONE_SIZE,
			pads = pads,
		})
	end

	return zones
end

--- The station layout. Ids are wire-stable: the client shows a panel per
--- id and the server needs no station validation at all - the functs guard
--- themselves, and standing here is theatre rather than authority.
function LobbyZones.stations(): { Station }
	return {
		{
			id = "Gacha",
			displayName = "TROOP GACHA",
			center = Vector3.new(-STATION_X, 0, STATION_ROW_Z),
			size = LobbyZones.STATION_SIZE,
		},
		{
			id = "Reroll",
			displayName = "TRAIT REROLL",
			center = Vector3.new(STATION_X, 0, STATION_ROW_Z),
			size = LobbyZones.STATION_SIZE,
		},
	}
end

local function insideXZ(position: Vector3, center: Vector3, size: Vector3): boolean
	return math.abs(position.X - center.X) <= size.X / 2 and math.abs(position.Z - center.Z) <= size.Z / 2
end

--- Which map zone and difficulty pad `position` is in.
---
--- Returns (nil, nil) outside every zone, (mapId, nil) inside a zone but on
--- no pad. A difficulty without a map is impossible by construction: pads
--- exist only inside zones.
function LobbyZones.resolve(position: Vector3): (string?, string?)
	for _, zone in LobbyZones.zones() do
		if insideXZ(position, zone.center, zone.size) then
			for _, pad in zone.pads do
				if insideXZ(position, pad.center, pad.size) then
					return zone.mapId, pad.difficultyId
				end
			end

			return zone.mapId, nil
		end
	end

	return nil, nil
end

--- Which station `position` stands in, or nil. XZ-only like resolve, for
--- the same jumping-player reason.
function LobbyZones.resolveStation(position: Vector3): string?
	for _, station in LobbyZones.stations() do
		if insideXZ(position, station.center, station.size) then
			return station.id
		end
	end

	return nil
end

return LobbyZones

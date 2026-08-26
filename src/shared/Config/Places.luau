--!strict
--[[
	Place identity and the Studio role switch.

	THIS FILE NEEDS REAL IDS BEFORE THE GAME CAN SHIP. Both are 0 below, which
	is not a valid place id - see `isConfigured`. Publishing with them unset
	means the lobby cannot teleport anyone anywhere, and TeleportGate says so
	out loud rather than failing silently.

	Why a role switch exists at all:

	Each published place is built from its own project file, so the match place
	contains only ServerScriptService.Server and the lobby place contains only
	ServerScriptService.Lobby. In production each entry script exists solely in
	its own place and no check is needed.

	The test place is the exception. test.project.json mounts BOTH trees,
	because luau-lsp builds its sourcemap from it and the lobby's requires have
	to resolve. Without a guard, opening the test place would boot a match and
	a lobby at once. STUDIO_ROLE decides which one wins, and it only ever
	applies in Studio.
]]

local Places = {}

export type PlaceRole = "Match" | "Lobby"

--- Set these to the real place ids after publishing. `game.PlaceId` on the
--- published place is the value each one wants.
Places.LOBBY_PLACE_ID = 108948328624758
Places.MATCH_PLACE_ID = 80721394481917

--- Which entry point boots in a Studio place the config does NOT recognise
--- (a fresh clone, a scratch place). In the real lobby and match places the
--- PLACE ID decides, Studio included - this switch no longer applies there.
Places.STUDIO_ROLE = "Match" :: PlaceRole

--- False until both ids above are real. TeleportGate refuses to attempt a
--- teleport while this is false, because TeleportAsync to place 0 fails with
--- an error that reads like a Roblox outage rather than a missing constant.
function Places.isConfigured(): boolean
	return Places.LOBBY_PLACE_ID ~= 0 and Places.MATCH_PLACE_ID ~= 0
end

--- Whether an entry script should boot.
---
--- Pure, and takes `isStudio` and `placeId` rather than reaching for
--- RunService or game, so that src/shared/ stays free of service lookups at
--- require time and this stays testable.
---
--- A REAL place id decides EVERYWHERE, Studio included. The dev windows
--- have the actual places open, and a playtest in the lobby window must
--- boot the lobby no matter how the role switch happens to be set - the
--- day it did not, pressing Play on the lobby produced a match, which
--- reads as "the lobby is broken", not as "a switch needs flipping".
--- STUDIO_ROLE only breaks ties for places the config does not recognise:
--- a fresh clone's local file, a copy, a scratch place.
---
--- In production an UNKNOWN place boots nothing at all: the superset
--- published to a third place must not run two games in one world.
function Places.shouldBoot(role: PlaceRole, isStudio: boolean, placeId: number): boolean
	if Places.isConfigured() then
		if placeId == Places.LOBBY_PLACE_ID then
			return role == "Lobby"
		end

		if placeId == Places.MATCH_PLACE_ID then
			return role == "Match"
		end

		return isStudio and Places.STUDIO_ROLE == role
	end

	-- Ids unset: the old rules. Entry presence decides in production (each
	-- published place holds only its own entry); the switch decides in
	-- Studio.
	if not isStudio then
		return true
	end

	return Places.STUDIO_ROLE == role
end

return Places

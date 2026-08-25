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

--- Which entry point boots in Studio and in the test place. Flip to "Lobby"
--- to work on the lobby without publishing anything.
Places.STUDIO_ROLE = "Match" :: PlaceRole

--- False until both ids above are real. TeleportGate refuses to attempt a
--- teleport while this is false, because TeleportAsync to place 0 fails with
--- an error that reads like a Roblox outage rather than a missing constant.
function Places.isConfigured(): boolean
	return Places.LOBBY_PLACE_ID ~= 0 and Places.MATCH_PLACE_ID ~= 0
end

--- Whether an entry script should boot.
---
--- Pure, and takes `isStudio` rather than reaching for RunService, so that
--- src/shared/ stays free of service lookups at require time and this stays
--- testable.
function Places.shouldBoot(role: PlaceRole, isStudio: boolean): boolean
	if not isStudio then
		-- Published places contain exactly one entry script, so its presence
		-- is the answer.
		return true
	end

	return Places.STUDIO_ROLE == role
end

return Places

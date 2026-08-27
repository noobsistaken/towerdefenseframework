--!strict
--[[
	Studio fallback configuration (ARCHITECTURE.md D1).

	TeleportService does not function in Studio, so a match place that could
	only be configured by arriving teleport data would be untestable in the
	one environment this project can test runtime behaviour in.

	When RunService:IsStudio() is true, or when a player arrives with no
	usable teleport data, the match boots from here instead. Everything
	downstream of the arrival gate is then exercised normally - the
	unverifiable surface shrinks to the TeleportAsync call itself.

	Edit these while working on a specific map or difficulty; they have no
	effect in a published server.
]]

local DevMatch = {}

DevMatch.MAP_ID = "Bastion"
DevMatch.DIFFICULTY_ID = "Normal"

--- Skip straight past the long first build phase when iterating in Studio.
--- Set false to test the real opening timing.
DevMatch.SHORTEN_FIRST_PREPARE = true
DevMatch.SHORTENED_PREPARE_SECONDS = 6

return DevMatch

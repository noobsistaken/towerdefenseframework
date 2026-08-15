--!strict
--[[
	Validates the launch parameters a player arrives with.

	TeleportData is UNTRUSTED. Roblox's own guidance is not to rely on it being
	tamper-proof, and this design deliberately does not depend on the answer:
	every field is checked against the same config allowlist the lobby votes
	over, and anything unrecognised falls back to the default. A forged payload
	can therefore, at worst, pick a map the player could have voted for anyway.

	`parse` is pure and takes the raw table, so the validation - which is the
	part with the security property - is testable without a teleport, a
	Player, or a second place. `resolveFrom` is the thin shell that reads
	GetJoinData and is the only part that cannot be tested outside a published
	pair of places.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Types = require(ReplicatedStorage.Shared.Types)

local ArrivalGate = {}

--- Reads one string field out of an untrusted table.
---
--- Every step is defensive on purpose: the value may be nil, may not be a
--- table, and the field may be any type at all. Indexing a non-table raises,
--- and an arriving player raising in PlayerAdded is a player who never
--- finishes loading.
local function readString(raw: any, key: string): string?
	if type(raw) ~= "table" then
		return nil
	end

	local value = raw[key]

	if type(value) ~= "string" then
		return nil
	end

	return value
end

--- Validates raw teleport data into launch parameters.
---
--- Pure. Never raises, and never returns an id that is not in the registry -
--- both properties are what let the caller use the result without a second
--- check.
function ArrivalGate.parse(raw: any): Types.MatchLaunchData
	local mapId = readString(raw, "mapId")
	local difficultyId = readString(raw, "difficultyId")

	-- `find` is the allowlist. This is the same lookup the lobby's Poll used
	-- to accept the vote in the first place, so a legitimate payload always
	-- survives it.
	local map = if mapId ~= nil then MapRegistry.find(mapId) else nil
	local difficulty = if difficultyId ~= nil then Difficulty.find(difficultyId) else nil

	return {
		mapId = if map ~= nil then map.id else MapRegistry.DEFAULT_ID,
		difficultyId = if difficulty ~= nil then difficulty.id else Difficulty.DEFAULT_ID,
	}
end

--- Launch parameters for this server, taken from the first arriving player
--- who carries a usable payload.
---
--- Every player in a teleport batch receives identical TeleportData, so the
--- first one that parses is as good as any. Scanning rather than taking
--- player one outright matters because a player can leave mid-teleport, and
--- because a player who joined the reserved server by other means carries no
--- data at all.
function ArrivalGate.resolveFrom(players: { Player }): Types.MatchLaunchData
	for _, player in players do
		-- GetJoinData can raise for a player who has already left.
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)

		if not ok or joinData == nil then
			continue
		end

		local raw = (joinData :: any).TeleportData

		if raw == nil then
			continue
		end

		return ArrivalGate.parse(raw)
	end

	-- Nobody carried usable data. Legitimate in three cases: a Studio
	-- playtest, a solo join straight into the match place, and a reserved
	-- server whose original party all left before it booted.
	return ArrivalGate.parse(nil)
end

return ArrivalGate

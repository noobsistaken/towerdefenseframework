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

local Players = game:GetService("Players")
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
function ArrivalGate.tryResolveFrom(players: { Player }): Types.MatchLaunchData?
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

	return nil
end

function ArrivalGate.resolveFrom(players: { Player }): Types.MatchLaunchData
	-- Nobody carrying data is legitimate in three cases: a Studio playtest,
	-- a solo join straight into the match place, and a reserved server whose
	-- original party all left before it booted.
	return ArrivalGate.tryResolveFrom(players) or ArrivalGate.parse(nil)
end

--- Launch parameters, waiting up to `timeoutSeconds` for a player to bring
--- them.
---
--- THE WAIT IS THE POINT. A reserved server boots BEFORE its party finishes
--- joining - server scripts run first, so Players:GetPlayers() at that
--- moment is empty and the vote is nowhere on the server yet. Resolving
--- there and then found no data, fell back to the default map, and did it
--- every single time: the lobby's vote was carried correctly all the way
--- across the teleport and then read one moment too early. Every live match
--- opened the default map whatever anyone picked.
---
--- Falls back to the defaults if the window passes with nobody carrying
--- data, so a direct join still boots rather than hanging.
function ArrivalGate.resolveOnArrival(timeoutSeconds: number): Types.MatchLaunchData
	local started = os.clock()
	local deadline = started + timeoutSeconds

	repeat
		local launch = ArrivalGate.tryResolveFrom(Players:GetPlayers())

		if launch ~= nil then
			-- Logged unconditionally, and this is the line that would have
			-- caught the boot race on day one: it names the map, where it
			-- came from, and how long the party took to show up. Read it in
			-- the live game with F9 -> Server.
			print(
				`[td-launch] match booting map={launch.mapId} difficulty={launch.difficultyId} `
					.. `source=teleport waited={string.format("%.1f", os.clock() - started)}s `
					.. `players={#Players:GetPlayers()}`
			)

			return launch
		end

		task.wait(0.1)
	until os.clock() >= deadline

	local fallback = ArrivalGate.parse(nil)

	-- The loud case. Reaching here in a live match means nobody arrived
	-- carrying a vote within the window, so the map below is a DEFAULT and
	-- not anybody's choice - which is exactly the failure that looked like
	-- "the vote does nothing".
	print(
		`[td-launch] match booting map={fallback.mapId} difficulty={fallback.difficultyId} `
			.. `source=DEFAULT (no teleport data after {string.format("%.1f", timeoutSeconds)}s) `
			.. `players={#Players:GetPlayers()}`
	)

	return fallback
end

return ArrivalGate

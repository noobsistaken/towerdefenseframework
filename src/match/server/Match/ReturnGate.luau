--!strict
--[[
	The teleport back to the lobby.

	The counterpart to the lobby's TeleportGate, and it carries the same
	caveat: TeleportService does not function in Studio, so this call is
	unverifiable outside a published pair of places. Same three mitigations -
	decide what can be decided first, skip the call entirely in Studio, and
	pcall the one line that cannot be tested.

	Deliberately NOT shared with TeleportGate despite the similarity. The two
	differ in the ways that matter: this one has no reserved server, carries no
	teleport data, and must tolerate being called for players who are already
	gone. Folding them together would mean a parameterised gate whose branches
	are each only exercised in one place.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Places = require(ReplicatedStorage.Shared.Config.Places)

local ReturnGate = {}

--- Sends everyone still present back to the lobby.
---
--- Yields. Failures are logged rather than surfaced: by the time this runs
--- the match is over and the results screen is up, so there is no UI left to
--- show an error in, and a player left behind in a finished match place will
--- be moved by Roblox's own matchmaking soon enough.
function ReturnGate.send()
	local players = Players:GetPlayers()

	if #players == 0 then
		return
	end

	if not Places.isConfigured() then
		warn("[ReturnGate] LOBBY_PLACE_ID is not set in Config/Places.luau; staying put.")
		return
	end

	if RunService:IsStudio() then
		print(`[ReturnGate] Studio: would return {#players} player(s) to place {Places.LOBBY_PLACE_ID}`)
		return
	end

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Places.LOBBY_PLACE_ID, players)
	end)

	if not ok then
		warn(`[ReturnGate] teleport back to the lobby failed: {tostring(err)}`)
	end
end

return ReturnGate

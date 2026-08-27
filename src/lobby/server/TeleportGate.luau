--!strict
--[[
	The teleport into a match.

	THIS IS THE ONE SEAM THE VERIFICATION GATE CANNOT REACH.

	TeleportService does not function in Studio. `TeleportAsync` raises there,
	every time, whatever the arguments. So no amount of lint, typecheck or Jest
	proves this module works - only a published pair of places does. That is
	the cost Alexei accepted when choosing two places over one round-based
	place, and pretending otherwise would be the dishonest part.

	Three things follow from that, and all three are deliberate:

	  1. Everything decidable WITHOUT teleporting is decided first and
	     separately - are the place ids configured, is the player list
	     non-empty. Those are ordinary testable code and they are where most
	     real failures will actually be.
	  2. In Studio the call is not attempted at all. It logs the exact payload
	     it would have sent instead, so the lobby remains fully playable and
	     the data being handed over is inspectable.
	  3. The single unverifiable call is wrapped in pcall and its failure is
	     reported to players. A teleport that silently does nothing is
	     indistinguishable from the game being broken.

	The manual procedure for verifying this against real places is written up
	in docs/MANUAL-VERIFICATION.md.
]]

local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Config.Places)
local Types = require(ReplicatedStorage.Shared.Types)

local TeleportGate = {}

export type Outcome = {
	ok: boolean,
	--- Human-readable, shown to players. Safe to expose: there is nothing an
	--- exploiter can do with "the place ids are not configured".
	reason: string?,
	--- True when the teleport was deliberately skipped rather than failed,
	--- which is the normal path in Studio.
	simulated: boolean,
}

local function failure(reason: string): Outcome
	return { ok = false, reason = reason, simulated = false }
end

--- Builds the TeleportOptions carrying the match parameters.
---
--- `ShouldReserveServer` gives each match its own private server, which is
--- what makes a match a match rather than a room in a shared world. It also
--- removes the need for a separate ReserveServer call and the access code
--- bookkeeping that goes with it.
local function buildOptions(launch: Types.MatchLaunchData): TeleportOptions
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true

	options:SetTeleportData({
		mapId = launch.mapId,
		difficultyId = launch.difficultyId,
	})

	return options
end

--- Everything that can be checked without touching TeleportService.
--- Separated so the failure modes that will actually happen in practice are
--- ordinary, testable code rather than hidden behind an untestable call.
function TeleportGate.preflight(players: { Player }): Outcome
	if #players == 0 then
		return failure("Nobody left in the lobby to send.")
	end

	if not Places.isConfigured() then
		-- Worth its own message. TeleportAsync to place id 0 fails with an
		-- error that reads like a Roblox outage rather than a missing
		-- constant, and that misdiagnosis costs hours.
		return failure("Match place is not configured yet. Set MATCH_PLACE_ID in Config/Places.luau.")
	end

	return { ok = true, reason = nil, simulated = false }
end

--- Sends `players` into a fresh reserved match server.
---
--- Yields. Call it from a task, never from a signal handler that something
--- else is waiting on.
function TeleportGate.send(players: { Player }, launch: Types.MatchLaunchData): Outcome
	local preflight = TeleportGate.preflight(players)

	if not preflight.ok then
		return preflight
	end

	if RunService:IsStudio() then
		-- Deliberately not attempted. See the header: this call cannot
		-- succeed in Studio, so trying it would turn every Studio playtest
		-- into a red herring.
		local names = {}

		for _, player in players do
			table.insert(names, player.Name)
		end

		print(
			`[TeleportGate] Studio: would teleport {#players} player(s) `
				.. `[{table.concat(names, ", ")}] to place {Places.MATCH_PLACE_ID} `
				.. `with mapId="{launch.mapId}" difficultyId="{launch.difficultyId}"`
		)

		return { ok = true, reason = nil, simulated = true }
	end

	local options = buildOptions(launch)

	-- The unverifiable call, and the only one in this module. pcall rather
	-- than a bare call because a raised teleport error would otherwise kill
	-- the lobby's state machine and leave everyone stuck in a launching
	-- state with no way out.
	print(
		`[td-launch] lobby teleporting {#players} player(s) to place {Places.MATCH_PLACE_ID} `
			.. `mapId="{launch.mapId}" difficultyId="{launch.difficultyId}"`
	)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Places.MATCH_PLACE_ID, players, options)
	end)

	if not ok then
		return failure(`Teleport failed: {tostring(err)}`)
	end

	return { ok = true, reason = nil, simulated = false }
end

--- Hooks TeleportInitFailed so a player whose teleport fails in flight is
--- told, rather than being left standing in the lobby wondering.
---
--- Returns the connection so the caller can own its lifetime.
function TeleportGate.onFailure(handler: (Player, string) -> ()): RBXScriptConnection
	return TeleportService.TeleportInitFailed:Connect(
		function(player: Player, result: Enum.TeleportResult, message: string)
			handler(player, `{result.Name}: {message}`)
		end
	)
end

return TeleportGate

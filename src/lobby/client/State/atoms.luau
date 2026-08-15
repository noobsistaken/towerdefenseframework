--!strict
--[[
	Lobby client state.

	Charm atoms are the single source of truth on the client; React reads them
	and stores no second copy. Everything above the divider is a REPLICA of
	server state and is written only by the net handlers in init.client.luau.
	Everything below it describes this player's local intent and never leaves
	the client except as a request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Types = require(ReplicatedStorage.Shared.Types)

export type Tally = {
	option: string,
	votes: number,
}

local atoms = {}

-- ---------------------------------------------------------------------------
-- Replicas. Written only by the net handlers.
-- ---------------------------------------------------------------------------

--- Annotated at the call site so the atom accepts any LobbyState rather than
--- narrowing to the literal it was initialised with.
atoms.lobbyState = Charm.atom("Gathering" :: Types.LobbyState)

atoms.secondsRemaining = Charm.atom(0)
atoms.playerCount = Charm.atom(0)
atoms.readyCount = Charm.atom(0)

atoms.mapTallies = Charm.atom({} :: { Tally })
atoms.difficultyTallies = Charm.atom({} :: { Tally })

--- Computed by the server so every client shows the same winner. Recomputing
--- it here would mean reimplementing the tie-break rule a second time.
atoms.winningMapId = Charm.atom("")
atoms.winningDifficultyId = Charm.atom("")

-- ---------------------------------------------------------------------------
-- Local intent. Never authoritative.
--
-- These exist so a button can highlight the instant it is pressed rather than
-- waiting for the round trip. The server's tally is what actually counts, and
-- it overwrites the display above regardless of what is stored here.
-- ---------------------------------------------------------------------------

atoms.isReady = Charm.atom(false)
atoms.myMapVote = Charm.atom(nil :: string?)
atoms.myDifficultyVote = Charm.atom(nil :: string?)

--- Why matchmaking failed, if it did. Cleared on the next state change.
atoms.failureReason = Charm.atom(nil :: string?)

return atoms

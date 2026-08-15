--!strict
--[[
	Client match state.

	Charm atoms are the single source of truth on the client; React reads
	them and stores no second copy. Everything here is a REPLICA - the server
	owns all of it, and nothing in this file may be written from UI code.
	The only writers are the network handlers in init.client.luau.

	Note that enemy positions and health are absent. Those ride on the
	server-owned parts themselves (ARCHITECTURE.md D2/D5), so the client
	reads them straight off the Instance rather than mirroring them here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Types = require(ReplicatedStorage.Shared.Types)

local atoms = {}

--- Annotated at the call site so the atom accepts any MatchState rather than
--- narrowing to the literal "Loading".
atoms.matchState = Charm.atom("Loading" :: Types.MatchState)
atoms.waveNumber = Charm.atom(0)

--- os.time() at which the current phase ends. 0 means the phase is untimed,
--- which the HUD renders as a dash rather than as "0s".
atoms.phaseEndsAt = Charm.atom(0)

--- True once the campaign's final wave has been cleared. A modifier on the
--- phase rather than a MatchState of its own, because endless waves still
--- cycle Preparing -> WaveActive -> Intermission.
atoms.endless = Charm.atom(false)

export type MatchResult = {
	won: boolean,
	wavesCleared: number,
	coinsAwarded: number,
	xpAwarded: number,
}

--- The last MatchEnded payload, or nil while a run is still going.
---
--- Nil-until-set rather than a flag plus fields, so the results screen cannot
--- render half a result. Note that this can be set TWICE in one run: once
--- when the campaign is cleared, and again if endless mode later ends in
--- defeat. The second overwrites the first, which is right - the screen
--- should show how the run actually finished.
atoms.matchResult = Charm.atom(nil :: MatchResult?)

atoms.baseHealth = Charm.atom(0)
atoms.baseHealthMax = Charm.atom(1)

--- This player's match cash. Per-player, TDS style - never another player's.
atoms.cash = Charm.atom(0)

--- Ticks once a second so the countdown re-renders without every other
--- component re-rendering with it.
atoms.clock = Charm.atom(0)

--- Which map is running. Drives the client's copy of the map config, which
--- placement preview validates against.
atoms.mapId = Charm.atom("")

--- Tower ids this player owns. Advisory - it greys out shop buttons. The
--- server re-checks unlock on every placement request.
atoms.unlockedTowers = Charm.atom({} :: { string })

-- ---------------------------------------------------------------------------
-- Local UI state
--
-- The only atoms below that are NOT replicas. They describe what this player
-- is currently looking at or holding, which the server has no opinion about.
-- ---------------------------------------------------------------------------

--- The tower being placed, or nil when not in placement mode.
atoms.selectedTowerDefId = Charm.atom(nil :: string?)

--- The placed tower the inspector is showing, or nil.
atoms.selectedTowerId = Charm.atom(nil :: number?)

--- Most recent placement refusal, for the feedback toast. Cleared on a
--- timer by whoever sets it.
atoms.placementRejection = Charm.atom(nil :: string?)

return atoms

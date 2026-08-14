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

atoms.baseHealth = Charm.atom(0)
atoms.baseHealthMax = Charm.atom(1)

--- This player's match cash. Per-player, TDS style - never another player's.
atoms.cash = Charm.atom(0)

--- Ticks once a second so the countdown re-renders without every other
--- component re-rendering with it.
atoms.clock = Charm.atom(0)

return atoms

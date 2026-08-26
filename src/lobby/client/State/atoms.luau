--!strict
--[[
	Lobby client state.

	Charm atoms are the single source of truth on the client; React reads
	them and stores no second copy. Everything above the divider is a
	REPLICA of server state, written by the net handlers in
	init.client.luau - plus the gacha panels, which patch the profile atoms
	with balances the server just RETURNED from a funct call. Everything
	below the divider describes this player's local intent and never leaves
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
-- Replicas.
-- ---------------------------------------------------------------------------

--- Annotated at the call site so the atom accepts any LobbyState rather than
--- narrowing to the literal it was initialised with.
atoms.lobbyState = Charm.atom("Gathering" :: Types.LobbyState)

atoms.playerCount = Charm.atom(0)

atoms.mapTallies = Charm.atom({} :: { Tally })
atoms.difficultyTallies = Charm.atom({} :: { Tally })

--- Computed by the server so every client shows the same winner. Recomputing
--- it here would mean reimplementing the tie-break rule a second time.
atoms.winningMapId = Charm.atom("")
atoms.winningDifficultyId = Charm.atom("")

--- This player's collection, fetched via GetLobbyProfile and PATCHED by
--- the roll replies (which carry the post-transaction balances precisely so
--- the display never has to derive money locally).
atoms.coins = Charm.atom(0)
atoms.rerollTokens = Charm.atom(0)
atoms.level = Charm.atom(1)
atoms.xp = Charm.atom(0)
atoms.unlockedTowers = Charm.atom({} :: { string })
--- The deck: at most Loadouts.MAX ids, always a subset of unlockedTowers.
atoms.loadout = Charm.atom({} :: { string })
--- towerId -> traitId. Flat pairs on the wire, a map here.
atoms.traits = Charm.atom({} :: { [string]: string })
--- False until the first REAL GetLobbyProfile answer (loaded=true), so the
--- UI can tell "no coins" from "not loaded yet".
atoms.profileLoaded = Charm.atom(false)

--- Everyone on this server, for the custom player list.
atoms.roster = Charm.atom({} :: { { userId: number, name: string, level: number } })

-- ---------------------------------------------------------------------------
-- Local intent. Never authoritative.
-- ---------------------------------------------------------------------------

--- This player's own picks in the game-area chooser, so the buttons can
--- highlight instantly. The server's tally is what actually counts.
atoms.myMapVote = Charm.atom(nil :: string?)
atoms.myDifficultyVote = Charm.atom(nil :: string?)

--- Why matchmaking failed, if it did. Cleared on the next state change.
atoms.failureReason = Charm.atom(nil :: string?)

--- Which walk-in area the local character stands in, from the shared
--- layout. Drives which panel is open; walking away closes it.
atoms.activeArea = Charm.atom(nil :: string?)

--- Whether the loadout editor is open. UI-only, but shared between the HUD
--- button that opens it and the panel that closes itself.
atoms.loadoutOpen = Charm.atom(false)

--- The unit featured on the reroll screen. Nil means "first owned". Set by
--- the unit-picker overlay, read by the panel - they are separate mounts,
--- which is why this lives here and not in component state.
atoms.rerollUnit = Charm.atom(nil :: string?)

--- The reroll screen's two overlays. Mounted at the ROOT of the UI tree
--- rather than inside the panel, so they can never z-fight the panel that
--- opened them - the lesson of the unreadable first Trait Chances popup.
atoms.traitChancesOpen = Charm.atom(false)
atoms.unitPickerOpen = Charm.atom(false)

return atoms

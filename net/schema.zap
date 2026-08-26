-- Networking contract. THIS FILE IS THE SOURCE OF TRUTH.
--
-- Never hand-write a RemoteEvent or RemoteFunction anywhere in src/.
-- Add or change a wire message here, run `zap net/schema.zap`, and commit the
-- regenerated files in net/generated/.
--
-- Why: a schema is a small, typed, reviewable surface. Hand-rolled remotes are
-- an unbounded one, and the failure mode (a typo'd event name, an unvalidated
-- payload from an exploiter) is silent at build time and expensive at runtime.
--
-- Zap validates every incoming payload against these types automatically, so
-- a client cannot send a shape the server did not ask for. It proves SHAPE.
-- It cannot prove PERMISSION - ownership, affordability, tower caps and
-- placement legality are all checked by hand on the server.
--
-- ---------------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT HERE (ARCHITECTURE.md D2, D5)
--
-- No enemy positions. No enemy health. No damage-number event.
--
-- Enemies are server-owned anchored parts, so their CFrame replicates
-- natively, and their health rides as an Attribute which is read-only to
-- clients. The client derives health bars and floating damage numbers from
-- GetAttributeChangedSignal("Health"). Several hits landing in one frame
-- coalescing into a single number is desirable, not a loss.
--
-- Adding a position or health message here would be duplicating replication
-- that Roblox already does, at 30Hz, for every enemy.
-- ---------------------------------------------------------------------------

-- NOTE: output paths are relative to THIS FILE, not to the repo root.
opt server_output = "generated/server.luau"
opt client_output = "generated/client.luau"

-- Strict typing on the generated API surface.
opt casing = "PascalCase"
opt write_checks = true
opt typescript = false

-- Yield on the server for SingleAsync/ManyAsync listeners, so a slow handler
-- cannot stall the whole remote queue.
opt call_default = "ManyAsync"

-- ---------------------------------------------------------------------------
-- Shared types
-- ---------------------------------------------------------------------------

-- Must stay in lockstep with Types.MatchState in src/shared/Types.luau.
type MatchState = enum { Loading, Preparing, WaveActive, Intermission, Victory, Defeat }

-- Must stay in lockstep with Types.LobbyState. Two states only: the hub
-- never counts down - a launch happens when someone in the game area
-- presses START, and until then the lobby is just a place.
type LobbyState = enum { Gathering, Launching }

-- Which of the lobby's two votes a message refers to. One event covers both,
-- because the tally logic is identical and a second near-identical event is
-- how the two drift apart.
type PollKind = enum { Map, Difficulty }

type TargetingMode = enum { First, Last, Strongest, Closest }

-- Why a placement request can be refused. The client shows a message; the
-- server never explains more than this, so probing it leaks nothing useful.
type PlacementRejectReason = enum {
	UnknownTower,
	NotUnlocked,
	CannotAfford,
	OutOfBounds,
	NotBuildable,
	WrongSurface,
	OverlapsTower,
	BlocksPath,
	-- Owned but not brought: the loadout is the deck, and the server
	-- refuses what you left at home.
	NotInLoadout,
	TowerCapReached,
	WrongMatchState,
}

-- ---------------------------------------------------------------------------
-- Match: client -> server intent
--
-- Every one of these is a REQUEST. The server decides. A client that sends a
-- well-formed message it has no right to send gets silently ignored or a
-- PlacementRejected, never the action.
-- ---------------------------------------------------------------------------

event RequestPlaceTower = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerDefId: string.utf8,
		-- Y is advisory only. The server raycasts the surface and overrides
		-- it, so a client cannot float a tower or sink it into terrain.
		position: vector,
		rotationY: f32,
	},
}

event RequestUpgradeTower = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
	},
}

event RequestSellTower = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
	},
}

event RequestSetTargeting = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
		mode: TargetingMode,
	},
}

-- Fires a tower's active ability. The server checks ownership, that the
-- tower HAS an ability, and its cooldown - all from state it already owns.
event RequestAbility = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
	},
}

-- Ends the build phase early. The remaining prep time converts to a cash
-- bonus for everyone, so the server reads its own clock and never trusts a
-- client-supplied duration.
event RequestEarlyStart = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
}

-- ---------------------------------------------------------------------------
-- Match: server -> client
-- ---------------------------------------------------------------------------

event MatchStateChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		state: MatchState,
		waveNumber: u16,
		-- os.time() at which the current phase ends. 0 when untimed.
		phaseEndsAt: f64,
		-- True once the campaign's final wave has been cleared and the run is
		-- on borrowed time. A modifier on the phase, not a phase of its own:
		-- endless waves still cycle Preparing -> WaveActive -> Intermission,
		-- so making it a MatchState would have duplicated all three.
		endless: boolean,
	},
}

-- Per-player, TDS style. Fired to one client, never broadcast.
event CashChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		cash: u32,
	},
}

event BaseHealthChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		current: u32,
		max: u32,
	},
}

event PlacementRejected = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		reason: PlacementRejectReason,
	},
}

event MatchEnded = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		won: boolean,
		wavesCleared: u16,
		coinsAwarded: u32,
		xpAwarded: u32,
		-- RerollTokens granted by this payout, spent on trait rerolls in the
		-- lobby. Small by design; u8 is generous.
		tokensAwarded: u8,
	},
}

-- An ability went off - the cue every client plays. Reliable, unlike the
-- tracers: abilities are rare and missing one reads as a dead button.
event AbilityUsed = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
		abilityId: string.utf8(..24),
		position: vector,
		-- Blast radius for the cue's expanding ring. 0 draws none.
		radius: f32,
	},
}

-- Cosmetic only. Unreliable because a dropped tracer is invisible, and at
-- 60 towers firing several times a second these must never queue.
event TowerFired = {
	from: Server,
	type: Unreliable,
	call: ManyAsync,
	data: struct {
		towerId: u32,
		targetPosition: vector,
	},
}

-- Sound hook. The key indexes Config/Sounds.luau; the client resolves it to
-- an asset id, and an unfilled slot plays nothing.
event PlaySound = {
	from: Server,
	type: Unreliable,
	call: ManyAsync,
	data: struct {
		-- Bounded deliberately: an unreliable packet must stay under 998
		-- bytes, and zap refuses to compile an unbounded string in one. Sound
		-- keys are short identifiers, so 32 is generous.
		soundKey: string.utf8(..32),
		position: vector?,
	},
}

-- Everything a joining or rejoining client needs to render the match at once.
-- Preferred over a RemoteFunction: typed on both ends, and it cannot yield the
-- caller indefinitely.
funct GetMatchSnapshot = {
	call: Async,
	args: struct {},
	rets: struct {
		state: MatchState,
		mapId: string.utf8,
		waveNumber: u16,
		baseHealth: u32,
		baseHealthMax: u32,
		cash: u32,
		phaseEndsAt: f64,
		-- Carried here as well as on MatchStateChanged, so a client joining
		-- mid-run renders the right header immediately rather than waiting
		-- for the next phase transition to tell it.
		endless: boolean,
		-- This player's persisted audio setting. Carried in the snapshot
		-- because it is read exactly once, at join, and a dedicated settings
		-- message for a value that never changes mid-match would be a message
		-- that only ever fires once.
		sfxEnabled: boolean,
		-- Which towers this player owns, so the shop can grey out the rest.
		-- Advisory: the server re-checks unlock on every placement request,
		-- so a client that ignores this gains nothing.
		unlockedTowers: string.utf8(..24)[0..64],
		-- The deck this player brought. THIS is what the shop shows -
		-- unlockedTowers is the collection, and twenty-six buttons was a
		-- shop nobody could read.
		loadout: string.utf8(..24)[0..6],
	},
}

-- ---------------------------------------------------------------------------
-- Lobby
--
-- Only ever fired in the lobby place. The two places share one schema file
-- deliberately: one generated module pair, one trust boundary to review, and
-- no chance of the two drifting into incompatible wire formats.
-- ---------------------------------------------------------------------------

-- One event for both votes. The tally logic is identical, and a second
-- near-identical event is exactly how two code paths drift apart.
--
-- `option` is validated against the server's own allowlist - MapRegistry.find
-- or Difficulty.find - before it is recorded. Zap proves it is a short string;
-- it cannot prove it names a real map.
event CastVote = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		poll: PollKind,
		option: string.utf8(..24),
	},
}

-- Launches a match for everyone standing in the GAME area, using the
-- area's votes. A request like every other: the server checks the sender
-- is actually in the area, from positions it already owns.
event RequestLaunch = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
}

-- Replaces the whole loadout - the deck of towers brought to a match.
-- Validated by Loadouts.apply: 1..6 entries, owned, real, no duplicates;
-- an invalid request changes nothing and echoes the standing deck.
funct SetLoadout = {
	call: Async,
	args: struct {
		towerIds: string.utf8(..24)[0..6],
	},
	rets: struct {
		ok: boolean,
		-- The deck as the server now holds it, accepted or not, so the
		-- client never has to guess what a refusal left behind.
		loadout: string.utf8(..24)[0..6],
	},
}

event LobbyStateChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		state: LobbyState,
		playerCount: u8,
	},
}

-- Sent whole rather than as deltas. A lobby holds at most a handful of
-- options and this fires only when someone votes, so the simplest thing that
-- cannot desync is the right one.
event VoteTallyChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		mapTallies: struct {
			option: string.utf8(..24),
			votes: u8,
		}[0..16],
		difficultyTallies: struct {
			option: string.utf8(..24),
			votes: u8,
		}[0..16],
		-- Precomputed by the server so every client shows the same winner.
		-- Recomputing it per client would mean reimplementing the tie-break.
		winningMapId: string.utf8(..24),
		winningDifficultyId: string.utf8(..24),
	},
}

-- One gacha roll, paid in Coins (Economy.GACHA_ROLL_COST). The server owns
-- the RNG, the price and the pool; the client owns nothing but the button.
-- A funct rather than an event pair so the reveal animation has its result
-- in hand the moment it starts.
--
-- `outcome` tells the client which of three screens to render. On Rolled
-- the tower was ADDED to the player's unlocks; on Duplicate the refund has
-- already been credited; on CannotAfford nothing changed. towerId and
-- rarityId are empty strings when there was no roll.
funct RollTower = {
	call: Async,
	args: struct {},
	rets: struct {
		-- Unavailable means NO SESSION - distinct from CannotAfford so the
		-- client neither shows "you are broke" nor patches its balances
		-- from a reply that knows nothing.
		outcome: enum { Rolled, Duplicate, CannotAfford, Unavailable },
		towerId: string.utf8(..24),
		rarityId: string.utf8(..24),
		-- Coin balance AFTER the roll, so the UI never derives money.
		coins: u32,
		-- Coins handed back on a duplicate. 0 otherwise.
		refunded: u32,
	},
}

-- Rerolls the trait on one OWNED tower, paid in RerollTokens. The old
-- trait is replaced, never stacked - Traits.SLOTS is 1 and the server
-- enforces it regardless of what the client believes.
funct RerollTrait = {
	call: Async,
	args: struct {
		towerId: string.utf8(..24),
	},
	rets: struct {
		outcome: enum { Rolled, CannotAfford, UnknownTower, Unavailable },
		traitId: string.utf8(..24),
		rarityId: string.utf8(..24),
		-- Token balance AFTER the reroll.
		tokens: u16,
	},
}

-- Everything the lobby UI renders about this player's collection. Fetched
-- once at join and refreshed after every roll and reroll; the amounts on
-- the roll replies keep the hot numbers current between fetches.
funct GetLobbyProfile = {
	call: Async,
	args: struct {},
	rets: struct {
		-- False when the profile session was not up when the server
		-- answered. The zeroed fields that follow are then MEANINGLESS,
		-- not a fresh account - without this flag the two were
		-- byte-identical, and a client latched the zeros for the whole
		-- session whenever the handoff outran the 10s wait.
		loaded: boolean,
		coins: u32,
		-- For the lobby HUD: account level and the XP inside it, so the
		-- hub can show progression without a second fetch.
		level: u16,
		xp: u32,
		loadout: string.utf8(..24)[0..6],
		rerollTokens: u16,
		unlockedTowers: string.utf8(..24)[0..64],
		-- Flattened { towerId, traitId } pairs: zap structs cannot carry a
		-- map, and SLOTS = 1 makes one pair per tower exact.
		traits: struct {
			towerId: string.utf8(..24),
			traitId: string.utf8(..24),
		}[0..64],
	},
}

-- Admin console. The server checks Config/Admins.luau on EVERY call -
-- the console rendering client-side is cosmetic, this check is the gate.
-- Cash is the per-match currency and only the match place honours it;
-- Coins and Tokens write to the profile and work in both places.
funct AdminGrant = {
	call: Async,
	args: struct {
		currency: enum { Cash, Coins, Tokens },
		-- Clamped server-side to a sane grant; u32 alone is not a policy.
		amount: u32,
	},
	rets: struct {
		ok: boolean,
		-- The balance AFTER the grant, for the console's feedback line.
		balance: u32,
	},
}

-- The teleport failed, or was never attempted because Config/Places.luau
-- still has placeholder ids. Carries a human-readable reason because there is
-- nothing an exploiter can do with it and a silent failure here is
-- indistinguishable from the game being broken.
event MatchmakingFailed = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		reason: string.utf8(..120),
	},
}

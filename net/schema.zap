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
		-- Which towers this player owns, so the shop can grey out the rest.
		-- Advisory: the server re-checks unlock on every placement request,
		-- so a client that ignores this gains nothing.
		unlockedTowers: string.utf8(..24)[0..32],
	},
}

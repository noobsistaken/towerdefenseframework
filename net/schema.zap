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
-- a client cannot send a shape the server did not ask for.

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
-- Example messages. Delete these once you have real ones - they exist to show
-- the four shapes you will actually need.
-- ---------------------------------------------------------------------------

-- Server -> client broadcast, unreliable, fire-and-forget.
event PlayerScoreChanged = {
	from: Server,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		player: Instance.Player,
		score: u32,
	},
}

-- Client -> server request. Zap validates the payload before your handler runs.
event RequestPurchase = {
	from: Client,
	type: Reliable,
	call: ManyAsync,
	data: struct {
		itemId: string.utf8,
		quantity: u8 (1..99),
	},
}

-- Client -> server, high frequency, drop-on-congestion.
event ReportInput = {
	from: Client,
	type: Unreliable,
	call: ManyAsync,
	data: struct {
		moveDirection: vector,
	},
}

-- Request/response. Prefer this over a RemoteFunction: it cannot yield the
-- caller indefinitely and it is typed on both ends.
funct GetLeaderboard = {
	call: Async,
	args: struct {
		page: u8 (0..99),
	},
	rets: struct {
		entries: struct {
			name: string.utf8,
			score: u32,
		}[0..50],
	},
}

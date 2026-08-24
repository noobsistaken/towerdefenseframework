# Tower Defense Framework

A server-authoritative Roblox tower defense framework, built to ship games on
rather than to demo. Two places — a lobby and a match — sharing one networking
schema and one shared module tree.

**→ Picking this up on a new machine? Start with [HANDOFF.md](HANDOFF.md).**

---

## Status

All five planned phases are built. The static gate is green: selene 0 errors,
stylua clean, **luau-lsp 0 diagnostics**, zap compiles, all three places build.

**Two things are not verified, and a green gate says nothing about either:**

1. **The test suite has never executed.** 12 spec files, 253 assertions, zero
   runs — Jest-Lua needs a Roblox VM, so CI proves lint, format, types and
   build, and nothing about behaviour. Open `build/test.rbxl` in Studio to run
   them.
2. **The lobby → match → lobby teleport has never run.** `TeleportService`
   does not function in Studio. Procedure:
   [docs/MANUAL-VERIFICATION.md](docs/MANUAL-VERIFICATION.md).

---

## Quick start

```bash
rokit install && wally install && mkdir -p build
```

Confirm the toolchain actually resolves before trusting any result — if this
does not print seven versions, prepend `~/.rokit/bin` to `PATH`:

```bash
for t in rojo wally selene stylua luau-lsp lune zap; do printf '%-10s ' "$t"; $t --version 2>&1 | head -1; done
```

Build and play the match place:

```bash
rojo build default.project.json --output build/game.rbxl
```

---

## What it does

**Towers** — six across three placement categories. Ground and Hillside towers
are restricted to tagged surfaces; Hillside towers are the ones that can hit
air, which is what makes an elevated plateau worth holding. Three to five
upgrade levels each, four targeting modes, partial-refund selling, and a range
preview during placement.

**Status effects** — a generic system covering damage-over-time, speed and
damage-taken multipliers, and stun, with per-effect stacking policies and
per-enemy resistances. Bleed and Slow ship; poison or burn is one config entry
with no new code.

**Enemies** — five types including an air unit and a boss, with a behaviour
system for the two that need state-dependent logic: Runner accelerates toward
the base, Titan enrages below 35% health.

**Waves** — hand-authored for the opening twelve so the player meets one new
idea at a time, then rule-driven, then endless with a steeper curve. Kill
bounty grows strictly slower than enemy health at every wave, so income falls
behind threat by design.

**Lobby** — map and difficulty voting, ready-up, and a reserved-server teleport
into the match.

**Economy** — per-player cash, TDS style. Kill bounty splits by damage
contribution rather than last hit, which is the only rule that is fair in
co-op. Wave-completion bonuses and an early-start bonus for skipping build
time.

Everything visual is a placeholder. Every slot is catalogued with real
dimensions in [docs/ASSET-MANIFEST.md](docs/ASSET-MANIFEST.md).

---

## Design

Adding content should be a config entry, not a code change:

- **A tower** → one entry in `Config/Towers.luau`, plus a behaviour module
  only if it does something `BaseTower` cannot express. Of the six shipped,
  two need one.
- **An enemy** → one entry in `Config/Enemies.luau` plus a count in
  `Config/Waves.luau`.
- **A status effect** → one entry in `Config/StatusEffects.luau`.
- **A map** → one module in `Config/Maps/` plus a line in `MapRegistry.luau`.
  Maps are Luau modules built at runtime, not `.rbxmx` files, so they stay
  diffable.

The structural rule everything else follows: **`src/shared/` holds pure
functions and data; anything touching an Instance or a Player lives under
`src/match/` or `src/lobby/`.** That boundary is the only reason a test suite
is possible — the enemy simulation is numbers with no Instance references, so
it can be stepped in a test.

Eight decisions are settled and written up with their reasoning in
[ARCHITECTURE.md](ARCHITECTURE.md). The one most likely to surprise: there is
**no class inheritance**, because strict Luau will not accept a derived
metatable type where the parent is expected. That was tested against the
compiler, not chosen by taste, and the findings are recorded.

---

## Documentation

| | |
|---|---|
| [HANDOFF.md](HANDOFF.md) | current state, setup, what is unverified, where to go next |
| [AGENTS.md](AGENTS.md) | working rules and the exact verification commands |
| [ARCHITECTURE.md](ARCHITECTURE.md) | why things are shaped this way; settled decisions |
| [docs/ASSET-MANIFEST.md](docs/ASSET-MANIFEST.md) | every art and audio slot, with dimensions |
| [docs/MANUAL-VERIFICATION.md](docs/MANUAL-VERIFICATION.md) | the teleport loop, which no gate can reach |

---

## Stack

Rojo · Wally · Zap · selene · StyLua · luau-lsp · Jest-Lua, all pinned in
[`rokit.toml`](rokit.toml). Strict Luau throughout. Dependencies are committed,
so a fresh clone typechecks and builds before it can reach the network.

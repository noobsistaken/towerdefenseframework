# Handoff

Everything needed to pick this up on another machine. Read this first, then
[AGENTS.md](AGENTS.md) for the working rules and
[ARCHITECTURE.md](ARCHITECTURE.md) for why things are shaped the way they are.

---

## What this is

A server-authoritative Roblox tower defense framework. Two places — a lobby
and a match — sharing one networking schema and one shared module tree.

All five planned phases are built and committed. The gate is green:
selene 0 errors, stylua clean, **luau-lsp 0 diagnostics**, zap compiles, all
three places build.

| | Files | Lines |
|---|---|---|
| `src/shared` | 28 | 3,422 |
| `src/match` | 30 | 5,614 |
| `src/lobby` | 7 | 1,141 |
| `tests` | 12 | 2,279 |

---

## Read this before trusting any green result

**Two things are unverified. Neither is a green gate away from being verified,
and neither should be reported as working.**

### 1. The test suite has never executed

12 spec files, **253 assertions, zero runs.** Jest-Lua needs a Roblox VM, so
CI proves lint + format + types + build and *nothing about behaviour*.

```bash
rojo build test.project.json --output build/test.rbxl
```

Open `build/test.rbxl` in Studio, press **Play**, read the Output window. You
are looking for `[tests] All suites passed.`

The three worth reading closely if something is red:

- **`Path.spec`** — arc-length parameterisation. If this is wrong, every enemy
  moves at the wrong speed and everything downstream is wrong too.
- **`Placement.spec`** (33 assertions) — includes the stacked-surface bug found
  in playtest, where Ground towers could be built on hills and Hillside towers
  could not.
- **`Scaling.spec`** — that kill bounty grows strictly slower than enemy
  health, at every wave. If that ever inverts, late waves print money and the
  difficulty collapses exactly where it should peak. Invisible until wave 35.

### 2. The lobby → match → lobby teleport has never run

`TeleportService` does not function in Studio — `TeleportAsync` raises there
every time, whatever the arguments. This is the cost of the two-place design,
accepted deliberately.

It is contained rather than hidden: everything decidable *without* teleporting
is decided separately and tested, Studio skips the call and logs the payload it
would have sent, and the single unverifiable line is `pcall`ed. What remains
untested is two function calls.

Full written procedure: **[docs/MANUAL-VERIFICATION.md](docs/MANUAL-VERIFICATION.md)**

It needs two published places and real ids in `src/shared/Config/Places.luau`
(both are `0` right now).

---

## Setup on a new machine

```bash
git clone https://github.com/noobsistaken/towerdefenseframework.git
cd towerdefenseframework
rokit install
wally install
mkdir -p build
```

### The trap that will cost you an hour

Rokit installs its shims to `~/.rokit/bin`. **If that is not on `PATH`, every
gate in this repo silently passes having checked nothing** — each one invokes
its tools behind `command -v` and treats a missing tool as a deliberate no-op,
so nothing fails, it just stops checking.

This is not hypothetical: on the machine this was built on, six of the seven
tools resolved to nothing until that directory was prepended. If you also have
Aftman installed, its `~/.aftman/bin` may shadow rokit for tools it manages —
this repo still carries an `aftman.toml` listing rojo, kept from the template.

Verify before trusting anything:

```bash
for t in rojo wally selene stylua luau-lsp lune zap; do printf '%-10s ' "$t"; $t --version 2>&1 | head -1; done
```

If that does not print seven versions:

```bash
export PATH="$HOME/.rokit/bin:$PATH"
```

`.claude/hooks/post-edit-luau.sh` self-heals — it prepends the directory
itself. Plain shell commands do not.

---

## Commands

Full gate, run before claiming anything works:

```bash
rojo sourcemap test.project.json --output sourcemap.json && selene src tests && stylua --check . && luau-lsp analyze --sourcemap=sourcemap.json --defs=types/globalTypes.d.luau --ignore="**/Packages/**" --ignore="**/ServerPackages/**" --ignore="**/DevPackages/**" src tests
```

Builds:

```bash
rojo build default.project.json --output build/game.rbxl
```

```bash
rojo build lobby.project.json --output build/lobby.rbxl
```

```bash
rojo build test.project.json --output build/test.rbxl
```

After editing `net/schema.zap`:

```bash
zap --no-warnings net/schema.zap
```

> Zap output is **not byte-reproducible** — it emits `export type` aliases in a
> nondeterministic order, so a regeneration can dirty `net/generated/` with
> nothing having changed. See ARCHITECTURE.md for the one-line diff filter that
> tells you whether a change was real.

---

## Playing it

**Match:** open `build/game.rbxl`, press Play. Which map and difficulty you get
is set in `src/shared/Config/DevMatch.luau` — Studio never arrives by teleport,
so there is no join data to read.

**Lobby:** set `Places.STUDIO_ROLE = "Lobby"` in
`src/shared/Config/Places.luau`, rebuild the test place, press Play. Voting,
ready-up, countdown and tally all work; the teleport prints what it would have
sent. **Set it back to `"Match"` afterwards** or the test place stops booting
the game.

---

## Layout

```
net/schema.zap        networking contract — the source of truth
net/generated/        zap output — committed, never hand-edited
src/shared/           ReplicatedStorage.Shared (both places) — pure logic + config
src/match/server/     ServerScriptService.Server
src/match/client/     StarterPlayerScripts.Client
src/lobby/server/     ServerScriptService.Lobby
src/lobby/client/     StarterPlayerScripts.LobbyClient
tests/                ServerScriptService.Tests (test place only)
docs/                 asset manifest, manual verification, design spec
```

The split rule: **`src/shared/` holds pure functions and data; anything that
touches an Instance or a Player lives under `src/match/` or `src/lobby/`.**
That boundary is the only reason a test suite is possible at all.

`test.project.json` mounts **both** place trees, because luau-lsp builds its
sourcemap from it and every require has to resolve from one map.
`Places.STUDIO_ROLE` decides which entry point actually boots there.

---

## Decisions that are settled

Do not re-litigate these. Full reasoning in ARCHITECTURE.md.

| # | Decision |
|---|---|
| D1 | Two places + TeleportService, with a Studio fallback so the match is playable solo |
| D2 | Enemies are a numeric simulation projected one-way onto pooled hitbox parts. Never read position back off a part |
| D3 | **No class inheritance.** One concrete class per family + a `behavior` vtable field |
| D4 | Content is config; a behaviour module exists only when config cannot express it |
| D5 | Instance-resident state replicates via Attributes; everything else via Zap |
| D6 | Kill bounty splits by damage contribution, not last hit |
| D7 | Maps are Luau config modules built at runtime, never `.rbxmx` |
| D8 | `distanceToBase = pathLength - progress` is the universal ordering key |

**On D3 specifically** — this was tested against the compiler, not chosen by
taste. Strict Luau will not accept a derived metatable type where the parent is
expected, nor against a plain structural record. Classical inheritance needs a
cast at *every inherited method call*, which are the per-frame hot paths, and
that is exactly the `:: any` this project's strict-mode rule forbids. The
findings are written up in ARCHITECTURE.md → "Why there is no `BaseTower`
subclass hierarchy".

---

## Where to go next

**Highest value first:**

1. **Run the test suite.** 253 assertions are sitting unexecuted. Everything
   below is less valuable than knowing whether they pass.
2. **Publish two places and walk `docs/MANUAL-VERIFICATION.md`.** That closes
   the second gap.
3. **Fill asset slots** from [docs/ASSET-MANIFEST.md](docs/ASSET-MANIFEST.md) —
   every dimension in it was read out of the config, not remembered.

**Known gaps that are genuinely empty, not placeholder:**

- `BossDeath` is defined but never fired — the client plays `EnemyDeath` for
  every kill and does not distinguish a boss
- No music. `PlayerData.Settings.MusicEnabled` is persisted and unused —
  deliberately, because music needs a track list and a crossfade policy, which
  is a design decision rather than a slot

**Adding content is config-only:**

- A tower → one entry in `Config/Towers.luau`, plus a behaviour module only if
  it does something `BaseTower` cannot express
- An enemy → one entry in `Config/Enemies.luau` + a count in `Config/Waves.luau`
- A status effect → one entry in `Config/StatusEffects.luau`. Bleed and Slow
  already cover two of the four kinds
- A map → one module in `Config/Maps/` + a line in `MapRegistry.luau`

---

## Rules worth restating

- **Never end a turn with code that has not passed the gate.** Not "it looks
  right", not "the edit was small".
- **Never hand-write a RemoteEvent.** Edit `net/schema.zap`, run zap, commit
  the regenerated output.
- **Never edit anything in `Packages/`, `ServerPackages/`, `DevPackages/`.**
  The next `wally install` destroys it.
- **Never silence a type error with `:: any`.** If a cast is genuinely needed
  it gets a comment saying why, like the ProfileStore one in
  `src/match/server/init.server.luau`.
- **Data shape changes** go through `src/shared/DataSchema.luau` — bump
  `CURRENT_VERSION` and add exactly one migration step.
- **Never claim tests passed in CI.** They cannot run there.

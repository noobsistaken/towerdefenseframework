# 2026-08-25 — Effects pass: status tint, splash, enrage, boss death

## Goal

Work the "Fill asset slots" item from HANDOFF.md's *Where to go next* — the
only one of its three that does not require Studio or published places. Closed
four of the effect/audio gaps listed in `docs/ASSET-MANIFEST.md`.

## State

Branch `feat/status-effect-visuals`, four commits on top of `main` (2f66417).
**Local only — never pushed.**

| Commit | What |
|---|---|
| `e501278` | Status effects tint the enemy (Bleed red, Slow blue) |
| `d3299bd` | Splash burst sphere + the `Splash` sound cue |
| `991569a` | Titan enrage tell (pulsing Highlight) |
| `469aa93` | `BossDeath` for boss kills, with an `isFilled` fallback |

**Verified:** selene 0/0/0, luau-lsp 0 diagnostics, all three places build,
stylua clean on every touched file (LF-normalised — see landmines). Re-run
after each commit, not just at the end.

**NOT verified — nothing here has run.** Zero of these four effects has been
seen. The test suite's 253 assertions are still unexecuted. `build/test.rbxl`
is built and current; open it in Studio, press Play, look for
`[tests] All suites passed.`

## Next step

Open `build/game.rbxl` in Studio and look at the four effects. Specifically:

1. Bleed/Slow tint — needs a Lacerator or a slow source on the field.
2. Splash sphere — build a Mortar (radius 14/16/19) or Flak (10/12/14).
3. Enrage — chip a Titan below 35% health (wave 10+).
4. Boss death — inaudible by construction today; every `assetId` is `""`.

Then run `build/test.rbxl` for the 253 assertions.

## Landmines

- **`stylua --check .` is red across the whole tree and always was on this
  machine.** Git's system-level `core.autocrlf = true` plus no `.gitattributes`
  means all 78 `.luau` files are CRLF, while `stylua.toml` sets
  `line_endings = "Unix"`. Measured per-file: 78/78 fail as CRLF, 0/78 fail
  once converted to LF. Not caused by any of this branch's work. Fix is
  `core.autocrlf false` + re-checkout, or a committed `.gitattributes`.
  Alexei was asked and said it doesn't matter — do not "fix" it unprompted.
- **Do not count `stylua --check` output.** It interleaves across threads; the
  same command returned 11, 12 and 13 on three consecutive runs. Check
  exit codes per file instead.
- **The `.claude` PostToolUse hook is a no-op until Claude Code restarts.** jq
  was installed this session (winget, `jqlang.jq` 1.8.2) but winget writes PATH
  to the registry and running processes do not re-read it. The hook exits 0 at
  `command -v jq` and verifies nothing. Rokit toolchain is installed and all
  seven tools resolve when `~/.rokit/bin` is prepended.
- **`~/.aftman/bin` sits AHEAD of `~/.rokit/bin` in the user PATH.** Harmless
  right now — it only holds `aftman.exe` and a `rojo.exe.disabled` — but it
  will start shadowing if aftman is ever used again.
- **Enemy parts now carry five attributes**, not three: `Health`, `MaxHealth`,
  `EnemyId`, `StatusEffects`, `Enraged`. `ASSET-MANIFEST` § *Swapping parts for
  models* is updated to match.

## Decisions made

- **Status effects replicate as an Attribute, not Zap** (D5: instance-resident
  state). The server publishes live effect **ids**, not a colour, so the client
  resolves colour from shared config and a new effect tints with no code change.
  The sort in `describeEffects` is load-bearing: `enemy.effects` is a hash map
  with no stable iteration order, so an unsorted join would replicate every
  frame for an unchanged set.
- **Splash derives client-side; enrage does not.** Deliberately opposite. Splash
  reads `splashRadius`, a number already in shared config. Enrage would have
  meant the client reimplementing a predicate that lives in a server behaviour
  module, so the server publishes the fact via an optional `enraged` hook on
  `BaseEnemy.EnemyBehavior`. `speedMultiplier > 1` is NOT usable as a proxy —
  Runner returns >1 for most of its life.
- **A sphere, not a ground ring**, for splash: `Splash.luau` tests a true 3D
  distance over X/Y/Z, so a flat disc would misdescribe what Flak catches.
- **A Highlight, not a colour change**, for enrage: `Color` is already owned by
  the status tint, and a bleeding enraged Titan has to show both.
- **`BossDeath` falls back to `EnemyDeath`** via `Sounds.isFilled` rather than
  replacing it outright, so recording `EnemyDeath` alone cannot make the Titan
  the only silent death.

## Found but deliberately not fixed

- **A damage-over-time kill plays no death cue at all.** `EnemySimulation.step`
  calls `collectDead` at the end of the same step a bleed tick kills in, so the
  part is released and its attributes wiped before any `view:sync()` writes
  `Health = 0`. Bullet kills escape only because `towers:update` sits between
  `simulation:update` and `view:sync()`. Read out of the call order, **not
  observed in Studio** — confirm there before touching server ordering. Filed
  in HANDOFF under *Known defects*.
- **Four sound keys have no call site**: `PlacementRejected`, `ButtonClick`,
  `VoteCast`, `MatchLaunching`. The last two are unfireable — `src/lobby/` has
  no audio path whatsoever.
- **No spec covers enemy behaviours.** Runner's acceleration and Titan's enrage
  threshold have zero test coverage; `tests/` holds only shared-module specs.
  The Titan refactor in `991569a` is behaviour-preserving by reading, not by a
  test.
- **A same-frame pool recycle may be invisible to the client.** `PartPool`
  free-list is LIFO and a part can go container -> nil -> container inside one
  server tick, which would leave `EnemyVisuals`' cached per-entry state stale.
  Pre-existing — `maxHealth` has the same exposure. `Constants.ATTR_ENEMY_ID`
  is written every acquire and read by nothing; it is the obvious signal if
  this ever needs solving.

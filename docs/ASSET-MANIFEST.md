# Asset replacement manifest

Every visual and audio slot in the framework, what it currently is, and what
it expects. **Every dimension below was read out of the config, not
remembered** — if you change a config value, that column is what changed.

Nothing here is a rewrite. Each slot is either a config field or a single
function in one module, and the code around it does not care what you put in.

---

## How the slots work

Three mechanisms, and it is worth knowing which one you are touching:

| Mechanism | Where | Replacing it means |
|---|---|---|
| **Config field** | `src/shared/Config/*.luau` | edit a value — colour, size, asset id |
| **Builder function** | `MapBuilder`, `TowerSystem`, `EnemyView` | swap `Instance.new("Part")` for a Model clone |
| **Theme token** | `src/shared/Theme.luau` | edit one value, every component follows |

The builder functions are the only place a Part is created. There are five of
them, listed under [Swapping parts for models](#swapping-parts-for-models).

---

## 1. Towers — 23 level visuals across 6 towers

Currently a single coloured `Part` per tower, resized per level.
**Slot:** `levels[n].modelSize` and `levels[n].color` in
[`Config/Towers.luau`](../src/shared/Config/Towers.luau).

A model must fit its **footprint** on the XZ plane — placement collision uses
`max(x, z) / 2` as a radius and does not read the model. Height is free.

| Tower | Category | Targets | Footprint | Level sizes (X, Y, Z studs) | Range |
|---|---|---|---|---|---|
| **Rifleman** | Ground | Ground | 6×6 | 4×6×4 · 4×7×4 · 4.5×8×4.5 · 5×9×5 · 5.5×10×5.5 | 42→60 |
| **Mortar** | Ground | Ground | 9×9 | 7×5×7 · 7.5×5.5×7.5 · 8×6×8 | 70→82 |
| **Marksman** | Hillside | Air+Ground | 7×7 | 5×9×5 · 5×10×5 · 5.5×11×5.5 · 6×12.5×6 | 95→130 |
| **Flak** | Hillside | Air+Ground | 8×8 | 6×6×6 · 6.5×7×6.5 · 7×8×7 | 60→72 |
| **Ranger** | Hybrid | Air+Ground | 6×6 | 4.5×7×4.5 · 4.5×8×4.5 · 5×9×5 · 5.5×10×5.5 | 55→72 |
| **Lacerator** | Hybrid | Air+Ground | 6×6 | 4.5×7×4.5 · 4.5×8×4.5 · 5×9×5 · 5.5×10×5.5 | 50→64 |

**Design note worth keeping:** the model grows visibly with each level. That
is the only cue a player has that an upgrade landed, so if a real model keeps
a constant size, add a different per-level cue (a barrel, a banner, an emissive
trim) or upgrades become invisible.

**Also needed per tower:** a **shop icon**, 256×256 PNG, transparent
background. Currently a coloured square in
[`ShopBar.luau`](../src/match/client/UI/ShopBar.luau).

---

## 2. Enemies — 5 types

Currently one coloured `Part` each, pooled and recycled.
**Slot:** `hitboxSize`, `color`, `hoverHeight` in
[`Config/Enemies.luau`](../src/shared/Config/Enemies.luau).

`hitboxSize` is the collision and visual box. `hoverHeight` lifts the model's
centre above the path line — it is what makes Drifter read as flying.

| Enemy | Class | Hitbox (X, Y, Z) | Hover | Notes |
|---|---|---|---|---|
| **Zombie** | Ground | 2 × 4 × 2 | 2 | baseline |
| **Runner** | Ground | 1.6 × 3.4 × 1.6 | 1.7 | accelerates toward the base — wants a run cycle |
| **Tank** | Ground | 3.4 × 4.6 × 3.4 | 2.3 | slow, heavy |
| **Drifter** | **Air** | 2.6 × 2.6 × 2.6 | **14** | must read as airborne from directly above |
| **Titan** | Ground (boss) | 7 × 11 × 7 | 5.5 | enrages below 35% health — pulsing Highlight marks it |

**Hard constraint:** enemies are moved with `WorldRoot:BulkMoveTo` in one call
per frame. A replacement must be a **single anchored part or a model with one
anchored PrimaryPart**. A rigged, animated model with loose parts will not move
— it must be welded to the primary part.

**Titan's enrage** is marked by a pulsing `Highlight` on the enemy part, driven
by an `Enraged` attribute the server publishes from the behaviour's own
predicate — so the speed bonus and the glow cannot disagree. A `Highlight`
rather than a colour change because `Color` belongs to the status tint, and a
Titan that is both bleeding and enraged has to show both.

Any behaviour returning `true` from the optional `enraged` hook on
`BaseEnemy.EnemyBehavior` gets the same tell with no extra code.

---

## 3. Maps — 3 maps

All geometry is built at runtime from config by
[`MapBuilder.luau`](../src/match/server/Match/MapBuilder.luau). Maps are Luau
modules, not `.rbxmx` files, so they stay diffable.

**You can still author them in Studio.** The loop is build -> drag -> extract:

1. Build the map into the Edit session:
   `MapBuilder.build(MapRegistry.get("Crossroads"))`. It emits a `Lanes` folder
   of draggable waypoint markers alongside the geometry - visible in Studio,
   invisible in a live server.
2. Move things. Drag waypoints, resize the ground, add decor, add buildable
   pads (tag them `TDBuildable` and give them a `SurfaceType` attribute).
3. Extract: `MapExtract.fromFolder(workspace.TDMap, id, displayName)` returns
   the config plus a list of problems, and `MapExtract.toSource(config)`
   renders the module to drop into `Config/Maps/`.

The runtime still consumes plain data, which is why the placement and pathing
specs keep working. Extraction reports rather than guesses: an untagged pad, a
waypoint with no order, or a missing ground part comes back as a named problem
instead of a silently wrong map.

Re-extraction overwrites the module, so a generated map loses hand-written
comments. Crossroads, Switchback and Fork stay hand-authored for that reason -
their comments carry design intent worth keeping.

| Map | Lanes | Lane lengths | Plateaus | Ground plane | Decor |
|---|---|---|---|---|---|
| **Crossroads** | 1 | 610 studs | 2 | 340 × 300 | 3 |
| **Switchback** | 1 | 820 studs | 1 | 340 × 320 | 2 |
| **Fork** | 2 | 370 + 450 studs | 2 | 340 × 320 | 4 |

**Slots per map** — all in `Config/Maps/<Name>.luau`:

| Slot | Current | Expects |
|---|---|---|
| Ground plane | flat coloured Part | terrain or a tiled floor model |
| Walkway | 16-stud-wide strip, `y = 0.15` | path texture or decal; **width is cosmetic, clearance is not** |
| Buildable apron | 1 stud proud, tinted | must stay visually distinct from non-buildable ground |
| Plateaus | 12 studs tall | ramps are currently *implied* by decor, not walkable |
| Base marker | coloured Part at `basePosition` | the thing enemies are attacking |
| Spawn markers | red slab per lane | portal, gate, tunnel mouth |

**Do not change without reading the code:** `PATH_CLEARANCE` (9 studs) is a
*gameplay* rule, not a visual one. Making the walkway wider does not widen the
no-build corridor — that constant does, in
[`Constants.luau`](../src/shared/Constants.luau).

---

## 4. Sounds — 21 keys, all empty

**Slot:** `assetId` in [`Config/Sounds.luau`](../src/shared/Config/Sounds.luau).
Every entry is `""` and plays nothing. Set it to `"rbxassetid://…"` and it
plays. No code change.

`spatial = true` plays at a world position; `false` is a flat 2D cue.

| Key | Vol | Pitch var | Spatial |
|---|---|---|---|
| `TowerPlaced` | 0.5 | ±0.05 | no |
| `TowerUpgraded` | 0.5 | ±0.05 | no |
| `TowerSold` | 0.45 | ±0.05 | no |
| `PlacementRejected` | 0.4 | — | no |
| `ButtonClick` | 0.3 | ±0.04 | no |
| `Fire_Rifleman` | 0.25 | ±0.08 | yes |
| `Fire_Mortar` | 0.45 | ±0.06 | yes |
| `Fire_Marksman` | 0.4 | ±0.05 | yes |
| `Fire_Flak` | 0.3 | ±0.08 | yes |
| `Fire_Ranger` | 0.28 | ±0.08 | yes |
| `Fire_Lacerator` | 0.28 | ±0.1 | yes |
| `EnemyDeath` | 0.3 | ±0.12 | yes |
| `BossDeath` | 0.7 | — | yes |
| `Splash` | 0.4 | ±0.08 | yes |
| `WaveStart` | 0.6 | — | no |
| `WaveCleared` | 0.55 | — | no |
| `BaseDamaged` | 0.6 | ±0.05 | no |
| `Victory` | 0.8 | — | no |
| `Defeat` | 0.8 | — | no |
| `VoteCast` | 0.35 | ±0.06 | no |
| `MatchLaunching` | 0.7 | — | no |

**Fire sounds are the ones to get right.** A tower fires up to 2.5×/second and
sixty can be on the field, so a fire cue with a long tail or no pitch variance
turns into noise. `pitchVariance` exists for exactly this.

**Four keys still have no call site:** `PlacementRejected`, `ButtonClick`,
`VoteCast` and `MatchLaunching`. Filling their asset ids changes nothing until
something fires them. (An earlier revision of this file claimed only one key
was unfired. It was wrong — these four were already dead then.)

`VoteCast` and `MatchLaunching` are the awkward pair: they are lobby cues, but
`SoundController` lives under `src/match/client/` and nothing anywhere in
`src/lobby/` mentions sound. They are **unfireable**, not merely unfired —
wiring them means giving the lobby an audio path first.

`BossDeath` is fired by `EnemyVisuals.luau` in place of `EnemyDeath` when the
dying enemy's definition has `isBoss = true`, and falls back to `EnemyDeath`
while it has no audio behind it — so recording `EnemyDeath` alone cannot make
the Titan the one enemy that dies silently. Derived from the part's name
rather than sent, so like `Splash` it costs no network message.

**Neither death cue fires for a kill by a damage-over-time tick.** Both are
inferred client-side from the enemy's last replicated health, and
`EnemySimulation.step` calls `collectDead` at the end of the same step a bleed
tick kills in — the part is released, its attributes wiped, before any
`view:sync()` writes `Health = 0`. A bullet kill escapes this only because
`towers:update` runs between `simulation:update` and `view:sync()`. Read out of
the call order in `EnemySimulation.luau` and `MatchController.luau`, not
observed in Studio. Pre-existing; the fix is server-side ordering.

`Splash` is fired by `Tracers.luau`, derived from the firing tower's level
rather than sent, so it costs no network message.

**No music slot exists.** `PlayerData.Settings.MusicEnabled` is persisted and
unused. Music is a deliberate gap, not an oversight — it needs a track list and
a crossfade policy, which is a design decision rather than a slot.

---

## 5. UI

**Slot:** [`Theme.luau`](../src/shared/Theme.luau) — 11 colours, 2 fonts,
2 corner radii. Every component reads from it, so an art pass is one file.

| Token | Current | Used for |
|---|---|---|
| `PANEL` / `RAISED` | dark blue-grey | panel and button backgrounds |
| `TEXT` / `MUTED` / `INVERSE` | off-white / grey / near-black | type |
| `ACCENT` | blue | phase label, primary buttons |
| `HEALTH` | red | base health bar |
| `CASH` | gold | currency |
| `POSITIVE` / `NEGATIVE` | green / red | enemy health, refusals |
| `DISABLED` | grey | unaffordable shop buttons |
| `FONT` / `FONT_BODY` | GothamBold / GothamMedium | replace with a custom font |

**Panels needing real art:** shop bar, tower inspector, HUD panels (base
health / wave / cash), results card, lobby vote buttons and map plinths.

`Theme.REJECTION_TEXT` holds the ten placement refusal strings — the only
player-facing copy in the codebase, and where localisation would start.

---

## 6. Effects

| Effect | Current | Slot |
|---|---|---|
| Shot tracer | thin cylinder, 0.09s fade | [`Tracers.luau`](../src/match/client/Effects/Tracers.luau) — beam, projectile, or muzzle flash |
| Damage number | white text rising 6 studs over 0.8s | [`EnemyVisuals.luau`](../src/match/client/Effects/EnemyVisuals.luau) |
| Health bar | 4 × 0.5 stud billboard, culled past 260 studs | same file |
| Splash | neon sphere expanding to the real `splashRadius`, 0.18s fade | [`Tracers.luau`](../src/match/client/Effects/Tracers.luau) — particles or a shockwave |
| Status effect | enemy tinted to the effect's `color` | [`EnemyVisuals.luau`](../src/match/client/Effects/EnemyVisuals.luau) — particles, or an icon on the bar |

Both were gaps rather than placeholders until recently. Both are now filled at
the cheapest level that reads correctly in play, and neither needed a network
message:

- The splash sphere is sized off `splashRadius`, read from the firing tower's
  `TowerDefId` and `Level` attributes, so the player sees the area that was
  actually damaged. A sphere and not a ground ring because the server's test
  is a true 3D distance.
- The status tint reads a `StatusEffects` attribute carrying the live effect
  ids, and resolves the colour from shared config — so a new effect tints with
  no code change on either realm.

---

## Swapping parts for models

Five functions create every Part in the game. Nothing else needs to change.

| What | File | Function |
|---|---|---|
| Enemies | `Simulation/PartPool.luau` | `newPooledPart` |
| Towers | `Systems/TowerSystem.luau` | tower part creation |
| Map geometry | `Match/MapBuilder.luau` | `newPart` |
| Lobby geometry | `lobby/server/LobbyBuilder.luau` | `newPart` |
| Placement ghost | `Placement/PlacementController.luau` | ghost creation |

**Constraints that survive the swap:**

1. Enemy models need **one anchored PrimaryPart**, everything else welded —
   `BulkMoveTo` moves one part per enemy.
2. Enemy parts must keep the `Health`, `MaxHealth`, `EnemyId`,
   `StatusEffects` and `Enraged` **attributes**. Health bars, damage numbers,
   the status tint and the enrage tell all read them, and no network message
   carries any of it (ARCHITECTURE.md D5).
3. Tower parts must keep `TowerId`, `TowerDefId`, `Level`, `OwnerUserId`,
   `TargetingMode`, `Range`, `SellValue`. The inspector and the fire-sound
   lookup read them off the part.
4. Buildable pads must keep the `TDBuildable` tag and `SurfaceType` attribute.
5. Everything stays **anchored**. Nothing in this game is simulated by physics.

---

## What should NOT become an asset

- **Range preview** — a generated circle. A ring texture would alias at the
  40–130 stud range spread.
- **Placement ghost tint** — green/red is the entire feedback mechanism.
- **Health bar fill** — a resized Frame. An image would stretch.
- **The `TDMap` / `TDEnemies` / `TDTowers` folders** — code contracts, not
  organisation. `EnemyVisuals` and `Tracers` find their targets by folder name.

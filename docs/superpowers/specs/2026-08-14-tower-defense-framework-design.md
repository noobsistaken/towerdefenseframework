# Tower Defense Framework — Design

**Status:** approved 2026-08-14 · **Branch:** `feat/td-framework`

A production-quality, extensible tower defense framework. Adding a tower or an
enemy must mean adding a config entry plus an optional behaviour override, and
nothing else.

---

## Verified facts

Checked against `types/globalTypes.d.luau` on 2026-08-14. These are quoted
signatures, not recollections.

| API | Signature |
|---|---|
| `WorldRoot:BulkMoveTo` | `(partList: {BasePart}, cframeList: {CFrame}, eventMode: EnumBulkMoveMode?) -> nil` |
| `TeleportService:TeleportAsync` | `(placeId: number, players: {Player}, teleportOptions: TeleportOptions?) -> TeleportAsyncResult` |
| `TeleportOptions.ShouldReserveServer` | `boolean` — removes the need for a separate `ReserveServer` call |
| `Player:GetJoinData` | `-> { LaunchData: string?, Members: {number}?, SourceGameId: number?, SourcePlaceId: number?, TeleportData: TeleportData? }` |
| `TeleportService.TeleportInitFailed` | `RBXScriptSignal<Player, EnumTeleportResult, string, number, TeleportOptions>` |
| `WorldRoot:GetPartBoundsInRadius` | `(position: Vector3, radius: number, overlapParams: OverlapParams?) -> {BasePart}` |

**Deliberately not asserted:** whether `TeleportData` is tamper-proof in
transit. Roblox's own guidance is to treat it as untrusted and this design does
not depend on the answer — the match place validates every arriving field
against the config allowlist and falls back to defaults. Correct either way.

---

## Constraints

- **Data schema change:** yes. `CURRENT_VERSION` stays `1`; the placeholder
  template is replaced wholesale because the template has never shipped and
  there is no live player data to migrate.
- **Network schema change:** yes, total rewrite. All four example messages
  are deleted.
- **New dependency:** no. See ARCHITECTURE.md → Locked Dependencies.
- **Runtime verification:** Jest runs only inside a Roblox VM. CI proves
  lint + format + types + build and never behaviour. Studio-verified items
  are named as such and never reported done on a passing typecheck.

---

## Decisions

Alexei overruled the recommendation on the first two. Both are settled.

**D1 — Two places, with a Studio fallback.**
Lobby (`build/lobby.rbxl`) teleports parties into reserved servers of the match
place (`build/game.rbxl`). `default.project.json` stays the *match* place so
every command already in AGENTS.md keeps working. `RunService:IsStudio()` makes
the match place boot from `Config/DevMatch.luau` instead of join data, so it is
fully playable solo in Studio; the lobby logs the payload it would have sent.
The unverifiable surface is exactly one `TeleportAsync` call, which gets a
written manual procedure in Phase 4.

**D2 — The simulation owns truth; parts are a one-way projection.**
`EnemySimulation` stores `{ guid, defId, pathIndex, progress, health, effects }`
— no Instance references, no userdata — and steps on a fixed 30 Hz accumulator,
making it deterministic and steppable in a test. `EnemyView` writes that state
to pooled hitbox parts in one `BulkMoveTo` per step. Position is never read
back off a part.

Two consequences:
- Enemy position and HP cost **nothing** in the net schema. Parts replicate
  natively; HP rides as an Attribute. Health bars and damage numbers derive
  from `GetAttributeChangedSignal("Health")`, and coalescing several hits in
  one frame into a single number is desirable.
- Targeting is near-O(1). Enemies stay sorted by `distanceToBase`, and a
  tower's range maps to a fixed arc-length window on each path, computable
  once at placement since both are static. Acquisition is a binary search plus
  a few exact checks, not 60 towers × 200 enemies × 30 Hz.

Target scale: ~200 concurrent enemies, ~60 towers.

**D3 — The class pattern is compiled before it is adopted.**
Strict-mode Luau metatable inheritance does not always resolve the way it
reads. The first unit builds a throwaway inheritance prototype and runs
`luau-lsp analyze` over it; whichever variant typechecks with zero `:: any`
becomes `Class.luau` and the house pattern.

**D4 — Content is config; behaviour is an optional override.**
A tower definition carries id, category, targets, footprint and a `levels`
array. `BaseTower` implements acquire → cooldown → fire → apply. A subclass
module exists only when a tower does something the base cannot express.

**D5 — Instance-resident state replicates via Attributes; everything else via
Zap.** Tower level, targeting mode, owner, enemy HP → Attributes: free, and
read-only to clients. Match state, cash and all client intent → Zap.
Hand-written remotes remain banned. Zap proves shape; ownership,
affordability, tower caps and placement legality are ours to prove.

**D6 — Kill bounty splits proportionally by damage contribution.** Each enemy
tracks `damageByPlayer`. Last-hit bounty punishes the wrong player in co-op.

**D7 — Maps are Luau config modules,** built at runtime by `MapBuilder` from
`{ waypoints, buildableSurfaces, spawns, basePosition, decor }`. A binary
`.rbxmx` is neither diffable nor agent-editable.

**D8 — `distanceToBase = pathLength - progress` is the universal ordering
key.** Maps declare N independent paths; each enemy is assigned one at spawn.
Ordering by remaining distance makes First/Last correct across paths of
differing length with no special casing.

---

## Layout

```
src/shared/          ReplicatedStorage.Shared   — pure functions and data only
  Types  DataSchema  Class  Path  Targeting  Scaling  Footprint  WaveGenerator
  Config/  Towers Enemies StatusEffects Waves Difficulty Economy Sounds
           Places DevMatch  Maps/{Crossroads,Switchback,Fork}

src/match/server/    ServerScriptService.Server (match place)
  Match/       MatchController  MapBuilder  ArrivalGate
  Simulation/  EnemySimulation  EnemyView  PartPool
  Entities/    BaseEnemy  Enemies/*   BaseTower  Towers/*
  Systems/     TowerSystem  PlacementValidator  StatusEffectSystem
               DamageBus  EconomyService  WaveDirector  BaseHealth  RewardService
  Net/Handlers

src/match/client/    StarterPlayerScripts.Client (match place)
  State/atoms  Placement/PlacementController  Effects/*  Audio/*  UI/*

src/lobby/{server,client}   the lobby place
tests/                      one spec per pure module
```

The split rule: **`src/shared/` holds pure functions and data; anything that
touches an Instance or a Player lives under `src/match/`.** That boundary is
what makes the test suite possible.

---

## Content

**Towers** — six, three categories, ≥3 levels each:

| Tower | Category | Targets | Levels | Note |
|---|---|---|---|---|
| Rifleman | Ground | Ground | 5 | cheap single-target |
| Mortar | Ground | Ground | 3 | splash, slow |
| Marksman | Hillside | Air + Ground | 4 | long range, high single-target |
| Flak | Hillside | Air + Ground | 3 | air-focused splash |
| Ranger | Hybrid | Air + Ground | 4 | balanced |
| Lacerator | Hybrid | Air + Ground | 4 | **applies Bleed** |

**Status effects** — generic, four kinds: `DamageOverTime`, `SpeedMultiplier`,
`DamageTakenMultiplier`, `Stun`. Bleed ships; poison, burn and slow are then
one config entry each. Per-effect stacking policy (`Refresh` / `Stack` /
`Independent`), per-enemy `resistances` and `immunities`. Speed resolves as the
product of active multipliers so slows compose.

**Enemies** — Zombie, Tank, Runner, Titan (boss, milestone waves), plus one air
variant in Phase 3: the Hillside category is meaningless without something the
Ground towers cannot hit.

**Scaling**, tuned for a 30–50 wave run and unit-tested for monotonicity:
`hp(w) = base × 1.11^(w−1) × difficultyMult` (~63× by wave 40), a boss
multiplier on milestone waves, count on a separate gentler curve, and bounty on
a **sub-linear** curve so late waves do not print money. Waves 1–40 authored
with per-wave overrides; beyond 40 `WaveGenerator` goes procedural from the
unlocked pool. Enemy definitions carry `introducesAtWave`.

---

## Network schema

**C→S** `RequestPlaceTower` `RequestUpgradeTower` `RequestSellTower`
`RequestSetTargeting` `RequestEarlyStart` `RequestLeaveMatch` · lobby:
`CastMapVote` `SetReady`

**S→C** `MatchStateChanged` `CashChanged` `BaseHealthChanged`
`PlacementRejected` `MatchEnded` · unreliable: `TowerFired` `PlaySound` ·
lobby: `LobbyStateChanged` `VoteTallyChanged` `MatchmakingFailed`

**funct** `GetMatchSnapshot` — full state for join-in-progress

Note the absences: no enemy position stream, no HP stream, no damage-number
event. D2 and D5 removed the need for all three.

---

## Data schema

`CURRENT_VERSION = 1`, template replaced. All DataStore-safe primitives:

```
Version, Coins, XP, Level,
UnlockedTowers: {string},
Stats: { MatchesPlayed, MatchesWon, HighestWave, EnemiesKilled },
Settings: { MusicEnabled, SfxEnabled }
```

Match cash is **not** persisted — per-match, server-side only.

---

## Phases

Each ends with `/verify` green, a commit, both places building, and a written
Studio checklist for anything static analysis cannot prove.

| Phase | Delivers | Playable at the end |
|---|---|---|
| 1 Foundation | Class pattern, Types, DataSchema, net schema, Config skeleton, `Path`, one map + MapBuilder, MatchController, EnemySimulation + EnemyView, BaseHealth | enemies spawn, walk, leak, base HP drops, match ends |
| 2 Towers | BaseTower + 6 towers, targeting, PlacementValidator, placement client, upgrade/sell, EconomyService, StatusEffectSystem + Bleed | you can defend |
| 3 Enemies & waves | 4 enemy classes + air variant, WaveGenerator, scaling, boss waves, endless, difficulty presets, early-start bonus | a full 40-wave run |
| 4 Lobby & maps | lobby place, voting, party, ready-up, TeleportGate + Studio fallback, 3 maps, return-to-lobby, reward persistence | lobby → match → lobby |
| 5 Polish | damage numbers, health bars, sound hooks, results screen, UI pass, tower caps, join-in-progress, test suite | shippable + asset manifest |

**Test suite** (Studio-only): `Path`, `Scaling`, `Targeting`, `Footprint`,
`WaveGenerator`, `StatusEffects`, `Economy`, `DataSchema`. That list is exactly
the pure surface, which is the argument for D2.

---

## Risks the gate cannot catch

1. **The teleport call.** Unverifiable until both places are published and
   real IDs are set in `Config/Places.luau`. Manual procedure in Phase 4.
2. **Balance.** The curves will typecheck and be monotonic; whether wave 37 is
   fun needs play. Every constant lives in config for this reason.
3. **Replication cost at scale.** 200 hitbox parts is a real load and cannot
   be measured outside a live server. `BulkMoveTo` and the part pool are the
   mitigations; the escape hatch is dropping to numeric replication, and D2's
   projection boundary is what keeps that contained rather than a rewrite.
4. **`TeleportData` trust.** Neutralised by allowlist validation.

# Plan: from framework to full game

Written 2026-08-26 night; **executed 2026-08-26**. Kept as the record of
what was planned against what shipped - every numbered section below is
DONE and annotated with how it landed and where its tests live.

**FRAMING, from Alexei: this is a PORTFOLIO PIECE, not a live game.** That
recolours the priorities: demonstrable systems and clean inspectable code
over retention tuning; visible variety over meta balance; the rarity ladder
and gacha exist to SHOW the craft (data-driven content, server authority,
tested economy) rather than to monetise.

## 0. BUG: zombies sunk in the ground - FIXED

`Pads.WALKWAY_TOP` is the single shared constant; MapBuilder's walkway
draws at it and `Rigs.attachMoving` plants feet on it. Visual-only - the
hitbox stays on the path plane, one comment in Rigs explains why. Verified
live: feet at 1.15-1.4 on the walkway.

## 1. Lobby v2 - SHIPPED, then REDESIGNED same-day per Alexei's sketch

First build: one walk-in vote zone per map. Alexei's correction: the
lobby is a HUB - spawn in the centre, NO countdown ever, and nothing
launches until you walk into the GAME area, where a chooser GUI opens
(map + difficulty buttons with live tallies) and a START button - the
only launch path in the game - teleports everyone standing in the area.
GACHA and REROLL are walk-in areas on the other sides, each with a
store-model prop (quarantine pipeline, scripts stripped) and a UI
reveal animation over the server's already-decided result. A lobby HUD
shows level/coins/tokens, player count, and the LOADOUT button.
Occupancy still scanned server-side from positions the server owns.
Tests: LobbyZones.spec (areas, resolver, spawn clearance).

Loadouts joined the same rework: own the roster, BRING six. Pure rules
in Loadouts.luau (1..6, owned, real, no dupes, replace-whole), schema
v4 deals a first deck, the match shop renders ONLY the deck, placement
refuses NotInLoadout, and the lobby edits it through a draft panel.
Tests: Loadouts.spec, DataSchema.spec v3->v4, Placement.spec.

## 2. Persistence + economy for rolls - SHIPPED

- DataSchema v3: `Traits: { [towerId]: { traitId } }` + `RerollTokens`.
  Coins ARE the gacha currency (the recommended answer, taken).
- `Config/Rarity.luau`: 7 tiers (Common -> Mythic + **Secret**), weights
  summing to exactly 100; colour read by shop, gacha UI and reroll grid.
- `Config/Traits.luau`: 12 traits across all tiers, multiplier bundles;
  every trait an overall buff (spec-enforced). `TraitEffects` folds them;
  BaseTower applies at stat READ time (range/beginReload/dealDamage),
  snapshotted at placement. Tests: Traits.spec, TraitEffects.spec.
- `Gacha` (pure tier-first roller, falls down the ladder, walks up only
  when nothing below) + `GachaFlow` (check-then-charge-then-roll, dupes
  refund half, reroll REPLACES - SLOTS=1 enforced at the write). Rolled
  server-side only, server-owned RNG. Wire: RollTower / RerollTrait /
  GetLobbyProfile functs. Tests: Gacha.spec (20k-roll distribution),
  GachaFlow.spec (ledger conservation over 1500 rolls).
- RerollTokens earned at match end (1 per payout, +1 win, difficulty-
  blind), shown on the results screen. The lobby holds real ProfileStore
  sessions now - the session lock makes the two-place handoff safe, and
  the lobby entry documents why the old "never load data here" rule fell.

## 3. 20 new troops - SHIPPED (roster 6 -> 26)

All pure config through a `makeLevel` constructor; splash DERIVES from
`splashRadius > 0` (no behaviour registry line to forget), status effects
from `applies`. Three new effects, one config entry each: Burn (stacking
DoT), Sunder (+20% damage taken), Concuss (short stun, uptime capped by
design ~60%). Pyramid distribution: 7/5/5/4/3/1/1 across the ladder.
Rigs reuse the nine templates already in the place. Tests:
TowerBalance.spec (structure, monotonic upgrades, effect references,
typo band on pure single-target openers).

## 4. Maps - SHIPPED (3 -> 5)

Config-authored (the MapExtract Studio loop remains available for later
maps): **Gauntlet** - one 320-stud lane, the shortest walk in the game,
flanking plateaus, pressure is money; **Bastion** - centre base, two
pincer lanes from opposite edges, 350 vs 415 studs (D8). Tests:
MapIntegrity.spec, registry-wide - axis-aligned segments, waypoints on
the slab, lanes end at the base, both surface types, unequal lanes.

## 5. Publish flow reminder - STILL OPEN

Place publishing is still File->Publish x2 in each window (no Open Cloud
key). The current cloud places predate this whole run - **both need a
republish before any of this is live**.

## Standing debts (unchanged)

- Rig templates -> committed assets/ (blocks: fresh clones get boxes,
  noobsv8-as-Titan in the original place)
- MAX_RIGGED=64 profiling, now that 26 tower types can crowd the field
- LobbyController itself has no spec (its pure pieces - Poll, LobbyZones,
  GachaFlow - do)

## What a next session could add

1. Trait display in the match TowerInspector (the part already carries a
   Traits attribute; the UI just doesn't read it yet).
2. Air enemies beyond the current roster - Flaresman is priced as an air
   specialist and earns its band only when air actually shows up.
3. A pity counter on the Secret tier, if the gacha should read kinder.
4. Screenshots + README pass - the portfolio deliverable proper.

# Plan: from framework to full game

Written 2026-08-26 night, for the next session. Ordered by dependency, not
ambition - the bug first, then the systems the content hangs off, then the
content, because 20 troops rolled through a gacha need the gacha to exist.

**FRAMING, from Alexei: this is a PORTFOLIO PIECE, not a live game.** That
recolours the priorities: demonstrable systems and clean inspectable code
over retention tuning; visible variety over meta balance; the rarity ladder
and gacha exist to SHOW the craft (data-driven content, server authority,
tested economy) rather than to monetise. Concretely - the paid-odds
compliance note in section 2 becomes moot, screenshots and a strong README
become deliverables, and "does this read impressively in 10 minutes of
play" beats "is wave 60 balanced".

## 0. BUG: zombies sunk in the ground (diagnosed, not yet fixed)

From the published-game screenshot: rigs buried to the waist in the walkway.

DIAGNOSIS: enemy feet align to the HOST hitbox bottom, which sits on the
path plane at y = 0 - but the walkway SURFACE was raised to y = 1.15 when
the buried-walkway bug was fixed (PATH_TOP_Y = Pads.GROUND_TOP + 0.15). A
full-size 4-stud box hid the 1.15-stud sink; a half-scale 2-stud rig is
buried past the knees. The boxes were always sunk too - it just read less.

FIX: enemies must stand on the WALKWAY surface, not the path plane.
Cleanest: hoist the visual in Rigs.attachMoving's bottom-align by the
walkway surface height, taken from a new shared constant that MapBuilder's
PATH_TOP_Y also derives from (single source, or the two drift). Decide
whether the HITBOX should also lift (gameplay: splash origin, tower range) -
default no, visual-only, one comment explaining. Verify with the live drift
probe plus a screenshot at ground level.

## 1. Lobby v2: zones instead of menus

Today: spawn + vote plinths + UI buttons. Wanted: a real lobby you RUN
around - distinct zones you walk into (TDS-style):

- **Map zones**: one walk-in pad per map (3 now, more later); standing in
  one = your map vote. Zone occupancy IS the vote - kills the vote UI.
- **Difficulty zones** the same way, or difficulty pads inside each map
  zone (decide: fewer zones reads better; recommend map zone x difficulty
  pad inside).
- **Reroll zone** and **Gacha zone**: walk up, UI prompt opens (section 2).
- Ready-up stays a button (walking away must un-ready you - zone exit).

BUILD: extend LobbyBuilder with zone geometry from a LOBBY CONFIG module
(zones as data, same philosophy as maps). Server: zone occupancy via
spatial check per heartbeat against zone bounds (NOT Touched events - flaky,
and the sim owns truth). Rewire LobbyController's vote intake from CastVote
messages to occupancy; KEEP the CastVote wire message for a while (mobile
fallback + the Poll spec covers the tally logic - reuse, do not rewrite).
TeleportGate untouched - it reads the winning tally exactly as now.

## 2. Persistence + economy for rolls (the foundation)

DataSchema v3 (one version bump, one migration - the ladder works, 196
tests green):

- `Traits: { [towerId]: { trait ids } }` - rolled traits per owned tower
- `RollCurrency` (rerolls) + `GachaCurrency` (character rolls) - decide
  names; Coins already exist and are currently a dead sink, so RECOMMEND:
  Coins ARE the gacha currency, add only `RerollTokens`
- Trait definitions in Config/Traits.luau: id, displayName, rarity, effect
  hooks (damage mult, range mult, fireRate mult, splash bonus, bounty
  mult). Effects apply in BaseTower stat reads - ONE place, like status
  multipliers on enemies.
- **Rarity ladder** (per Alexei): Common, Uncommon, Rare, Epic, Legendary,
  Mythic, plus one chase tier above - recommend **Secret** (genre-native
  for Roblox TD; alternatives: Exotic, Celestial). Defined once in
  Config/Rarity.luau: id, order, display name, colour, gacha weight. The
  colour becomes a Theme-adjacent token the shop, gacha UI and inspector
  all read, so a rarity is one config row and every surface follows -
  which is exactly the data-driven story the portfolio wants to tell.
- Gacha pool config: weight = the tower's rarity's weight. Server-rolled
  ONLY (server authority, D-rules), results through a new zap message pair.
- Rates/pity: pick sane defaults (advertise odds - Roblox requires
  disclosed paid-random odds if Robux ever touches it; free-currency-only
  for now keeps that moot, note it).

## 3. 20 new troops

Config-first: each = Config/Towers.luau entry (levels, damage curves) +
rig assignment + store-rig audit through the established pipeline (insert,
strip scripts, arm, muzzle tag). Balance: extend Scaling.spec-style
assertions - every tower's DPS-per-cost inside a band, so 26 towers stay
comparable by test rather than by feel. Realistic sequencing: 5 archetypes
x variants (sniper/splash/DoT/support/economy), not 20 bespoke mechanics -
behaviour modules only where config cannot express (D4). Distribute the 26
across the rarity ladder pyramid-style (many commons, one or two Secrets);
a variant's tier tracks its power so rarity reads as meaningful. Rigs: batch-audit
20 store rigs in one quarantine pass; expect ~1/3 rejects.

## 4. Maps x2-3

Author in Studio via the build->drag->extract loop (MapExtract is tested,
lossless, and reports authoring mistakes). One map with a genuinely
different shape: dual-lane merge, or a spiral with interior plateaus.

## 5. Publish flow reminder

Place publishing is still File->Publish x2 (StudioPublishService is not
reachable from MCP; no Open Cloud key exists). If iteration pace hurts,
create the Open Cloud API key (universe-places:write) and publishing goes
CLI - see docs/session-notes.

## Standing debts that block pieces of the above

- Rig templates -> committed assets/ (blocks: new places get boxes,
  noobsv8-as-Titan, fresh clones)
- MAX_RIGGED profiling before 20 troops multiply rigged towers on field
- The suite has no LobbyController/zone coverage - write specs with the
  Poll tally reuse

## Open decisions parked for Alexei

1. Coins as gacha currency (recommended) or a separate currency?
2. Traits reroll per-tower-per-match, or persistent per-owned-character?
   (Recommended: persistent - it is what makes collection feel like a game.)
3. Difficulty selection: pads inside map zones, or its own zone row?

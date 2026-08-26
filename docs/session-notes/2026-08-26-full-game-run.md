# 2026-08-26 - the full-game run

One autonomous session, PLAN-full-game.md sections 0-4 all shipped. The
plan doc itself now carries the what-landed annotations; this note keeps
only what a future session needs operationally.

## Suite

21 suites, 255 tests, 0 failures - run in the LOBBY Studio window, which
permanently serves `test.project.json` on port 34872 (Alexei: "its a
lobby upgrade"). The match window stays on `default.project.json` /
34873. Production safety for that superset came first: `shouldBoot`
gates by PLACE ID outside Studio, so publishing either window's tree
anywhere is harmless.

## Live verification done this session

- Lobby playtest (STUDIO_ROLE flipped to Lobby, reverted after): five
  zone boards up, floor auto-widened to 196 studs, both stations built;
  walking onto the Gacha pad opened the panel with the odds line;
  RollTower round-tripped CannotAfford at 270 coins without charging;
  Reroll panel showed all six owned towers coloured by rarity.
  Screenshot: reroll-station-panel.
- A successful roll/reroll was NOT seen live (fresh profile: 0 tokens,
  270 < 400 coins). The transaction rules are spec-covered
  (GachaFlow.spec); the first real verification will be in the published
  game after a match pays out.

## MCP operational notes (hard-won this session)

- `execute_luau` datamodel_type during a playtest: `Server` / `Client`
  (not Play/PlayServer). `start_stop_play` takes `is_start: bool`;
  `screen_capture` needs a `capture_id` string.
- `character_navigation` (datamodel_type Client) returned Success but
  never moved the character; `character:PivotTo` from a Server context is
  the reliable way to steer a playtest character.

## Traps re-confirmed

- Edit-tool string matching fights this repo's CRLF files - python with
  `newline=''` and explicit `\r\n` anchors remains the way to edit
  existing files; files (re)written whole via the Write tool are LF and
  then pass `stylua --check` individually.
- A fixed-seed distribution test still needs enough draws: 200 rolls
  miss the 0.7% Secret tier a quarter of the time. Seeds make it
  deterministic; the draw count must be one where that seed completes.

## Before anything is "live"

1. Republish BOTH places (File -> Publish in each window) - the cloud
   places predate the whole run: no place-id boot gates, no traits, no
   gacha, 6 towers, 3 maps, zombies waist-deep.
2. After publish, earn coins/tokens in a real match, then roll and
   reroll at the stations - the two paths a Studio fresh profile could
   not exercise.

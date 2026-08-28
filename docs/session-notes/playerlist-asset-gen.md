# Custom player list - asset generation notes

Feature: replace the default Roblox player list with a custom panel in
both places. Art generated through the Codex CLI relay (gpt-image-2 on
the ChatGPT subscription), uploaded into Roblox via the Studio MCP's
upload_image, ids recorded in `Config/RosterArt.luau`.

## The asset set

| Asset | Use | Size on screen |
|---|---|---|
| emblem | toggle button icon, panel corner mark | ~36px |
| header | wide banner behind the panel title | ~300x60 |
| badge_bronze | level 1-4 rank badge | ~24px |
| badge_silver | level 5-9 | ~24px |
| badge_gold | level 10-19 | ~24px |
| badge_diamond | level 20+ | ~24px |

## Style clause (written once, reused verbatim - only the subject varies)

> polished dark-fantasy game UI icon, brushed gunmetal and steel with a
> soft cyan rim light, subtle emboss, centered composition, flat frontal
> view, solid deep charcoal background colour #121418, no text, no
> numerals, no branding, no logos, no watermarks, no checkerboard, no
> transparency grid, no vignette, no drop shadow

Named solid background rather than transparency, deliberately: the
transparent flag has a documented failure mode of PAINTING a literal
checkerboard. The charcoal matches Theme.PANEL (18,20,24) and gets
verified by corner-pixel sampling, then the panel renders the art on a
matching ground so no repaint is needed.

## Run log

(appended as generations happen)

### Run 1 (7 assets, 1 retry)

- emblem: PERFECT first try. Style validated on one image before batching.
- badges bronze/silver/diamond/header/row/frame: first try. badge_gold
  failed SILENTLY (4/5 outputs, exit 0) - retry succeeded. Lesson: count
  the output files, never trust the exit code of a parallel batch.
- Requested #121418 backgrounds came back ~#0F1115 - close enough for the
  flood knockout, and why the knockout exists at all.
- size=auto returned 1254x1254 and 1402x1122. Advisory, as documented.

### Post-processing

- knockout.py: corner-seeded flood fill -> alpha, trim, downscale. Cleared
  55-84% of pixels per icon; enclosed dark interiors survived (the trap a
  global colour-distance knockout falls into).
- frame kept its centre (it IS the panel), downscaled to 1024x819.
- 16 MB of generations became ~1.1 MB of shipped assets.

### Upload

- Studio MCP upload_image takes URLs only - served the folder on
  localhost:8093 for a minute and passed http URLs. Seven ids minted, in
  Config/RosterArt.luau.

### Verdict

Probe-rendered in a playtest: slices clean at 260px panel and 44px rows,
badges legible at 26px, no checkerboards, no visible squares. Looks good
- shipping without another iteration round.

## Run 2 - the HUD material system (6 assets, 0 retries)

Same style clause, six more generations: a compact steel plate and five
stat icons (coin, token crystal, armored heart, zombie skull, star
medal). All six landed first try - counted files before trusting.
Knockout cleared 29-91%; icons shipped at 96px, plate at 1024x613.

Applied as ONE material system through shared UiArt components:
  FRAME (the roster's frame, reused) skins every big panel underlay;
  PLATE skins every HUD chip; BUTTON (the row plate, reused) is the CTA
  surface awaiting adoption; ICONS sit beside the numbers they name.
SliceScale 0.18 after the first look - 0.25 borders ate small panels.

Verified in playtests of BOTH places: lobby chips + gacha panel on
steel with icons; match BASE/WAVE/CASH chips with heart/skull/coin.
Deliberate taste call: the CTA buttons KEEP their flat accent colours -
against steel everywhere, colour is what says "press me".

## Run 3 - trait icons and interior textures (15 assets, 1 retry)

Twelve trait emblems (one per Config/Traits entry, same icon clause) and
three near-uniform interior weaves (brushed / carbon fiber / hex mesh,
their own texture clause: "extremely low contrast, near-uniform deep
charcoal #14161a, flat edge to edge"). All fifteen landed on the first
pass - but the upload map exposed that trait_elite and trait_ascendant
were BYTE-IDENTICAL files: six concurrent relay runs raced in the
staging directory and one copied the other's output. The asset server's
content-hash dedupe is what surfaced it (same rbxassetid for two
"different" uploads). Regenerated elite solo. New rule: after a
concurrent batch, md5 the outputs against each other, not just count.

Textures ship opaque at 512 (no knockout - they ARE the background),
applied as inset Crop ImageLabels. Icons knocked out and shipped at 128
for the reroll reel.

## The layout rule this session kept paying for

A scale-sized image must never share a UIListLayout with the content it
backs, and must never be a DIRECT child of an AutomaticSize element -
it inflates the auto-size into a screen-height void. Hit three times
(shop bar, roster, tower inspector). For auto-sized panels the fix is
UiArt.Frame: the sliced image IS the host, so it tracks the resolved
height and needs no scale child at all.

## Run 4 - the textures, regenerated (3 assets, 0 retries)

The first texture set was prompted for "extremely low contrast,
near-uniform" and delivered precisely that. Measured standard deviation
on the brushed tile: 1.7. That is a flat colour with a rumour of a
pattern, and no transparency setting can rescue it - at 0.45 it was
invisible and at 0.18 it was still invisible, because there was nothing
there to see.

Reprompted for a pattern that is VISIBLE while staying dark - "defined
highlights and shadow in the grooves, medium contrast" - and measured
the result rather than judging it: stddev 20.0 / 27.2 / 22.0, between
five and twelve times the old set, at a mean luminance of 40-48 so white
text still sits on it comfortably.

LESSON: "subtle" is a rendering decision, not a generation one. Generate
the pattern with real contrast and dial it back with ImageTransparency,
because you can always hide a texture you have and never reveal one you
do not. Measure stddev before and after; the eye cannot judge a 1.7
against a 20 in a thumbnail.

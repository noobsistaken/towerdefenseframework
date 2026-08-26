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

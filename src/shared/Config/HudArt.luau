--!strict
--[[
	The HUD's generated material system. Three surfaces and an icon set,
	shared by every panel and button in both places:

	  * FRAME - the big riveted panel (borrowed from RosterArt; one
	    material system, not one per feature).
	  * PLATE - the compact chip behind small HUD panels.
	  * BUTTON - the steel bar behind every CTA, tinted per state
	    through ImageColor3 rather than regenerated per colour.
	  * ICONS - small transparent stat icons drawn beside numbers.

	All generated through the Codex relay pipeline documented in
	docs/session-notes/playerlist-asset-gen.md, and all OPTIONAL: an empty
	id falls back to the flat themed surface, so the game survives a place
	where the art never loads - and the code could ship before the ids did.
]]

local RosterArt = require(script.Parent.RosterArt)

local HudArt = {}

--- The big panel frame. One material system: the roster's frame IS the
--- game's frame.
HudArt.FRAME = RosterArt.FRAME
HudArt.FRAME_SLICE = RosterArt.FRAME_SLICE

--- The compact chip behind small HUD panels (health, wave, cash, wallet).
---
--- DELIBERATELY EMPTY. The generated plate is a 1024x613 bar whose 9-slice
--- borders are 280px on each side - more than twice the width of the 220px
--- chip they had to fit. Roblox crushes them to fit, and what survives is
--- a thick grey bevel wrapped around a sliver of the actual steel: at chip
--- size the art read as a grey band rather than a plate, which is what
--- Alexei kept pointing at. The empty id takes the tolerance path every
--- art slot in this file already has, so the chips render as the flat
--- themed panel instead - the ornate frame stays where it has room to be
--- ornate, on the big panels.
HudArt.PLATE = ""
HudArt.PLATE_SLICE = Rect.new(280, 240, 744, 400)

--- The CTA bar. The roster's row plate again - a button and a roster row
--- are the same steel.
HudArt.BUTTON = RosterArt.ROW
HudArt.BUTTON_SLICE = RosterArt.ROW_SLICE

--- Stat icons, transparent. Keys are stable; consumers ask by name.
HudArt.ICONS = {
	Coin = "rbxassetid://130392582967996",
	Token = "rbxassetid://77923096751950",
	Heart = "rbxassetid://92767544274015",
	Skull = "rbxassetid://79141414071944",
	Star = "rbxassetid://126670432225589",
} :: { [string]: string }

function HudArt.icon(name: string): string
	return HudArt.ICONS[name] or ""
end

--- Near-uniform dark textures for the flat interiors of panels, applied
--- as inset Crop ImageLabels so no surface reads as an empty black void.
--- Different rooms wear different weaves; all read as one material family.
--- Regenerated once, because the first set was prompted for "extremely low
--- contrast, near-uniform" and delivered exactly that: measured standard
--- deviation of 1.7 on the brushed tile, which is a flat colour with a
--- rumour of a pattern. It read as nothing on screen at any transparency
--- worth using. This set asks for a pattern that is VISIBLE while staying
--- dark, and measures 20.0 / 27.2 / 22.0 - between five and twelve times
--- the contrast - at a mean luminance of 40-48, still dark enough for white
--- text to sit on.
HudArt.TEXTURES = {
	Brushed = "rbxassetid://132122291275194",
	Carbon = "rbxassetid://121799022617636",
	Hexmesh = "rbxassetid://90274878629327",
} :: { [string]: string }

function HudArt.texture(name: string): string
	return HudArt.TEXTURES[name] or ""
end

return HudArt

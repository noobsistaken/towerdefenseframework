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
HudArt.PLATE = "rbxassetid://136830143652126"
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

return HudArt

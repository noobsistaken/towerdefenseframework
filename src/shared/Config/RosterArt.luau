--!strict
--[[
	Art for the custom player list - AI-generated through the Codex relay
	(gpt-image-2 on the ChatGPT subscription), post-processed with a
	corner-seeded flood knockout for transparency, and uploaded through the
	Studio MCP. Prompts, retries and the pipeline live in
	docs/session-notes/playerlist-asset-gen.md.

	Every id is optional by design: an empty string renders the text
	fallback, so the panel survives a place where the assets fail to load.
]]

local RosterArt = {}

--- The shield-and-tower emblem on the toggle button. Transparent.
RosterArt.EMBLEM = "rbxassetid://80162264811731"

--- Optional banner art behind the header text. Deliberately empty: the
--- sliced frame already carries the look, and a second full-bleed image
--- inside it read as two competing surfaces.
RosterArt.HEADER = ""

--- The riveted steel panel frame with a flat charcoal centre. Drawn as a
--- 9-sliced ImageLabel so it stretches to any panel height; the slice
--- rectangle sits well inside the cyan trim, in the flat region.
RosterArt.FRAME = "rbxassetid://134320085958945"
RosterArt.FRAME_SLICE = Rect.new(300, 260, 720, 560)

--- One row's plate: a brushed steel bar with a cyan underglow, transparent
--- outside the bar. Sliced horizontally so it stretches to row width
--- without distorting the rounded caps.
RosterArt.ROW = "rbxassetid://70816033070793"
RosterArt.ROW_SLICE = Rect.new(200, 70, 824, 90)

export type Badge = {
	--- Minimum account level for this badge.
	minLevel: number,
	assetId: string,
	--- The tier's name colour, and the fallback tint when the asset is
	--- missing.
	color: Color3,
}

--- Highest tier first; badgeFor returns the first match.
RosterArt.BADGES = {
	{ minLevel = 20, assetId = "rbxassetid://101074916527117", color = Color3.fromRGB(150, 220, 255) },
	{ minLevel = 10, assetId = "rbxassetid://86102785512273", color = Color3.fromRGB(240, 196, 84) },
	{ minLevel = 5, assetId = "rbxassetid://102674239252571", color = Color3.fromRGB(196, 200, 210) },
	{ minLevel = 0, assetId = "rbxassetid://70641345075217", color = Color3.fromRGB(196, 132, 84) },
} :: { Badge }

function RosterArt.badgeFor(level: number): Badge
	for _, badge in RosterArt.BADGES do
		if level >= badge.minLevel then
			return badge
		end
	end

	return RosterArt.BADGES[#RosterArt.BADGES]
end

return RosterArt

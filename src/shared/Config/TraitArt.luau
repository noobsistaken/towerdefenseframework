--!strict
--[[
	Generated icons for the trait roster - one steel emblem per trait, all
	from the shared style clause (see docs/session-notes/playerlist-asset-gen.md
	for the pipeline). The reroll spinner reels through these.

	Optional like every other art table: a missing id renders the text
	fallback, never a broken image.
]]

local TraitArt = {}

TraitArt.ICONS = {
	Sturdy = "rbxassetid://89389794777385",
	Keen = "rbxassetid://134368010109040",
	Nimble = "rbxassetid://98134614833513",
	Brutal = "rbxassetid://70581594948058",
	Farsighted = "rbxassetid://96291600306765",
	Rapid = "rbxassetid://106027560433017",
	Veteran = "rbxassetid://106144110459640",
	Overclocked = "rbxassetid://104380351183371",
	Elite = "rbxassetid://108638193552010",
	Berserk = "rbxassetid://115028178751744",
	Ascendant = "rbxassetid://105598571374054",
	Godslayer = "rbxassetid://97389434194039",
} :: { [string]: string }

function TraitArt.icon(traitId: string): string
	return TraitArt.ICONS[traitId] or ""
end

return TraitArt

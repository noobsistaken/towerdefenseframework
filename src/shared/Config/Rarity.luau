--!strict
--[[
	The rarity ladder, defined exactly once.

	Everything that touches rarity - the gacha's weights, the shop's colours,
	the inspector's badge, trait tiers - reads THIS table, so adding a tier
	is one entry here and every surface follows. That single-row property is
	the point of the exercise: this project is a portfolio piece, and the
	story it tells is data-driven content.

	Weights are the gacha's per-tier chance and deliberately sum to 100, so
	the number shown to a player IS the number the roll uses - no conversion
	step to drift. Order is display and sort order, ascending.
]]

local Rarity = {}

export type Definition = {
	id: string,
	displayName: string,
	--- Ascending: higher is rarer.
	order: number,
	--- Every surface's colour for this tier.
	color: Color3,
	--- Per-tier gacha chance, in percent. The tier's towers share it evenly.
	gachaWeight: number,
}

local DEFINITIONS: { [string]: Definition } = {
	Common = {
		id = "Common",
		displayName = "Common",
		order = 1,
		color = Color3.fromRGB(158, 165, 174),
		gachaWeight = 40,
	},
	Uncommon = {
		id = "Uncommon",
		displayName = "Uncommon",
		order = 2,
		color = Color3.fromRGB(96, 190, 120),
		gachaWeight = 25,
	},
	Rare = {
		id = "Rare",
		displayName = "Rare",
		order = 3,
		color = Color3.fromRGB(86, 148, 245),
		gachaWeight = 16,
	},
	Epic = {
		id = "Epic",
		displayName = "Epic",
		order = 4,
		color = Color3.fromRGB(168, 96, 235),
		gachaWeight = 10,
	},
	Legendary = {
		id = "Legendary",
		displayName = "Legendary",
		order = 5,
		color = Color3.fromRGB(240, 176, 66),
		gachaWeight = 5.5,
	},
	Mythic = {
		id = "Mythic",
		displayName = "Mythic",
		order = 6,
		color = Color3.fromRGB(235, 78, 120),
		gachaWeight = 2.8,
	},
	--- The chase tier. Genre-native name for Roblox tower defense.
	Secret = {
		id = "Secret",
		displayName = "Secret",
		order = 7,
		color = Color3.fromRGB(30, 30, 34),
		gachaWeight = 0.7,
	},
}

Rarity.DEFINITIONS = DEFINITIONS

--- Ids in ascending rarity order, for UI rows and deterministic iteration.
local ids: { string } = {}

for id in DEFINITIONS do
	table.insert(ids, id)
end

table.sort(ids, function(a: string, b: string): boolean
	return DEFINITIONS[a].order < DEFINITIONS[b].order
end)

Rarity.IDS = table.freeze(ids)

--- Non-throwing lookup, for hot paths and render code.
function Rarity.find(id: string): Definition?
	return DEFINITIONS[id]
end

--- Throwing lookup, for config validation and tests.
function Rarity.get(id: string): Definition
	local definition = DEFINITIONS[id]

	if definition == nil then
		error(`Rarity.get: no tier with id "{id}"`)
	end

	return definition
end

return Rarity

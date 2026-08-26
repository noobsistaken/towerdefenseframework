--!strict
--[[
	Trait roster: the rollable modifiers a tower can carry.

	A trait is a named bundle of stat multipliers with a rarity tier, rolled
	through the same tier-first core the tower gacha uses - one rolling rule,
	two pools. Effects apply wherever the stat is READ (BaseTower), never by
	editing config values, so a trait can never corrupt the shared definition
	every other tower reads.

	Multipliers cover the three stats every tower has. A trait that needs a
	new hook (splash radius, bounty, status power) adds the field here AND its
	one read-site application - which is a deliberate speed bump, because a
	hook is a balance surface, not just a number.
]]

local Traits = {}

export type Definition = {
	id: string,
	displayName: string,
	--- Tier in Config/Rarity.luau. Drives roll odds and display colour.
	rarity: string,
	--- Multiplied into the stat at read time. 1 means untouched.
	damage: number,
	range: number,
	fireRate: number,
}

local function trait(
	id: string,
	displayName: string,
	rarity: string,
	damage: number,
	range: number,
	fireRate: number
): Definition
	return {
		id = id,
		displayName = displayName,
		rarity = rarity,
		damage = damage,
		range = range,
		fireRate = fireRate,
	}
end

local DEFINITIONS: { [string]: Definition } = {
	-- Commons: one small nudge each, the floor of the pool.
	Sturdy = trait("Sturdy", "Sturdy", "Common", 1.05, 1, 1),
	Keen = trait("Keen", "Keen", "Common", 1, 1.05, 1),
	Nimble = trait("Nimble", "Nimble", "Common", 1, 1, 1.05),

	-- Uncommons: a real nudge, still single-stat.
	Brutal = trait("Brutal", "Brutal", "Uncommon", 1.12, 1, 1),
	Farsighted = trait("Farsighted", "Farsighted", "Uncommon", 1, 1.12, 1),
	Rapid = trait("Rapid", "Rapid", "Uncommon", 1, 1, 1.12),

	-- Rares: two stats, with a haircut on one so the total stays honest.
	Veteran = trait("Veteran", "Veteran", "Rare", 1.1, 1.08, 1),
	Overclocked = trait("Overclocked", "Overclocked", "Rare", 1, 0.95, 1.25),

	-- Epic: the first strictly-better bundle.
	Elite = trait("Elite", "Elite", "Epic", 1.15, 1.1, 1.08),

	-- Legendary: a glass cannon with a visible cost.
	Berserk = trait("Berserk", "Berserk", "Legendary", 1.45, 0.85, 1.15),

	-- Mythic: strictly better and meant to feel it.
	Ascendant = trait("Ascendant", "Ascendant", "Mythic", 1.3, 1.2, 1.2),

	-- Secret: the chase roll.
	Godslayer = trait("Godslayer", "Godslayer", "Secret", 1.6, 1.25, 1.3),
}

Traits.DEFINITIONS = DEFINITIONS

--- Ids sorted for deterministic pools and UI.
local ids: { string } = {}

for id in DEFINITIONS do
	table.insert(ids, id)
end

table.sort(ids)
Traits.IDS = table.freeze(ids)

--- How many traits a tower carries at once. One, deliberately: a single
--- named trait reads at a glance in the inspector, where a stack of three
--- becomes a spreadsheet.
Traits.SLOTS = 1

function Traits.find(id: string): Definition?
	return DEFINITIONS[id]
end

function Traits.get(id: string): Definition
	local definition = DEFINITIONS[id]

	if definition == nil then
		error(`Traits.get: no trait with id "{id}"`)
	end

	return definition
end

return Traits

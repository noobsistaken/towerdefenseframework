--!strict
--[[
	The gacha's transaction rules: what a roll costs, what it may pay out,
	and what it writes into player data. Pure over (PlayerData, Random), like
	Placement is pure over its params - the lobby entry point owns the
	ProfileStore session and the real RNG, this owns every rule, and a spec
	drives the whole thing with a table and a seed.

	Money-handling invariants, stated because they are the bugs gachas have:

	  * Check, then charge, then roll - a refused roll must never take coins.
	  * The duplicate refund is credited in the SAME call that charged, so no
	    partial state exists for a crash to expose.
	  * A reroll REPLACES the trait list wholesale. Traits.SLOTS is 1; writing
	    a fresh list rather than appending is what enforces it here, whatever
	    the client believes.
]]

local Economy = require(script.Parent.Config.Economy)
local Gacha = require(script.Parent.Gacha)
local Towers = require(script.Parent.Config.Towers)
local Traits = require(script.Parent.Config.Traits)
local Types = require(script.Parent.Types)

local GachaFlow = {}

--- The tier the pity guarantee pays out in. Named once so the constant and
--- the rarity ladder cannot drift apart silently.
local SECRET_TIER = "Secret"

export type RollOutcome = "Rolled" | "Duplicate" | "CannotAfford"

export type RollResult = {
	outcome: RollOutcome,
	--- Empty strings when there was no roll (CannotAfford).
	towerId: string,
	rarityId: string,
	--- Coins handed back on a duplicate. 0 otherwise.
	refunded: number,
	--- True when the pity guarantee, not the dice, produced this Secret.
	pitied: boolean,
}

export type RerollOutcome = "Rolled" | "CannotAfford" | "UnknownTower"

export type RerollResult = {
	outcome: RerollOutcome,
	traitId: string,
	rarityId: string,
}

--- The tower pool: the WHOLE roster, owned or not. Rolling over everything
--- and refunding duplicates is what keeps the advertised tier odds true for
--- every player; a pool that shrank to "towers you lack" would make the last
--- Secret a guarantee instead of a chase.
function GachaFlow.towerPool(): { Gacha.PoolEntry }
	local pool: { Gacha.PoolEntry } = {}

	for _, id in Towers.IDS do
		table.insert(pool, { id = id, rarityId = Towers.get(id).rarity })
	end

	return pool
end

function GachaFlow.traitPool(): { Gacha.PoolEntry }
	local pool: { Gacha.PoolEntry } = {}

	for _, id in Traits.IDS do
		table.insert(pool, { id = id, rarityId = Traits.get(id).rarity })
	end

	return pool
end

--- One tower roll. Mutates `data` (coins, unlocks) and returns what the wire
--- reply needs. The caller passes a real Random in production and a seeded
--- one in tests; this module never constructs its own.
function GachaFlow.rollTower(data: Types.PlayerData, rng: Random): RollResult
	local cost = Economy.GACHA_ROLL_COST

	if data.Coins < cost then
		return { outcome = "CannotAfford", towerId = "", rarityId = "", refunded = 0, pitied = false }
	end

	-- The pity guarantee. Counted in ROLLS PAID FOR, so it advances on
	-- duplicates too: a player who rolled forty duplicates has still had
	-- forty rolls of bad luck, and telling them otherwise would be a lie
	-- the counter is supposed to prevent.
	local pitied = data.RollsSinceSecret >= Economy.GACHA_SECRET_PITY
	local result = if pitied
		then Gacha.rollWithinTier(rng, GachaFlow.towerPool(), SECRET_TIER)
		else Gacha.roll(rng, GachaFlow.towerPool())

	if result == nil then
		-- Impossible while the roster is non-empty; refusing without charging
		-- is the correct degradation if it ever is. Also covers an empty
		-- Secret tier, where the guarantee simply has nothing to hand over.
		result = Gacha.roll(rng, GachaFlow.towerPool())
		pitied = false
	end

	if result == nil then
		return { outcome = "CannotAfford", towerId = "", rarityId = "", refunded = 0, pitied = false }
	end

	data.Coins -= cost

	-- Charged, so the streak advances - then resets if this was the Secret.
	data.RollsSinceSecret += 1

	if result.rarityId == SECRET_TIER then
		data.RollsSinceSecret = 0
	end

	if table.find(data.UnlockedTowers, result.id) ~= nil then
		local refund = math.floor(cost * Economy.GACHA_DUPLICATE_REFUND_RATE)
		data.Coins += refund

		return {
			outcome = "Duplicate",
			towerId = result.id,
			rarityId = result.rarityId,
			refunded = refund,
			pitied = pitied,
		}
	end

	table.insert(data.UnlockedTowers, result.id)

	return { outcome = "Rolled", towerId = result.id, rarityId = result.rarityId, refunded = 0, pitied = pitied }
end

--- One trait reroll on an owned tower. Landing the same trait again is a
--- legal outcome, as in every gacha - guaranteeing "different" would make
--- the last reroll before a full set deterministic.
function GachaFlow.rerollTrait(data: Types.PlayerData, towerId: string, rng: Random): RerollResult
	if table.find(data.UnlockedTowers, towerId) == nil or Towers.find(towerId) == nil then
		return { outcome = "UnknownTower", traitId = "", rarityId = "" }
	end

	if data.RerollTokens < Economy.TRAIT_REROLL_TOKEN_COST then
		return { outcome = "CannotAfford", traitId = "", rarityId = "" }
	end

	local result = Gacha.roll(rng, GachaFlow.traitPool())

	if result == nil then
		return { outcome = "CannotAfford", traitId = "", rarityId = "" }
	end

	data.RerollTokens -= Economy.TRAIT_REROLL_TOKEN_COST

	-- A fresh one-element list, never an append: this line is where
	-- Traits.SLOTS = 1 is actually enforced.
	data.Traits[towerId] = { result.id }

	return { outcome = "Rolled", traitId = result.id, rarityId = result.rarityId }
end

return GachaFlow

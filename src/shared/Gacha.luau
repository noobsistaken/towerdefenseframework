--!strict
--[[
	The gacha's rolling core: pure, deterministic, and blind to everything
	except the pool it is handed.

	No Instances, no network, no player - a roll is a function of a pool and
	a Random object, so the spec can seed the Random and assert the exact
	sequence, and a thousand-roll distribution check is just a loop. The
	server wraps this with authority (who may roll, what it costs, what gets
	persisted); none of that lives here, which is what keeps this testable.

	TIER-FIRST ROLLING: first a rarity tier is drawn by the ladder's weights,
	then a tower is drawn uniformly from that tier's entries in the pool.
	Tier-first means the advertised per-tier odds hold no matter how many
	towers each tier holds - with per-tower weights, adding a fifth Common
	would silently dilute every other Common's chance while the ladder still
	claimed 40%.

	A drawn tier with NO towers in the pool falls through to the next lower
	tier, and so on to Common. Falling DOWN rather than rerolling keeps a
	sparse pool's expected value honest: an empty Secret tier becomes extra
	Mythic-and-below probability, never a silent retry loop.
]]

local Rarity = require(script.Parent.Config.Rarity)

local Gacha = {}

export type PoolEntry = {
	towerId: string,
	rarityId: string,
}

export type Result = {
	towerId: string,
	rarityId: string,
}

--- Draws a rarity tier by the ladder's weights, using `roll` in [0, total).
local function tierFor(roll: number): string
	local accumulated = 0

	for _, id in Rarity.IDS do
		accumulated += Rarity.get(id).gachaWeight

		if roll < accumulated then
			return id
		end
	end

	-- Float edge: a roll landing exactly on the total falls to the rarest.
	return Rarity.IDS[#Rarity.IDS]
end

--- Total gacha weight of the ladder. Exposed so UI can show odds as the
--- fraction they actually are.
function Gacha.totalWeight(): number
	local total = 0

	for _, id in Rarity.IDS do
		total += Rarity.get(id).gachaWeight
	end

	return total
end

--- Rolls once from `pool` using `rng`. Returns nil only for an empty pool.
---
--- `rng` is a Random object the CALLER owns. The server passes a real one;
--- a spec passes Random.new(seed) and gets the same sequence every run.
function Gacha.roll(rng: Random, pool: { PoolEntry }): Result?
	if #pool == 0 then
		return nil
	end

	-- Bucket the pool by tier once per roll. Pools are small (tens), and a
	-- fresh bucket per roll means a caller can mutate its pool between rolls
	-- without stale buckets lying to the next draw.
	local byTier: { [string]: { PoolEntry } } = {}

	for _, entry in pool do
		local bucket = byTier[entry.rarityId]

		if bucket == nil then
			bucket = {}
			byTier[entry.rarityId] = bucket
		end

		table.insert(bucket, entry)
	end

	local drawn = tierFor(rng:NextNumber(0, Gacha.totalWeight()))

	-- Fall DOWN the ladder from the drawn tier until a populated one.
	local startOrder = Rarity.get(drawn).order

	for order = startOrder, 1, -1 do
		for _, id in Rarity.IDS do
			if Rarity.get(id).order == order then
				local bucket = byTier[id]

				if bucket ~= nil and #bucket > 0 then
					local pick = bucket[rng:NextInteger(1, #bucket)]

					return { towerId = pick.towerId, rarityId = pick.rarityId }
				end
			end
		end
	end

	-- The drawn tier and everything below it were empty; the pool holds only
	-- HIGHER tiers. Walk up instead - the pool is non-empty by the guard.
	for order = startOrder + 1, #Rarity.IDS do
		for _, id in Rarity.IDS do
			if Rarity.get(id).order == order then
				local bucket = byTier[id]

				if bucket ~= nil and #bucket > 0 then
					local pick = bucket[rng:NextInteger(1, #bucket)]

					return { towerId = pick.towerId, rarityId = pick.rarityId }
				end
			end
		end
	end

	return nil
end

return Gacha

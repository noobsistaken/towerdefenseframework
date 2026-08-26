--!strict
--[[
	Economy constants and the pure arithmetic that uses them.

	Per-player cash, TDS style. Nothing here touches a Player or an Instance,
	so all of it is testable.
]]

local Types = require(script.Parent.Parent.Types)

local Economy = {}

--- Fraction of total investment returned on sell. Below 1 so that placing a
--- tower is a commitment; too far below and repositioning becomes a
--- punishment rather than a decision.
Economy.SELL_REFUND_RATE = 0.6

--- One gacha roll, paid in Coins - the meta-currency matches award.
--- Tuned against Rewards: a decent run pays 400-800, so a roll is
--- roughly one run, and a bad run is still most of the way there.
Economy.GACHA_ROLL_COST = 400

--- Fraction of the roll price returned when the roll lands a tower the
--- player already owns. Below 1 so a full collection still burns coins
--- slowly; above 0 so a duplicate stings rather than robs.
Economy.GACHA_DUPLICATE_REFUND_RATE = 0.5

--- One trait reroll, paid in RerollTokens (earned per match, not bought).
Economy.TRAIT_REROLL_TOKEN_COST = 1

--- Cash per second of build phase skipped, awarded to every player.
Economy.EARLY_START_PER_SECOND = 3

--- Flat bonus on top, so starting a wave early is worth doing even with only
--- a second or two left on the clock.
Economy.EARLY_START_FLAT = 25

--- Total cash actually paid to bring a tower to `level`, counting the
--- purchase and every upgrade. Costs are per-step, not cumulative, so this
--- has to sum them.
function Economy.totalInvested(definition: Types.TowerDefinition, level: number): number
	local total = 0

	for index = 1, math.min(level, #definition.levels) do
		total += definition.levels[index].cost
	end

	return total
end

--- What selling returns. Computed from real investment rather than base
--- price, so a fully upgraded tower is not refunded as if it were level 1.
function Economy.sellValue(definition: Types.TowerDefinition, level: number): number
	return math.floor(Economy.totalInvested(definition, level) * Economy.SELL_REFUND_RATE)
end

--- Cost to upgrade from `level` to `level + 1`, or nil at max level.
function Economy.upgradeCost(definition: Types.TowerDefinition, level: number): number?
	local next = definition.levels[level + 1]

	if next == nil then
		return nil
	end

	return next.cost
end

--- Bonus for starting a wave early. The server reads its own clock for
--- `secondsRemaining`; a client-supplied value would be free money.
function Economy.earlyStartBonus(secondsRemaining: number, rewardMultiplier: number): number
	local seconds = math.max(0, secondsRemaining)
	local raw = Economy.EARLY_START_FLAT + Economy.EARLY_START_PER_SECOND * seconds

	return math.max(0, math.floor(raw * rewardMultiplier + 0.5))
end

--- Splits `total` across contributors in proportion to their contribution
--- (ARCHITECTURE.md D6). Last-hit bounty punishes the wrong player in co-op:
--- the tower that did 95% of the work loses to whoever happened to land the
--- final tick.
---
--- Generic in the key so it can be tested without Player instances.
---
--- Conservation: shares are floored, then the shortfall - at most one coin
--- per contributor - is handed to the largest contributor, so the payout sums
--- to exactly `total` and the system can neither mint nor destroy cash. On an
--- exact tie for largest the winner depends on table iteration order; the
--- amount at stake is under one coin per player, so this is left unspecified
--- rather than paid for with a sort.
function Economy.splitByContribution<K>(contributions: { [K]: number }, total: number): { [K]: number }
	local shares: { [K]: number } = {}

	if total <= 0 then
		return shares
	end

	local sum = 0

	for _, amount in contributions do
		if amount > 0 then
			sum += amount
		end
	end

	if sum <= 0 then
		return shares
	end

	local distributed = 0
	local topKey: K? = nil
	local topAmount = 0

	for key, amount in contributions do
		if amount <= 0 then
			continue
		end

		local share = math.floor(total * (amount / sum))
		shares[key] = share
		distributed += share

		if amount > topAmount then
			topAmount = amount
			topKey = key
		end
	end

	local remainder = total - distributed

	if remainder > 0 and topKey ~= nil then
		local key: K = topKey
		shares[key] = (shares[key] or 0) + remainder
	end

	return shares
end

return Economy

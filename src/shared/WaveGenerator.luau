--!strict
--[[
	Turns a wave number into a time-ordered spawn plan.

	Pure: no Instances, no simulation, no services. It reads config and
	returns a list of records. That is what makes the entire difficulty ramp
	testable, and balance is one of the few things static analysis provably
	cannot check for us.

	WaveDirector consumes the plan and does the spawning. Keeping the two
	apart means "what should wave 37 contain" can be asserted without standing
	up a simulation.

	Composition comes from one of two sources:

	  1. Config/Waves.AUTHORED, if that wave has an entry. Counts are literal
	     and taken at face value - including bosses, because overriding the
	     author is what makes an override table useless.
	  2. Otherwise the rules: every type whose introducesAtWave has passed,
	     counted by Scaling.enemyCount, with bosses gated to boss waves.

	Determinism matters here and is deliberate in three places: iteration runs
	over Enemies.IDS (sorted, unlike a pairs() order), every plan entry carries
	an emission ordinal, and the final sort breaks ties on it. Without all
	three the same wave number could produce different sequences on two
	servers running the same build.
]]

local Enemies = require(script.Parent.Config.Enemies)
local Scaling = require(script.Parent.Scaling)
local Types = require(script.Parent.Types)
local WavesConfig = require(script.Parent.Config.Waves)

local WaveGenerator = {}

--- One scheduled spawn. Carries the enemy ID rather than the definition so
--- the plan stays plain data - easy to assert on, and free of any reference
--- into config that a test would have to construct.
export type PlanEntry = {
	enemyId: string,
	--- Seconds after the wave starts at which this enemy appears.
	at: number,
	pathIndex: Types.PathIndex,
	health: number,
	bounty: number,
	speed: number,
	--- Emission order, used only to break ties in the final sort so the plan
	--- is byte-identical across servers.
	ordinal: number,
}

type CompositionEntry = {
	id: string,
	count: number,
}

--- What this wave contains, before scheduling.
local function compositionFor(wave: number): { CompositionEntry }
	local authored = WavesConfig.AUTHORED[wave]

	if authored ~= nil then
		return authored
	end

	local list: { CompositionEntry } = {}
	local isBossWave = Scaling.isBossWave(wave)

	for _, id in Enemies.IDS do
		local baseCount = WavesConfig.BASE_COUNTS[id]

		if baseCount == nil then
			continue
		end

		local definition = Enemies.get(id)

		if wave < definition.introducesAtWave then
			continue
		end

		if definition.isBoss and WavesConfig.BOSS_ONLY_ON_BOSS_WAVES and not isBossWave then
			continue
		end

		-- Scale from the wave this type was INTRODUCED, not from wave 1, so a
		-- type arriving at wave 8 starts at its base count rather than at
		-- eight waves' worth of growth.
		local relativeWave = wave - definition.introducesAtWave + 1
		local count = Scaling.enemyCount(baseCount, relativeWave)

		-- Bosses get their own, much tighter ceiling. They share the same
		-- geometric count growth as everything else, and left uncapped a
		-- Titan count reaches the per-wave limit deep into endless mode -
		-- which would starve the regular budget to zero, since bosses are
		-- reserved out of it below.
		if definition.isBoss then
			count = math.min(count, Scaling.MAX_BOSSES_PER_WAVE)
		end

		table.insert(list, {
			id = id,
			count = count,
		})
	end

	return list
end

--- Builds the plan for `wave`.
--- Shares a capped wave budget across the regular types.
---
--- THE CEILING USED TO BE FIRST-COME. Every type emitted against one shared
--- counter in `Enemies.IDS` order - which is ALPHABETICAL - so whoever
--- sorted first spent the budget and whoever sorted last got whatever was
--- left, which past a certain wave is nothing. Measured on the real config
--- before this fix: wave 66 emitted zero Zombies, wave 80 zero Tanks, and
--- wave 100 was 214 Drifters and 6 Titans - 97% air, forever, because
--- "Drifter" happens to sort before "Zombie". Endless mode had quietly
--- become an all-air mode, and an enemy's NAME decided whether it existed.
---
--- Now every type keeps its share of the ceiling. Largest-remainder
--- rounding distributes the seats that division leaves over, so the total
--- is exact rather than approximately right, and one seat is reserved per
--- type first: a type that asked to appear at all appears, even when the
--- budget is tight.
local function allocateRegulars(regulars: { CompositionEntry }, budget: number): { number }
	local allocation: { number } = {}
	local requested = 0

	for index, entry in regulars do
		allocation[index] = entry.count
		requested += entry.count
	end

	-- The common case, including every authored wave: nothing is over the
	-- ceiling, so nothing is scaled.
	if requested <= budget or requested == 0 then
		return allocation
	end

	local count = #regulars
	local reserved = math.min(count, budget)

	for index = 1, count do
		allocation[index] = if index <= reserved then 1 else 0
	end

	local pool = budget - reserved

	if pool <= 0 then
		return allocation
	end

	type Remainder = { index: number, fraction: number }

	local remainders: { Remainder } = {}
	local handed = 0

	for index, entry in regulars do
		local exact = entry.count / requested * pool
		local whole = math.floor(exact)

		allocation[index] += whole
		handed += whole
		table.insert(remainders, { index = index, fraction = exact - whole })
	end

	table.sort(remainders, function(a: Remainder, b: Remainder): boolean
		if a.fraction ~= b.fraction then
			return a.fraction > b.fraction
		end

		return a.index < b.index
	end)

	for seat = 1, pool - handed do
		allocation[remainders[seat].index] += 1
	end

	-- Never hand a type more than it asked for; the ceiling is a cap, not a
	-- quota to fill.
	for index, entry in regulars do
		allocation[index] = math.min(allocation[index], entry.count)
	end

	return allocation
end

function WaveGenerator.generate(wave: number, difficulty: Types.DifficultyConfig, laneCount: number): { PlanEntry }
	if laneCount < 1 then
		error(`WaveGenerator.generate: laneCount must be at least 1, got {laneCount}`)
	end

	local composition = compositionFor(wave)

	-- Past the campaign's final wave, health compounds faster. Exactly 1 up
	-- to and including finalWave, so campaign balance is untouched.
	local endless = Scaling.endlessFactor(wave, difficulty.finalWave)
	local healthMultiplier = difficulty.healthMultiplier * endless

	local bosses: { CompositionEntry } = {}
	local regulars: { CompositionEntry } = {}
	local bossTotal = 0

	for _, entry in composition do
		local definition = Enemies.find(entry.id)

		-- An authored wave naming an enemy that no longer exists is a config
		-- mistake, not a crash. Skip it and let the rest of the wave run.
		if definition == nil then
			continue
		end

		if definition.isBoss then
			table.insert(bosses, entry)
			bossTotal += entry.count
		else
			table.insert(regulars, entry)
		end
	end

	-- The per-wave ceiling is a performance guard, not a balance knob. Bosses
	-- are reserved out of it rather than competing for it: a boss wave that
	-- silently dropped its boss because the chaff filled the budget would be
	-- the worst possible failure mode.
	local regularBudget = math.max(0, Scaling.MAX_ENEMIES_PER_WAVE - bossTotal)
	local allocation = allocateRegulars(regulars, regularBudget)

	local plan: { PlanEntry } = {}
	local clock = 0
	local lane = 0
	local ordinal = 0

	--- One scheduled spawn, before it has a time. `fraction` is where in the
	--- wave it belongs, which is what lets types interleave.
	type Slot = {
		entryIndex: number,
		order: number,
		fraction: number,
	}

	-- Every allocated spawn gets a position in [0, 1) spread EVENLY across
	-- its own type: four Drifters sit at 1/8, 3/8, 5/8, 7/8 rather than in
	-- one clump. Sorting those positions is what actually interleaves the
	-- types.
	--
	-- The previous code walked one type to exhaustion at a time against a
	-- shared, never-reset clock, so every wave arrived as one block per
	-- type - despite the comment below promising the opposite. Sorting
	-- afterwards could not fix it: the times were already monotonic, so
	-- there was nothing left for the sort to reorder.
	local slots: { Slot } = {}

	for index, count in allocation do
		for order = 1, count do
			table.insert(slots, {
				entryIndex = index,
				order = order,
				fraction = (order - 0.5) / count,
			})
		end
	end

	table.sort(slots, function(a: Slot, b: Slot): boolean
		if a.fraction ~= b.fraction then
			return a.fraction < b.fraction
		end

		-- Ties resolve by config order then by index, so the plan is
		-- byte-identical on every server that generates it.
		if a.entryIndex ~= b.entryIndex then
			return a.entryIndex < b.entryIndex
		end

		return a.order < b.order
	end)

	--- Health and bounty depend only on the TYPE, so they are computed once
	--- per type rather than once per spawn.
	local stats: { { health: number, bounty: number, interval: number } } = {}

	for index, entry in regulars do
		local definition = Enemies.get(entry.id)
		-- Clamped at 1: an authored wave may legitimately include an enemy
		-- before its own introducesAtWave, and a negative exponent there
		-- would scale its health DOWN below the values in config.
		local relativeWave = math.max(1, wave - definition.introducesAtWave + 1)

		stats[index] = {
			health = Scaling.enemyHealth(definition.baseHealth, relativeWave, healthMultiplier),
			bounty = Scaling.bounty(definition.baseBounty, relativeWave, difficulty.rewardMultiplier),
			interval = if WavesConfig.BURST_TYPES[entry.id]
				then WavesConfig.BURST_INTERVAL
				else WavesConfig.SPAWN_INTERVAL,
		}
	end

	for _, slot in slots do
		local entry = regulars[slot.entryIndex]
		local stat = stats[slot.entryIndex]

		lane = (lane % laneCount) + 1
		ordinal += 1

		table.insert(plan, {
			enemyId = entry.id,
			at = clock,
			pathIndex = lane,
			health = stat.health,
			bounty = stat.bounty,
			speed = Enemies.get(entry.id).baseSpeed,
			ordinal = ordinal,
		})

		clock += stat.interval
	end

	-- Bosses last and held back, so they arrive behind the chaff rather than
	-- leading it and getting focused down before anything else shows up.
	-- They are not budgeted, having been reserved out of it above.
	if #bosses > 0 then
		clock += WavesConfig.BOSS_LEAD_IN

		for _, entry in bosses do
			local definition = Enemies.get(entry.id)
			local relativeWave = math.max(1, wave - definition.introducesAtWave + 1)
			local health = Scaling.enemyHealth(definition.baseHealth, relativeWave, healthMultiplier)
			local bounty = Scaling.bounty(definition.baseBounty, relativeWave, difficulty.rewardMultiplier)

			for _ = 1, entry.count do
				lane = (lane % laneCount) + 1
				ordinal += 1

				table.insert(plan, {
					enemyId = definition.id,
					at = clock,
					pathIndex = lane,
					health = health,
					bounty = bounty,
					speed = definition.baseSpeed,
					ordinal = ordinal,
				})

				clock += WavesConfig.SPAWN_INTERVAL
			end
		end
	end

	-- Types were appended type-by-type, so the list is grouped rather than
	-- time-ordered. Sorting interleaves them, which is what makes a wave feel
	-- mixed instead of arriving in blocks.
	table.sort(plan, function(a: PlanEntry, b: PlanEntry): boolean
		if a.at ~= b.at then
			return a.at < b.at
		end

		-- table.sort is not stable in Luau, so equal times need an explicit
		-- tie-break or the plan varies between runs.
		return a.ordinal < b.ordinal
	end)

	return plan
end

--- Total enemies a wave will spawn. Cheaper to read than to count at the
--- call site, and used by the HUD and by the curve tests.
function WaveGenerator.plannedCount(wave: number, difficulty: Types.DifficultyConfig, laneCount: number): number
	return #WaveGenerator.generate(wave, difficulty, laneCount)
end

return WaveGenerator

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

	local plan: { PlanEntry } = {}
	local clock = 0
	local lane = 0
	local ordinal = 0
	local regularsEmitted = 0

	local function emit(definition: Types.EnemyDefinition, count: number, interval: number, budget: number?)
		-- Clamped at 1: an authored wave may legitimately include an enemy
		-- before its own introducesAtWave, and a negative exponent there
		-- would scale its health DOWN below the values in config.
		local relativeWave = math.max(1, wave - definition.introducesAtWave + 1)

		local health = Scaling.enemyHealth(definition.baseHealth, relativeWave, healthMultiplier)
		local bounty = Scaling.bounty(definition.baseBounty, relativeWave, difficulty.rewardMultiplier)

		for _ = 1, count do
			if budget ~= nil and regularsEmitted >= budget then
				break
			end

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

			if budget ~= nil then
				regularsEmitted += 1
			end

			clock += interval
		end
	end

	for _, entry in regulars do
		local definition = Enemies.get(entry.id)
		local interval = if WavesConfig.BURST_TYPES[entry.id]
			then WavesConfig.BURST_INTERVAL
			else WavesConfig.SPAWN_INTERVAL

		emit(definition, entry.count, interval, regularBudget)
	end

	-- Bosses last and held back, so they arrive behind the chaff rather than
	-- leading it and getting focused down before anything else shows up.
	if #bosses > 0 then
		clock += WavesConfig.BOSS_LEAD_IN

		for _, entry in bosses do
			emit(Enemies.get(entry.id), entry.count, WavesConfig.SPAWN_INTERVAL, nil)
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

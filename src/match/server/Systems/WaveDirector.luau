--!strict
--[[
	Turns a wave number into a timed sequence of spawns.

	Phase 1 ships the rule-driven generator. Phase 3 layers an authored
	override table on top for the first N waves and reuses this as the
	endless-mode source. The INTERFACE below is what Phase 3 must preserve -
	beginWave / update / isSpawningComplete - so the internals can change
	without touching MatchController.

	Composition rules:
	  * A type is eligible once wave >= its introducesAtWave, and only if it
	    appears in Waves.BASE_COUNTS.
	  * Its count grows from the wave it was INTRODUCED, not from wave 1, so a
	    type arriving at wave 7 starts at its base count rather than at seven
	    waves' worth of scaling.
	  * Bosses are gated to boss waves and arrive after the chaff.
	  * Spawns round-robin across lanes, so a multi-lane map is fed evenly
	    without the caller having to think about it.

	Iteration order comes from Enemies.IDS, which is sorted. A hash-table
	pairs() order is not stable in Luau, and an unstable order would make the
	same wave number produce different sequences on different servers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local Scaling = require(ReplicatedStorage.Shared.Scaling)
local Types = require(ReplicatedStorage.Shared.Types)
local WavesConfig = require(ReplicatedStorage.Shared.Config.Waves)

local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)

local WaveDirector = {}
WaveDirector.__index = WaveDirector

export type SpawnEntry = {
	definition: Types.EnemyDefinition,
	--- Seconds after the wave starts at which this enemy appears.
	at: number,
	pathIndex: Types.PathIndex,
	health: number,
	bounty: number,
}

export type Director = typeof(setmetatable(
	{} :: {
		simulation: EnemySimulation.Simulation,
		difficulty: Types.DifficultyConfig,
		laneCount: number,
		queue: { SpawnEntry },
		--- Index of the next entry to spawn. The queue is time-ordered, so
		--- this only ever moves forward.
		cursor: number,
		elapsed: number,
		waveNumber: number,
	},
	WaveDirector
))

function WaveDirector.new(simulation: EnemySimulation.Simulation, difficulty: Types.DifficultyConfig): Director
	return setmetatable({
		simulation = simulation,
		difficulty = difficulty,
		laneCount = #simulation.paths,
		queue = {},
		cursor = 1,
		elapsed = 0,
		waveNumber = 0,
	}, WaveDirector)
end

--- Builds the time-ordered spawn plan for `wave`.
local function buildQueue(self: Director, wave: number): { SpawnEntry }
	local difficulty = self.difficulty
	local isBossWave = Scaling.isBossWave(wave)
	local queue: { SpawnEntry } = {}

	local clock = 0
	local lane = 0
	local bosses: { Types.EnemyDefinition } = {}

	local function nextLane(): number
		lane = (lane % self.laneCount) + 1
		return lane
	end

	local function enqueue(definition: Types.EnemyDefinition, at: number)
		-- Scale from the wave this type was introduced, not from wave 1.
		local relativeWave = wave - definition.introducesAtWave + 1

		table.insert(queue, {
			definition = definition,
			at = at,
			pathIndex = nextLane(),
			health = Scaling.enemyHealth(definition.baseHealth, relativeWave, difficulty.healthMultiplier),
			bounty = Scaling.bounty(definition.baseBounty, relativeWave, difficulty.rewardMultiplier),
		})
	end

	for _, id in Enemies.IDS do
		local baseCount = WavesConfig.BASE_COUNTS[id]

		if baseCount == nil then
			continue
		end

		local definition = Enemies.get(id)

		if wave < definition.introducesAtWave then
			continue
		end

		if definition.isBoss then
			if isBossWave or not WavesConfig.BOSS_ONLY_ON_BOSS_WAVES then
				table.insert(bosses, definition)
			end
			continue
		end

		local relativeWave = wave - definition.introducesAtWave + 1
		local count = Scaling.enemyCount(baseCount, relativeWave)
		local interval = if WavesConfig.BURST_TYPES[id] then WavesConfig.BURST_INTERVAL else WavesConfig.SPAWN_INTERVAL

		for _ = 1, count do
			enqueue(definition, clock)
			clock += interval
		end
	end

	-- Bosses last, held back so they arrive behind the chaff.
	if #bosses > 0 then
		clock += WavesConfig.BOSS_LEAD_IN

		for _, definition in bosses do
			local baseCount = WavesConfig.BASE_COUNTS[definition.id] or 1
			local relativeWave = wave - definition.introducesAtWave + 1
			local count = Scaling.enemyCount(baseCount, relativeWave)

			for _ = 1, count do
				enqueue(definition, clock)
				clock += WavesConfig.SPAWN_INTERVAL
			end
		end
	end

	-- Types were appended type-by-type, so the list is grouped rather than
	-- time-ordered. A stable sort by time interleaves them, which is what
	-- makes a wave feel mixed instead of arriving in blocks.
	table.sort(queue, function(a: SpawnEntry, b: SpawnEntry): boolean
		return a.at < b.at
	end)

	return queue
end

--- Starts `wave`. Discards anything left unspawned from a previous wave.
function WaveDirector.beginWave(self: Director, wave: number)
	self.waveNumber = wave
	self.queue = buildQueue(self, wave)
	self.cursor = 1
	self.elapsed = 0
end

--- Number of enemies this wave will spawn in total. Used by the HUD and by
--- tests asserting on the difficulty curve.
function WaveDirector.plannedCount(self: Director): number
	return #self.queue
end

--- Releases every spawn whose time has arrived.
function WaveDirector.update(self: Director, deltaTime: number)
	self.elapsed += deltaTime

	while self.cursor <= #self.queue do
		local entry = self.queue[self.cursor]

		if entry.at > self.elapsed then
			break
		end

		self.simulation:spawn({
			definition = entry.definition,
			pathIndex = entry.pathIndex,
			health = entry.health,
			speed = entry.definition.baseSpeed,
			bounty = entry.bounty,
		})

		self.cursor += 1
	end
end

--- True once every planned enemy has been released. Note this says nothing
--- about whether they are still alive - MatchController pairs this with the
--- simulation's live count to decide the wave is over.
function WaveDirector.isSpawningComplete(self: Director): boolean
	return self.cursor > #self.queue
end

function WaveDirector.reset(self: Director)
	self.queue = {}
	self.cursor = 1
	self.elapsed = 0
	self.waveNumber = 0
end

return WaveDirector

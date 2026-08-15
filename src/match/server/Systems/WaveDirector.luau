--!strict
--[[
	Releases a wave's spawn plan into the simulation on schedule.

	This used to build the plan itself. It no longer does: composition and
	scaling live in the pure WaveGenerator, which can be asserted on without
	standing up a simulation. What is left here is the part that genuinely
	needs the simulation - walking a time-ordered list against a clock and
	spawning as each entry comes due.

	The interface is unchanged - beginWave / update / isSpawningComplete /
	plannedCount / reset - so MatchController did not have to move.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local Types = require(ReplicatedStorage.Shared.Types)
local WaveGenerator = require(ReplicatedStorage.Shared.WaveGenerator)

local EnemyBehaviors = require(script.Parent.Parent.Entities.EnemyBehaviors)
local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)

local WaveDirector = {}
WaveDirector.__index = WaveDirector

export type Director = typeof(setmetatable(
	{} :: {
		simulation: EnemySimulation.Simulation,
		difficulty: Types.DifficultyConfig,
		laneCount: number,
		queue: { WaveGenerator.PlanEntry },
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

--- Starts `wave`. Discards anything left unspawned from a previous wave.
function WaveDirector.beginWave(self: Director, wave: number)
	self.waveNumber = wave
	self.queue = WaveGenerator.generate(wave, self.difficulty, self.laneCount)
	self.cursor = 1
	self.elapsed = 0
end

--- Number of enemies this wave will spawn in total. Used by the HUD.
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

		local definition = Enemies.find(entry.enemyId)

		if definition ~= nil then
			self.simulation:spawn({
				definition = definition,
				-- Resolved here rather than baked into the plan, so the plan
				-- stays plain data and behaviours stay a server concern.
				behavior = EnemyBehaviors.find(entry.enemyId),
				pathIndex = entry.pathIndex,
				health = entry.health,
				speed = entry.speed,
				bounty = entry.bounty,
			})
		end

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

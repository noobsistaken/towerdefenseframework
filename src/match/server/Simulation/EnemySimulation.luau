--!strict
--[[
	The authoritative enemy simulation (ARCHITECTURE.md D2).

	This module is the single source of truth for every enemy in the match.
	It holds no Instances. Everything it knows is numbers, which is what makes
	it deterministic, cheap, and steppable by hand in a test.

	Fixed timestep. `update` accumulates real frame time and calls `step` in
	whole ticks of Constants.SIMULATION_STEP. Tests call `step` directly and
	get exact, reproducible results; the server calls `update` and gets the
	same simulation regardless of its frame rate.

	The accumulator is capped at MAX_STEPS_PER_FRAME. Without a cap, a server
	hitch feeds a spiral: the backlog grows, catching up costs more than real
	time, and the backlog grows further. Falling behind wall-clock is a much
	better failure than locking the server, so the cap drops the excess.

	--------------------------------------------------------------------------
	Why plain listener lists here instead of the Signal package

	Signal is typed `Signal.new<T...>(): Signal<T...>`, and Wally's re-export
	link file does not propagate type exports, so `Signal.Signal<Enemy>` is
	unavailable. The documented workaround - `type S = typeof(Signal.new())` -
	produces ONE instantiation, so three signal fields sharing that alias all
	collapse to the same T. In practice Luau pinned T to `number` from the
	first concrete Fire and then rejected `Fire(enemy)` on the other two.

	Three explicitly typed listener lists cost about twenty lines, type
	correctly, and keep this module - the one piece of the codebase most worth
	testing in isolation - free of package dependencies. Signal remains the
	right tool everywhere a single payload type is involved.
	--------------------------------------------------------------------------
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Path = require(ReplicatedStorage.Shared.Path)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)
local StatusEffectSystem = require(script.Parent.Parent.Systems.StatusEffectSystem)

local EnemySimulation = {}
EnemySimulation.__index = EnemySimulation

export type DiedListener = (enemy: BaseEnemy.Enemy) -> ()
export type LeakedListener = (enemy: BaseEnemy.Enemy, baseDamage: number) -> ()
export type RemovedListener = (id: Types.EnemyId) -> ()

--- Returned by every subscribe method. Calling it unsubscribes; calling it
--- twice is harmless.
export type Unsubscribe = () -> ()

export type Simulation = typeof(setmetatable(
	{} :: {
		paths: { Path.Path },
		--- Live enemies. Rebuilt whenever anything is removed, so it stays
		--- dense and safe to iterate.
		enemies: { BaseEnemy.Enemy },
		byId: { [Types.EnemyId]: BaseEnemy.Enemy? },
		nextId: number,
		accumulator: number,
		--- Simulation time in seconds, advanced only by `step`. Status effects
		--- expire and tick against this rather than os.clock, so their
		--- behaviour does not depend on server frame rate and a test can drive
		--- them exactly.
		time: number,
		diedListeners: { DiedListener },
		leakedListeners: { LeakedListener },
		removedListeners: { RemovedListener },
	},
	EnemySimulation
))

export type SpawnRequest = {
	definition: Types.EnemyDefinition,
	behavior: BaseEnemy.EnemyBehavior?,
	pathIndex: Types.PathIndex,
	health: number,
	speed: number,
	bounty: number,
}

function EnemySimulation.new(paths: { Path.Path }): Simulation
	if #paths == 0 then
		error("EnemySimulation.new: a map must have at least one lane")
	end

	return setmetatable({
		paths = paths,
		enemies = {},
		byId = {},
		nextId = 1,
		accumulator = 0,
		time = 0,
		diedListeners = {},
		leakedListeners = {},
		removedListeners = {},
	}, EnemySimulation)
end

-- ---------------------------------------------------------------------------
-- Subscriptions
-- ---------------------------------------------------------------------------

--- Fired after a kill, before the enemy is removed, so a listener can still
--- read its damageByPlayer table to split the bounty (D6).
function EnemySimulation.onEnemyDied(self: Simulation, listener: DiedListener): Unsubscribe
	table.insert(self.diedListeners, listener)

	return function()
		local index = table.find(self.diedListeners, listener)

		if index ~= nil then
			table.remove(self.diedListeners, index)
		end
	end
end

--- Fired when an enemy completes its lane, with the base damage it deals.
function EnemySimulation.onEnemyLeaked(self: Simulation, listener: LeakedListener): Unsubscribe
	table.insert(self.leakedListeners, listener)

	return function()
		local index = table.find(self.leakedListeners, listener)

		if index ~= nil then
			table.remove(self.leakedListeners, index)
		end
	end
end

--- Fired once an enemy has left the simulation for any reason. EnemyView
--- listens to this to release the part back to the pool.
function EnemySimulation.onEnemyRemoved(self: Simulation, listener: RemovedListener): Unsubscribe
	table.insert(self.removedListeners, listener)

	return function()
		local index = table.find(self.removedListeners, listener)

		if index ~= nil then
			table.remove(self.removedListeners, index)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function EnemySimulation.get(self: Simulation, id: Types.EnemyId): BaseEnemy.Enemy?
	return self.byId[id]
end

function EnemySimulation.count(self: Simulation): number
	return #self.enemies
end

--- World position of an enemy right now, derived from its progress.
--- This is the ONLY way anything should learn where an enemy is.
function EnemySimulation.positionOf(self: Simulation, enemy: BaseEnemy.Enemy): Vector3
	local path = self.paths[enemy.pathIndex]
	return path:positionAt(enemy.progress) + Vector3.new(0, enemy.definition.hoverHeight, 0)
end

function EnemySimulation.directionOf(self: Simulation, enemy: BaseEnemy.Enemy): Vector3
	return self.paths[enemy.pathIndex]:directionAt(enemy.progress)
end

--- Studs remaining before this enemy leaks. The universal ordering key (D8).
function EnemySimulation.distanceToBase(self: Simulation, enemy: BaseEnemy.Enemy): number
	return self.paths[enemy.pathIndex]:distanceToBase(enemy.progress)
end

-- ---------------------------------------------------------------------------
-- Mutation
-- ---------------------------------------------------------------------------

--- Adds an enemy at the start of its lane.
function EnemySimulation.spawn(self: Simulation, request: SpawnRequest): BaseEnemy.Enemy
	local pathIndex = request.pathIndex

	if pathIndex < 1 or pathIndex > #self.paths then
		error(`EnemySimulation.spawn: no lane {pathIndex} on this map`)
	end

	local id = self.nextId
	self.nextId += 1

	local enemy = BaseEnemy.new({
		id = id,
		definition = request.definition,
		behavior = request.behavior,
		pathIndex = pathIndex,
		pathLength = self.paths[pathIndex].totalLength,
		health = request.health,
		speed = request.speed,
		bounty = request.bounty,
	})

	table.insert(self.enemies, enemy)
	self.byId[id] = enemy

	return enemy
end

--- Applies damage from outside the step - a tower firing, or a
--- damage-over-time tick. Fires the death listeners exactly once.
--- Returns true if this call killed the enemy.
function EnemySimulation.damage(self: Simulation, id: Types.EnemyId, amount: number, source: Player?): boolean
	local enemy = self.byId[id]

	if enemy == nil then
		return false
	end

	local died = enemy:takeDamage(amount, source)

	if died then
		for _, listener in self.diedListeners do
			listener(enemy)
		end
	end

	return died
end

--- Drops every enemy whose `alive` flag is false. Rebuilds the array rather
--- than removing in place: removing while iterating is the classic way to
--- skip elements, and at these counts the rebuild is not worth optimising.
local function collectDead(self: Simulation)
	local survivors: { BaseEnemy.Enemy } = {}
	local removed: { Types.EnemyId } = {}

	for _, enemy in self.enemies do
		if enemy.alive then
			table.insert(survivors, enemy)
		else
			self.byId[enemy.id] = nil
			table.insert(removed, enemy.id)
		end
	end

	if #removed == 0 then
		return
	end

	self.enemies = survivors

	-- Fired after the tables are already consistent, so a listener that reads
	-- back into the simulation sees the post-removal state.
	for _, id in removed do
		for _, listener in self.removedListeners do
			listener(id)
		end
	end
end

local function fireDied(self: Simulation, enemy: BaseEnemy.Enemy)
	for _, listener in self.diedListeners do
		listener(enemy)
	end
end

--- Applies a status effect to one enemy, stamped with the simulation clock.
--- Towers go through here rather than calling StatusEffectSystem directly, so
--- there is exactly one definition of "now".
function EnemySimulation.applyEffect(
	self: Simulation,
	id: Types.EnemyId,
	application: Types.StatusApplication,
	source: Player?
)
	local enemy = self.byId[id]

	if enemy == nil then
		return
	end

	StatusEffectSystem.apply(enemy, application, self.time, source)
end

--- Advances the simulation by exactly `deltaTime` seconds.
--- Called directly by tests; the server goes through `update`.
function EnemySimulation.step(self: Simulation, deltaTime: number)
	self.time += deltaTime

	for _, enemy in self.enemies do
		if not enemy.alive then
			continue
		end

		-- Effects resolve BEFORE movement, so an enemy killed by a bleed tick
		-- this step does not also get a step of travel out of it. At the base
		-- that is the difference between a leak and a kill.
		local ticks = StatusEffectSystem.step(enemy, self.time)

		if ticks ~= nil then
			for _, tick in ticks do
				-- Routed through takeDamage rather than writing health, so a
				-- bleed kill fires the same death path as a bullet kill:
				-- damage credited for the bounty split, listeners run, normal
				-- removal.
				if enemy:takeDamage(tick.amount, tick.source) then
					fireDied(self, enemy)
					break
				end
			end
		end

		if not enemy.alive then
			continue
		end

		local path = self.paths[enemy.pathIndex]
		enemy:advance(deltaTime)

		if path:hasReachedEnd(enemy.progress) then
			local damage = enemy:markLeaked()

			if damage > 0 then
				for _, listener in self.leakedListeners do
					listener(enemy, damage)
				end
			end
		end
	end

	collectDead(self)
end

--- Accumulates real time and runs whole fixed steps.
function EnemySimulation.update(self: Simulation, realDeltaTime: number)
	self.accumulator += realDeltaTime

	local steps = 0

	while self.accumulator >= Constants.SIMULATION_STEP do
		if steps >= Constants.MAX_STEPS_PER_FRAME then
			-- Drop the backlog rather than trying to catch up. See the header.
			self.accumulator = 0
			break
		end

		self.accumulator -= Constants.SIMULATION_STEP
		self:step(Constants.SIMULATION_STEP)
		steps += 1
	end
end

--- Removes every enemy without firing died or leaked: the enemies are gone,
--- but nobody is paid for them and the base takes no damage. Used when a
--- match ends.
function EnemySimulation.reset(self: Simulation)
	local ids: { Types.EnemyId } = {}

	for _, enemy in self.enemies do
		table.insert(ids, enemy.id)
	end

	self.enemies = {}
	self.byId = {}
	self.accumulator = 0
	self.time = 0

	for _, id in ids do
		for _, listener in self.removedListeners do
			listener(id)
		end
	end
end

function EnemySimulation.destroy(self: Simulation)
	self:reset()
	self.diedListeners = {}
	self.leakedListeners = {}
	self.removedListeners = {}
end

return EnemySimulation

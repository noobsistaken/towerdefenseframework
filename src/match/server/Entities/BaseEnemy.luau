--!strict
--[[
	One live enemy.

	This is the class family described in ARCHITECTURE.md -> "Why there is no
	BaseTower subclass hierarchy". BaseEnemy is the single concrete class and
	holds all shared state and all shared implementations. A "subclass" is a
	behaviour table in the `behavior` field carrying optional override hooks.
	That keeps override, call-up-to-base and polymorphic dispatch, without the
	casts that classical inheritance would need at every call site in strict
	Luau.

	Critically, an Enemy holds NO Instance reference and NO position. It knows
	how far it has walked and which lane it is on; EnemyView turns that into
	a part. Position is never read back off a part (D2). That is what keeps
	this whole module pure enough to step by hand in a test.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = {}
BaseEnemy.__index = BaseEnemy

--- Optional override hooks for one kind of enemy. Every field is optional:
--- an enemy that differs from the baseline only in its stats needs no
--- behaviour module at all, which is the whole point of the data-driven
--- design (D4).
export type EnemyBehavior = {
	id: string,
	onSpawned: ((enemy: Enemy) -> ())?,
	--- Fired after health has already been reduced.
	onDamaged: ((enemy: Enemy, amount: number) -> ())?,
	onDied: ((enemy: Enemy) -> ())?,
	onLeaked: ((enemy: Enemy) -> ())?,
	--- Multiplies movement speed. Return 1 for no change. Called every step,
	--- so keep it cheap - this is where an accelerating or stuttering enemy
	--- would be implemented.
	speedMultiplier: ((enemy: Enemy) -> number)?,
}

export type Enemy = typeof(setmetatable(
	{} :: {
		id: Types.EnemyId,
		definition: Types.EnemyDefinition,
		behavior: EnemyBehavior,
		--- Which lane. Index into the simulation's path list.
		pathIndex: Types.PathIndex,
		--- Studs walked. The single number this whole design rests on.
		progress: number,
		health: number,
		maxHealth: number,
		--- Studs per second before behaviour and status modifiers.
		baseSpeed: number,
		bounty: number,
		alive: boolean,
		--- Total damage each player has contributed, for the proportional
		--- bounty split in D6. Cleared on death once the split is paid.
		damageByPlayer: { [Player]: number },
		--- Set when the enemy reaches the end of its lane, so the simulation
		--- can tell a leak apart from a kill during cleanup.
		leaked: boolean,
	},
	BaseEnemy
))

--- The default behaviour: nothing overridden. Shared by every enemy that has
--- no behaviour module of its own, so the common case allocates nothing.
local DEFAULT_BEHAVIOR: EnemyBehavior = {
	id = "Default",
}

BaseEnemy.DEFAULT_BEHAVIOR = DEFAULT_BEHAVIOR

export type SpawnParams = {
	id: Types.EnemyId,
	definition: Types.EnemyDefinition,
	behavior: EnemyBehavior?,
	pathIndex: Types.PathIndex,
	health: number,
	speed: number,
	bounty: number,
}

function BaseEnemy.new(params: SpawnParams): Enemy
	local enemy = setmetatable({
		id = params.id,
		definition = params.definition,
		behavior = params.behavior or DEFAULT_BEHAVIOR,
		pathIndex = params.pathIndex,
		progress = 0,
		health = params.health,
		maxHealth = params.health,
		baseSpeed = params.speed,
		bounty = params.bounty,
		alive = true,
		damageByPlayer = {},
		leaked = false,
	}, BaseEnemy)

	local hook = enemy.behavior.onSpawned

	if hook ~= nil then
		hook(enemy)
	end

	return enemy
end

--- Studs per second right now, after behaviour modifiers.
--- Status effects hook in here in Phase 2; the clamp is already in place so
--- a stacking slow can never reverse an enemy back up its lane.
function BaseEnemy.currentSpeed(self: Enemy): number
	local speed = self.baseSpeed

	local modifier = self.behavior.speedMultiplier

	if modifier ~= nil then
		speed *= modifier(self)
	end

	return math.max(0, speed)
end

--- Advances along the lane. Returns the new progress.
--- Movement is separated from the leak test deliberately: the simulation owns
--- the decision about what reaching the end means.
function BaseEnemy.advance(self: Enemy, deltaTime: number): number
	self.progress += self:currentSpeed() * deltaTime
	return self.progress
end

--- Applies damage and records who dealt it.
--- Returns true if this call is what killed the enemy - exactly once per
--- enemy, so the caller can pay out a bounty without double-counting.
function BaseEnemy.takeDamage(self: Enemy, amount: number, source: Player?): boolean
	if not self.alive or amount <= 0 then
		return false
	end

	-- Credit the full requested amount rather than the amount actually
	-- absorbed. Overkill still reflects contribution, and clamping it would
	-- quietly under-pay whoever landed the finishing hit.
	if source ~= nil then
		self.damageByPlayer[source] = (self.damageByPlayer[source] or 0) + amount
	end

	self.health -= amount

	local hook = self.behavior.onDamaged

	if hook ~= nil then
		hook(self, amount)
	end

	if self.health > 0 then
		return false
	end

	self.health = 0
	self.alive = false

	local died = self.behavior.onDied

	if died ~= nil then
		died(self)
	end

	return true
end

--- Marks the enemy as having reached the base. Returns the base damage it
--- deals. Idempotent: a second call returns 0, so a leak can never be
--- double-counted by a retry or a duplicated cleanup pass.
function BaseEnemy.markLeaked(self: Enemy): number
	if not self.alive or self.leaked then
		return 0
	end

	self.leaked = true
	self.alive = false

	local hook = self.behavior.onLeaked

	if hook ~= nil then
		hook(self)
	end

	return self.definition.leakDamage
end

--- Fraction of max health remaining, in [0, 1]. Drives the health bar.
function BaseEnemy.healthFraction(self: Enemy): number
	if self.maxHealth <= 0 then
		return 0
	end

	return math.clamp(self.health / self.maxHealth, 0, 1)
end

return BaseEnemy

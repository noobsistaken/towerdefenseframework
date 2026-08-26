--!strict
--[[
	One placed tower.

	Same class family as BaseEnemy (ARCHITECTURE.md -> "Why there is no
	BaseTower subclass hierarchy"): one concrete class holding all shared
	state and all shared implementations, plus a `behavior` table of optional
	override hooks. Of the six towers in the roster, four need no behaviour
	module at all - they are pure config.

	Like BaseEnemy, a Tower holds NO Instance. TowerSystem owns the visible
	part; this owns the truth. Splash resolves against simulation positions
	rather than a GetPartBoundsInRadius query for the same reason: the parts
	are a projection, and a server-side query against them would be reading
	the picture instead of the thing (D2).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local TraitEffects = require(ReplicatedStorage.Shared.TraitEffects)
local Types = require(ReplicatedStorage.Shared.Types)

local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)

local BaseTower = {}
BaseTower.__index = BaseTower

--- Optional per-tower overrides. Every field is optional; a tower that only
--- differs in its numbers needs none of them.
export type TowerBehavior = {
	id: string,
	onPlaced: ((tower: Tower) -> ())?,
	onUpgraded: ((tower: Tower, level: number) -> ())?,
	--- Replaces the whole damage application. Used by the splash towers.
	onFire: ((
		tower: Tower,
		simulation: EnemySimulation.Simulation,
		targetId: Types.EnemyId,
		targetPosition: Vector3
	) -> ())?,
	--- Adjusts outgoing damage. Runs for the default path and for any
	--- behaviour that calls BaseTower.dealDamage.
	modifyDamage: ((tower: Tower, base: number) -> number)?,
	onSold: ((tower: Tower) -> ())?,
}

export type Tower = typeof(setmetatable(
	{} :: {
		id: Types.TowerId,
		definition: Types.TowerDefinition,
		behavior: TowerBehavior,
		owner: Player,
		level: number,
		--- Centre of the footprint, resting on the surface.
		position: Vector3,
		--- Cosmetic only. Placement geometry is rotation-invariant, so this
		--- is never trusted for anything (see Footprint).
		rotationY: number,
		targetingMode: Types.TargetingMode,
		--- Seconds until this tower may fire again.
		---
		--- Targets are deliberately NOT cached between shots. Acquisition only
		--- runs when this reaches zero, so its cost is bounded by fire rate
		--- rather than by frame rate, and re-acquiring each shot is what makes
		--- First and Closest actually track as enemies move.
		cooldown: number,
		--- Cash actually paid, purchase plus upgrades. Sell refunds against
		--- this rather than the base price.
		invested: number,
		--- Trait ids this tower carries, snapshotted at PLACEMENT. Traits
		--- change only in the lobby, so a mid-match reroll cannot exist;
		--- snapshotting keeps every stat read allocation-free.
		traits: { string },
		--- Precomputed from `traits`. Applied at stat READ time - never
		--- written into the shared definition, which every tower of this
		--- type reads.
		traitMultipliers: TraitEffects.Multipliers,
		--- Overcharge state: fire rate is multiplied by boostMultiplier
		--- while boostRemaining is above zero. Ticked down with the same
		--- clock the reload uses, so a boost and a reload can never drift.
		boostMultiplier: number,
		boostRemaining: number,
		--- os.time() at which the ability may fire again. 0 means ready
		--- (or no ability at all - the definition decides).
		abilityReadyAt: number,
	},
	BaseTower
))

local DEFAULT_BEHAVIOR: TowerBehavior = {
	id = "Default",
}

BaseTower.DEFAULT_BEHAVIOR = DEFAULT_BEHAVIOR

export type PlaceParams = {
	id: Types.TowerId,
	definition: Types.TowerDefinition,
	behavior: TowerBehavior?,
	owner: Player,
	position: Vector3,
	rotationY: number,
	--- Rolled trait ids for this tower type, from the owner's profile.
	traits: { string }?,
}

function BaseTower.new(params: PlaceParams): Tower
	local definition = params.definition

	local tower = setmetatable({
		id = params.id,
		definition = definition,
		behavior = params.behavior or DEFAULT_BEHAVIOR,
		owner = params.owner,
		level = 1,
		position = params.position,
		rotationY = params.rotationY,
		targetingMode = definition.defaultTargeting,
		-- Ready immediately: a tower placed mid-wave should not owe a full
		-- reload before its first shot.
		cooldown = 0,
		invested = definition.levels[1].cost,
		traits = params.traits or {},
		traitMultipliers = TraitEffects.multipliers(params.traits or {}),
		boostMultiplier = 1,
		boostRemaining = 0,
		abilityReadyAt = 0,
	}, BaseTower)

	local hook = tower.behavior.onPlaced

	if hook ~= nil then
		hook(tower)
	end

	return tower
end

-- ---------------------------------------------------------------------------
-- Stats
-- ---------------------------------------------------------------------------

function BaseTower.currentLevel(self: Tower): Types.TowerLevel
	return self.definition.levels[self.level]
end

function BaseTower.range(self: Tower): number
	return self:currentLevel().range * self.traitMultipliers.range
end

function BaseTower.maxLevel(self: Tower): number
	return #self.definition.levels
end

function BaseTower.canUpgrade(self: Tower): boolean
	return self.level < #self.definition.levels
end

--- Cost of the next upgrade, or nil at max level.
function BaseTower.upgradeCost(self: Tower): number?
	return Economy.upgradeCost(self.definition, self.level)
end

function BaseTower.sellValue(self: Tower): number
	return math.floor(self.invested * Economy.SELL_REFUND_RATE)
end

--- Advances to the next level. The caller has already taken payment; this
--- records what was paid so the refund stays honest.
function BaseTower.upgrade(self: Tower, paid: number)
	if not self:canUpgrade() then
		return
	end

	self.level += 1
	self.invested += paid

	local hook = self.behavior.onUpgraded

	if hook ~= nil then
		hook(self, self.level)
	end
end

function BaseTower.setTargeting(self: Tower, mode: Types.TargetingMode)
	self.targetingMode = mode
end

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------

--- Whether this tower may shoot that enemy class.
function BaseTower.canTarget(self: Tower, category: Types.EnemyCategory): boolean
	return Towers.canTarget(self.definition, category)
end

function BaseTower.isReady(self: Tower): boolean
	return self.cooldown <= 0
end

--- Ticks the reload clock. Separate from firing so a tower with no target
--- still becomes ready.
function BaseTower.tickCooldown(self: Tower, deltaTime: number)
	if self.cooldown > 0 then
		self.cooldown = math.max(0, self.cooldown - deltaTime)
	end

	if self.boostRemaining > 0 then
		self.boostRemaining = math.max(0, self.boostRemaining - deltaTime)
	end
end

--- Starts an Overcharge: fire rate multiplied for a fixed window. A second
--- cast REPLACES the window rather than stacking - the cooldown makes that
--- almost impossible anyway, but almost is how exploits start.
function BaseTower.beginBoost(self: Tower, multiplier: number, durationSeconds: number)
	self.boostMultiplier = multiplier
	self.boostRemaining = durationSeconds
end

--- Starts the reload. fireRate is shots per second.
function BaseTower.beginReload(self: Tower)
	local rate = self:currentLevel().fireRate * self.traitMultipliers.fireRate

	if self.boostRemaining > 0 then
		rate *= self.boostMultiplier
	end

	self.cooldown = if rate > 0 then 1 / rate else math.huge
end

--- Applies this tower's damage and effects to one enemy.
--- Behaviours call this so that modifyDamage and the effect list are applied
--- consistently no matter which one is doing the hitting.
function BaseTower.dealDamage(
	self: Tower,
	simulation: EnemySimulation.Simulation,
	targetId: Types.EnemyId,
	scale: number
)
	local level = self:currentLevel()
	local damage = level.damage * scale * self.traitMultipliers.damage

	local modifier = self.behavior.modifyDamage

	if modifier ~= nil then
		damage = modifier(self, damage)
	end

	if damage > 0 then
		simulation:damage(targetId, damage, self.owner)
	end

	-- Effects land even on a killing blow. Harmless, and the alternative -
	-- checking liveness first - would make a bleed fail to transfer on a
	-- target that a splash killed in the same frame.
	for _, application in level.applies do
		simulation:applyEffect(targetId, application, self.owner)
	end
end

--- The default shot: single target, full damage. Splash towers replace this
--- wholesale through behavior.onFire.
function BaseTower.fire(
	self: Tower,
	simulation: EnemySimulation.Simulation,
	targetId: Types.EnemyId,
	targetPosition: Vector3
)
	local hook = self.behavior.onFire

	if hook ~= nil then
		hook(self, simulation, targetId, targetPosition)
	else
		self:dealDamage(simulation, targetId, 1)
	end

	self:beginReload()
end

return BaseTower

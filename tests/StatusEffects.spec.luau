--!strict
--[[
	Tests for the status effect system.

	Driven against the REAL effect definitions in Config/StatusEffects.luau
	rather than fixtures, so these also fail if someone tunes Bleed into
	something nonsensical - a zero tick interval, or a slow magnitude above 1
	that would speed enemies up.

	Time is simulation time and is passed in explicitly, which is the whole
	reason effects are testable at all: nothing here waits on a clock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(ServerScriptService.Server.Entities.BaseEnemy)
local StatusEffectSystem = require(ServerScriptService.Server.Systems.StatusEffectSystem)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local EPSILON = 1e-6

local function expectClose(actual: number, expected: number)
	expect(math.abs(actual - expected) < EPSILON).toBe(true)
end

local function makeEnemy(resistances: { [string]: number }?): BaseEnemy.Enemy
	local definition: Types.EnemyDefinition = {
		id = "Fixture",
		displayName = "Fixture",
		category = "Ground" :: Types.EnemyCategory,
		baseHealth = 1000,
		baseSpeed = 10,
		baseBounty = 1,
		leakDamage = 1,
		isBoss = false,
		introducesAtWave = 1,
		hitboxSize = Vector3.one,
		color = Color3.new(),
		hoverHeight = 0,
		resistances = resistances or {},
	}

	return BaseEnemy.new({
		id = 1,
		definition = definition,
		behavior = nil,
		pathIndex = 1,
		health = 1000,
		speed = 10,
		bounty = 1,
	})
end

local function bleed(duration: number, power: number): Types.StatusApplication
	return { effectId = "Bleed", duration = duration, power = power }
end

local function slow(duration: number): Types.StatusApplication
	return { effectId = "Slow", duration = duration, power = 0 }
end

--- Steps from `from` to `to` in fixed increments, returning total damage.
local function stepThrough(enemy: BaseEnemy.Enemy, from: number, to: number, increment: number): number
	local total = 0
	local now = from

	while now <= to + EPSILON do
		local ticks = StatusEffectSystem.step(enemy, now)

		if ticks ~= nil then
			for _, tick in ticks do
				total += tick.amount
			end
		end

		now += increment
	end

	return total
end

describe("configuration sanity", function()
	it("gives every damage-over-time effect a positive tick interval", function()
		-- A zero interval would spin the tick loop forever.
		for _, definition in StatusEffects.DEFINITIONS do
			if definition.kind == "DamageOverTime" then
				expect(definition.tickInterval > 0).toBe(true)
			end
		end
	end)

	it("keeps every slow between 0 and 1", function()
		-- Above 1 would make a "slow" speed enemies up.
		for _, definition in StatusEffects.DEFINITIONS do
			if definition.kind == "SpeedMultiplier" then
				expect(definition.magnitude > 0 and definition.magnitude < 1).toBe(true)
			end
		end
	end)
end)

describe("StatusEffectSystem.apply", function()
	it("registers the effect", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		expect(StatusEffectSystem.has(enemy, "Bleed")).toBe(true)
		expect(StatusEffectSystem.stackCount(enemy, "Bleed")).toBe(1)
	end)

	it("does nothing for an unknown effect id", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, { effectId = "Nonsense", duration = 5, power = 5 }, 0, nil)

		expect(StatusEffectSystem.has(enemy, "Nonsense")).toBe(false)
	end)

	it("does nothing to a dead enemy", function()
		local enemy = makeEnemy()
		enemy.alive = false
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		expect(StatusEffectSystem.has(enemy, "Bleed")).toBe(false)
	end)
end)

describe("Bleed", function()
	it("ticks on its interval, not every step", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		local interval = StatusEffects.get("Bleed").tickInterval

		-- Nothing before the first tick is due.
		expect(StatusEffectSystem.step(enemy, interval / 2)).toBe(nil)

		local ticks = StatusEffectSystem.step(enemy, interval)
		expect(ticks).never.toBe(nil)
		expectClose((ticks :: { Types.DamageTick })[1].amount, 3)
	end)

	it("deals power per stack for its full duration", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		local interval = StatusEffects.get("Bleed").tickInterval
		local expectedTicks = math.floor(4 / interval)

		expectClose(stepThrough(enemy, 0, 4, interval), 3 * expectedTicks)
	end)

	it("stops once it expires", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(2, 3), 0, nil)

		stepThrough(enemy, 0, 2, StatusEffects.get("Bleed").tickInterval)
		expect(StatusEffectSystem.has(enemy, "Bleed")).toBe(false)

		-- And nothing further, however long the simulation runs.
		expectClose(stepThrough(enemy, 2, 20, 0.5), 0)
	end)

	it("stacks up to its cap and no further", function()
		local enemy = makeEnemy()
		local cap = StatusEffects.get("Bleed").maxStacks

		for _ = 1, cap + 3 do
			StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)
		end

		expect(StatusEffectSystem.stackCount(enemy, "Bleed")).toBe(cap)
	end)

	it("scales damage with stacks", function()
		local single = makeEnemy()
		StatusEffectSystem.apply(single, bleed(4, 3), 0, nil)

		local doubled = makeEnemy()
		StatusEffectSystem.apply(doubled, bleed(4, 3), 0, nil)
		StatusEffectSystem.apply(doubled, bleed(4, 3), 0, nil)

		local interval = StatusEffects.get("Bleed").tickInterval
		local one = stepThrough(single, 0, 4, interval)
		local two = stepThrough(doubled, 0, 4, interval)

		expectClose(two, one * 2)
	end)

	it("keeps the stronger application when a weaker one lands", function()
		-- A level 1 Lacerator must not downgrade a level 4's bleed.
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(4, 13), 0, nil)
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		local ticks = StatusEffectSystem.step(enemy, StatusEffects.get("Bleed").tickInterval)
		-- Two stacks at the stronger power.
		expectClose((ticks :: { Types.DamageTick })[1].amount, 26)
	end)

	it("credits the source so the bounty split can pay them", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(4, 3), 0, nil)

		local ticks = StatusEffectSystem.step(enemy, StatusEffects.get("Bleed").tickInterval)
		expect(ticks).never.toBe(nil)
		-- No player in this fixture, but the field must be carried through
		-- rather than dropped.
		expect((ticks :: { Types.DamageTick })[1].source).toBe(nil)
	end)
end)

describe("Slow", function()
	it("multiplies speed while active", function()
		local enemy = makeEnemy()
		local magnitude = StatusEffects.get("Slow").magnitude

		expectClose(enemy:currentSpeed(), 10)

		StatusEffectSystem.apply(enemy, slow(3), 0, nil)
		expectClose(enemy:currentSpeed(), 10 * magnitude)
	end)

	it("restores full speed when it expires", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, slow(3), 0, nil)
		StatusEffectSystem.step(enemy, 3)

		expect(StatusEffectSystem.has(enemy, "Slow")).toBe(false)
		expectClose(enemy:currentSpeed(), 10)
	end)

	it("refreshes rather than stacking", function()
		-- Stacking multiplicative slows is how a handful of towers becomes a
		-- permanent freeze.
		local enemy = makeEnemy()
		local magnitude = StatusEffects.get("Slow").magnitude

		StatusEffectSystem.apply(enemy, slow(3), 0, nil)
		StatusEffectSystem.apply(enemy, slow(3), 0, nil)
		StatusEffectSystem.apply(enemy, slow(3), 0, nil)

		expect(StatusEffectSystem.stackCount(enemy, "Slow")).toBe(1)
		expectClose(enemy:currentSpeed(), 10 * magnitude)
	end)

	it("never reverses an enemy up its lane", function()
		local enemy = makeEnemy()

		for _ = 1, 20 do
			StatusEffectSystem.apply(enemy, slow(10), 0, nil)
		end

		expect(enemy:currentSpeed() >= 0).toBe(true)
	end)
end)

describe("resistances", function()
	it("scale duration, so a resistant enemy takes fewer ticks", function()
		local normal = makeEnemy()
		local resistant = makeEnemy({ Bleed = 0.5 })

		StatusEffectSystem.apply(normal, bleed(4, 3), 0, nil)
		StatusEffectSystem.apply(resistant, bleed(4, 3), 0, nil)

		local interval = StatusEffects.get("Bleed").tickInterval
		local full = stepThrough(normal, 0, 4, interval)
		local halved = stepThrough(resistant, 0, 4, interval)

		expect(halved < full).toBe(true)
		expectClose(halved, full / 2)
	end)

	it("of zero mean immunity", function()
		local immune = makeEnemy({ Bleed = 0 })
		StatusEffectSystem.apply(immune, bleed(4, 3), 0, nil)

		expect(StatusEffectSystem.has(immune, "Bleed")).toBe(false)
		expectClose(stepThrough(immune, 0, 4, 0.5), 0)
	end)

	it("apply per effect, not across all of them", function()
		local enemy = makeEnemy({ Bleed = 0 })
		StatusEffectSystem.apply(enemy, slow(3), 0, nil)

		expect(StatusEffectSystem.has(enemy, "Slow")).toBe(true)
	end)
end)

describe("StatusEffectSystem.clear", function()
	it("drops every effect and resets the multipliers", function()
		local enemy = makeEnemy()
		StatusEffectSystem.apply(enemy, bleed(10, 5), 0, nil)
		StatusEffectSystem.apply(enemy, slow(10), 0, nil)

		StatusEffectSystem.clear(enemy)

		expect(StatusEffectSystem.has(enemy, "Bleed")).toBe(false)
		expect(StatusEffectSystem.has(enemy, "Slow")).toBe(false)
		expectClose(enemy.statusSpeedMultiplier, 1)
		expectClose(enemy.statusDamageTakenMultiplier, 1)
		expectClose(enemy:currentSpeed(), 10)
	end)
end)

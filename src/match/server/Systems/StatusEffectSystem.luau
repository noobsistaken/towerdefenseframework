--!strict
--[[
	Applies, ticks and expires status effects.

	Pure with respect to the world: it takes an enemy and a simulation time,
	mutates the enemy's effect tables, and RETURNS the damage it wants dealt
	rather than dealing it. Damage goes back through EnemySimulation.damage so
	a bleed kill fires exactly the same death path as a bullet kill - bounty
	split, listeners, removal. An effect that killed things by writing to
	`health` directly would silently skip all of it.

	All times are simulation time, advanced in fixed steps, so effects expire
	and tick identically at any server frame rate and a test can drive them
	exactly.

	Storage is a list per effect id. Refresh and Stack keep exactly one entry
	in that list; Independent appends. Modelling all three the same way is why
	adding a poison that stacks independently needs no code here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)

local StatusEffectSystem = {}

--- Recomputes the cached speed and damage-taken products.
---
--- Multiplicative, and per stack, so two 30% slows leave 49% speed rather
--- than stopping the enemy dead. Additive stacking is how a handful of slow
--- towers becomes an accidental permanent freeze.
function StatusEffectSystem.refreshMultipliers(enemy: BaseEnemy.Enemy)
	local speed = 1
	local damageTaken = 1

	for effectId, instances in enemy.effects do
		local definition = StatusEffects.find(effectId)

		if definition == nil then
			continue
		end

		for _, instance in instances do
			if definition.kind == "SpeedMultiplier" then
				speed *= definition.magnitude ^ instance.stacks
			elseif definition.kind == "DamageTakenMultiplier" then
				damageTaken *= definition.magnitude ^ instance.stacks
			elseif definition.kind == "Stun" then
				speed = 0
			end
		end
	end

	enemy.statusSpeedMultiplier = speed
	enemy.statusDamageTakenMultiplier = damageTaken
end

--- Applies one effect to one enemy.
---
--- Resistance scales DURATION, not magnitude, so a resistant enemy takes the
--- same hit for less time. A resistance of 0 is immunity and is handled here
--- rather than by every caller.
function StatusEffectSystem.apply(
	enemy: BaseEnemy.Enemy,
	application: Types.StatusApplication,
	now: number,
	source: Player?
)
	if not enemy.alive then
		return
	end

	local definition = StatusEffects.find(application.effectId)

	if definition == nil then
		return
	end

	local resistance = enemy.definition.resistances[application.effectId]
	local multiplier = if resistance ~= nil then resistance else 1
	local duration = application.duration * multiplier

	if duration <= 0 then
		return
	end

	local expiresAt = now + duration
	local instances = enemy.effects[application.effectId]

	if instances == nil then
		instances = {}
		enemy.effects[application.effectId] = instances
	end

	local list: { Types.ActiveStatusEffect } = instances
	local existing = list[1]

	if definition.stacking == "Independent" or existing == nil then
		table.insert(list, {
			effectId = application.effectId,
			stacks = 1,
			expiresAt = expiresAt,
			nextTickAt = now + math.max(definition.tickInterval, 0),
			power = application.power,
			source = source,
		})
	elseif definition.stacking == "Stack" then
		existing.stacks = math.min(existing.stacks + 1, math.max(1, definition.maxStacks))
		existing.expiresAt = expiresAt
		-- Keep the stronger application. A level 4 Lacerator's bleed should
		-- not be downgraded by a level 1 landing a hit on the same target.
		existing.power = math.max(existing.power, application.power)
		existing.source = source
	else
		-- Refresh: one instance, timer reset, strength replaced.
		existing.stacks = 1
		existing.expiresAt = expiresAt
		existing.power = application.power
		existing.source = source
	end

	StatusEffectSystem.refreshMultipliers(enemy)
end

--- Advances every effect on one enemy to `now`.
---
--- Returns the damage owed, or nil when nothing ticked - which is the common
--- case, since a 0.5s tick interval against a 1/30s step means 29 of every 30
--- calls produce nothing and should not allocate.
function StatusEffectSystem.step(enemy: BaseEnemy.Enemy, now: number): { Types.DamageTick }?
	local ticks: { Types.DamageTick }? = nil
	local changed = false

	for effectId, instances in enemy.effects do
		local definition = StatusEffects.find(effectId)

		if definition == nil then
			enemy.effects[effectId] = nil
			changed = true
			continue
		end

		local isDamageOverTime = definition.kind == "DamageOverTime"
		local interval = definition.tickInterval

		-- Iterated backwards so removing an expired instance cannot skip the
		-- next one.
		for index = #instances, 1, -1 do
			local instance = instances[index]

			-- A non-positive interval would spin forever below. Config should
			-- never produce one, so this is a guard rather than a behaviour.
			if isDamageOverTime and interval > 0 then
				while instance.nextTickAt <= now and instance.nextTickAt <= instance.expiresAt do
					local amount = instance.power * instance.stacks

					if amount > 0 then
						if ticks == nil then
							ticks = {}
						end

						local list: { Types.DamageTick } = ticks :: { Types.DamageTick }
						table.insert(list, { amount = amount, source = instance.source })
					end

					instance.nextTickAt += interval
				end
			end

			if now >= instance.expiresAt then
				table.remove(instances, index)
				changed = true
			end
		end

		if #instances == 0 then
			enemy.effects[effectId] = nil
			changed = true
		end
	end

	if changed then
		StatusEffectSystem.refreshMultipliers(enemy)
	end

	return ticks
end

--- True if any instance of `effectId` is active. Used by the client tint and
--- by tests.
function StatusEffectSystem.has(enemy: BaseEnemy.Enemy, effectId: string): boolean
	local instances = enemy.effects[effectId]
	return instances ~= nil and #instances > 0
end

--- Total stacks of `effectId` across every instance.
function StatusEffectSystem.stackCount(enemy: BaseEnemy.Enemy, effectId: string): number
	local instances = enemy.effects[effectId]

	if instances == nil then
		return 0
	end

	local total = 0

	for _, instance in instances do
		total += instance.stacks
	end

	return total
end

--- Drops every effect and resets the cached multipliers.
function StatusEffectSystem.clear(enemy: BaseEnemy.Enemy)
	enemy.effects = {}
	enemy.statusSpeedMultiplier = 1
	enemy.statusDamageTakenMultiplier = 1
end

return StatusEffectSystem

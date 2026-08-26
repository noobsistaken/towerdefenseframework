--!strict
--[[
	Config-integrity tests for tower abilities.

	An ability is a balance surface wired straight into the simulation, so
	a wrong field is not a cosmetic bug: a FreezeBurst naming a dead effect
	silently does nothing, an Overcharge with power below one is a button
	that makes your tower WORSE, and a cooldown of zero is a key to hold
	down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local KINDS: { [string]: boolean } = {
	Barrage = true,
	Overcharge = true,
	FreezeBurst = true,
	Payday = true,
}

describe("Tower abilities", function()
	it("exist on a flagship handful, each with a unique id", function()
		local seen: { [string]: string } = {}
		local count = 0

		for _, id in Towers.IDS do
			local ability = Towers.get(id).ability

			if ability ~= nil then
				count += 1
				expect(seen[ability.id]).toBeNil()
				seen[ability.id] = id
			end
		end

		expect(count >= 5).toBe(true)
		-- Flagships, not a keyboard: most towers must NOT have one.
		expect(count <= 10).toBe(true)
	end)

	it("keeps every field the right shape for its kind", function()
		for _, id in Towers.IDS do
			local ability = Towers.get(id).ability

			if ability == nil then
				continue
			end

			expect(KINDS[ability.kind]).toBe(true)
			expect(#ability.displayName > 0).toBe(true)
			expect(#ability.description > 0).toBe(true)

			-- A cooldown short enough to hold down is a passive stat
			-- pretending to be a button; one over three minutes is a button
			-- nobody presses twice.
			expect(ability.cooldownSeconds >= 10).toBe(true)
			expect(ability.cooldownSeconds <= 180).toBe(true)

			if ability.kind == "Barrage" then
				expect(ability.power > 0).toBe(true)
				expect(ability.strikes >= 1).toBe(true)
			elseif ability.kind == "Overcharge" then
				-- Below one would make the button a downgrade.
				expect(ability.power > 1).toBe(true)
				expect(ability.durationSeconds > 0).toBe(true)
				-- The boost must not outlast its own cooldown, or it is not
				-- an ability - it is a permanent stat with a ritual.
				expect(ability.durationSeconds < ability.cooldownSeconds).toBe(true)
			elseif ability.kind == "FreezeBurst" then
				local effectId = ability.effectId

				expect(effectId).never.toBeNil()
				expect(StatusEffects.find(effectId :: string)).never.toBeNil()
				expect(ability.durationSeconds > 0).toBe(true)
				-- One-shot bursts stay short: a Stun-kind burst over two
				-- seconds on a 40s cooldown starts competing with Concuss's
				-- permafreeze invariant from the other direction.
				expect(ability.durationSeconds <= 5).toBe(true)
			elseif ability.kind == "Payday" then
				expect(ability.power > 0).toBe(true)
			end
		end
	end)
end)

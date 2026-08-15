--!strict
--[[
	Tests for the difficulty curves.

	Balance is one of the few things static analysis provably cannot check, so
	these assert the SHAPE of each curve rather than specific tuned numbers.
	Asserting exact values would mean every balance tweak breaks the suite,
	which trains you to update tests without reading them.

	The one that matters most is the bounty relationship. If bounty ever grows
	as fast as health, late waves print money, every tower gets maxed, and the
	difficulty collapses exactly where it should peak. That failure is
	invisible until someone plays to wave 35.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Scaling = require(ReplicatedStorage.Shared.Scaling)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Scaling: wave 1 is the fixed point", function()
	-- The numbers written in Config/Enemies.luau should mean literally what
	-- they say at wave 1. If any curve moved off 1.0 here, every authored
	-- value in config would silently mean something else.
	it("leaves health untouched", function()
		expect(Scaling.healthFactor(1)).toBe(1)
		expect(Scaling.enemyHealth(100, 1, 1)).toBe(100)
	end)

	it("leaves count untouched", function()
		expect(Scaling.enemyCount(6, 1)).toBe(6)
	end)

	it("leaves bounty untouched", function()
		expect(Scaling.bounty(10, 1, 1)).toBe(10)
	end)
end)

describe("Scaling.enemyHealth", function()
	it("increases every single wave", function()
		local previous = 0

		for wave = 1, 60 do
			local health = Scaling.enemyHealth(100, wave, 1)
			expect(health > previous).toBe(true)
			previous = health
		end
	end)

	it("escalates rather than plateaus over a full run", function()
		-- A 30-50 wave run has to feel like it is going somewhere. An order
		-- of magnitude by wave 40 is the floor for that.
		local ratio = Scaling.enemyHealth(100, 40, 1) / Scaling.enemyHealth(100, 1, 1)
		expect(ratio > 10).toBe(true)
	end)

	it("respects the difficulty multiplier", function()
		expect(Scaling.enemyHealth(100, 5, 2) > Scaling.enemyHealth(100, 5, 1)).toBe(true)
	end)

	it("never returns less than one health", function()
		expect(Scaling.enemyHealth(1, 1, 0) >= 1).toBe(true)
	end)
end)

describe("Scaling.bounty", function()
	it("grows strictly slower than health", function()
		-- THE load-bearing assertion in this file. Income must fall behind
		-- threat across the whole run, at every wave, not just on average.
		for wave = 2, 60 do
			local healthRatio = Scaling.enemyHealth(100, wave, 1) / 100
			local bountyRatio = Scaling.bounty(100, wave, 1) / 100

			expect(bountyRatio < healthRatio).toBe(true)
		end
	end)

	it("still grows", function()
		-- Falling behind is the goal; going flat or backwards is not, or
		-- late waves would be unaffordable rather than merely tight.
		expect(Scaling.bounty(10, 30, 1) > Scaling.bounty(10, 10, 1)).toBe(true)
	end)
end)

describe("Scaling.enemyCount", function()
	it("grows more slowly than health", function()
		-- Health carries difficulty, count carries texture. Scaling both hard
		-- produces a wave 40 that is unkillable AND a performance problem.
		local countRatio = Scaling.enemyCount(100, 30) / 100
		local healthRatio = Scaling.enemyHealth(100, 30, 1) / 100

		expect(countRatio < healthRatio).toBe(true)
	end)

	it("never exceeds the per-wave ceiling", function()
		-- The ceiling is a performance guard, so it has to hold at absurd
		-- wave numbers, not just plausible ones.
		for _, wave in { 50, 100, 500 } do
			expect(Scaling.enemyCount(200, wave) <= Scaling.MAX_ENEMIES_PER_WAVE).toBe(true)
		end
	end)

	it("always spawns at least one", function()
		expect(Scaling.enemyCount(1, 1) >= 1).toBe(true)
	end)
end)

describe("Scaling.isBossWave", function()
	it("fires on the interval and nowhere else", function()
		expect(Scaling.isBossWave(10)).toBe(true)
		expect(Scaling.isBossWave(20)).toBe(true)
		expect(Scaling.isBossWave(9)).toBe(false)
		expect(Scaling.isBossWave(11)).toBe(false)
	end)

	it("is false at wave zero", function()
		-- 0 % 10 == 0, so this needs the explicit guard and would otherwise
		-- report a boss wave before the match has started.
		expect(Scaling.isBossWave(0)).toBe(false)
	end)
end)

describe("Scaling endless mode", function()
	local FINAL = 40

	it("leaves the campaign completely untouched", function()
		-- Endless existing must not change campaign balance by even a hair.
		for wave = 1, FINAL do
			expect(Scaling.endlessFactor(wave, FINAL)).toBe(1)
			expect(Scaling.isEndlessWave(wave, FINAL)).toBe(false)
		end
	end)

	it("compounds past the final wave", function()
		expect(Scaling.isEndlessWave(FINAL + 1, FINAL)).toBe(true)
		expect(Scaling.endlessFactor(FINAL + 1, FINAL) > 1).toBe(true)
		expect(Scaling.endlessFactor(FINAL + 10, FINAL) > Scaling.endlessFactor(FINAL + 1, FINAL)).toBe(true)
	end)

	it("climbs faster than the campaign did", function()
		-- Endless is meant to find where a defence breaks, not to be survived
		-- indefinitely. Matching the campaign slope would take hundreds of
		-- waves to do that.
		local campaignStep = Scaling.healthFactor(11) / Scaling.healthFactor(10)
		local endlessStep = (Scaling.healthFactor(FINAL + 11) * Scaling.endlessFactor(FINAL + 11, FINAL))
			/ (Scaling.healthFactor(FINAL + 10) * Scaling.endlessFactor(FINAL + 10, FINAL))

		expect(endlessStep > campaignStep).toBe(true)
	end)
end)

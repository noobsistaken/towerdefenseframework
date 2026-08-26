--!strict
--[[
	Config-integrity tests for the full tower roster.

	Twenty-six towers is past the point where a human eyeballs the table and
	catches the wrong number. These tests encode the STRUCTURE every entry
	must have; they deliberately do not encode a full effectiveness model,
	because splash, status effects and range premiums make a single DPS band
	a lie. What a band CAN catch is a magnitude typo - damage 400 where 40
	was meant - so pure single-target towers get exactly that.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("Tower roster structure", function()
	it("holds the full expanded roster", function()
		expect(#Towers.IDS).toBe(26)
	end)

	it("gives every tower a real rarity tier", function()
		for _, id in Towers.IDS do
			expect(Rarity.find(Towers.get(id).rarity)).never.toBeNil()
		end
	end)

	it("populates every tier, pyramid-style", function()
		local counts: { [string]: number } = {}

		for _, id in Towers.IDS do
			local rarity = Towers.get(id).rarity
			counts[rarity] = (counts[rarity] or 0) + 1
		end

		for _, tierId in Rarity.IDS do
			local count: number? = counts[tierId]

			expect(count).never.toBeNil()
			-- Common is the widest tier; nothing above it may outnumber it.
			expect((count :: number) <= (counts.Common :: number)).toBe(true)
		end
	end)

	it("keeps id, key and displayName coherent", function()
		for key, definition in Towers.DEFINITIONS do
			expect(definition.id).toBe(key)
			expect(#definition.displayName > 0).toBe(true)
			expect(#definition.description > 0).toBe(true)
		end
	end)

	it("gives every tower at least three levels and a sane footprint", function()
		for _, id in Towers.IDS do
			local definition = Towers.get(id)

			expect(#definition.levels >= 3).toBe(true)
			expect(definition.footprint.X > 0).toBe(true)
			expect(definition.footprint.Y > 0).toBe(true)
			expect(definition.perPlayerCap >= 0).toBe(true)
			expect(Targeting.isValid(definition.defaultTargeting)).toBe(true)
		end
	end)
end)

describe("Tower level tables", function()
	it("keeps every number the right sign and shape", function()
		for _, id in Towers.IDS do
			for _, level in Towers.get(id).levels do
				expect(level.cost > 0).toBe(true)
				expect(level.damage >= 0).toBe(true)
				expect(level.fireRate > 0).toBe(true)
				expect(level.range > 0).toBe(true)
				expect(level.splashRadius >= 0).toBe(true)
				expect(level.modelSize.X > 0).toBe(true)
				expect(level.modelSize.Y > 0).toBe(true)
				expect(level.modelSize.Z > 0).toBe(true)
			end
		end
	end)

	it("makes every upgrade an upgrade: DPS strictly up, range never down", function()
		for _, id in Towers.IDS do
			local levels = Towers.get(id).levels

			for index = 2, #levels do
				local previous = levels[index - 1]
				local current = levels[index]

				local previousDps = previous.damage * previous.fireRate
				local currentDps = current.damage * current.fireRate

				expect(currentDps > previousDps).toBe(true)
				expect(current.range >= previous.range).toBe(true)
				expect(current.splashRadius >= previous.splashRadius).toBe(true)
			end
		end
	end)

	it("references only real status effects, with sane applications", function()
		for _, id in Towers.IDS do
			for _, level in Towers.get(id).levels do
				for _, application in level.applies do
					local effect = StatusEffects.find(application.effectId)

					expect(effect).never.toBeNil()
					expect(application.duration > 0).toBe(true)

					if effect == nil then
						continue
					end

					-- power drives DamageOverTime and nothing else; a power on
					-- a multiplier effect would be a number silently ignored.
					if effect.kind == "DamageOverTime" then
						expect(application.power > 0).toBe(true)
					else
						expect(application.power).toBe(0)
					end
				end
			end
		end
	end)

	it("keeps pure single-target openers inside the typo band", function()
		-- Only towers with no splash and no status at level 1: everything
		-- else legitimately trades raw DPS for utility, and pricing that
		-- trade is design, not a spec's business.
		for _, id in Towers.IDS do
			local first = Towers.get(id).levels[1]

			if first.splashRadius == 0 and #first.applies == 0 then
				local efficiency = first.damage * first.fireRate / first.cost

				expect(efficiency >= 0.05).toBe(true)
				expect(efficiency <= 0.15).toBe(true)
			end
		end
	end)
end)

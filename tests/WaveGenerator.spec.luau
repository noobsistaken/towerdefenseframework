--!strict
--[[
	Tests for wave composition and scheduling.

	The difficulty config is built here rather than read from
	Config/Difficulty.luau on purpose: these assertions are about the
	generator's behaviour, and pulling in live balance values would make a
	tuning change break tests that have nothing to do with tuning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Scaling = require(ReplicatedStorage.Shared.Scaling)
local Types = require(ReplicatedStorage.Shared.Types)
local WaveGenerator = require(ReplicatedStorage.Shared.WaveGenerator)
local WavesConfig = require(ReplicatedStorage.Shared.Config.Waves)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local FINAL_WAVE = 40

local DIFFICULTY: Types.DifficultyConfig = {
	id = "TestNormal",
	displayName = "Test Normal",
	startingCash = 500,
	baseHealth = 100,
	healthMultiplier = 1,
	rewardMultiplier = 1,
	finalWave = FINAL_WAVE,
}

--- How many entries of one enemy id a plan contains.
local function countOf(plan: { WaveGenerator.PlanEntry }, enemyId: string): number
	local total = 0

	for _, entry in plan do
		if entry.enemyId == enemyId then
			total += 1
		end
	end

	return total
end

describe("WaveGenerator: authored waves", function()
	it("reproduces an authored roster exactly", function()
		-- Authored counts are literal and must NOT be scaled - that is the
		-- entire reason for authoring them.
		local plan = WaveGenerator.generate(1, DIFFICULTY, 1)

		expect(#plan).toBe(6)
		expect(countOf(plan, "Zombie")).toBe(6)
	end)

	it("introduces one new idea at a time", function()
		-- Waves 1-3 are Zombies only. A Runner leaking into wave 2 would mean
		-- the player meets two mechanics before understanding either.
		for wave = 1, 3 do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)
			expect(countOf(plan, "Zombie")).toBe(#plan)
		end

		expect(countOf(WaveGenerator.generate(4, DIFFICULTY, 1), "Runner") > 0).toBe(true)
		expect(countOf(WaveGenerator.generate(7, DIFFICULTY, 1), "Tank") > 0).toBe(true)
		expect(countOf(WaveGenerator.generate(8, DIFFICULTY, 1), "Drifter") > 0).toBe(true)
	end)

	it("puts the Titan on the authored boss wave", function()
		expect(countOf(WaveGenerator.generate(10, DIFFICULTY, 1), "Titan")).toBe(1)
		expect(countOf(WaveGenerator.generate(9, DIFFICULTY, 1), "Titan")).toBe(0)
		expect(countOf(WaveGenerator.generate(11, DIFFICULTY, 1), "Titan")).toBe(0)
	end)
end)

describe("WaveGenerator: rules path", function()
	local BEYOND = WavesConfig.HIGHEST_AUTHORED_WAVE + 1

	it("takes over past the authored range", function()
		expect(#WaveGenerator.generate(BEYOND, DIFFICULTY, 1) > 0).toBe(true)
	end)

	it("never spawns a type before its introduction wave", function()
		-- Checked across the rules range specifically, since the authored
		-- table is allowed to override this and the rules path is not.
		for wave = BEYOND, 60 do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)

			for _, entry in plan do
				local definition = Enemies.get(entry.enemyId)
				expect(wave >= definition.introducesAtWave).toBe(true)
			end
		end
	end)

	it("gates bosses to boss waves", function()
		for wave = BEYOND, 60 do
			if Scaling.isBossWave(wave) then
				continue
			end

			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)

			for _, entry in plan do
				expect(Enemies.get(entry.enemyId).isBoss).toBe(false)
			end
		end
	end)

	it("holds bosses back behind the chaff", function()
		-- A boss that arrives first gets focused down before anything else
		-- shows up, which inverts the point of a boss wave.
		local plan = WaveGenerator.generate(50, DIFFICULTY, 1)

		local lastRegular = -1
		local firstBoss = math.huge

		for _, entry in plan do
			if Enemies.get(entry.enemyId).isBoss then
				firstBoss = math.min(firstBoss, entry.at)
			else
				lastRegular = math.max(lastRegular, entry.at)
			end
		end

		expect(firstBoss > lastRegular).toBe(true)
	end)
end)

describe("WaveGenerator: scheduling", function()
	it("returns a time-ordered plan", function()
		-- The director walks the plan with a forward-only cursor, so an
		-- out-of-order entry would silently never spawn.
		for _, wave in { 1, 8, 10, 25, 47 } do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 2)
			local previous = -1

			for _, entry in plan do
				expect(entry.at >= previous).toBe(true)
				previous = entry.at
			end
		end
	end)

	it("feeds every lane", function()
		local plan = WaveGenerator.generate(12, DIFFICULTY, 3)
		local seen: { [number]: boolean } = {}

		for _, entry in plan do
			seen[entry.pathIndex] = true
			expect(entry.pathIndex >= 1 and entry.pathIndex <= 3).toBe(true)
		end

		expect(seen[1] and seen[2] and seen[3]).toBe(true)
	end)

	it("rejects a nonsensical lane count", function()
		expect(function()
			WaveGenerator.generate(1, DIFFICULTY, 0)
		end).toThrow()
	end)

	it("is deterministic", function()
		-- Two servers running the same build must produce the same wave, so
		-- this has to survive the unsorted pairs() order of the config tables.
		for _, wave in { 4, 10, 33 } do
			local first = WaveGenerator.generate(wave, DIFFICULTY, 2)
			local second = WaveGenerator.generate(wave, DIFFICULTY, 2)

			expect(#first).toBe(#second)

			for index, entry in first do
				expect(entry.enemyId).toBe(second[index].enemyId)
				expect(entry.at).toBe(second[index].at)
				expect(entry.pathIndex).toBe(second[index].pathIndex)
				expect(entry.health).toBe(second[index].health)
			end
		end
	end)
end)

describe("WaveGenerator: endless mode", function()
	it("leaves campaign waves unscaled", function()
		local plan = WaveGenerator.generate(FINAL_WAVE, DIFFICULTY, 1)
		local zombie = Enemies.get("Zombie")
		local relative = FINAL_WAVE - zombie.introducesAtWave + 1

		for _, entry in plan do
			if entry.enemyId == "Zombie" then
				expect(entry.health).toBe(Scaling.enemyHealth(zombie.baseHealth, relative, 1))
				break
			end
		end
	end)

	it("scales health harder past the final wave", function()
		local function zombieHealth(wave: number): number
			for _, entry in WaveGenerator.generate(wave, DIFFICULTY, 1) do
				if entry.enemyId == "Zombie" then
					return entry.health
				end
			end

			return 0
		end

		local atFinal = zombieHealth(FINAL_WAVE)
		local justPast = zombieHealth(FINAL_WAVE + 1)
		local wellPast = zombieHealth(FINAL_WAVE + 10)

		expect(atFinal > 0).toBe(true)
		expect(justPast > atFinal).toBe(true)
		expect(wellPast > justPast).toBe(true)
	end)

	it("does not inflate bounty along with health", function()
		-- Endless must not become a cash faucet, or surviving it stops being
		-- about the defence you built and starts being about income.
		local function zombieBounty(wave: number): number
			for _, entry in WaveGenerator.generate(wave, DIFFICULTY, 1) do
				if entry.enemyId == "Zombie" then
					return entry.bounty
				end
			end

			return 0
		end

		local zombie = Enemies.get("Zombie")
		local wave = FINAL_WAVE + 10
		local relative = wave - zombie.introducesAtWave + 1

		expect(zombieBounty(wave)).toBe(Scaling.bounty(zombie.baseBounty, relative, 1))
	end)
end)

describe("WaveGenerator: the per-wave ceiling", function()
	it("is never exceeded by regular enemies", function()
		for _, wave in { 60, 120, 300 } do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)
			local regulars = 0

			for _, entry in plan do
				if not Enemies.get(entry.enemyId).isBoss then
					regulars += 1
				end
			end

			expect(regulars <= Scaling.MAX_ENEMIES_PER_WAVE).toBe(true)
		end
	end)

	it("never drops the boss to make room", function()
		-- A boss wave that silently loses its boss because chaff filled the
		-- budget is the worst possible failure of the cap.
		local plan = WaveGenerator.generate(300, DIFFICULTY, 1)
		local bosses = 0

		for _, entry in plan do
			if Enemies.get(entry.enemyId).isBoss then
				bosses += 1
			end
		end

		expect(bosses > 0).toBe(true)
	end)
end)
describe("Air arrives in three escalating shapes", function()
	it("introduces each flyer on the wave its config claims", function()
		-- Waves 1-13 are hand-authored and OVERRIDE the rules path entirely,
		-- so an air type with introducesAtWave = 12 appears then only because
		-- wave 12 authors it. Getting this wrong fails silently as "the
		-- config says 12 but I never see one until 14".
		expect(countOf(WaveGenerator.generate(8, DIFFICULTY, 1), "Drifter") > 0).toBe(true)
		expect(countOf(WaveGenerator.generate(12, DIFFICULTY, 1), "Wisp") > 0).toBe(true)
		expect(countOf(WaveGenerator.generate(18, DIFFICULTY, 1), "Zeppelin") > 0).toBe(true)
	end)

	it("holds each flyer back until its own wave", function()
		expect(countOf(WaveGenerator.generate(7, DIFFICULTY, 1), "Drifter")).toBe(0)
		expect(countOf(WaveGenerator.generate(11, DIFFICULTY, 1), "Wisp")).toBe(0)
		expect(countOf(WaveGenerator.generate(17, DIFFICULTY, 1), "Zeppelin")).toBe(0)
	end)

	it("never lets air take over a wave outright", function()
		-- Air is pressure, not the whole game. Before the budget was shared
		-- proportionally this reached 97% by wave 100.
		for _, wave in { 20, 40, 66, 100, 140 } do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)
			local air = 0

			for _, entry in plan do
				if Enemies.get(entry.enemyId).category == "Air" then
					air += 1
				end
			end

			expect(air < #plan * 0.6).toBe(true)
		end
	end)
end)

describe("The per-wave ceiling shares out, rather than going first-come", function()
	-- Every assertion here FAILED before the budget was made proportional.
	-- The ceiling used to be spent by whichever type came first in
	-- Enemies.IDS, which is alphabetical: measured on the real config,
	-- wave 66 emitted zero Zombies, wave 80 zero Tanks, and wave 100 was
	-- 214 Drifters and 6 Titans - 97% air - purely because "Drifter" sorts
	-- before "Zombie". An enemy's NAME decided whether it existed.
	local CAPPED_WAVES = { 66, 80, 100, 140 }

	it("never starves a type out of a capped wave", function()
		for _, wave in CAPPED_WAVES do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)

			for _, id in Enemies.IDS do
				local definition = Enemies.get(id)

				-- Bosses are reserved out of the budget separately, and only
				-- appear on boss waves.
				if definition.isBoss or WavesConfig.BASE_COUNTS[id] == nil then
					continue
				end

				if wave >= definition.introducesAtWave then
					expect(countOf(plan, id) > 0).toBe(true)
				end
			end
		end
	end)

	it("lets no single type run away with the wave", function()
		-- Drifter reached 97% before the fix. Half is far looser than the
		-- proportional split actually produces, and still catches a
		-- runaway.
		for _, wave in CAPPED_WAVES do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)

			for _, id in Enemies.IDS do
				if not Enemies.get(id).isBoss then
					expect(countOf(plan, id) <= #plan * 0.5).toBe(true)
				end
			end
		end
	end)

	it("still respects the ceiling it is sharing out", function()
		for _, wave in CAPPED_WAVES do
			local plan = WaveGenerator.generate(wave, DIFFICULTY, 1)

			expect(#plan <= Scaling.MAX_ENEMIES_PER_WAVE + Scaling.MAX_BOSSES_PER_WAVE).toBe(true)
		end
	end)

	it("keeps the bigger request bigger", function()
		-- The point of proportional sharing: scaling down must not reorder
		-- who is most numerous. Zombie has grown since wave 1 and Drifter
		-- only since wave 8, so Zombie asks for more and must stay ahead.
		--
		-- Wave 66 rather than 100 deliberately. Scaling.enemyCount clamps
		-- EACH type at MAX_ENEMIES_PER_WAVE, so deep enough into endless
		-- every type asks for the same 220 and an even split is the correct
		-- answer - there is no "bigger request" left to preserve. Asserting
		-- this at wave 100 would be asserting a tie-break, not a property.
		local plan = WaveGenerator.generate(66, DIFFICULTY, 1)

		expect(countOf(plan, "Zombie") > countOf(plan, "Drifter")).toBe(true)
	end)
end)

describe("A wave arrives mixed, not in blocks", function()
	it("interleaves its types instead of emptying one at a time", function()
		-- The module always claimed to interleave, and never did: types were
		-- emitted one at a time against a clock that only moved forward, so
		-- the sort afterwards had nothing left to reorder. Every wave came
		-- as one block per type - all the Drifters, then all the Runners.
		local plan = WaveGenerator.generate(40, DIFFICULTY, 1)
		local seen: { [string]: boolean } = {}
		local distinct = 0

		for index = 1, math.min(12, #plan) do
			local id = plan[index].enemyId

			if not seen[id] then
				seen[id] = true
				distinct += 1
			end
		end

		expect(distinct >= 2).toBe(true)
	end)

	it("spreads a type across the wave rather than clumping it at the front", function()
		local plan = WaveGenerator.generate(40, DIFFICULTY, 1)
		local total = countOf(plan, "Drifter")

		expect(total > 0).toBe(true)

		-- With an even spread, roughly half of any type lands in the back
		-- half of the wave. Before the fix every Drifter was in the first
		-- block, so the back half held none at all.
		local half = math.floor(#plan / 2)
		local late = 0

		for index = half + 1, #plan do
			if plan[index].enemyId == "Drifter" then
				late += 1
			end
		end

		expect(late > 0).toBe(true)
	end)
end)

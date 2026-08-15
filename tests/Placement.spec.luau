--!strict
--[[
	Tests for tower placement rules.

	This is the module that stands between the game and an exploiter, so it
	gets the most adversarial tests in the suite. Every case here is phrased as
	"what would a malicious or confused client send", not "what does the happy
	path do".

	Map and tower fixtures are built here rather than read from live config on
	purpose: these assert the RULES, and pulling in real balance values would
	make a tuning change break tests that have nothing to do with tuning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Placement = require(ReplicatedStorage.Shared.Placement)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local COST = 100

local function towerDef(
	id: string,
	category: Types.TowerCategory,
	footprint: number,
	perPlayerCap: number
): Types.TowerDefinition
	return {
		id = id,
		displayName = id,
		description = "",
		category = category,
		targets = "Both" :: Types.TargetClass,
		footprint = Vector2.new(footprint, footprint),
		defaultTargeting = "First" :: Types.TargetingMode,
		perPlayerCap = perPlayerCap,
		levels = {
			{
				cost = COST,
				damage = 1,
				fireRate = 1,
				range = 10,
				splashRadius = 0,
				applies = {},
				modelSize = Vector3.one,
				color = Color3.new(),
			},
		},
	}
end

local GROUND_TOWER = towerDef("G", "Ground", 6, 0)
local HILLSIDE_TOWER = towerDef("H", "Hillside", 6, 0)
local HYBRID_TOWER = towerDef("Y", "Hybrid", 6, 0)

--- Apron top sits at y = 1, plateau top at y = 12, and the plateau sits
--- ENTIRELY INSIDE the apron in XZ. That containment is the whole point of
--- this fixture - it is the shape that broke in play.
local APRON_TOP = 1
local PLATEAU_TOP = 12

local MAP: Types.MapConfig = {
	id = "TestMap",
	displayName = "Test Map",
	paths = {
		-- Far from every placement below, so nothing trips the lane clearance
		-- rule except the test that means to.
		{ waypoints = { Vector3.new(-150, 0, -150), Vector3.new(-150, 0, 150) } },
	},
	basePosition = Vector3.new(-150, 0, 150),
	buildableSurfaces = {
		{ position = Vector3.new(0, -1, 0), size = Vector3.new(320, 4, 320), surfaceType = "Ground" },
		{ position = Vector3.new(100, 10, 100), size = Vector3.new(60, 4, 60), surfaceType = "Elevated" },
	},
	decor = {},
	groundSize = Vector3.new(400, 4, 400),
	groundColor = Color3.new(),
}

local ON_APRON = Vector3.new(0, 0, 0)
local ON_PLATEAU = Vector3.new(100, 0, 100)

local function request(
	definition: Types.TowerDefinition,
	position: Vector3,
	overrides: { [string]: any }?
): Placement.Request
	local base: { [string]: any } = {
		definition = definition,
		position = position,
		map = MAP,
		existing = {},
		unlocked = true,
		cash = COST * 10,
		ownedOfType = 0,
		canBuildNow = true,
	}

	-- An explicit nil check rather than `overrides or {}`: the latter gives
	-- Luau a union of two table types and it refuses to iterate it.
	if overrides ~= nil then
		for key, value in overrides do
			base[key] = value
		end
	end

	return base :: any
end

describe("Placement: stacked surfaces", function()
	-- THE regression. A plateau sits on top of the apron, so both surfaces
	-- contain any point on it. Resolving to the apron instead of the plateau
	-- inverts the whole category rule, and in play reads as "Ground towers
	-- can be built on the hills and Hillside towers cannot".
	it("resolves a plateau to the plateau, not the apron beneath it", function()
		local result = Placement.validate(request(HILLSIDE_TOWER, ON_PLATEAU))

		expect(result.ok).toBe(true)
		expect((result.position :: Vector3).Y).toBe(PLATEAU_TOP)
	end)

	it("refuses a Ground tower on a plateau", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_PLATEAU))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("WrongSurface")
	end)

	it("refuses a Hillside tower on open ground", function()
		local result = Placement.validate(request(HILLSIDE_TOWER, ON_APRON))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("WrongSurface")
	end)

	it("accepts a Ground tower on open ground", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON))

		expect(result.ok).toBe(true)
		expect((result.position :: Vector3).Y).toBe(APRON_TOP)
	end)

	it("lets Hybrid build on either", function()
		expect(Placement.validate(request(HYBRID_TOWER, ON_APRON)).ok).toBe(true)
		expect(Placement.validate(request(HYBRID_TOWER, ON_PLATEAU)).ok).toBe(true)
	end)
end)

describe("Placement: the client cannot pick its own height", function()
	it("ignores the requested Y entirely", function()
		-- A client that could set Y could float a tower out of reach or sink
		-- it into the ground. Height comes from the surface, always.
		for _, y in { -500, -1, 0, 7, 500 } do
			local result = Placement.validate(request(GROUND_TOWER, Vector3.new(0, y, 0)))

			expect(result.ok).toBe(true)
			expect((result.position :: Vector3).Y).toBe(APRON_TOP)
		end
	end)

	it("preserves X and Z exactly", function()
		local result = Placement.validate(request(GROUND_TOWER, Vector3.new(42, 999, -17)))

		expect((result.position :: Vector3).X).toBe(42)
		expect((result.position :: Vector3).Z).toBe(-17)
	end)
end)

describe("Placement: geometry rules", function()
	it("refuses a spot with no buildable surface under it", function()
		-- Inside the map bounds but off the apron entirely.
		local result = Placement.validate(request(GROUND_TOWER, Vector3.new(175, 0, 175)))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("NotBuildable")
	end)

	it("refuses a footprint hanging off the map", function()
		local result = Placement.validate(request(GROUND_TOWER, Vector3.new(5000, 0, 0)))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("OutOfBounds")
	end)

	it("refuses a tower that would wall the lane shut", function()
		-- Directly on the lane centre line. This is the one placement bug
		-- that turns a tower defense into a maze game.
		local result = Placement.validate(request(GROUND_TOWER, Vector3.new(-150, 0, 0)))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("BlocksPath")
	end)

	it("refuses a tower overlapping one already placed", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, {
			existing = { { position = Vector3.new(2, APRON_TOP, 0), radius = 3 } },
		}))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("OverlapsTower")
	end)

	it("allows two towers resting exactly flush", function()
		-- Radius 3 each, 6 apart. Adjacent towers should be able to touch,
		-- or the usable build area shrinks for no stated reason.
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, {
			existing = { { position = Vector3.new(6, APRON_TOP, 0), radius = 3 } },
		}))

		expect(result.ok).toBe(true)
	end)
end)

describe("Placement: permission rules", function()
	-- Zap proves the SHAPE of a request. It cannot prove permission, so every
	-- one of these is checked by hand on the server and must hold here.
	it("refuses a tower the player has not unlocked", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, { unlocked = false }))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("NotUnlocked")
	end)

	it("refuses a tower the player cannot afford", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, { cash = COST - 1 }))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("CannotAfford")
	end)

	it("refuses once the per-type cap is reached", function()
		local capped = towerDef("C", "Ground", 6, 2)
		local result = Placement.validate(request(capped, ON_APRON, { ownedOfType = 2 }))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("TowerCapReached")
	end)

	it("treats a cap of zero as unlimited", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, { ownedOfType = 999 }))

		expect(result.ok).toBe(true)
	end)

	it("refuses outside the phases where building is allowed", function()
		local result = Placement.validate(request(GROUND_TOWER, ON_APRON, { canBuildNow = false }))

		expect(result.ok).toBe(false)
		expect(result.reason).toBe("WrongMatchState")
	end)

	it("reports match state before anything else", function()
		-- Check order decides which message the player sees. A finished match
		-- should say so rather than complaining about their wallet.
		local result = Placement.validate(request(GROUND_TOWER, Vector3.new(5000, 0, 0), {
			canBuildNow = false,
			cash = 0,
			unlocked = false,
		}))

		expect(result.reason).toBe("WrongMatchState")
	end)
end)

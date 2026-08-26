--!strict
--[[
	Tests for reading a map back out of a Studio tree.

	Worth having because extraction is the step where an authoring mistake
	becomes committed data. A dragged part that lands slightly off, a waypoint
	with no order, a buildable pad someone forgot to tag - each of those turns
	into a map config that typechecks perfectly and plays wrong.

	Every tree here is built by hand rather than by MapBuilder, deliberately:
	testing the extractor against the builder's output would only prove the two
	agree, not that either matches the convention the docs promise an author.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local MapExtract = require(ReplicatedStorage.Shared.MapExtract)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function part(name: string, position: Vector3, size: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.Parent = parent
	return p
end

--- Strict mode will not dot-index a Folder for a child it cannot see
--- statically, so every lookup into a built tree goes through these.
local function child(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	assert(found ~= nil, `test tree is missing {name}`)
	return found
end

local function childPart(parent: Instance, name: string): BasePart
	local found = child(parent, name)
	assert(found:IsA("BasePart"), `{name} is not a BasePart`)
	return found
end

local function firstLane(root: Instance): Instance
	return child(child(root, "Lanes"), "Lane1")
end

--- A minimal tree that extracts cleanly. Individual tests break one thing.
local function goodTree(): Folder
	local root = Instance.new("Folder")
	root.Name = Constants.MAP_FOLDER

	part("Ground", Vector3.new(0, -2, 0), Vector3.new(340, 4, 300), root)
	part("Base", Vector3.new(140, 0, 90), Vector3.new(20, 24, 20), root)

	local lanes = Instance.new("Folder")
	lanes.Name = "Lanes"
	lanes.Parent = root

	local lane1 = Instance.new("Folder")
	lane1.Name = "Lane1"
	lane1.Parent = lanes

	-- Deliberately parented out of order, with a stray y on each, so the test
	-- proves both the ordering rule and the flattening rule.
	local w3 = part("Waypoint3", Vector3.new(50, 7, 0), Vector3.one, lane1)
	local w1 = part("Waypoint1", Vector3.new(-50, 3, 0), Vector3.one, lane1)
	local w2 = part("Waypoint2", Vector3.new(0, 5, 0), Vector3.one, lane1)
	w1:SetAttribute("Order", 1)
	w2:SetAttribute("Order", 2)
	w3:SetAttribute("Order", 3)

	local buildable = Instance.new("Folder")
	buildable.Name = "Buildable"
	buildable.Parent = root

	local pad = part("Pad1", Vector3.new(0, -1, 0), Vector3.new(320, 4, 280), buildable)
	pad:SetAttribute(Constants.ATTR_SURFACE_TYPE, "Ground")
	CollectionService:AddTag(pad, Constants.BUILDABLE_TAG)

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root

	part("Decor1", Vector3.new(10, 6, 10), Vector3.new(4, 12, 4), decor)

	return root
end

describe("MapExtract.fromFolder", function()
	it("reads a well-formed tree with no problems", function()
		local result = MapExtract.fromFolder(goodTree(), "Test", "Test Map")

		expect(#result.problems).toBe(0)
		expect(result.config).never.toBeNil()
	end)

	it("orders waypoints by their Order attribute, not by child order", function()
		local result = MapExtract.fromFolder(goodTree(), "Test", "Test Map")
		local waypoints = (result.config :: any).paths[1].waypoints

		expect(#waypoints).toBe(3)
		expect(waypoints[1].X).toBe(-50)
		expect(waypoints[2].X).toBe(0)
		expect(waypoints[3].X).toBe(50)
	end)

	it("flattens waypoints onto the path plane", function()
		local result = MapExtract.fromFolder(goodTree(), "Test", "Test Map")
		local waypoints = (result.config :: any).paths[1].waypoints

		-- Each was authored at a different height; a dragged y must not tilt
		-- the lane, because the walkway is drawn FROM these.
		for _, point in waypoints do
			expect(point.Y).toBe(0)
		end
	end)

	it("keeps the ground and base as authored", function()
		local result = MapExtract.fromFolder(goodTree(), "Test", "Test Map")
		local config = result.config :: any

		expect(config.groundSize).toBe(Vector3.new(340, 4, 300))
		expect(config.basePosition).toBe(Vector3.new(140, 0, 90))
	end)

	it("reports a lane whose waypoints have no order", function()
		local root = goodTree()
		local stray = part("Marker", Vector3.new(99, 0, 99), Vector3.one, firstLane(root))

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		expect(#result.problems).toBe(1)
		expect(string.find(result.problems[1], stray.Name) ~= nil).toBe(true)
	end)

	it("reports a buildable pad that was never tagged", function()
		local root = goodTree()
		local pad = part("Pad2", Vector3.new(80, -1, 0), Vector3.new(20, 4, 20), child(root, "Buildable"))
		pad:SetAttribute(Constants.ATTR_SURFACE_TYPE, "Ground")

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		-- Untagged means placement validation would never find it, which is
		-- invisible in the geometry and obvious only in play.
		expect(#result.problems).toBe(1)
		expect(#(result.config :: any).buildableSurfaces).toBe(1)
	end)

	it("reports a pad with an unusable surface type", function()
		local root = goodTree()
		local pad = part("Pad2", Vector3.new(80, -1, 0), Vector3.new(20, 4, 20), child(root, "Buildable"))
		pad:SetAttribute(Constants.ATTR_SURFACE_TYPE, "Hillside")
		CollectionService:AddTag(pad, Constants.BUILDABLE_TAG)

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		expect(#result.problems).toBe(1)
		expect(#(result.config :: any).buildableSurfaces).toBe(1)
	end)

	it("refuses to produce a config when the ground is missing", function()
		local root = goodTree()
		child(root, "Ground"):Destroy()

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		-- No config at all rather than one with a default ground: guessing the
		-- play area's extents would silently change where towers may be built.
		expect(result.config).toBeNil()
		expect(#result.problems > 0).toBe(true)
	end)

	it("reports a ground that was dragged off the y = 0 plane", function()
		local root = goodTree()
		childPart(root, "Ground").CFrame = CFrame.new(0, 6, 0)

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		-- The ground's position is derived, not extracted, so a drag here
		-- silently does nothing. Saying so beats snapping it back in silence.
		expect(#result.problems).toBe(1)
		expect(string.find(result.problems[1], "Ground") ~= nil).toBe(true)
	end)

	it("reports a missing Lanes folder", function()
		local root = goodTree()
		child(root, "Lanes"):Destroy()

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		expect(#result.problems > 0).toBe(true)
	end)

	it("reports a lane with only one waypoint", function()
		local root = goodTree()
		child(firstLane(root), "Waypoint2"):Destroy()
		child(firstLane(root), "Waypoint3"):Destroy()

		local result = MapExtract.fromFolder(root, "Test", "Test Map")

		expect(#result.problems > 0).toBe(true)
	end)
end)

describe("MapExtract.toSource", function()
	it("emits a module carrying the id and every waypoint", function()
		local result = MapExtract.fromFolder(goodTree(), "Test", "Test Map")
		local source = MapExtract.toSource(result.config :: any)

		expect(string.find(source, 'id = "Test"') ~= nil).toBe(true)
		expect(string.find(source, "return map") ~= nil).toBe(true)
		expect(string.find(source, "Vector3.new%(%-50, 0, 0%)") ~= nil).toBe(true)
	end)

	it("rounds float noise out of a dragged position", function()
		local root = goodTree()
		-- What Studio actually hands back after a drag.
		childPart(firstLane(root), "Waypoint1").CFrame = CFrame.new(-49.999984741210938, 3, 0)

		local result = MapExtract.fromFolder(root, "Test", "Test Map")
		local source = MapExtract.toSource(result.config :: any)

		-- Without rounding, every re-extraction would diff even when nothing
		-- moved, which defeats keeping maps as text.
		expect(string.find(source, "49.999") ~= nil).toBe(false)
		expect(string.find(source, "Vector3.new%(%-50, 0, 0%)") ~= nil).toBe(true)
	end)
end)

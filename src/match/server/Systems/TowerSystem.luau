--!strict
--[[
	Owns every placed tower: the registry, their visible parts, and the
	per-frame combat tick.

	Same split as the enemy side. BaseTower holds the truth and knows nothing
	about Instances; this module projects it into the world and drives it.

	Acquisition cost, stated plainly because it is the thing that would bite
	at scale: a tower only searches for a target on a frame it can actually
	shoot. At 60 towers averaging 1.5 shots a second against 200 enemies that
	is roughly 18k distance checks a second, which is nothing. Searching every
	frame instead would be 360k, which is not.

	No target caching between shots, deliberately. First and Closest are
	supposed to track as enemies move, and a cached target makes them stick.

	Candidate tables are allocated per acquisition rather than pooled. That is
	a few thousand short-lived tables a second, which Luau's collector handles
	comfortably; if a profile ever says otherwise, pooling them is the first
	thing to try and it is contained entirely within this file.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ServerScriptService.Net)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Types = require(ReplicatedStorage.Shared.Types)
local Wire = require(ReplicatedStorage.Shared.Wire)

local Rigs = require(script.Parent.Rigs)

local BaseTower = require(script.Parent.Parent.Entities.BaseTower)
local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)
local TowerBehaviors = require(script.Parent.Parent.Entities.TowerBehaviors)

local TowerSystem = {}
TowerSystem.__index = TowerSystem

export type System = typeof(setmetatable(
	{} :: {
		simulation: EnemySimulation.Simulation,
		container: Folder,
		towers: { BaseTower.Tower },
		byId: { [Types.TowerId]: BaseTower.Tower? },
		parts: { [Types.TowerId]: Part? },
		nextId: number,
	},
	TowerSystem
))

export type PlaceParams = {
	definition: Types.TowerDefinition,
	owner: Player,
	position: Vector3,
	rotationY: number,
	--- Rolled trait ids for this tower type, from the owner's profile.
	traits: { string }?,
}

function TowerSystem.new(simulation: EnemySimulation.Simulation, parent: Instance): System
	local container = Instance.new("Folder")
	container.Name = Constants.TOWER_FOLDER
	container.Parent = parent

	return setmetatable({
		simulation = simulation,
		container = container,
		towers = {},
		byId = {},
		parts = {},
		nextId = 1,
	}, TowerSystem)
end

-- ---------------------------------------------------------------------------
-- Visuals
--
-- Attributes carry the per-tower state a client needs (ARCHITECTURE.md D5).
-- They replicate for free and are read-only to clients, so none of this
-- costs a network message.
-- ---------------------------------------------------------------------------

local function writeAttributes(part: Part, tower: BaseTower.Tower)
	part:SetAttribute("TowerId", tower.id)
	part:SetAttribute("TowerDefId", tower.definition.id)
	part:SetAttribute("Level", tower.level)
	part:SetAttribute("OwnerUserId", tower.owner.UserId)
	part:SetAttribute("TargetingMode", tower.targetingMode)
	part:SetAttribute("Range", tower:range())
	part:SetAttribute("SellValue", tower:sellValue())
	-- Comma-joined, because attributes cannot hold tables. The client
	-- only displays these; the numbers they change already arrive
	-- through the Range attribute and the server's own combat maths.
	part:SetAttribute("Traits", table.concat(tower.traits, ","))
end

local function buildPart(self: System, tower: BaseTower.Tower): Part
	local level = tower:currentLevel()
	local part = Instance.new("Part")

	part.Name = tower.definition.id
	part.Size = level.modelSize
	part.Color = level.color
	part.Anchored = true
	-- Queryable but not collidable: the client raycasts these to select a
	-- tower, and players should never be able to shove one.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(tower.position + Vector3.new(0, level.modelSize.Y / 2, 0))
		* CFrame.Angles(0, math.rad(tower.rotationY), 0)

	writeAttributes(part, tower)
	part.Parent = self.container

	-- Parented first: attachStatic measures the host's world position to sit
	-- the rig's feet on it, and an unparented part has none.
	--
	-- The part stays exactly what it was - same size, same attributes, same
	-- CanQuery - and only stops being drawn. Everything that finds a tower
	-- finds this, not the rig.
	if tower.definition.rig ~= nil and Rigs.attachStatic(part, tower.definition.rig, tower.rotationY) then
		part.Transparency = 1
	end

	return part
end

--- Re-syncs the part after a level change: size, colour and every attribute.
local function refreshPart(self: System, tower: BaseTower.Tower)
	local part = self.parts[tower.id]

	if part == nil then
		return
	end

	local level = tower:currentLevel()
	part.Size = level.modelSize
	part.Color = level.color
	part.CFrame = CFrame.new(tower.position + Vector3.new(0, level.modelSize.Y / 2, 0))
		* CFrame.Angles(0, math.rad(tower.rotationY), 0)

	-- The rig grows with the level because the host part does. That preserves
	-- the ONLY cue a player has that an upgrade landed - ASSET-MANIFEST calls
	-- this out: a model that keeps a constant size makes upgrades invisible.
	Rigs.refit(part, tower.rotationY)

	writeAttributes(part, tower)
end

-- ---------------------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------------------

function TowerSystem.place(self: System, params: PlaceParams): BaseTower.Tower
	local id = self.nextId
	self.nextId += 1

	local tower = BaseTower.new({
		id = id,
		definition = params.definition,
		behavior = TowerBehaviors.find(params.definition.id),
		owner = params.owner,
		position = params.position,
		rotationY = params.rotationY,
		traits = params.traits,
	})

	table.insert(self.towers, tower)
	self.byId[id] = tower
	self.parts[id] = buildPart(self, tower)

	return tower
end

function TowerSystem.get(self: System, id: Types.TowerId): BaseTower.Tower?
	return self.byId[id]
end

--- Removes a tower and its part. Returns it so the caller can pay a refund.
function TowerSystem.remove(self: System, id: Types.TowerId): BaseTower.Tower?
	local tower = self.byId[id]

	if tower == nil then
		return nil
	end

	local index = table.find(self.towers, tower)

	if index ~= nil then
		table.remove(self.towers, index)
	end

	self.byId[id] = nil

	local part = self.parts[id]

	if part ~= nil then
		part:Destroy()
		self.parts[id] = nil
	end

	local hook = tower.behavior.onSold

	if hook ~= nil then
		hook(tower)
	end

	return tower
end

--- Applies an upgrade that the caller has already paid for.
function TowerSystem.upgrade(self: System, tower: BaseTower.Tower, paid: number)
	tower:upgrade(paid)
	refreshPart(self, tower)
end

function TowerSystem.setTargeting(self: System, tower: BaseTower.Tower, mode: Types.TargetingMode)
	tower:setTargeting(mode)
	refreshPart(self, tower)
end

--- How many towers this player owns, optionally of one definition. Drives the
--- per-tower cap.
function TowerSystem.countFor(self: System, player: Player, definitionId: string?): number
	local count = 0

	for _, tower in self.towers do
		if tower.owner ~= player then
			continue
		end

		if definitionId == nil or tower.definition.id == definitionId then
			count += 1
		end
	end

	return count
end

--- Removes every tower belonging to a player. Called when they leave, so a
--- disconnected player's towers do not keep fighting for free.
function TowerSystem.removeAllFor(self: System, player: Player)
	local doomed: { Types.TowerId } = {}

	for _, tower in self.towers do
		if tower.owner == player then
			table.insert(doomed, tower.id)
		end
	end

	for _, id in doomed do
		self:remove(id)
	end
end

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------

--- Every enemy this tower could legally shoot right now.
local function candidatesFor(self: System, tower: BaseTower.Tower): { Targeting.Candidate }
	local simulation = self.simulation
	local origin = tower.position
	local range = tower:range()
	local rangeSquared = range * range
	local candidates: { Targeting.Candidate } = {}

	for _, enemy in simulation.enemies do
		if not enemy.alive then
			continue
		end

		if not tower:canTarget(enemy.definition.category) then
			continue
		end

		local offset = simulation:positionOf(enemy) - origin
		local distanceSquared = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z

		if distanceSquared > rangeSquared then
			continue
		end

		table.insert(candidates, {
			id = enemy.id,
			distanceToBase = simulation:distanceToBase(enemy),
			health = enemy.health,
			maxHealth = enemy.maxHealth,
			distanceToTower = math.sqrt(distanceSquared),
		})
	end

	return candidates
end

function TowerSystem.update(self: System, deltaTime: number)
	local simulation = self.simulation

	for _, tower in self.towers do
		tower:tickCooldown(deltaTime)

		if not tower:isReady() then
			continue
		end

		local candidates = candidatesFor(self, tower)
		local target = Targeting.select(tower.targetingMode, candidates)

		if target == nil then
			continue
		end

		local enemy = simulation:get(target.id)

		if enemy == nil then
			continue
		end

		local targetPosition = simulation:positionOf(enemy)
		tower:fire(simulation, target.id, targetPosition)

		-- Cosmetic tracer. Unreliable, because a dropped one is invisible and
		-- these must never queue behind reliable traffic.
		Net.TowerFired.FireAll({
			towerId = tower.id,
			targetPosition = Wire.toWire(targetPosition),
		})
	end
end

function TowerSystem.destroy(self: System)
	self.towers = {}
	self.byId = {}
	self.parts = {}
	self.container:Destroy()
end

return TowerSystem

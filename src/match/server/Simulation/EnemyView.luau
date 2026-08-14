--!strict
--[[
	Projects the enemy simulation onto server-owned parts (ARCHITECTURE.md D2).

	Strictly one-way. The simulation is the truth; these parts are a picture of
	it. Nothing anywhere reads a position back off a part - if the two ever
	disagree, the part is wrong by definition. Keeping that arrow pointing one
	way is what stops "numeric sim plus hitbox parts" from becoming two sources
	of truth that drift.

	Because the parts are server-owned and anchored, Roblox replicates their
	CFrame natively and health rides as an Attribute. That is why the network
	schema carries no enemy position, health or damage-number message at all.

	All movement goes through one BulkMoveTo per sync rather than N individual
	CFrame writes. Signature verified against types/globalTypes.d.luau:
	    WorldRoot:BulkMoveTo(partList: {BasePart}, cframeList: {CFrame},
	                         eventMode: EnumBulkMoveMode?): nil
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)
local EnemySimulation = require(script.Parent.EnemySimulation)
local PartPool = require(script.Parent.PartPool)

local EnemyView = {}
EnemyView.__index = EnemyView

export type View = typeof(setmetatable(
	{} :: {
		simulation: EnemySimulation.Simulation,
		container: Folder,
		pool: PartPool.Pool,
		parts: { [Types.EnemyId]: Part? },
		--- Last health value written per enemy. Attribute writes replicate,
		--- so writing an unchanged value every frame would be pure waste.
		lastHealth: { [Types.EnemyId]: number? },
		unsubscribeRemoved: EnemySimulation.Unsubscribe?,
	},
	EnemyView
))

--- FireCFrameChanged rather than FireAllEvents: the cheaper of the two modes
--- the enum offers, and nothing here depends on the full event set.
local MOVE_MODE = Enum.BulkMoveMode.FireCFrameChanged

function EnemyView.new(simulation: EnemySimulation.Simulation, parent: Instance): View
	local container = Instance.new("Folder")
	container.Name = Constants.ENEMY_FOLDER
	container.Parent = parent

	-- Annotated rather than inferred: without this the `unsubscribeRemoved =
	-- nil` in the literal infers the field as exactly `nil`, and the
	-- assignment below stops typechecking.
	local view: View = setmetatable({
		simulation = simulation,
		container = container,
		pool = PartPool.new(container),
		parts = {},
		lastHealth = {},
		unsubscribeRemoved = nil,
	}, EnemyView)

	view.unsubscribeRemoved = simulation:onEnemyRemoved(function(id: Types.EnemyId)
		view:releaseEnemy(id)
	end)

	return view
end

--- Returns this enemy's part, creating and configuring it on first sight.
--- Per-enemy setup happens exactly once; the per-frame path touches only the
--- CFrame and, when it changed, the health attribute.
local function acquireFor(self: View, enemy: BaseEnemy.Enemy): Part
	local existing = self.parts[enemy.id]

	if existing ~= nil then
		return existing
	end

	local definition = enemy.definition
	local fresh = self.pool:acquire()

	fresh.Name = definition.id
	fresh.Size = definition.hitboxSize
	fresh.Color = definition.color
	fresh.Transparency = 0
	fresh:SetAttribute(Constants.ATTR_ENEMY_ID, enemy.id)
	fresh:SetAttribute(Constants.ATTR_MAX_HEALTH, enemy.maxHealth)
	fresh:SetAttribute(Constants.ATTR_HEALTH, enemy.health)

	self.parts[enemy.id] = fresh
	self.lastHealth[enemy.id] = enemy.health

	return fresh
end

function EnemyView.releaseEnemy(self: View, id: Types.EnemyId)
	local part = self.parts[id]

	if part == nil then
		return
	end

	self.parts[id] = nil
	self.lastHealth[id] = nil
	self.pool:release(part)
end

--- Rebuilds the visual state from the simulation. Call once per frame.
function EnemyView.sync(self: View)
	local simulation = self.simulation
	local movingParts: { BasePart } = {}
	local targetFrames: { CFrame } = {}

	for _, enemy in simulation.enemies do
		local part = acquireFor(self, enemy)

		-- Only write when it actually changed: every attribute write
		-- replicates to every client, and health is unchanged on most frames.
		if self.lastHealth[enemy.id] ~= enemy.health then
			self.lastHealth[enemy.id] = enemy.health
			part:SetAttribute(Constants.ATTR_HEALTH, enemy.health)
		end

		local position = simulation:positionOf(enemy)
		local facing = simulation:directionOf(enemy)

		table.insert(movingParts, part)
		table.insert(targetFrames, CFrame.lookAt(position, position + facing))
	end

	if #movingParts > 0 then
		workspace:BulkMoveTo(movingParts, targetFrames, MOVE_MODE)
	end
end

function EnemyView.destroy(self: View)
	local unsubscribe = self.unsubscribeRemoved

	if unsubscribe ~= nil then
		unsubscribe()
		self.unsubscribeRemoved = nil
	end

	self.parts = {}
	self.lastHealth = {}
	self.pool:destroy()
	self.container:Destroy()
end

return EnemyView

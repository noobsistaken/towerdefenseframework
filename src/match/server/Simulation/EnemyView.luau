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
local Rigs = require(script.Parent.Parent.Systems.Rigs)

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
		--- Last effect-id string written per enemy, for the same reason.
		lastEffects: { [Types.EnemyId]: string? },
		--- Last enrage flag written per enemy. Same reason again.
		lastEnraged: { [Types.EnemyId]: boolean? },
		--- Enemies currently wearing a rig, and each rig's parts with their
		--- offsets from the host - the extra entries sync() feeds into the
		--- same BulkMoveTo, because BulkMoveTo moves only what it is given.
		riggedCount: number,
		rigOffsets: { [Part]: Rigs.Offsets? },
		unsubscribeRemoved: EnemySimulation.Unsubscribe?,
	},
	EnemyView
))

--- FireCFrameChanged rather than FireAllEvents: the cheaper of the two modes
--- the enum offers, and nothing here depends on the full event set.
local MOVE_MODE = Enum.BulkMoveMode.FireCFrameChanged

--- Hard ceiling on enemies wearing a rig at once. Beyond it new spawns fall
--- back to the coloured box - degradation, never breakage.
---
--- A single blunt cap rather than the per-type budgets a concurrency sweep
--- proposed, because that sweep was refuted on review: it omitted the Runner
--- sprint, ignored the shipped Slow effect inflating time-on-path, and its
--- headline cost model had the axis backwards - measured cost tracks PART
--- count, not root count. 64 rigs at ~17 visible parts each is roughly
--- 1,100 extra parts, which is conservative on the numbers that DID hold up.
--- The honest way to raise this is profiling a real wave in Studio, not a
--- bigger estimate.
local MAX_RIGGED = 64

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
		lastEffects = {},
		lastEnraged = {},
		riggedCount = 0,
		rigOffsets = {},
		unsubscribeRemoved = nil,
	}, EnemyView)

	view.unsubscribeRemoved = simulation:onEnemyRemoved(function(id: Types.EnemyId)
		view:releaseEnemy(id)
	end)

	return view
end

--- Stable description of which effects are live on an enemy, for the
--- attribute below.
---
--- Sorted deliberately, and not for tidiness: `enemy.effects` is a hash map
--- and Luau does not promise a stable iteration order, so an unsorted join
--- could produce a different string frame to frame for an UNCHANGED set of
--- effects - and the change check below would then replicate on every one of
--- them. Sorting makes the value a pure function of the set.
---
--- The empty-list guard matters because an id whose instances have all
--- expired may still be present as a key.
local function describeEffects(enemy: BaseEnemy.Enemy): string
	local ids: { string } = {}

	for effectId, instances in enemy.effects do
		if #instances > 0 then
			table.insert(ids, effectId)
		end
	end

	if #ids == 0 then
		return ""
	end

	table.sort(ids)

	return table.concat(ids, ",")
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

	-- Rig or box. Attach reuses a matching rig a pooled part came back with,
	-- and refuses a template with no visible geometry, so a non-nil result
	-- genuinely means "there is something to look at" before the host goes
	-- invisible.
	local offsets: Rigs.Offsets? = nil

	if definition.rig ~= nil and self.riggedCount < MAX_RIGGED then
		offsets = Rigs.attachMoving(fresh, definition.rig)
	end

	if offsets ~= nil then
		self.riggedCount += 1
		self.rigOffsets[fresh] = offsets
	else
		-- A pooled part can come back wearing the previous occupant's rig.
		Rigs.clear(fresh)
	end

	fresh.Transparency = if offsets ~= nil then 1 else 0
	fresh:SetAttribute(Constants.ATTR_ENEMY_ID, enemy.id)
	fresh:SetAttribute(Constants.ATTR_MAX_HEALTH, enemy.maxHealth)
	fresh:SetAttribute(Constants.ATTR_HEALTH, enemy.health)
	fresh:SetAttribute(Constants.ATTR_STATUS_EFFECTS, "")
	fresh:SetAttribute(Constants.ATTR_ENRAGED, false)

	self.parts[enemy.id] = fresh
	self.lastHealth[enemy.id] = enemy.health
	self.lastEffects[enemy.id] = ""
	self.lastEnraged[enemy.id] = false

	return fresh
end

function EnemyView.releaseEnemy(self: View, id: Types.EnemyId)
	local part = self.parts[id]

	if part == nil then
		return
	end

	self.parts[id] = nil
	self.lastHealth[id] = nil
	self.lastEffects[id] = nil
	self.lastEnraged[id] = nil

	-- The rig stays on the pooled part - recycling it is the cheap path - but
	-- it stops counting toward the cap, which bounds what is on the FIELD.
	-- The offsets go: a re-acquire recomputes them, and a part the pool
	-- destroys must not be pinned by this table.
	if self.rigOffsets[part] ~= nil then
		self.rigOffsets[part] = nil
		self.riggedCount -= 1
	end

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

		local effects = describeEffects(enemy)

		if self.lastEffects[enemy.id] ~= effects then
			self.lastEffects[enemy.id] = effects
			part:SetAttribute(Constants.ATTR_STATUS_EFFECTS, effects)
		end

		local enraged = false
		local isEnraged = enemy.behavior.enraged

		if isEnraged ~= nil then
			enraged = isEnraged(enemy)
		end

		if self.lastEnraged[enemy.id] ~= enraged then
			self.lastEnraged[enemy.id] = enraged
			part:SetAttribute(Constants.ATTR_ENRAGED, enraged)
		end

		local position = simulation:positionOf(enemy)
		local facing = simulation:directionOf(enemy)
		local target = CFrame.lookAt(position, position + facing)

		table.insert(movingParts, part)
		table.insert(targetFrames, target)

		-- The rig rides in the SAME bulk move. BulkMoveTo moves exactly the
		-- parts it is handed - measured, twice, against both weld mechanisms
		-- - so each rig part is listed explicitly at its cached offset.
		local rigParts = self.rigOffsets[part]

		if rigParts ~= nil then
			for _, entry in rigParts do
				table.insert(movingParts, entry.part)
				table.insert(targetFrames, target * entry.offset)
			end
		end
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

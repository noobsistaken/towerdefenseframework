--!strict
--[[
	Health bars and floating damage numbers.

	Both are driven entirely by the Health attribute the server writes onto
	each enemy part (ARCHITECTURE.md D5). Nothing here needs a network message,
	which is why the schema carries no enemy-health event and no damage-number
	event: the data is already replicating.

	One module rather than two, because both hang off the SAME attribute
	subscription. At 200 concurrent enemies, two modules would mean 400
	connections doing the same work twice.

	Damage numbers COALESCE, deliberately. Several towers hitting one enemy in
	the same frame produce one number showing the total rather than four
	overlapping numbers, which is both cheaper and easier to read. D5 called
	this out as desirable rather than a compromise, and it is the reason the
	server does not send per-hit events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local Theme = require(ReplicatedStorage.Shared.Theme)

local SoundController = require(script.Parent.Parent.Audio.SoundController)

local EnemyVisuals = {}

--- Bars stop rendering past this. A bar 400 studs away is a pixel, and at 200
--- enemies the ones you cannot read are most of the cost.
local BAR_MAX_DISTANCE = 260

local BAR_WIDTH = 4
local BAR_HEIGHT = 0.5

--- Accumulated damage is flushed into a number at most this often, per enemy.
--- Long enough to coalesce a volley, short enough to feel responsive.
local FLUSH_INTERVAL = 0.15

--- Hard ceiling on numbers on screen at once. A boss wave with sixty towers
--- firing can generate them faster than they expire, and past this the
--- screen is unreadable anyway.
local MAX_NUMBERS = 40

local NUMBER_RISE = 6
local NUMBER_SECONDS = 0.8

type Entry = {
	part: BasePart,
	gui: BillboardGui,
	fill: Frame,
	maxHealth: number,
	lastHealth: number,
	pendingDamage: number,
	sinceFlush: number,
	connection: RBXScriptConnection,
	statusConnection: RBXScriptConnection,
}

--- Reads a numeric attribute, or nil if absent or the wrong type.
--- GetAttribute returns `any`, and a recycled pool part briefly has none.
local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)

	if type(value) ~= "number" then
		return nil
	end

	return value
end

--- Reads a string attribute, or nil if absent or the wrong type.
local function stringAttribute(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)

	if type(value) ~= "string" then
		return nil
	end

	return value
end

--- The colour an enemy should render as, given the effect ids the server
--- published on ATTR_STATUS_EFFECTS.
---
--- First id wins. The server writes them sorted, so this is deterministic -
--- but between two live effects it is ARBITRARY. Blending a red bleed with a
--- blue slow gives a purple that reads as neither, and nothing in the config
--- ranks one above the other. A `priority` field on StatusEffectDefinition is
--- the natural upgrade if which one shows ever matters.
local function tintFor(encoded: string): Color3?
	for id in string.gmatch(encoded, "[^,]+") do
		local definition = StatusEffects.find(id)

		if definition ~= nil then
			return definition.color
		end
	end

	return nil
end

--- Repaints one enemy to its effect tint, or back to its definition colour
--- when nothing is live.
---
--- The part's Name is its definition id (EnemyView sets both), so the base
--- colour is recoverable without spending a second attribute on it. Writing
--- Color on the client is local-only; the server sets it once at spawn and
--- never again, so this does not fight replication.
local function refreshTint(part: BasePart)
	local encoded = stringAttribute(part, Constants.ATTR_STATUS_EFFECTS)
	local tint = if encoded ~= nil then tintFor(encoded) else nil

	if tint ~= nil then
		part.Color = tint
		return
	end

	local definition = Enemies.find(part.Name)

	if definition ~= nil then
		part.Color = definition.color
	end
end

local function buildBar(part: BasePart): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(BAR_WIDTH, BAR_HEIGHT)
	gui.SizeOffset = Vector2.zero
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = BAR_MAX_DISTANCE
	gui.Parent = part

	local track = Instance.new("Frame")
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
	track.BorderSizePixel = 0
	track.Parent = gui

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.POSITIVE
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	return gui, fill
end

local activeNumbers = 0

--- One floating number, rising and fading from `position`.
---
--- Parented to its own anchored part rather than adorned to the enemy: the
--- enemy's part is pooled and may be recycled onto a different enemy while
--- this is still animating, which would make the number teleport across the
--- map mid-flight.
local function spawnNumber(position: Vector3, amount: number)
	if activeNumbers >= MAX_NUMBERS then
		return
	end

	activeNumbers += 1

	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 1.4)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BAR_MAX_DISTANCE
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.Text = tostring(math.floor(amount + 0.5))
	label.TextColor3 = Theme.TEXT
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	local info = TweenInfo.new(NUMBER_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(anchor, info, { CFrame = CFrame.new(position + Vector3.new(0, NUMBER_RISE, 0)) }):Play()

	local fade = TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })

	fade.Completed:Connect(function()
		activeNumbers -= 1
		anchor:Destroy()
	end)

	fade:Play()
end

--- Starts watching. Returns a cleanup function.
function EnemyVisuals.start(): () -> ()
	local folder = workspace:WaitForChild(Constants.ENEMY_FOLDER)
	local entries: { [BasePart]: Entry } = {}

	local function detach(part: BasePart)
		local entry = entries[part]

		if entry == nil then
			return
		end

		entries[part] = nil
		entry.connection:Disconnect()
		entry.statusConnection:Disconnect()

		-- Health at or below zero when the part goes away means a kill.
		-- Inferred rather than sent: a death event per enemy would be
		-- hundreds of unreliable packets a wave for something the client can
		-- already see.
		if entry.lastHealth <= 0 then
			SoundController.play("EnemyDeath", part.Position)
		end

		if entry.gui.Parent ~= nil then
			entry.gui:Destroy()
		end
	end

	local function attach(child: Instance)
		if not child:IsA("BasePart") then
			return
		end

		local maxHealth = numberAttribute(child, Constants.ATTR_MAX_HEALTH)
		local health = numberAttribute(child, Constants.ATTR_HEALTH)

		-- A pooled part is parented before its attributes are written, so
		-- absent values here mean "not an enemy yet", not "not an enemy".
		if maxHealth == nil or health == nil or maxHealth <= 0 then
			return
		end

		local gui, fill = buildBar(child)

		local entry: Entry = {
			part = child,
			gui = gui,
			fill = fill,
			maxHealth = maxHealth,
			lastHealth = health,
			pendingDamage = 0,
			sinceFlush = 0,
			connection = nil :: any,
			statusConnection = nil :: any,
		}

		entry.connection = child:GetAttributeChangedSignal(Constants.ATTR_HEALTH):Connect(function()
			local current = numberAttribute(child, Constants.ATTR_HEALTH)

			if current == nil then
				return
			end

			local delta = entry.lastHealth - current
			entry.lastHealth = current

			if delta > 0 then
				entry.pendingDamage += delta
			end

			fill.Size = UDim2.fromScale(math.clamp(current / entry.maxHealth, 0, 1), 1)
		end)

		refreshTint(child)

		entry.statusConnection = child:GetAttributeChangedSignal(Constants.ATTR_STATUS_EFFECTS):Connect(function()
			refreshTint(child)
		end)

		entries[child] = entry
	end

	for _, child in folder:GetChildren() do
		attach(child)
	end

	local addedConnection = folder.ChildAdded:Connect(function(child)
		-- Attributes are written the same frame the part is parented, but not
		-- necessarily before. Defer one step so the first read sees them.
		task.defer(attach, child)
	end)

	local removedConnection = folder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			detach(child)
		end
	end)

	local flushConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		for part, entry in entries do
			if entry.pendingDamage <= 0 then
				continue
			end

			entry.sinceFlush += deltaTime

			if entry.sinceFlush < FLUSH_INTERVAL then
				continue
			end

			spawnNumber(part.Position + Vector3.new(0, part.Size.Y / 2, 0), entry.pendingDamage)

			entry.pendingDamage = 0
			entry.sinceFlush = 0
		end
	end)

	return function()
		addedConnection:Disconnect()
		removedConnection:Disconnect()
		flushConnection:Disconnect()

		for part in entries do
			detach(part)
		end
	end
end

return EnemyVisuals

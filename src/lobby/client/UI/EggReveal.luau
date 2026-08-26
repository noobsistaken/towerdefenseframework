--!strict
--[[
	The gacha's egg-opening cinematic.

	Deliberately IMPERATIVE, not a React component: this is transient
	theatre with a strict timeline - rise, shake, flash, crack, showcase -
	and a timeline reads as a straight-line script where a component version
	would be a state machine spread across effects. It builds its own
	ScreenGui, runs once, destroys everything, and calls `onDone` exactly
	once. GachaPanel holds its roll guard until then, so two eggs can never
	stack.

	The reveal shows the unit's MODEL, per the brief - the rig template
	cloned into a ViewportFrame - with the name only as a caption. A place
	without ReplicatedStorage.RigTemplates (a fresh clone) degrades to the
	tower's config box, never to a broken reveal.

	The outcome is decided before the first frame draws: the server's reply
	is already in hand when play() is called, so nothing here can desync
	from the truth - it is suspense applied retroactively.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local UnitPreview = require(ReplicatedStorage.Shared.UnitPreview)

local EggReveal = {}

export type Request = {
	towerId: string,
	rarityId: string,
	duplicate: boolean,
	refunded: number,
}

-- Timeline, in seconds. Tuned as a set: the shake must feel like it EARNS
-- the crack, and the whole thing must stay under ~2s to the reveal so
-- chain-rolling never drags.
local RISE_SECONDS = 0.45
local SHAKE_SECONDS = 1.2
local CRACK_FLASH_SECONDS = 0.12
local FLASH_FADE_SECONDS = 0.35
local SHOWCASE_SECONDS = 4
local FADE_OUT_SECONDS = 0.25

local SHAKE_STEP = 0.03

local function rarityColor(rarityId: string): Color3
	local tier = Rarity.find(rarityId)

	return if tier ~= nil then tier.color else Theme.MUTED
end

--- The egg: a squashed ball with a rarity-tinted band, built in code so the
--- reveal owes nothing to any place's contents.
local function buildEgg(tint: Color3): Model
	local model = Instance.new("Model")

	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(4, 4, 4)
	shell.Color = Color3.fromRGB(242, 236, 216)
	shell.Material = Enum.Material.SmoothPlastic
	shell.Anchored = true
	shell.CFrame = CFrame.new(0, 0, 0)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.32, 1)
	mesh.Parent = shell
	shell.Parent = model

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Shape = Enum.PartType.Ball
	band.Size = Vector3.new(4.15, 4.15, 4.15)
	band.Color = tint
	band.Material = Enum.Material.Neon
	band.Transparency = 0.55
	band.Anchored = true
	band.CFrame = CFrame.new(0, 0, 0)

	local bandMesh = Instance.new("SpecialMesh")
	bandMesh.MeshType = Enum.MeshType.Sphere
	bandMesh.Scale = Vector3.new(0.98, 0.42, 0.98)
	bandMesh.Parent = band
	band.Parent = model

	return model
end

-- Unit building and camera framing live in shared UnitPreview: one
-- builder for the reveal, the reroll portrait, and the match shop, so no
-- two screens can disagree about what a unit looks like.
local frame = UnitPreview.frame

--- Plays the whole cinematic. `onDone` fires exactly once, after the
--- overlay has destroyed itself - hold roll guards until then.
function EggReveal.play(request: Request, onDone: () -> ())
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")

	if playerGui == nil then
		onDone()
		return
	end

	local definition = Towers.find(request.towerId)
	local tint = rarityColor(request.rarityId)

	local screen = Instance.new("ScreenGui")
	screen.Name = "EggReveal"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50

	-- Dimmer over the whole screen, so the egg owns the moment.
	local dimmer = Instance.new("Frame")
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 1
	dimmer.BorderSizePixel = 0
	dimmer.Parent = screen

	local viewport = Instance.new("ViewportFrame")
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 1.5)
	viewport.Size = UDim2.fromOffset(360, 360)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(180, 180, 190)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Parent = screen

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local caption = Instance.new("TextLabel")
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 0.5, 190)
	caption.Size = UDim2.fromOffset(500, 54)
	caption.BackgroundTransparency = 1
	caption.Font = Theme.FONT
	caption.Text = ""
	caption.TextColor3 = tint
	caption.TextSize = 24
	caption.TextTransparency = 1
	caption.Parent = screen

	-- The flash sits above everything, including the caption.
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 10
	flash.Parent = screen

	screen.Parent = playerGui

	local egg = buildEgg(tint)
	egg.Parent = viewport
	frame(camera, egg, false)

	local finished = false

	local function finish()
		if finished then
			return
		end

		finished = true
		screen:Destroy()
		onDone()
	end

	task.spawn(function()
		SoundKit.play("GachaRoll")

		-- 1. RISE: from below the screen to centre, with the dim coming up.
		TweenService:Create(dimmer, TweenInfo.new(RISE_SECONDS), { BackgroundTransparency = 0.35 }):Play()
		local rise = TweenService:Create(
			viewport,
			TweenInfo.new(RISE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5) }
		)
		rise:Play()
		task.wait(RISE_SECONDS + 0.05)

		-- 2. SHAKE: jitter that ramps, with three flash pulses on the way.
		-- Driven by steps rather than tweens because the jitter must be
		-- incoherent - a tween's easing would read as wobble, not struggle.
		local elapsed = 0
		local pulses = { 0.35, 0.7, 1.0 }
		local pulsed = 0

		while elapsed < SHAKE_SECONDS do
			local intensity = elapsed / SHAKE_SECONDS
			local amplitude = 2 + intensity * 8

			viewport.Rotation = (math.random() * 2 - 1) * amplitude
			viewport.Position = UDim2.new(
				0.5,
				(math.random() * 2 - 1) * amplitude * 1.4,
				0.5,
				(math.random() * 2 - 1) * amplitude * 1.4
			)

			if pulsed < #pulses and elapsed >= pulses[pulsed + 1] * SHAKE_SECONDS - 0.001 then
				pulsed += 1
				flash.BackgroundTransparency = 0.75 - pulsed * 0.15
				TweenService:Create(flash, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
				SoundKit.play("EggShake")
			end

			task.wait(SHAKE_STEP)
			elapsed += SHAKE_STEP
		end

		viewport.Rotation = 0
		viewport.Position = UDim2.fromScale(0.5, 0.5)

		-- 3. CRACK: a hard white flash, and the swap happens INSIDE it -
		-- the egg is gone and the unit is standing there when it fades.
		SoundKit.play("EggCrack")
		flash.BackgroundTransparency = 0
		task.wait(CRACK_FLASH_SECONDS)

		egg:Destroy()

		local unit = UnitPreview.buildUnit(definition)
		unit.Parent = viewport
		frame(camera, unit, true)

		local name = if definition ~= nil then definition.displayName else request.towerId
		caption.Text = if request.duplicate
			then `{name}  ({request.rarityId})  -  duplicate, +{request.refunded} coins back`
			else `{name}  ({request.rarityId})`
		caption.TextTransparency = 0
		SoundKit.play("EggReveal")

		TweenService:Create(flash, TweenInfo.new(FLASH_FADE_SECONDS), { BackgroundTransparency = 1 }):Play()

		-- 4. SHOWCASE: the unit turns on a slow pedestal spin. Click (the
		-- dimmer is the whole screen) or wait to dismiss.
		local clicker = Instance.new("TextButton")
		clicker.Size = UDim2.fromScale(1, 1)
		clicker.BackgroundTransparency = 1
		clicker.Text = ""
		clicker.ZIndex = 20
		clicker.Parent = screen
		clicker.Activated:Connect(finish)

		local shown = 0

		while shown < SHOWCASE_SECONDS and not finished do
			unit:PivotTo(unit:GetPivot() * CFrame.Angles(0, math.rad(1.2), 0))
			task.wait(SHAKE_STEP)
			shown += SHAKE_STEP
		end

		-- 5. FADE: everything out together.
		if not finished then
			TweenService:Create(dimmer, TweenInfo.new(FADE_OUT_SECONDS), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(caption, TweenInfo.new(FADE_OUT_SECONDS), { TextTransparency = 1 }):Play()
			TweenService:Create(viewport, TweenInfo.new(FADE_OUT_SECONDS), { ImageTransparency = 1 }):Play()
			task.wait(FADE_OUT_SECONDS)
		end

		finish()
	end)
end

return EggReveal

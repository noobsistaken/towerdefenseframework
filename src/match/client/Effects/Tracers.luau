--!strict
--[[
	Shot tracers and splash bursts.

	Purely cosmetic and entirely client-side. The server has already applied
	the damage by the time TowerFired arrives; this only draws the line.

	Both live here rather than in two modules because both hang off the SAME
	TowerFired message, and a second subscriber would mean doing the tower-part
	lookup twice for every shot - the same reasoning EnemyVisuals gives for
	keeping health bars and damage numbers together.

	Minimal on purpose - Phase 5 owns the real effects pass. Without something
	here, towers firing is completely invisible and the whole combat loop
	looks broken while actually working, which makes Phase 2 impossible to
	judge by eye.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)

local SoundController = require(script.Parent.Parent.Audio.SoundController)

local Tracers = {}

local LIFETIME = 0.09
local THICKNESS = 0.22

--- How long a blast takes to expand and fade. Longer than a tracer: a shell
--- landing is a slower, heavier event than a bullet leaving a barrel, and at
--- 0.09s the expansion is too fast to read as an area.
local SPLASH_LIFETIME = 0.18

--- Fraction of the final diameter the burst starts at. Starting from zero
--- wastes most of the tween on a sphere too small to see.
local SPLASH_START_SCALE = 0.35

--- Warm orange, deliberately unlike the tracer's pale yellow: the two fire in
--- the same frame from the same tower and must not read as one effect.
local SPLASH_COLOR = Color3.fromRGB(255, 176, 78)

--- The replicated part for a tower, or nil if it has not arrived yet.
local function towerPart(towerId: number): BasePart?
	local folder = workspace:FindFirstChild(Constants.TOWER_FOLDER)

	if folder == nil then
		return nil
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("TowerId") == towerId then
			return child
		end
	end

	return nil
end

--- Where a tower's muzzle is. Read off the replicated part, so no network
--- message carries tower positions.
---
--- Top of the part rather than its centre, so the line leaves the barrel
--- instead of the tower's waist.
local function muzzleOf(part: BasePart): Vector3
	return part.Position + Vector3.new(0, part.Size.Y / 2, 0)
end

--- The splash radius of the level this tower is currently at, or 0 for a
--- single-target tower.
---
--- Derived from the part's attributes and shared config rather than sent,
--- for the same reason the fire cue below is: the level is already on the
--- part, and splashRadius is already in Config/Towers.luau.
local function splashRadiusOf(part: BasePart): number
	local defId = part:GetAttribute("TowerDefId")
	local level = part:GetAttribute("Level")

	if type(defId) ~= "string" or type(level) ~= "number" then
		return 0
	end

	local definition = Towers.find(defId)

	if definition == nil then
		return 0
	end

	local levelDefinition = Towers.levelAt(definition, level)

	return if levelDefinition ~= nil then levelDefinition.splashRadius else 0
end

--- Draws the blast for an area-damage shot, sized to the radius that was
--- actually applied.
---
--- A sphere rather than a flat ring on the ground because the server's test
--- is a true 3D distance - Splash.luau sums X, Y and Z - so a disc would
--- misdescribe what a Flak burst catches above the path.
---
--- Every flag here matches the tracer's: anchored, non-colliding, unqueryable
--- and shadowless, because this is scenery that must never touch a raycast.
--- Placement uses raycasts, and a burst that blocked one would refuse builds
--- for as long as it was on screen.
local function drawSplash(target: Vector3, radius: number)
	local burst = Instance.new("Part")
	burst.Name = "TDSplash"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.CastShadow = false
	burst.Material = Enum.Material.Neon
	burst.Color = SPLASH_COLOR
	burst.Transparency = 0.35
	burst.Size = Vector3.one * (radius * 2 * SPLASH_START_SCALE)
	burst.CFrame = CFrame.new(target)
	burst.Parent = workspace

	local info = TweenInfo.new(SPLASH_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(burst, info, { Size = Vector3.one * (radius * 2), Transparency = 1 }):Play()

	Debris:AddItem(burst, SPLASH_LIFETIME)
end

--- Draws one shot. Silently does nothing if the tower part has not replicated
--- yet, which can happen for the very first shot after a placement.
function Tracers.draw(towerId: number, target: Vector3)
	local part = towerPart(towerId)

	if part == nil then
		return
	end

	-- The fire cue is derived here rather than sent. A tower firing twice a
	-- second across sixty towers would be a PlaySound packet per shot, for a
	-- key the client can read off the part it already has.
	local defId = part:GetAttribute("TowerDefId")

	if type(defId) == "string" then
		SoundController.play(Sounds.fireKey(defId), part.Position)
	end

	local splashRadius = splashRadiusOf(part)

	-- Ahead of the beam rather than after it: the beam returns early on a
	-- zero-length shot, and a blast that landed should still be drawn.
	if splashRadius > 0 then
		drawSplash(target, splashRadius)
		SoundController.play("Splash", target)
	end

	-- No nil check: the part existing is what was uncertain, and that was
	-- already handled above.
	local origin = muzzleOf(part)
	local delta = target - origin
	local length = delta.Magnitude

	if length <= 0 then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "TDTracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 232, 160)
	beam.Size = Vector3.new(THICKNESS, THICKNESS, length)
	beam.CFrame = CFrame.lookAt(origin:Lerp(target, 0.5), target)
	beam.Parent = workspace

	TweenService:Create(beam, TweenInfo.new(LIFETIME), { Transparency = 1 }):Play()

	-- Debris rather than a task.delay: it survives this script erroring and
	-- cannot leak a part if the match ends mid-tween.
	Debris:AddItem(beam, LIFETIME)
end

return Tracers

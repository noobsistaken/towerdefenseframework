--!strict
--[[
	Shot tracers.

	Purely cosmetic and entirely client-side. The server has already applied
	the damage by the time TowerFired arrives; this only draws the line.

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

local SoundController = require(script.Parent.Parent.Audio.SoundController)

local Tracers = {}

local LIFETIME = 0.09
local THICKNESS = 0.22

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

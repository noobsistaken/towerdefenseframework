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

local Tracers = {}

local LIFETIME = 0.09
local THICKNESS = 0.22

--- Where a tower's muzzle is. Read off the replicated part, so no network
--- message carries tower positions.
local function towerPosition(towerId: number): Vector3?
	local folder = workspace:FindFirstChild(Constants.TOWER_FOLDER)

	if folder == nil then
		return nil
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("TowerId") == towerId then
			-- Top of the part rather than its centre, so the line leaves the
			-- barrel instead of the tower's waist.
			return child.Position + Vector3.new(0, child.Size.Y / 2, 0)
		end
	end

	return nil
end

--- Draws one shot. Silently does nothing if the tower part has not replicated
--- yet, which can happen for the very first shot after a placement.
function Tracers.draw(towerId: number, target: Vector3)
	local origin = towerPosition(towerId)

	if origin == nil then
		return
	end

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

--!strict
--[[
	One-shot particle bursts: a puff when a tower lands, a burst when an
	enemy dies.

	Built from ParticleEmitters rather than a Creator Store VFX pack, on
	purpose. Store VFX models ship scripts - every model audited this project
	has - and a particle burst is one emitter with a dozen properties, which
	is less work to write than to audit. The default emitter texture is fine
	for a placeholder pass; a real texture later is one property.

	Everything here is cosmetic, client-side, and inferred from replication
	the client already receives - the same reasoning the death SOUND uses:
	no network message carries any of it.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Bursts = {}

--- Warm gold, matching the cash the placement spent.
local PLACE_COLOR = Color3.fromRGB(240, 210, 120)

local ANCHOR_LIFETIME = 1.5

--- Emits one burst of `count` particles at `position` in `color`.
function Bursts.emit(position: Vector3, color: Color3, count: number)
	local anchor = Instance.new("Part")
	anchor.Name = "TDBurst"
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.25, 0.55)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Emit() only; a Rate would keep spraying for the anchor's whole lifetime.
	emitter.Rate = 0
	emitter.Parent = anchor

	anchor.Parent = workspace
	emitter:Emit(count)

	-- Debris rather than task.delay: survives this script erroring and cannot
	-- leak a part if the match ends mid-burst. Same reasoning as the tracer.
	Debris:AddItem(anchor, ANCHOR_LIFETIME)
end

--- Watches for towers landing and puffs at their base. Returns a cleanup
--- function.
---
--- Inferred from the tower folder rather than sent: the server parents a new
--- tower part on success, and that replication IS the placement signal.
function Bursts.start(): () -> ()
	local folder = workspace:WaitForChild(Constants.TOWER_FOLDER)

	local connection = folder.ChildAdded:Connect(function(child)
		if not child:IsA("BasePart") then
			return
		end

		-- A typed capture: the IsA refinement does not survive into the
		-- deferred closure.
		local part: BasePart = child

		-- Deferred so the part's Size and CFrame are readable; a pooled or
		-- freshly created part can be parented before its properties settle.
		task.defer(function()
			if part.Parent ~= folder then
				return
			end

			Bursts.emit(part.Position - Vector3.new(0, part.Size.Y / 2 - 0.5, 0), PLACE_COLOR, 24)
		end)
	end)

	return function()
		connection:Disconnect()
	end
end

return Bursts

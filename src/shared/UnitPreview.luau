--!strict
--[[
	Shared unit-model builder for viewport previews.

	One builder feeding the egg reveal, the reroll portrait, and the match
	shop's buttons, so no two screens can disagree about what a unit looks
	like. Extracted from EggReveal when the shop bar needed it - the match
	place mounts none of the lobby's UI modules.

	The rig templates live in ReplicatedStorage.RigTemplates IN THE PLACE,
	not the repo; a fresh clone degrades to the tower's coloured config box,
	never to a broken preview.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local Types = require(script.Parent.Types)

local UnitPreview = {}

--- The unit: the rig template when the place carries one, the tower's
--- config box when it does not.
function UnitPreview.buildUnit(definition: Types.TowerDefinition?): Model
	local model = Instance.new("Model")

	if definition ~= nil then
		local rigName = definition.rig
		local templates = ReplicatedStorage:FindFirstChild("RigTemplates")
		local template = if templates ~= nil and rigName ~= nil then templates:FindFirstChild(rigName) else nil

		if template ~= nil and template:IsA("Model") then
			local rig = template:Clone()

			-- Statues only: no scripts ride along (templates are stripped at
			-- insert), and everything anchors because a viewport simulates
			-- no physics to catch a falling limb.
			for _, descendant in rig:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end

			rig:PivotTo(CFrame.new(0, 0, 0))
			rig.Parent = model

			return model
		end
	end

	-- Fallback: the same coloured box the match shows when a template is
	-- missing, so the preview always shows SOMETHING true.
	local box = Instance.new("Part")
	box.Anchored = true
	box.Material = Enum.Material.SmoothPlastic

	if definition ~= nil then
		local level = definition.levels[1]
		box.Size = level.modelSize
		box.Color = level.color
	else
		box.Size = Vector3.new(4, 6, 4)
		box.Color = Theme.MUTED
	end

	box.CFrame = CFrame.new(0, 0, 0)
	box.Parent = model

	return model
end

--- Points a viewport camera at a model, framed by its bounding box.
--- `fill` scales the camera distance: 1 is the reveal's framing, smaller
--- fills more of the viewport (the shop's small buttons use 0.72).
function UnitPreview.frame(camera: Camera, model: Model, lowAngle: boolean, fill: number?)
	local _, extents = model:GetBoundingBox()
	local distance = (extents.Magnitude * 0.85 + 2) * (fill or 1)
	local height = if lowAngle then extents.Y * 0.15 else extents.Y * 0.05

	camera.CFrame = CFrame.lookAt(Vector3.new(0, height, distance), Vector3.new(0, 0, 0))
end

return UnitPreview

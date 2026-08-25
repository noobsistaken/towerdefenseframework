--!strict
--[[
	Placement input, ghost preview and range indicator.

	The preview calls the SAME Placement.validate the server calls
	(src/shared/Placement.luau). That is the point of putting those rules in
	shared: a second client-side approximation of "can I build here" would
	drift, and the symptom is a green ghost the server then refuses.

	Everything here is advisory. The ghost turning green is a prediction, not
	a permission - the server re-validates every request and its answer is the
	only one that counts.

	Input model:
	    left click, holding a tower   place it
	    left click, holding nothing   select the tower under the cursor
	    right click / Escape          cancel or deselect
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Footprint = require(ReplicatedStorage.Shared.Footprint)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ReplicatedStorage.Net)
local Placement = require(ReplicatedStorage.Shared.Placement)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Types = require(ReplicatedStorage.Shared.Types)
local Wire = require(ReplicatedStorage.Shared.Wire)

local atoms = require(script.Parent.Parent.State.atoms)

local PlacementController = {}

local VALID_COLOR = Color3.fromRGB(96, 210, 128)
local INVALID_COLOR = Color3.fromRGB(216, 84, 84)
local CANCEL_ACTION = "TDCancelPlacement"

local camera = workspace.CurrentCamera

local janitor = Janitor.new()
local ghost: Part? = nil
local ghostRig: Model? = nil
local rangeDisc: Part? = nil
--- Last validated position, so the click handler does not have to redo the
--- raycast and can never place somewhere the preview did not show.
local lastValid: Vector3? = nil

-- ---------------------------------------------------------------------------
-- World queries
-- ---------------------------------------------------------------------------

--- Raycast the cursor onto the map. Restricted to the map folder with an
--- Include filter, so the ray cannot land on an enemy, a tower, or a player
--- and report a position the validator would then reject for a confusing
--- reason.
local function cursorOnMap(): Vector3?
	local mapFolder = workspace:FindFirstChild(Constants.MAP_FOLDER)

	if mapFolder == nil or camera == nil then
		return nil
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { mapFolder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * Constants.PLACEMENT_RAY_LENGTH, params)

	if result == nil then
		return nil
	end

	return result.Position
end

--- Towers already placed, read straight off their replicated parts.
---
--- No network message is needed for this: TowerSystem writes TowerDefId as an
--- attribute and the part's position is already replicated (D5). Only X and Z
--- matter, and Footprint.overlaps ignores Y, so the part position can be used
--- as-is without reconstructing the base height.
local function existingTowers(): { Placement.ExistingTower }
	local folder = workspace:FindFirstChild(Constants.TOWER_FOLDER)
	local list: { Placement.ExistingTower } = {}

	if folder == nil then
		return list
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end

		local defId = child:GetAttribute("TowerDefId")

		if typeof(defId) ~= "string" then
			continue
		end

		local definition = Towers.find(defId)

		if definition == nil then
			continue
		end

		table.insert(list, {
			position = child.Position,
			radius = Footprint.radius(definition.footprint),
		})
	end

	return list
end

-- ---------------------------------------------------------------------------
-- Ghost
-- ---------------------------------------------------------------------------

local function destroyGhost()
	if ghost ~= nil then
		ghost:Destroy()
		ghost = nil
	end

	if ghostRig ~= nil then
		ghostRig:Destroy()
		ghostRig = nil
	end

	if rangeDisc ~= nil then
		rangeDisc:Destroy()
		rangeDisc = nil
	end

	lastValid = nil
end

local function createGhost(definition: Types.TowerDefinition)
	destroyGhost()

	local level = definition.levels[1]

	local part = Instance.new("Part")
	part.Name = "TDGhost"
	part.Size = level.modelSize
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.4
	part.Material = Enum.Material.Neon
	part.Parent = workspace

	-- Flat disc showing range. A cylinder rotated onto its side reads far
	-- better on the ground than a sphere, which hides the footprint under it.
	local disc = Instance.new("Part")
	disc.Name = "TDRange"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, level.range * 2, level.range * 2)
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Transparency = 0.85
	disc.Material = Enum.Material.Neon
	disc.Color = VALID_COLOR
	disc.Parent = workspace

	-- The ghost previews the CHARACTER that will be built, not a box, when
	-- the tower has a rig and this client can see the template. Fitted with
	-- the same shared scale the server uses, so the preview cannot lie about
	-- the size of what lands.
	local templates = ReplicatedStorage:FindFirstChild("RigTemplates")
	local template = if templates ~= nil and definition.rig ~= nil
		then templates:FindFirstChild(definition.rig)
		else nil

	if template ~= nil and template:IsA("Model") then
		local rig = template:Clone()
		rig.Name = "TDGhostRig"

		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Humanoid") then
				descendant:Destroy()
			end
		end

		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.CastShadow = false
				descendant.Transparency = math.clamp(descendant.Transparency + 0.45, 0.45, 1)
			end
		end

		rig.PrimaryPart = nil

		local boxCFrame, boxSize = rig:GetBoundingBox()
		rig.WorldPivot = boxCFrame

		if boxSize.Y > 0.01 then
			rig:ScaleTo(level.modelSize.Y * Constants.RIG_SCALE / boxSize.Y)
		end

		rig.Parent = workspace
		ghostRig = rig

		-- The rig IS the preview now; the box would just wrap it in fog.
		part.Transparency = 1
	end

	ghost = part
	rangeDisc = disc
end

--- Runs every frame while a tower is held: raycast, validate, recolour.
local function updateGhost()
	local part = ghost
	local disc = rangeDisc

	if part == nil or disc == nil then
		return
	end

	local defId = atoms.selectedTowerDefId()

	if defId == nil then
		return
	end

	local definition = Towers.find(defId)
	local map = MapRegistry.find(atoms.mapId())

	if definition == nil or map == nil then
		return
	end

	local hit = cursorOnMap()

	if hit == nil then
		part.Transparency = 1
		disc.Transparency = 1

		if ghostRig ~= nil then
			ghostRig:PivotTo(CFrame.new(0, -1000, 0))
		end

		lastValid = nil
		return
	end

	local result = Placement.validate({
		definition = definition,
		position = hit,
		map = map,
		existing = existingTowers(),
		unlocked = table.find(atoms.unlockedTowers(), defId) ~= nil,
		cash = atoms.cash(),
		-- Not tracked client-side. The server owns the cap; showing the ghost
		-- as valid and letting the request be refused is better than keeping
		-- a second count here that could disagree.
		ownedOfType = 0,
		canBuildNow = atoms.matchState() == "Preparing" or atoms.matchState() == "WaveActive",
	})

	local resting = result.position or Vector3.new(hit.X, hit.Y, hit.Z)
	local level = definition.levels[1]

	part.Transparency = if ghostRig ~= nil then 1 else 0.4
	part.Color = if result.ok then VALID_COLOR else INVALID_COLOR
	part.CFrame = CFrame.new(resting + Vector3.new(0, level.modelSize.Y / 2, 0))

	local rig = ghostRig

	if rig ~= nil then
		-- Feet on the ground the cursor is pointing at, tinted by validity.
		-- The tint washes over mesh textures rather than replacing them,
		-- which still reads: the whole silhouette goes green or red.
		rig:PivotTo(CFrame.new(resting))

		local rigCFrame, rigSize = rig:GetBoundingBox()
		local lift = resting.Y - (rigCFrame.Position.Y - rigSize.Y / 2)
		rig:PivotTo(rig:GetPivot() + Vector3.new(0, lift, 0))

		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = part.Color
			end
		end
	end

	disc.Transparency = 0.85
	disc.Color = part.Color
	-- Cylinders extrude along their local X, so the disc has to be tipped
	-- onto its side to lie flat on the ground.
	disc.CFrame = CFrame.new(resting + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))

	lastValid = if result.ok then resting else nil
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function trySelectTowerUnderCursor()
	local folder = workspace:FindFirstChild(Constants.TOWER_FOLDER)

	if folder == nil or camera == nil then
		atoms.selectedTowerId(nil)
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * Constants.PLACEMENT_RAY_LENGTH, params)

	if result == nil then
		atoms.selectedTowerId(nil)
		return
	end

	local towerId = result.Instance:GetAttribute("TowerId")

	if typeof(towerId) == "number" then
		atoms.selectedTowerId(towerId)
	else
		atoms.selectedTowerId(nil)
	end
end

local function onPrimaryDown()
	local defId = atoms.selectedTowerDefId()

	if defId == nil then
		trySelectTowerUnderCursor()
		return
	end

	local position = lastValid

	if position == nil then
		-- Invalid spot. Stay in placement mode rather than dropping the
		-- selection, so a misclick does not cost the player their choice.
		return
	end

	Net.RequestPlaceTower.Fire({
		towerDefId = defId,
		position = Wire.toWire(position),
		rotationY = 0,
	})
end

local function cancel()
	atoms.selectedTowerDefId(nil)
	atoms.selectedTowerId(nil)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PlacementController.start()
	janitor:Add(
		Charm.subscribe(atoms.selectedTowerDefId, function(defId: string?)
			if defId == nil then
				destroyGhost()
				return
			end

			local definition = Towers.find(defId)

			if definition == nil then
				destroyGhost()
				return
			end

			-- Picking a tower to place closes the inspector; the two panels
			-- occupy the same corner and both being open reads as a bug.
			atoms.selectedTowerId(nil)
			createGhost(definition)
		end),
		true
	)

	janitor:Add(
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			-- `processed` is true when the click landed on UI. Without this
			-- check, clicking a shop button also fires a placement.
			if processed then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				onPrimaryDown()
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				cancel()
			end
		end),
		"Disconnect"
	)

	-- Escape is bound through ContextActionService rather than watched in
	-- InputBegan so it takes priority over the Roblox menu.
	ContextActionService:BindAction(CANCEL_ACTION, function(_name, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			cancel()
		end

		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Escape)

	janitor:Add(function()
		ContextActionService:UnbindAction(CANCEL_ACTION)
	end, true)

	janitor:Add(RunService.RenderStepped:Connect(updateGhost), "Disconnect")
	janitor:Add(destroyGhost, true)

	-- Placement is meaningless once the match is over, and a ghost left
	-- hanging over the results screen looks broken.
	janitor:Add(
		-- `string`, not Types.MatchState: Charm widens the literal union when
		-- it infers the atom's payload type, so a narrower annotation here
		-- fails to match the subscriber signature.
		Charm.subscribe(atoms.matchState, function(state: string)
			if state == "Victory" or state == "Defeat" then
				cancel()
			end
		end),
		true
	)
end

function PlacementController.stop()
	janitor:Destroy()
end

return PlacementController

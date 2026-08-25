--!strict
--[[
	Dresses a gameplay part in a character rig.

	THE SHAPE OF THIS, and it is deliberate: the rig is DECORATION welded onto
	the part that already exists. The part keeps its size, its attributes, its
	CanQuery flag and its identity - it just turns invisible. Nothing that
	looks a tower up, raycasts one, reads its Range, or hangs a range ring off
	its base has to change, because from every one of those angles the tower is
	exactly the part it always was.

	The alternative - making the tower BE a Model - breaks silently rather than
	loudly. Every client lookup filters on `child:IsA("BasePart")`
	(Tracers.luau, TowerInspector.luau, PlacementController.luau) and a Model
	is not one, so towers would simply stop being found: no error, no tracer,
	no inspector, no range ring. In a codebase worked on for someone who does
	not read Luau, a change that fails loudly is worth a lot more than one that
	fails quietly.

	TEMPLATES LIVE IN THE PLACE, not in the repo, under
	ServerStorage.RigTemplates. That is a real gap - a fresh clone has no rigs -
	so every lookup here degrades to "no rig" and the coloured placeholder part
	stays visible. The game is never broken by a missing template, only
	plainer.

	Rig parts are ANCHORED rather than welded, because towers never move.
	An enemy rig would need the opposite - unanchored and welded to the moving
	host - and that is a different function, not this one.
]]

local ServerStorage = game:GetService("ServerStorage")

local Rigs = {}

local TEMPLATE_FOLDER = "RigTemplates"

--- Name given to the rig once attached, so it can be found and replaced.
Rigs.CHILD_NAME = "Rig"

local function templateFolder(): Instance?
	return ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
end

--- The template for `name`, or nil if this place has no rigs installed.
function Rigs.find(name: string): Model?
	local folder = templateFolder()

	if folder == nil then
		return nil
	end

	local template = folder:FindFirstChild(name)

	return if template ~= nil and template:IsA("Model") then template else nil
end

--- Attribute on an attached rig naming its template, so a pooled part that
--- comes back still dressed can be matched against its next occupant.
Rigs.TEMPLATE_ATTR = "RigTemplate"

--- Attribute recording the host height the rig was fitted to. Two enemy
--- types can share one template at very different sizes - a recycled 4-stud
--- Zombie rig must not be kept on an 11-stud Titan just because the template
--- name matches.
Rigs.FITTED_ATTR = "FittedHeight"

--- Removes any rig previously attached to `host`.
local function clearRig(host: BasePart)
	local existing = host:FindFirstChild(Rigs.CHILD_NAME)

	if existing ~= nil then
		existing:Destroy()
	end
end

--- Scales `model` so its total height matches `height`, and sits it with its
--- feet on the bottom face of `host`, facing `rotationY` degrees.
---
--- Measured rather than assumed. A model's pivot is its PrimaryPart's CFrame,
--- which on a humanoid rig is somewhere around the chest - so pivoting to a
--- target position puts the chest there, not the feet. Reading the bounding
--- box back after the move and correcting is the only way this lands right for
--- a rig whose proportions we do not control.
local function fit(model: Model, host: BasePart, rotationY: number)
	local extents = model:GetExtentsSize()

	if extents.Y > 0.01 then
		model:ScaleTo(host.Size.Y / extents.Y)
	end

	model:PivotTo(CFrame.new(host.Position) * CFrame.Angles(0, math.rad(rotationY), 0))

	local boxCFrame, boxSize = model:GetBoundingBox()
	local currentBottom = boxCFrame.Position.Y - boxSize.Y / 2
	local wantedBottom = host.Position.Y - host.Size.Y / 2

	model:PivotTo(model:GetPivot() + Vector3.new(0, wantedBottom - currentBottom, 0))
end

--- Dresses `host` in the rig called `templateName`.
---
--- Returns true if a rig was attached. False means this place has no such
--- template and the caller should leave its placeholder part visible.
function Rigs.attachStatic(host: BasePart, templateName: string, rotationY: number): boolean
	clearRig(host)

	local template = Rigs.find(templateName)

	if template == nil then
		return false
	end

	local rig = template:Clone()
	rig.Name = Rigs.CHILD_NAME

	-- Belt and braces. The templates in ServerStorage were stripped when they
	-- were installed, but a rig is the one thing in this project that arrives
	-- from the Creator Store, and a script that reached the running game would
	-- be running with full server trust.
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Humanoid") then
			descendant:Destroy()
		end
	end

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			-- NOT queryable. The host part is what placement and selection
			-- raycast against; a rig limb answering those would let a player
			-- select a tower by its hat, and would give splash a second thing
			-- to find at the same position.
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end

	rig.Parent = host
	fit(rig, host, rotationY)

	return true
end

--- Removes any rig from `host`. For callers outside this module - the enemy
--- view hands pooled parts between rigged and unrigged occupants.
function Rigs.clear(host: BasePart)
	clearRig(host)
end

--- The parts a moving rig contributes to the per-frame bulk move, each with
--- its offset from the host.
export type Offsets = { { part: BasePart, offset: CFrame } }

local function offsetsFor(host: BasePart, rig: Model): Offsets
	local offsets: Offsets = {}
	local hostInverse = host.CFrame:Inverse()

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(offsets, { part = descendant, offset = hostInverse * descendant.CFrame })
		end
	end

	return offsets
end

--- Dresses `host` in `templateName`, for a host that MOVES, and returns the
--- offsets the mover must carry. nil means no rig - keep the box visible.
---
--- NO WELDS OF ANY KIND, and that is a measured decision, not a style. The
--- enemy mover is a single workspace:BulkMoveTo, and BulkMoveTo moves
--- exactly the parts in its list - nothing attached to them. Both attachment
--- mechanisms were tried against the live game and both failed the same way,
--- the rig frozen at its attach point while the host walked away at 12
--- studs/s: a WeldConstraint is solved by physics and a teleported anchored
--- part never wakes the solver, and a classic Weld joint fared no better
--- under BulkMoveTo. So the rig parts stay ANCHORED - consistent with this
--- project simulating nothing by physics - and EnemyView appends them to the
--- same bulk move using the offsets returned here.
---
--- Two more measured facts shape the fitting: Model.WorldPivot is IGNORED
--- while PrimaryPart is set, and an unassigned WorldPivot is the ORIGIN, not
--- the bounding-box centre - either wrong state sinks the rig into the
--- walkway.
function Rigs.attachMoving(host: BasePart, templateName: string): Offsets?
	local existing = host:FindFirstChild(Rigs.CHILD_NAME)

	-- A pooled part may come back still wearing the right rig at the right
	-- size. Keep it - clone-and-fit is the expensive path - but recompute the
	-- offsets from where things stand rather than trusting stored state.
	if
		existing ~= nil
		and existing:IsA("Model")
		and existing:GetAttribute(Rigs.TEMPLATE_ATTR) == templateName
		and existing:GetAttribute(Rigs.FITTED_ATTR) == host.Size.Y
	then
		return offsetsFor(host, existing)
	end

	clearRig(host)

	local template = Rigs.find(templateName)

	if template == nil then
		return nil
	end

	local rig = template:Clone()
	rig.Name = Rigs.CHILD_NAME
	rig:SetAttribute(Rigs.TEMPLATE_ATTR, templateName)
	rig:SetAttribute(Rigs.FITTED_ATTR, host.Size.Y)

	-- Same belt-and-braces as attachStatic, plus every joint and constraint:
	-- the rig is a statue moved by explicit CFrames, and a surviving Motor6D
	-- or BallSocketConstraint leaves limbs something else thinks it owns.
	for _, descendant in rig:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Humanoid")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
			or descendant:IsA("WeldConstraint")
		then
			descendant:Destroy()
		end
	end

	-- Refuse a rig with no visible geometry. The caller goes transparent on
	-- success, so accepting an all-invisible rig renders the enemy as
	-- NOTHING - towers keep firing at empty air and the player learns the
	-- game is broken instead of the template.
	local visible = false

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Transparency < 1 then
				visible = true
			end

			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			-- The host is what splash and any future query finds; a rig limb
			-- answering raycasts would double-count the enemy.
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end

	if not visible then
		rig:Destroy()
		return nil
	end

	rig.PrimaryPart = nil

	local boxCFrame, boxSize = rig:GetBoundingBox()
	rig.WorldPivot = boxCFrame

	if boxSize.Y > 0.01 then
		rig:ScaleTo(host.Size.Y / boxSize.Y)
	end

	rig:PivotTo(host.CFrame)

	local offsets = offsetsFor(host, rig)

	rig.Parent = host

	return offsets
end

--- Re-fits an already-attached rig after its host changed size, e.g. on an
--- upgrade. Does nothing if there is no rig.
function Rigs.refit(host: BasePart, rotationY: number)
	local rig = host:FindFirstChild(Rigs.CHILD_NAME)

	if rig ~= nil and rig:IsA("Model") then
		-- Back to scale 1 first: ScaleTo is absolute, but the measurement it
		-- is derived from is not, so re-fitting a rig that is already scaled
		-- would compound the factor on every upgrade.
		rig:ScaleTo(1)
		fit(rig, host, rotationY)
	end
end

return Rigs

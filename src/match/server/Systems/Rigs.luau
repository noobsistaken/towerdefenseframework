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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Rigs = {}

local TEMPLATE_FOLDER = "RigTemplates"

--- Name given to the rig once attached, so it can be found and replaced.
Rigs.CHILD_NAME = "Rig"

--- Templates live in ReplicatedStorage, NOT ServerStorage, because the
--- placement ghost is client-built and a client cannot see ServerStorage.
--- The cost is that clients can read the rig meshes - which they render
--- anyway the moment one spawns, so nothing is exposed that play does not.
local function templateFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
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

--- The animation joints' root, searched RECURSIVELY: store rigs nest their
--- parts inside inner models, and several tower templates carry a
--- PrimaryPart that is a VEST, not the body - anchoring the vest would leave
--- the actual joint tree dangling.
local function animationRoot(model: Model): BasePart?
	local named = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Torso", true)

	if named ~= nil and named:IsA("BasePart") then
		return named
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureAnimator(rig: Model): Animator
	local foundController = rig:FindFirstChildWhichIsA("AnimationController")
	local controller: AnimationController

	if foundController ~= nil then
		controller = foundController
	else
		controller = Instance.new("AnimationController")
		controller.Parent = rig
	end

	local foundAnimator = controller:FindFirstChildWhichIsA("Animator")
	local animator: Animator

	if foundAnimator ~= nil then
		animator = foundAnimator
	else
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	return animator
end

--- Idle cycles by TEMPLATE, in code rather than as Studio attributes, so the
--- roster is diffable and reviewed like everything else. Only the templates
--- that measured as ANIMATABLE appear - the id is the R6 idle, the one that
--- moved these Motor6D rigs when probed (limb swing 0.50-0.72); both R15
--- idles and both tool-hold animations moved nothing on any of them.
local R6_IDLE = "rbxassetid://180435792"

local IDLE_ANIMATIONS: { [string]: string } = {
	SwatSoldier = R6_IDLE,
	VDVSoldier = R6_IDLE,
	WinterSoldier = R6_IDLE,
	ToySoldier = R6_IDLE,
}

--- Layered over the idle at Action priority: the R6 tool-hold pose, which
--- raises the right arm - and the weapon welded to it - to a firing hold.
---
--- This one was nearly missed. The first animation probe measured limb
--- MOVEMENT over time and read 0.0 for every hold candidate, because a hold
--- is a static POSE: it moves the arm once and keeps it there. Re-measured
--- as pose-versus-baseline it scores 3.5, and layered over the idle the arm
--- stays put (drift 0.005) while the body keeps swaying (0.65).
local R6_TOOL_HOLD = "rbxassetid://182393478"

local HOLD_ANIMATIONS: { [string]: string } = {
	SwatSoldier = R6_TOOL_HOLD,
	VDVSoldier = R6_TOOL_HOLD,
	WinterSoldier = R6_TOOL_HOLD,
	ToySoldier = R6_TOOL_HOLD,
}

--- Whether anything in this rig can be DRIVEN by an Animator. A rig with no
--- animation joints must never have its limbs unanchored: unanchored parts
--- held by nothing simply fall out of the world - measured, the Rifleman
--- rig lost 9 of its 10 parts in about a second.
local function hasAnimationJoints(rig: Model): boolean
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			return true
		end
	end

	return false
end

local function playIdle(rig: Model, templateName: string)
	local animationId = IDLE_ANIMATIONS[templateName]

	if animationId == nil then
		return
	end

	local animator = ensureAnimator(rig)

	if #animator:GetPlayingAnimationTracks() > 0 then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	track:Play()

	local holdId = HOLD_ANIMATIONS[templateName]

	if holdId ~= nil then
		local holdAnimation = Instance.new("Animation")
		holdAnimation.AnimationId = holdId

		local hold = animator:LoadAnimation(holdAnimation)
		hold.Priority = Enum.AnimationPriority.Action
		hold.Looped = true
		hold:Play()
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
	-- Pivot about the bounding-box CENTRE with the ROOT part's ORIENTATION.
	-- The box's own axes are whatever orientation the template happened to be
	-- saved at; the root's axes are the rig's idea of forward - a
	-- HumanoidRootPart faces the character's front - and forward is what has
	-- to point down rotationY here, and down the lane for an enemy. Pivoting
	-- by the box axes is how a store rig ends up marching sideways.
	local forward = animationRoot(model)

	model.PrimaryPart = nil

	local boxCFrame, boxSize = model:GetBoundingBox()

	if forward ~= nil and forward:IsA("BasePart") then
		model.WorldPivot = CFrame.fromMatrix(boxCFrame.Position, forward.CFrame.XVector, forward.CFrame.YVector)
	else
		model.WorldPivot = boxCFrame
	end

	if boxSize.Y > 0.01 then
		model:ScaleTo(host.Size.Y * Constants.RIG_SCALE / boxSize.Y)
	end

	model:PivotTo(CFrame.new(host.Position) * CFrame.Angles(0, math.rad(rotationY), 0))

	local afterCFrame, afterSize = model:GetBoundingBox()
	local currentBottom = afterCFrame.Position.Y - afterSize.Y / 2
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

	-- Belt and braces. The templates were stripped at install, but a rig is
	-- the one thing in this project that arrives from the Creator Store, and
	-- a script that reached the running game would run with full server
	-- trust. BallSockets go too: they are ragdoll physics, and the limbs are
	-- about to be freed for the idle animation.
	for _, descendant in rig:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Humanoid")
			or descendant:IsA("BallSocketConstraint")
			or descendant:IsA("NoCollisionConstraint")
		then
			descendant:Destroy()
		end
	end

	-- Root anchored and limbs free ONLY when joints exist to hold them - the
	-- shape a moving rig uses, minus the movement. A fully anchored statue
	-- cannot animate, but an unanchored part with no joint falls out of the
	-- world, so a jointless rig stays a fully anchored statue.
	local root = animationRoot(rig)
	local animated = hasAnimationJoints(rig)

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = if animated then descendant == root else true
			descendant.Massless = true
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
	playIdle(rig, templateName)

	return true
end

--- Removes any rig from `host`. For callers outside this module - the enemy
--- view hands pooled parts between rigged and unrigged occupants.
function Rigs.clear(host: BasePart)
	clearRig(host)
end

--- A moving rig's handle: the one part EnemyView drives directly, at its
--- offset from the host.
export type MovingRig = { root: BasePart, offset: CFrame }

--- The walk cycle every walking rig plays. One constant rather than config
--- because exactly one rig walks today; move it to the template (an
--- attribute) or the enemy definition when a second walking rig exists.
---
--- Roblox's own R15 walk. Verified live before being relied on: it loads and
--- plays on the noobsv8 rig's AnimationConstraints with NO Humanoid present,
--- driven by a plain AnimationController.
local WALK_ANIMATION = "rbxassetid://507777826"

--- A template can override the walk cycle with a `WalkAnimation` attribute -
--- set at install, read here. Needed because animations bind to joints by
--- NAME: the R15 walk drives AnimationConstraint rigs like noobsv8, while a
--- Motor6D rig from the store answers to different joint names and gets its
--- own id, chosen by measuring which animation actually moves its limbs.
local WALK_ANIM_ATTR = "WalkAnimation"

--- Playback speed that reads as "walking" for a standard avatar moving at
--- 16 studs/s; scaled by each enemy's real speed so feet roughly track the
--- ground instead of moonwalking.
local WALK_REFERENCE_SPEED = 16

local function playWalk(rig: Model, walkSpeed: number)
	local animator = ensureAnimator(rig)

	-- A pooled rig comes back with its track still in the playing state, so
	-- only start one when nothing is playing - a second Play would stack.
	if #animator:GetPlayingAnimationTracks() > 0 then
		return
	end

	local animation = Instance.new("Animation")
	local override = rig:GetAttribute(WALK_ANIM_ATTR)
	animation.AnimationId = if type(override) == "string" and override ~= "" then override else WALK_ANIMATION

	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()
	track:AdjustSpeed(walkSpeed / WALK_REFERENCE_SPEED)
end

local function rootOf(rig: Model): BasePart?
	return animationRoot(rig)
end

--- Dresses `host` in `templateName` for a host that MOVES, plays its walk
--- cycle, and returns the handle the mover needs. nil means no rig - keep
--- the box visible.
---
--- HOW A MOVING RIG MOVES, all of it measured against the live game rather
--- than assumed, because the first two designs failed exactly here:
---
--- * BulkMoveTo moves ONLY the parts in its list. A WeldConstraint never
---   wakes, a classic Weld joint fares no better - both left the rig frozen
---   while its host walked away at 12 studs/s.
--- * A DIRECT CFrame write on a rig's anchored root DOES carry every jointed
---   limb with it: measured 24.98 of 25 studs. So EnemyView keeps the host
---   in its bulk move and drives each rig root with one direct write.
--- * The rig's AnimationConstraints, kept rather than stripped, are driven
---   by a plain AnimationController + Animator with NO Humanoid - so the
---   walk cycle animates limbs relative to the root the mover is driving.
---   A Humanoid would be a second authority over position, which is the one
---   thing D2 forbids.
--- * BallSocketConstraints are stripped: they are ragdoll physics, and with
---   the Humanoid gone they would fight the animation for the limbs.
---
--- Model.WorldPivot is IGNORED while PrimaryPart is set, and an unassigned
--- WorldPivot is the ORIGIN - either wrong state sinks the rig into the
--- walkway. Also measured.
function Rigs.attachMoving(host: BasePart, templateName: string, walkSpeed: number): MovingRig?
	local existing = host:FindFirstChild(Rigs.CHILD_NAME)

	-- A pooled part may come back still wearing the right rig at the right
	-- size. Keep it - clone-and-fit is the expensive path - but recompute the
	-- handle from where things stand rather than trusting stored state.
	if
		existing ~= nil
		and existing:IsA("Model")
		and existing:GetAttribute(Rigs.TEMPLATE_ATTR) == templateName
		and existing:GetAttribute(Rigs.FITTED_ATTR) == host.Size.Y
	then
		local keptRoot = rootOf(existing)

		if keptRoot ~= nil then
			playWalk(existing, walkSpeed)
			return { root = keptRoot, offset = host.CFrame:Inverse() * keptRoot.CFrame }
		end
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

	-- Belt and braces on scripts and Humanoids, then the ragdoll physics.
	-- KEPT deliberately: AnimationConstraint and Motor6D (the animation
	-- drives them), Weld and RigidConstraint (accessories hang from them),
	-- and the Attachments they all reference.
	for _, descendant in rig:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Humanoid")
			or descendant:IsA("BallSocketConstraint")
			or descendant:IsA("NoCollisionConstraint")
		then
			descendant:Destroy()
		end
	end

	local root = rootOf(rig)

	if root == nil then
		rig:Destroy()
		return nil
	end

	-- Refuse a rig with no visible geometry. The caller goes transparent on
	-- success, so accepting an all-invisible rig renders the enemy as
	-- NOTHING - towers keep firing at empty air and the player learns the
	-- game is broken instead of the template.
	local visible = false
	local animated = hasAnimationJoints(rig)

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Transparency < 1 then
				visible = true
			end

			-- Root anchored, limbs free on their joints so the walk cycle
			-- can move them while the root is driven along the path. A rig
			-- with NO joints gets welded to the root below instead - freed
			-- parts held by nothing fall out of the world.
			descendant.Anchored = descendant == root
			descendant.Massless = true
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

	-- Same facing rule as fit(): pivot at the box centre with the ROOT's
	-- orientation, so the rig's own forward - not the box's storage
	-- orientation - is what aligns to the host's walk direction.
	local boxCFrame, boxSize = rig:GetBoundingBox()
	rig.WorldPivot = CFrame.fromMatrix(boxCFrame.Position, root.CFrame.XVector, root.CFrame.YVector)

	if boxSize.Y > 0.01 then
		rig:ScaleTo(host.Size.Y * Constants.RIG_SCALE / boxSize.Y)
	end

	rig:PivotTo(host.CFrame)

	-- Feet on the bottom of the hitbox rather than floating at its centre:
	-- at half scale a centred rig hangs mid-air.
	local afterCFrame, afterSize = rig:GetBoundingBox()
	local bottomDelta = (host.Position.Y - host.Size.Y / 2) - (afterCFrame.Position.Y - afterSize.Y / 2)
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, bottomDelta, 0))

	if not animated then
		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= root then
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.C0 = root.CFrame:Inverse() * descendant.CFrame
				weld.Parent = root
			end
		end
	end

	local offset = host.CFrame:Inverse() * root.CFrame

	rig.Parent = host

	if animated then
		playWalk(rig, walkSpeed)
	end

	return { root = root, offset = offset }
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

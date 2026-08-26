--!strict
--[[
	Panel for the currently selected tower: stats, upgrade, sell, targeting.

	Everything shown here is read off the tower part's ATTRIBUTES, which the
	server writes and Roblox replicates (ARCHITECTURE.md D5). There is no
	"inspect tower" network message and no client-side mirror of tower state
	to fall out of date.

	Buttons on a tower this player does not own are hidden rather than
	disabled: someone else's tower is not a thing you can act on at all, and a
	greyed Sell button invites a support ticket.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Motion = require(script.Parent.Motion)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Wire = require(ReplicatedStorage.Shared.Wire)

local Theme = require(ReplicatedStorage.Shared.Theme)
local atoms = require(script.Parent.Parent.State.atoms)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local e = React.createElement

local localPlayer = Players.LocalPlayer

--- Whether this device can hover at all.
---
--- Read once: a session does not gain or lose a mouse. On a device without
--- one there is nothing to hover, so gating the upgrade preview behind hover
--- would make it permanently unreachable - it stays visible there instead.
local HOVER_AVAILABLE = UserInputService.MouseEnabled

type TowerInfo = {
	towerId: number,
	defId: string,
	level: number,
	ownerUserId: number,
	targetingMode: string,
	sellValue: number,
	--- The server's TRAITED combat numbers, from the replicated attributes.
	--- The config's base values must not drive the display: a trait changes
	--- what this tower actually does, and a range ring drawn from config
	--- contradicts the real acquisition radius.
	range: number,
	damage: number,
	fireRate: number,
}

--- Finds a tower part by its replicated TowerId attribute.
local function findTowerPart(towerId: number): BasePart?
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

local function readInfo(part: BasePart): TowerInfo?
	local towerId = part:GetAttribute("TowerId")
	local defId = part:GetAttribute("TowerDefId")
	local level = part:GetAttribute("Level")
	local ownerUserId = part:GetAttribute("OwnerUserId")
	local mode = part:GetAttribute("TargetingMode")
	local sellValue = part:GetAttribute("SellValue")
	local range = part:GetAttribute("Range")
	local damage = part:GetAttribute("Damage")
	local fireRate = part:GetAttribute("FireRate")

	if
		typeof(towerId) ~= "number"
		or typeof(defId) ~= "string"
		or typeof(level) ~= "number"
		or typeof(ownerUserId) ~= "number"
		or typeof(mode) ~= "string"
		or typeof(sellValue) ~= "number"
		or typeof(range) ~= "number"
		or typeof(damage) ~= "number"
		or typeof(fireRate) ~= "number"
	then
		return nil
	end

	return {
		towerId = towerId,
		defId = defId,
		level = level,
		ownerUserId = ownerUserId,
		targetingMode = mode,
		sellValue = sellValue,
		range = range,
		damage = damage,
		fireRate = fireRate,
	}
end

--- Wrapper so the React state is never nil.
---
--- `React.useState(nil)` infers the state type as exactly `nil`, and the
--- setter then refuses every real value. Holding the optional inside a table
--- keeps the state type honest without a cast.
type InfoState = {
	info: TowerInfo?,
}

local NO_OP: () -> () = function() end

--- How far the panel rises into place when a tower is selected. Small on
--- purpose: this is a confirmation the click landed, not an entrance.
local PANEL_RISE = 14

--- Tracks one tower's attributes, re-reading whenever any of them changes and
--- clearing the selection if the tower is sold out from under the panel.
local function useTowerInfo(towerId: number?): TowerInfo?
	local state, setState = React.useState({ info = nil } :: InfoState)

	-- Annotated, and every path returns a function. With bare early returns
	-- Luau infers the effect as returning `nil` and then rejects the real
	-- cleanup at the bottom.
	React.useEffect(function(): () -> ()
		if towerId == nil then
			setState({ info = nil })
			return NO_OP
		end

		local part = findTowerPart(towerId)

		if part == nil then
			setState({ info = nil })
			return NO_OP
		end

		local connections: { RBXScriptConnection } = {}

		local function refresh()
			setState({ info = readInfo(part) })
		end

		refresh()

		for _, attribute in { "Level", "TargetingMode", "SellValue", "Range", "Damage", "FireRate" } do
			table.insert(connections, part:GetAttributeChangedSignal(attribute):Connect(refresh))
		end

		-- Selling destroys the part. Without this the panel would keep
		-- showing a tower that no longer exists.
		table.insert(
			connections,
			part.AncestryChanged:Connect(function()
				if part.Parent == nil then
					atoms.selectedTowerId(nil)
				end
			end)
		)

		return function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end
		-- `towerId or 0` rather than `towerId`: a dependency array containing
		-- nil has length 0, so React would see it as an EMPTY array and never
		-- re-run the effect when a tower is first selected.
	end, { towerId or 0 })

	return state.info
end

type ActionProps = {
	text: string,
	color: Color3,
	textColor: Color3,
	layoutOrder: number,
	onActivated: () -> (),
	--- Both present only on the button that reveals the preview panel. The
	--- other buttons render exactly as before.
	onHover: ((hovering: boolean) -> ())?,
	glowRef: { current: UIStroke? }?,
}

local function ActionButton(props: ActionProps)
	local attributes: { [any]: any } = {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = props.color,
		BorderSizePixel = 0,
		Font = Theme.FONT,
		Text = props.text,
		TextColor3 = props.textColor,
		TextSize = 13,
		LayoutOrder = props.layoutOrder,
		[React.Event.Activated] = props.onActivated,
	}

	local children: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	}

	local onHover = props.onHover

	if onHover ~= nil then
		attributes[React.Event.MouseEnter] = function()
			onHover(true)
		end

		attributes[React.Event.MouseLeave] = function()
			onHover(false)
		end

		-- AutoButtonColor is deliberately left at its default. The engine tint
		-- is the only press feedback this button has, and it is the one button
		-- here that spends money; the stroke is added to it, not swapped for it.
		--
		-- Off-white rather than the accent, because the button's own fill IS
		-- the accent when the upgrade is affordable - an accent stroke would be
		-- brightest on the state where the button cannot be pressed.
		--
		-- Every prop here is constant, so React writes them once at mount and
		-- never again, leaving Transparency ours to animate. See Motion.luau.
		children.glow = e("UIStroke", {
			ref = props.glowRef,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.TEXT,
			Thickness = 1.5,
			Transparency = 1,
		})
	end

	return e("TextButton", attributes, children)
end

--- Seconds the range dome takes to expand out of the unit. Half a second,
--- per the brief - long enough to read as motion, short enough that
--- clicking through several towers never feels gated.
local RANGE_DOME_SECONDS = 0.5

--- Draws a half-sphere DOME showing the selected tower's range.
---
--- A dome rather than the old flat disc, deliberately: range checks are
--- 3D (TowerSystem measures straight-line distance), so an air enemy
--- crossing the dome's curve is genuinely in range where a flat ring lied
--- about anything above ground level. Roblox has no half-sphere primitive;
--- a full Ball centred on the tower's base is one, because the lower half
--- is buried and only the dome shows.
---
--- The dome EXPANDS from the unit over RANGE_DOME_SECONDS - tweened Size
--- with the CFrame pinned, so it inflates in place.
---
--- Lives here rather than in a module of its own because the lifetime it
--- follows is exactly this panel's: the dome is visible when the panel is.
local SPLASH_COLOR = Color3.fromRGB(236, 148, 58)

--- Closest point on any lane polyline to `from`, on the XZ plane. This is
--- where a splash tower's shells land in practice, which makes it the
--- honest place to draw the splash-radius preview.
local function closestLanePoint(from: Vector3): Vector3?
	local map = MapRegistry.find(atoms.mapId())

	if map == nil then
		return nil
	end

	local best: Vector3? = nil
	local bestDistance = math.huge

	for _, lane in map.paths do
		for index = 2, #lane.waypoints do
			local a = lane.waypoints[index - 1]
			local b = lane.waypoints[index]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local length = ab.Magnitude

			if length < 1e-3 then
				continue
			end

			local t = math.clamp(((from.X - a.X) * ab.X + (from.Z - a.Z) * ab.Z) / (length * length), 0, 1)
			local point = Vector3.new(a.X + ab.X * t, 0, a.Z + ab.Z * t)
			local distance = (Vector3.new(from.X, 0, from.Z) - point).Magnitude

			if distance < bestDistance then
				bestDistance = distance
				best = point
			end
		end
	end

	return best
end

local function useRangeDisc(towerId: number?, range: number?, splashRadius: number?)
	React.useEffect(function(): () -> ()
		if towerId == nil or range == nil or range <= 0 then
			return NO_OP
		end

		local part = findTowerPart(towerId)

		if part == nil then
			return NO_OP
		end

		-- One container for the whole preview, so cleanup is one Destroy no
		-- matter how many pieces the attack type adds.
		local container = Instance.new("Model")
		container.Name = "TDSelectionRange"

		local function ball(size: number, color: Color3, transparency: number): Part
			local sphere = Instance.new("Part")
			sphere.Shape = Enum.PartType.Ball
			sphere.Size = Vector3.new(size, size, size)
			sphere.Anchored = true
			sphere.CanCollide = false
			sphere.CanQuery = false
			sphere.CanTouch = false
			sphere.CastShadow = false
			sphere.Transparency = transparency
			sphere.Material = Enum.Material.Neon
			sphere.Color = color
			sphere.Parent = container
			return sphere
		end

		-- The range DOME. Centred at the BASE, not the part centre: the
		-- buried half makes the ball a dome, and the equator lands exactly
		-- on the ground the tower stands on - plateau included, since the
		-- base is derived from the part.
		local base = part.Position.Y - part.Size.Y / 2
		local dome = ball(0.5, Theme.ACCENT, 0.92)
		dome.CFrame = CFrame.new(part.Position.X, base, part.Position.Z)

		local tweens: { Tween } = {}

		local function grow(target: Part, diameter: number)
			local tween = TweenService:Create(
				target,
				TweenInfo.new(RANGE_DOME_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(diameter, diameter, diameter) }
			)
			table.insert(tweens, tween)
			tween:Play()
		end

		grow(dome, range * 2)

		-- The ATTACK TYPE. Single-target towers say it with silence; splash
		-- towers show WHERE their shells land and HOW they get there (a
		-- thrown arc), with the blast radius drawn true. The preview is
		-- LIVE: it opens on the closest lane point as an idle guess, then
		-- follows the tower's actual shots - every TowerFired for this
		-- tower re-aims the sphere and the arc at the real target, so the
		-- blast marker chases the zombies the tower is fighting. No tower
		-- in the roster attacks in a cone; if one ever does, this is where
		-- its wedge preview goes.
		local disconnectAim: (() -> ())? = nil

		if splashRadius ~= nil and splashRadius > 0 then
			local origin = Vector3.new(part.Position.X, base, part.Position.Z)
			local top = part.Position + Vector3.new(0, part.Size.Y / 2 + 1, 0)

			local blast = ball(0.5, SPLASH_COLOR, 0.72)
			local dots: { Part } = {}

			for _ = 1, 6 do
				table.insert(dots, ball(0.9, SPLASH_COLOR, 0.25))
			end

			-- One in-flight tween per piece, REPLACED on every re-aim. An
			-- Autocannon fires twice a second; accumulating tweens for a
			-- whole selection would be a slow leak dressed as smoothness.
			local aimTweens: { [Part]: Tween } = {}

			local function glide(target: Part, cframe: CFrame, animate: boolean)
				-- Annotated optional: indexing a map type yields the value
				-- type, not an optional.
				local previous: Tween? = aimTweens[target]

				if previous ~= nil then
					previous:Cancel()
					aimTweens[target] = nil
				end

				if animate then
					local tween = TweenService:Create(target, Theme.MOTION_REVEAL, { CFrame = cframe })
					aimTweens[target] = tween
					tween:Play()
				else
					target.CFrame = cframe
				end
			end

			--- Points the whole splash preview at `impact`. The y is kept
			--- (floored to the tower's base plane) so a Flak aiming at a
			--- Drifter shows its blast in the AIR, where it happens.
			local function aim(impact: Vector3, animate: boolean)
				local grounded = Vector3.new(impact.X, math.max(impact.Y, base), impact.Z)
				local flat = (Vector3.new(grounded.X, 0, grounded.Z) - Vector3.new(top.X, 0, top.Z)).Magnitude
				local apex = math.max(8, flat * 0.3)

				glide(blast, CFrame.new(grounded), animate)

				for step, dot in dots do
					local alpha = step / (#dots + 1)
					local along = top:Lerp(grounded, alpha)

					glide(dot, CFrame.new(along + Vector3.new(0, math.sin(alpha * math.pi) * apex, 0)), animate)
				end
			end

			-- The idle guess: the closest lane point, clamped into range -
			-- shown until the first real shot replaces guesswork with truth.
			local lanePoint = closestLanePoint(part.Position)
			local idle: Vector3

			if lanePoint ~= nil then
				local offset = Vector3.new(lanePoint.X - origin.X, 0, lanePoint.Z - origin.Z)
				local reach = math.min(offset.Magnitude, range * 0.92)
				idle = if offset.Magnitude > 1e-3
					then origin + offset.Unit * reach
					else origin + Vector3.new(reach, 0, 0)
			else
				idle = origin + Vector3.new(range * 0.6, 0, 0)
			end

			aim(idle, false)
			grow(blast, splashRadius * 2)

			-- Zap events take any number of listeners and hand back a
			-- disconnect, so the tracers keep their subscription and this
			-- one watches only the SELECTED tower's shots.
			disconnectAim = Net.TowerFired.On(function(value)
				if value.towerId == towerId then
					aim(Wire.toVector3(value.targetPosition), true)
				end
			end)
		end

		container.Parent = workspace

		return function()
			if disconnectAim ~= nil then
				disconnectAim()
			end

			for _, tween in tweens do
				tween:Cancel()
			end

			container:Destroy()
		end
	end, { towerId or 0, range or 0, splashRadius or 0 })
end

type StatProps = {
	label: string,
	value: string,
	layoutOrder: number,
}

--- One stat cell. Three sit in a row: what the tower hits for, how far it
--- reaches, how often it fires.
local function Stat(props: StatProps)
	return e("Frame", {
		Size = UDim2.new(1 / 3, -4, 0, 34),
		BackgroundColor3 = Theme.RAISED,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),

		label = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 12),
			Position = UDim2.fromOffset(0, 4),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = props.label,
			TextColor3 = Theme.MUTED,
			TextSize = 10,
		}),

		value = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 15),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = props.value,
			TextColor3 = Theme.TEXT,
			TextSize = 13,
		}),
	})
end

type DeltaProps = {
	label: string,
	from: string,
	to: string,
	layoutOrder: number,
}

--- One "this stat becomes that" row in the upgrade panel.
local function DeltaRow(props: DeltaProps)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		label = e("TextLabel", {
			Size = UDim2.fromScale(0.42, 1),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = props.label,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		value = e("TextLabel", {
			Position = UDim2.fromScale(0.42, 0),
			Size = UDim2.fromScale(0.58, 1),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = `{props.from}  →  {props.to}`,
			TextColor3 = Theme.POSITIVE,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

--- Shots per second to two places. Rounding to whole numbers would collapse
--- 1.10 and 1.35 into the same figure and make an upgrade look like it did
--- nothing.
local function rateText(fireRate: number): string
	return string.format("%.2f/s", fireRate)
end

--- Damage and range to at most one decimal. Traited values are fractional
--- (8 x 1.05 = 8.4), and printing float noise would read as a bug.
local function statText(value: number): string
	return string.format("%g", math.round(value * 10) / 10)
end

--- Fades the upgrade preview in while the UPGRADE button is hovered.
---
--- FADE, not a height wipe. The panel keeps its full layout footprint whether
--- shown or hidden, so the shell's height never changes and the UPGRADE button
--- cannot move out from under the cursor. A wipe would shorten the shell,
--- shift the button down, fire MouseLeave, hide the panel, move the button
--- back under the cursor - a flicker loop, at whatever rate the tween runs.
---
--- GroupTransparency is declared as a CONSTANT 1 on the CanvasGroup, so React
--- writes it once at mount and never again. That gives the correct hidden
--- initial state without an imperative first paint, and leaves the property
--- free to animate. See the rule in Motion.luau.
--- Fades and lifts the whole inspector into place when a tower is selected.
---
--- Keyed on the tower, so clicking a DIFFERENT tower replays it - which is the
--- point. Without that, selecting another tower silently swaps the contents of
--- a panel already on screen and the click has no visible result at all.
---
--- GroupTransparency and Position are both declared as CONSTANTS on the shell,
--- so React writes each once at mount and never again, leaving them free to
--- animate. See the rule in Motion.luau.
local function useSelectionEntrance(towerId: number?): { current: CanvasGroup? }
	local shellRef = React.useRef(nil :: CanvasGroup?)
	local tween = React.useRef(nil :: Motion.Handle)

	React.useLayoutEffect(function(): () -> ()
		local shell = shellRef.current

		if shell == nil then
			return NO_OP
		end

		Motion.stop(tween.current)

		-- Snap to the start of the animation, then play it. Snapping first
		-- matters on a re-selection, where the shell is still sitting at its
		-- resting values from the previous tower.
		shell.GroupTransparency = 1
		shell.Position = UDim2.new(1, -16, 1, -16 + PANEL_RISE)

		tween.current = Motion.retarget(nil, shell, Theme.MOTION_REVEAL, {
			GroupTransparency = 0,
			Position = UDim2.new(1, -16, 1, -16),
		})

		return function()
			Motion.stop(tween.current)
			tween.current = nil
		end
	end, { towerId or 0 })

	return shellRef
end

local function useHoverReveal(
	towerId: number?,
	hasPreview: boolean
): ({ current: CanvasGroup? }, { current: UIStroke? }, (boolean) -> ())
	local previewRef = React.useRef(nil :: CanvasGroup?)
	local glowRef = React.useRef(nil :: UIStroke?)
	local previewTween = React.useRef(nil :: Motion.Handle)
	local glowTween = React.useRef(nil :: Motion.Handle)

	local setHovered = React.useCallback(function(hovering: boolean)
		local preview = previewRef.current
		local glow = glowRef.current

		if preview ~= nil then
			previewTween.current = Motion.retarget(
				previewTween.current,
				preview,
				Theme.MOTION_REVEAL,
				{ GroupTransparency = if hovering then 0 else 1 }
			)
		end

		if glow ~= nil then
			glowTween.current = Motion.retarget(
				glowTween.current,
				glow,
				Theme.MOTION_QUICK,
				{ Transparency = if hovering then 0.25 else 1 }
			)
		end
	end, {})

	-- Keyed on hasPreview as well as the tower, and that second key is not
	-- decoration. Upgrading to max level unmounts BOTH animated instances
	-- while towerId stays the same, so a tower-only key would never re-run and
	-- would leave live tweens writing to destroyed instances.
	--
	-- Selecting a different tower is the other case: React reuses the same
	-- button and CanvasGroup, so MouseLeave never fires and the panel would
	-- stay visible on a tower the cursor is nowhere near.
	React.useEffect(function(): () -> ()
		local preview = previewRef.current
		local glow = glowRef.current

		Motion.stop(previewTween.current)
		Motion.stop(glowTween.current)
		previewTween.current = nil
		glowTween.current = nil

		if preview ~= nil then
			preview.GroupTransparency = if HOVER_AVAILABLE then 1 else 0
		end

		if glow ~= nil then
			glow.Transparency = 1
		end

		return function()
			Motion.stop(previewTween.current)
			Motion.stop(glowTween.current)
			previewTween.current = nil
			glowTween.current = nil
		end
		-- Numbers only: the dependency array is homogeneous, so the boolean
		-- is carried as 1/0 rather than as itself.
	end, { towerId or 0, if hasPreview then 1 else 0 })

	return previewRef, glowRef, setHovered
end

local function TowerInspector()
	local selectedId = useAtom(atoms.selectedTowerId)
	local cash = useAtom(atoms.cash)
	local info = useTowerInfo(selectedId)

	-- Resolved BEFORE the early return below. useRangeDisc is a hook, and a
	-- hook that only runs on some renders desynchronises React's hook order.
	local definition = if info ~= nil then Towers.find(info.defId) else nil
	local level = if definition ~= nil and info ~= nil then Towers.levelAt(definition, info.level) else nil

	-- The dome draws the ATTRIBUTE range - the server's traited number -
	-- never the config's. (The placement ghost still shows base range: traits
	-- are per-profile and the snapshot does not carry them pre-placement.)
	-- Splash radius is config: no trait touches it.
	useRangeDisc(
		if info ~= nil then info.towerId else nil,
		if info ~= nil then info.range else nil,
		if level ~= nil then level.splashRadius else nil
	)

	-- Whether a preview will render at all, computed here because the hook
	-- below has to be called before any early return.
	local hasPreview = info ~= nil
		and definition ~= nil
		and info.ownerUserId == localPlayer.UserId
		and Towers.levelAt(definition, info.level + 1) ~= nil

	local previewRef, glowRef, setHovered = useHoverReveal(if info ~= nil then info.towerId else nil, hasPreview)
	local shellRef = useSelectionEntrance(if info ~= nil then info.towerId else nil)

	if info == nil or definition == nil or level == nil then
		return nil
	end

	local isOwner = info.ownerUserId == localPlayer.UserId
	local upgradeCost = Economy.upgradeCost(definition, info.level)
	local maxLevel = #definition.levels
	local nextLevel = Towers.levelAt(definition, info.level + 1)

	-- The trait multipliers this tower carries, recovered from the ratio of
	-- the server's traited attribute to the config base. Used to scale the
	-- upgrade preview: showing base numbers there while the stat row shows
	-- traited ones would make the panel disagree with itself.
	local damageScale = if level ~= nil and level.damage > 0 then info.damage / level.damage else 1
	local rangeScale = if level ~= nil and level.range > 0 then info.range / level.range else 1
	local rateScale = if level ~= nil and level.fireRate > 0 then info.fireRate / level.fireRate else 1

	local children: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		name = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = definition.displayName,
			TextColor3 = Theme.TEXT,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),

		level = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = `Level {info.level} / {maxLevel}  ·  {info.targetingMode}`,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		}),

		-- Damage, reach and rate. Shown for every tower, owned or not: they
		-- describe the tower, and reading someone else's is not an action.
		stats = e("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, {
			layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			}),
			damage = e(Stat, { label = "DAMAGE", value = statText(info.damage), layoutOrder = 1 }),
			range = e(Stat, { label = "RANGE", value = statText(info.range), layoutOrder = 2 }),
			speed = e(Stat, { label = "SPEED", value = rateText(info.fireRate), layoutOrder = 3 }),
		}),
	}

	if not isOwner then
		children.notice = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = "Owned by another player",
			TextColor3 = Theme.MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 4,
		})
	else
		if upgradeCost ~= nil then
			children.upgrade = e(ActionButton, {
				text = `UPGRADE  $${upgradeCost}`,
				color = if cash >= upgradeCost then Theme.ACCENT else Theme.DISABLED,
				textColor = if cash >= upgradeCost then Theme.INVERSE else Theme.MUTED,
				layoutOrder = 4,
				onHover = if HOVER_AVAILABLE then setHovered else nil,
				glowRef = if HOVER_AVAILABLE then glowRef else nil,
				onActivated = function()
					-- Fired regardless of the local affordability read. The
					-- server is the authority; this button being dark is a
					-- hint, not a lock.
					Net.RequestUpgradeTower.Fire({ towerId = info.towerId })
				end,
			})
		else
			children.maxed = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = "MAX LEVEL",
				TextColor3 = Theme.POSITIVE,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 4,
			})
		end

		children.targeting = e(ActionButton, {
			text = `TARGET: {info.targetingMode}`,
			color = Theme.RAISED,
			textColor = Theme.TEXT,
			layoutOrder = 5,
			onActivated = function()
				Net.RequestSetTargeting.Fire({
					towerId = info.towerId,
					mode = Targeting.cycle(info.targetingMode :: any),
				})
			end,
		})

		children.sell = e(ActionButton, {
			text = `SELL  +$${info.sellValue}`,
			color = Theme.RAISED,
			textColor = Theme.CASH,
			layoutOrder = 6,
			onActivated = function()
				Net.RequestSellTower.Fire({ towerId = info.towerId })
			end,
		})
	end

	-- Second panel: what the money actually buys. Owner only, and only when
	-- there IS a next level - at max there is nothing to preview.
	local upgradePanel = nil

	if isOwner and nextLevel ~= nil then
		local rows: { [string]: any } = {
			corner = e("UICorner", { CornerRadius = Theme.CORNER }),
			padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}),
			layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			header = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = `NEXT  ·  LEVEL {info.level + 1}`,
				TextColor3 = Theme.ACCENT,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),

			damage = e(DeltaRow, {
				label = "Damage",
				from = statText(info.damage),
				to = statText(nextLevel.damage * damageScale),
				layoutOrder = 2,
			}),
			range = e(DeltaRow, {
				label = "Range",
				from = statText(info.range),
				to = statText(nextLevel.range * rangeScale),
				layoutOrder = 3,
			}),
			speed = e(DeltaRow, {
				label = "Speed",
				from = rateText(info.fireRate),
				to = rateText(nextLevel.fireRate * rateScale),
				layoutOrder = 4,
			}),
		}

		-- Splash only when it actually moves. For Mortar and Flak it is the
		-- headline of the upgrade; everywhere else it is a constant zero and a
		-- row reading "0 to 0" is noise.
		if nextLevel.splashRadius ~= level.splashRadius then
			rows.splash = e(DeltaRow, {
				label = "Splash",
				from = tostring(level.splashRadius),
				to = tostring(nextLevel.splashRadius),
				layoutOrder = 5,
			})
		end

		-- A CanvasGroup rather than a Frame purely for GroupTransparency: it
		-- fades the panel and everything in it as one surface, where fading a
		-- Frame would leave every label inside it at full opacity.
		--
		-- Same size, same children, same layout slot as the Frame it replaces,
		-- so the reveal costs no reflow.
		upgradePanel = e("CanvasGroup", {
			ref = previewRef,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			GroupTransparency = if HOVER_AVAILABLE then 1 else 0,
			LayoutOrder = 1,
		}, rows)
	end

	-- Transparent shell so the two panels stack with a real gap rather than
	-- reading as one box with a line through it. AutomaticSize means neither
	-- carries a hand-counted pixel height that goes stale when a row is added.
	return e("CanvasGroup", {
		ref = shellRef,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),

		upgradePanel = upgradePanel,

		mainPanel = e("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, children),
	})
end

return TowerInspector

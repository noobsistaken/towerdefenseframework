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

local Constants = require(ReplicatedStorage.Shared.Constants)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)

local Theme = require(ReplicatedStorage.Shared.Theme)
local atoms = require(script.Parent.Parent.State.atoms)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local e = React.createElement

local localPlayer = Players.LocalPlayer

type TowerInfo = {
	towerId: number,
	defId: string,
	level: number,
	ownerUserId: number,
	targetingMode: string,
	sellValue: number,
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

	if
		typeof(towerId) ~= "number"
		or typeof(defId) ~= "string"
		or typeof(level) ~= "number"
		or typeof(ownerUserId) ~= "number"
		or typeof(mode) ~= "string"
		or typeof(sellValue) ~= "number"
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

		for _, attribute in { "Level", "TargetingMode", "SellValue", "Range" } do
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
}

local function ActionButton(props: ActionProps)
	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = props.color,
		BorderSizePixel = 0,
		Font = Theme.FONT,
		Text = props.text,
		TextColor3 = props.textColor,
		TextSize = 13,
		LayoutOrder = props.layoutOrder,
		[React.Event.Activated] = props.onActivated,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

--- Draws a flat disc showing the selected tower's range.
---
--- Lives here rather than in a module of its own because the lifetime it
--- follows is exactly this panel's: the disc is visible when the panel is.
--- Sized and tipped the way the placement preview does it - cylinders extrude
--- along local X, so a disc has to be rolled onto its side to lie flat.
---
--- Sits just above whatever the tower is standing on, derived from the part
--- rather than assumed, so a Hillside tower on a 12-stud plateau gets its ring
--- on the plateau instead of buried under it.
local function useRangeDisc(towerId: number?, range: number?)
	React.useEffect(function(): () -> ()
		if towerId == nil or range == nil or range <= 0 then
			return NO_OP
		end

		local part = findTowerPart(towerId)

		if part == nil then
			return NO_OP
		end

		local disc = Instance.new("Part")
		disc.Name = "TDSelectionRange"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.2, range * 2, range * 2)
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Transparency = 0.88
		disc.Material = Enum.Material.Neon
		disc.Color = Theme.ACCENT

		local base = part.Position.Y - part.Size.Y / 2 + 0.3
		disc.CFrame = CFrame.new(part.Position.X, base, part.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = workspace

		return function()
			disc:Destroy()
		end
	end, { towerId or 0, range or 0 })
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

local function TowerInspector()
	local selectedId = useAtom(atoms.selectedTowerId)
	local cash = useAtom(atoms.cash)
	local info = useTowerInfo(selectedId)

	-- Resolved BEFORE the early return below. useRangeDisc is a hook, and a
	-- hook that only runs on some renders desynchronises React's hook order.
	local definition = if info ~= nil then Towers.find(info.defId) else nil
	local level = if definition ~= nil and info ~= nil then Towers.levelAt(definition, info.level) else nil

	useRangeDisc(if info ~= nil then info.towerId else nil, if level ~= nil then level.range else nil)

	if info == nil or definition == nil or level == nil then
		return nil
	end

	local isOwner = info.ownerUserId == localPlayer.UserId
	local upgradeCost = Economy.upgradeCost(definition, info.level)
	local maxLevel = #definition.levels
	local nextLevel = Towers.levelAt(definition, info.level + 1)

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
			damage = e(Stat, { label = "DAMAGE", value = tostring(level.damage), layoutOrder = 1 }),
			range = e(Stat, { label = "RANGE", value = tostring(level.range), layoutOrder = 2 }),
			speed = e(Stat, { label = "SPEED", value = rateText(level.fireRate), layoutOrder = 3 }),
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
				from = tostring(level.damage),
				to = tostring(nextLevel.damage),
				layoutOrder = 2,
			}),
			range = e(DeltaRow, {
				label = "Range",
				from = tostring(level.range),
				to = tostring(nextLevel.range),
				layoutOrder = 3,
			}),
			speed = e(DeltaRow, {
				label = "Speed",
				from = rateText(level.fireRate),
				to = rateText(nextLevel.fireRate),
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

		upgradePanel = e("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, rows)
	end

	-- Transparent shell so the two panels stack with a real gap rather than
	-- reading as one box with a line through it. AutomaticSize means neither
	-- carries a hand-counted pixel height that goes stale when a row is added.
	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
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

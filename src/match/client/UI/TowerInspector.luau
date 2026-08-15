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

local function TowerInspector()
	local selectedId = useAtom(atoms.selectedTowerId)
	local cash = useAtom(atoms.cash)
	local info = useTowerInfo(selectedId)

	if info == nil then
		return nil
	end

	local definition = Towers.find(info.defId)

	if definition == nil then
		return nil
	end

	local isOwner = info.ownerUserId == localPlayer.UserId
	local upgradeCost = Economy.upgradeCost(definition, info.level)
	local maxLevel = #definition.levels

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
			LayoutOrder = 3,
		})
	else
		if upgradeCost ~= nil then
			children.upgrade = e(ActionButton, {
				text = `UPGRADE  ${upgradeCost}`,
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
			text = `SELL  +${info.sellValue}`,
			color = Theme.RAISED,
			textColor = Theme.CASH,
			layoutOrder = 6,
			onActivated = function()
				Net.RequestSellTower.Fire({ towerId = info.towerId })
			end,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(220, 190),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, children)
end

return TowerInspector

--!strict
--[[
	Tower shop, along the bottom of the screen.

	One button per tower in the roster, in the stable sorted order from
	Config/Towers.luau, so the shop never reorders itself between servers or
	between sessions - muscle memory is worth more than any clever sorting.

	A button the player cannot use is greyed rather than removed. Removing it
	would reflow the whole bar every time cash crosses a price, which makes
	the row jump under the cursor mid-click.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Types = require(ReplicatedStorage.Shared.Types)

local Theme = require(script.Parent.Theme)
local atoms = require(script.Parent.Parent.State.atoms)
local useAtom = require(script.Parent.useAtom)

local e = React.createElement

local BUTTON_WIDTH = 116
local BUTTON_HEIGHT = 74

--- Short tag showing where a tower may stand, since that is the constraint
--- players get wrong most often.
local function categoryTag(category: Types.TowerCategory): string
	if category == "Ground" then
		return "GROUND"
	elseif category == "Hillside" then
		return "HIGH"
	end

	return "ANY"
end

type ButtonProps = {
	definition: Types.TowerDefinition,
	cash: number,
	unlocked: boolean,
	selected: boolean,
	layoutOrder: number,
}

local function TowerButton(props: ButtonProps)
	local definition = props.definition
	local cost = definition.levels[1].cost
	local affordable = props.cash >= cost
	local usable = props.unlocked and affordable

	local background = Theme.RAISED

	if props.selected then
		background = Theme.ACCENT
	elseif not usable then
		background = Theme.DISABLED
	end

	return e("TextButton", {
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		BackgroundColor3 = background,
		BorderSizePixel = 0,
		AutoButtonColor = usable,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.Activated] = function()
			if not usable then
				return
			end

			-- Clicking the held tower again puts it away, which is the
			-- expected way to cancel without hunting for a cancel button.
			if props.selected then
				atoms.selectedTowerDefId(nil)
			else
				atoms.selectedTowerDefId(definition.id)
			end
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),

		name = e("TextLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = definition.displayName,
			TextColor3 = if props.selected then Theme.INVERSE else Theme.TEXT,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),

		category = e("TextLabel", {
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.new(1, -20, 0, 14),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = categoryTag(definition.category),
			TextColor3 = if props.selected then Theme.INVERSE else Theme.MUTED,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		cost = e("TextLabel", {
			Position = UDim2.fromOffset(10, 46),
			Size = UDim2.new(1, -20, 0, 20),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = if props.unlocked then `${cost}` else "LOCKED",
			TextColor3 = if props.selected
				then Theme.INVERSE
				elseif not props.unlocked then Theme.MUTED
				elseif affordable then Theme.CASH
				else Theme.NEGATIVE,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function ShopBar()
	local cash = useAtom(atoms.cash)
	local unlocked = useAtom(atoms.unlockedTowers)
	local selected = useAtom(atoms.selectedTowerDefId)
	local state = useAtom(atoms.matchState)

	-- The shop is meaningless once the match is decided.
	if state == "Victory" or state == "Defeat" then
		return nil
	end

	local children: { [string]: any } = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}

	for index, id in Towers.IDS do
		children[id] = e(TowerButton, {
			definition = Towers.get(id),
			cash = cash,
			unlocked = table.find(unlocked, id) ~= nil,
			selected = selected == id,
			layoutOrder = index,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(#Towers.IDS * (BUTTON_WIDTH + 8) + 16, BUTTON_HEIGHT + 16),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, children)
end

return ShopBar

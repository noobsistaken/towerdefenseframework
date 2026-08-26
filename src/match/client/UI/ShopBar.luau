--!strict
--[[
	Tower shop, along the bottom of the screen.

	One button per tower in the LOADOUT - the deck this player brought, at
	most six - in the deck's own order. The collection stays in the lobby:
	twenty-six buttons was a shop nobody could read, and the loadout is
	where the choosing already happened.

	A button the player cannot afford is greyed rather than removed. Removing
	it would reflow the whole bar every time cash crosses a price, which
	makes the row jump under the cursor mid-click.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Types = require(ReplicatedStorage.Shared.Types)
local UiArt = require(ReplicatedStorage.Shared.UiArt)
local UiFx = require(ReplicatedStorage.Shared.UiFx)
local UnitPreview = require(ReplicatedStorage.Shared.UnitPreview)

local Theme = require(ReplicatedStorage.Shared.Theme)
local atoms = require(script.Parent.Parent.State.atoms)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local e = React.createElement

local BUTTON_WIDTH = 120
local BUTTON_HEIGHT = 118

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
	local viewportRef = React.useRef(nil :: ViewportFrame?)

	-- The unit stands in the button, angled a quarter-turn for depth.
	React.useEffect(function(): () -> ()
		local viewport = viewportRef.current

		if viewport == nil then
			return function() end
		end

		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local unit = UnitPreview.buildUnit(definition)
		unit:PivotTo(CFrame.Angles(0, math.rad(25), 0))
		unit.Parent = viewport
		UnitPreview.frame(camera, unit, true, 0.72)

		return function()
			unit:Destroy()
			camera:Destroy()
		end
	end, { definition.id })

	-- Tint multiplied into the steel row plate: white leaves the material
	-- as generated, accent marks the tower in hand, dark grey mutes what
	-- cannot be bought right now.
	local tint = Color3.fromRGB(255, 255, 255)

	if props.selected then
		tint = Theme.ACCENT
	elseif not usable then
		tint = Color3.fromRGB(96, 100, 110)
	end

	return e(UiArt.Button, {
		text = "",
		tint = tint,
		textColor = Theme.TEXT,
		size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		layoutOrder = props.layoutOrder,
		autoButtonColor = usable,
		onActivated = function()
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
		children = {
			-- A multiplied tint can only darken steel, so the held tower
			-- gets a bright accent stroke on top of its accent tint.
			stroke = if props.selected
				then e("UIStroke", { Color = Theme.ACCENT, Thickness = 2, Transparency = 0.1 })
				else nil,
			-- Centred stack, top to bottom: price, the unit itself,
			-- placement type, name.
			cost = e("TextLabel", {
				Position = UDim2.fromOffset(0, 6),
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = if props.unlocked then `${cost}` else "LOCKED",
				TextColor3 = if not props.unlocked
					then Theme.MUTED
					elseif affordable then Theme.CASH
					else Theme.NEGATIVE,
				TextSize = 15,
			}),
			viewport = e("ViewportFrame", {
				ref = viewportRef,
				Position = UDim2.fromOffset(16, 24),
				Size = UDim2.new(1, -32, 0, 58),
				BackgroundTransparency = 1,
				Ambient = Color3.fromRGB(185, 185, 195),
				LightColor = Color3.fromRGB(255, 250, 240),
				LightDirection = Vector3.new(-0.4, -1, -0.6),
			}),
			category = e("TextLabel", {
				Position = UDim2.fromOffset(0, 82),
				Size = UDim2.new(1, 0, 0, 12),
				BackgroundTransparency = 1,
				Font = Theme.FONT_BODY,
				Text = categoryTag(definition.category),
				TextColor3 = Theme.MUTED,
				TextSize = 10,
			}),
			name = e("TextLabel", {
				Position = UDim2.fromOffset(4, 94),
				Size = UDim2.new(1, -8, 0, 18),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = definition.displayName,
				TextColor3 = Theme.TEXT,
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		},
	})
end

local function ShopBar()
	local cash = useAtom(atoms.cash)
	local loadout = useAtom(atoms.loadout)
	local selected = useAtom(atoms.selectedTowerDefId)
	local state = useAtom(atoms.matchState)
	-- The shop is meaningless once the match is decided; it plays out
	-- instead of vanishing.
	local show, exiting = UiFx.usePresence(state ~= "Victory" and state ~= "Defeat")

	if not show then
		return nil
	end

	local rowChildren: { [string]: any } = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}

	for index, id in loadout do
		local definition = Towers.find(id)

		-- A deck id the registry no longer knows renders nothing rather than
		-- erroring the whole bar; the server's resolver filters these too.
		if definition ~= nil then
			rowChildren[id] = e(TowerButton, {
				definition = definition,
				cash = cash,
				unlocked = true,
				selected = selected == id,
				layoutOrder = index,
			})
		end
	end

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(math.max(#loadout, 1) * (BUTTON_WIDTH + 8) + 16, BUTTON_HEIGHT + 16),
			BackgroundTransparency = 1,
		},
		exit = exiting,
		children = {
			art = UiArt.Plate({ frame = { Size = UDim2.fromScale(1, 1), ZIndex = 0 } }),
			row = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, rowChildren),
		},
	})
end

return ShopBar

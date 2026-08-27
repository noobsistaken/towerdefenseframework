--!strict
--[[
	The custom player list, replacing the Roblox default in both places.

	One shared component because it IS the same panel twice; each place's
	client feeds it that place's roster atom through props, so this module
	knows no atoms and both places cannot drift apart visually.

	Collapsed: a small emblem button. Expanded: a panel of rows - avatar
	headshot (the rbxthumb protocol, no async), "name | LV n", and a role
	line - OWNER for admins, PLAYER TESTER for everyone else, which is the
	truth of a portfolio place. Tab toggles it too, PC-standard.

	LAYOUT RULE, learned the hard way twice (shop bar, then this panel): a
	background image must never share a UIListLayout with the content it
	backs. A scale-sized image in the flow stacks at parent height, the
	auto-size feeds back, and the panel inflates to the screen with its
	rows clipped out of sight. The art lives OUTSIDE the flow; only the
	content frame carries the layout.

	Art comes from Config/RosterArt.luau and every piece is optional: a
	missing asset renders the text fallback, never a broken image.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Admins = require(script.Parent.Config.Admins)
local HudArt = require(script.Parent.Config.HudArt)
local React = require(ReplicatedStorage.Packages.React)
local RosterArt = require(script.Parent.Config.RosterArt)
local Theme = require(script.Parent.Theme)
local UiFx = require(script.Parent.UiFx)

local PlayerRoster = {}

local e = React.createElement

export type Entry = {
	userId: number,
	name: string,
	level: number,
}

export type Props = {
	roster: { Entry },
	--- Pixels from the top edge for the toggle button; the panel hangs
	--- below it. Defaults to 86 (under the lobby wallet).
	topOffset: number?,
}

local TOGGLE_KEY = Enum.KeyCode.Tab

local OWNER_COLOR = Color3.fromRGB(240, 196, 84)

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={math.floor(userId)}&w=48&h=48`
end

type RowProps = {
	entry: Entry,
	order: number,
}

local function Row(props: RowProps)
	local badge = RosterArt.badgeFor(props.entry.level)
	local owner = Admins.isAdmin(props.entry.userId, false)

	local badgeElement
	if badge.assetId ~= "" then
		badgeElement = e("ImageLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Image = badge.assetId,
		})
	else
		badgeElement = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(44, 18),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = `LV {props.entry.level}`,
			TextColor3 = badge.color,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end

	local plate: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = props.order,
	}

	if RosterArt.ROW ~= "" then
		plate.Image = RosterArt.ROW
		plate.ScaleType = Enum.ScaleType.Slice
		plate.SliceCenter = RosterArt.ROW_SLICE
	else
		plate.BackgroundTransparency = 0.35
		plate.BackgroundColor3 = Theme.RAISED
		plate.BorderSizePixel = 0
	end

	return e(if RosterArt.ROW ~= "" then "ImageLabel" else "Frame", plate, {
		corner = if RosterArt.ROW == "" then e("UICorner", { CornerRadius = Theme.CORNER_SMALL }) else nil,
		avatar = e("ImageLabel", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = Theme.INVERSE,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Image = headshot(props.entry.userId),
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		}),
		name = e("TextLabel", {
			Position = UDim2.fromOffset(50, 4),
			Size = UDim2.new(1, -92, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = `{props.entry.name}  |  LV {props.entry.level}`,
			TextColor3 = Theme.TEXT,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		role = e("TextLabel", {
			Position = UDim2.fromOffset(50, 22),
			Size = UDim2.new(1, -92, 0, 14),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = if owner then "OWNER" else "PLAYER TESTER",
			TextColor3 = if owner then OWNER_COLOR else Theme.MUTED,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		badge = badgeElement,
	})
end

--- The panel plus its toggle. Mount once per place, fed by props.
function PlayerRoster.Panel(props: Props)
	local open, setOpen = React.useState(false)
	local show, exiting = UiFx.usePresence(open)

	React.useEffect(function(): () -> ()
		local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == TOGGLE_KEY then
				setOpen(function(current)
					return not current
				end)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	-- 18px padding twice + 26px header + 6px gap + 44px rows with 4px
	-- gaps. Explicit rather than AutomaticSize because a CanvasGroup's
	-- auto-size measured 600px for 112px of content in a live playtest.
	local rowCount = math.max(#props.roster, 1)
	local panelHeight = 64 + rowCount * 48

	local rows: { [string]: any } = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	}

	for order, entry in props.roster do
		rows[`u{entry.userId}`] = e(Row, { entry = entry, order = order })
	end

	local headerElement = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		Text = "DEFENDERS",
		TextColor3 = Theme.ACCENT,
		TextSize = 15,
		LayoutOrder = 0,
	})

	local toggleChildren: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	}

	if RosterArt.EMBLEM ~= "" then
		toggleChildren.icon = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			Image = RosterArt.EMBLEM,
		})
	end

	-- The 9-sliced steel frame (or the flat fallback), OUTSIDE the flow.
	local texture = HudArt.texture("Hexmesh")
	local artChildren: { [string]: any } = {}

	if texture ~= "" then
		artChildren.texture = e("ImageLabel", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 1, -24),
			BackgroundTransparency = 1,
			Image = texture,
			ScaleType = Enum.ScaleType.Crop,
			ImageTransparency = 0.18,
		})
	end

	local artElement
	if RosterArt.FRAME ~= "" then
		artElement = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = RosterArt.FRAME,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = RosterArt.FRAME_SLICE,
			SliceScale = 0.18,
			ZIndex = 0,
		}, artChildren)
	else
		artElement = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, props.topOffset or 86),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
		}),
		toggle = e("TextButton", {
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = if open then Theme.ACCENT else Theme.PANEL,
			BackgroundTransparency = if open then 0 else Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			Text = if RosterArt.EMBLEM ~= "" then "" else "≡",
			TextColor3 = if open then Theme.INVERSE else Theme.TEXT,
			TextSize = 20,
			LayoutOrder = 0,
			[React.Event.Activated] = function()
				setOpen(not open)
			end,
		}, toggleChildren),
		panel = if show
			then e(UiFx.PopIn, {
				frame = {
					Size = UDim2.fromOffset(240, panelHeight),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				},
				exit = exiting,
				children = {
					art = artElement,
					content = e("Frame", {
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}, {
						padding = e("UIPadding", {
							PaddingTop = UDim.new(0, 18),
							PaddingBottom = UDim.new(0, 18),
							PaddingLeft = UDim.new(0, 18),
							PaddingRight = UDim.new(0, 18),
						}),
						stack = e("UIListLayout", {
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 6),
						}),
						header = headerElement,
						list = e("Frame", {
							Size = UDim2.fromScale(1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							LayoutOrder = 1,
						}, rows),
					}),
				},
			})
			else nil,
	})
end

return PlayerRoster

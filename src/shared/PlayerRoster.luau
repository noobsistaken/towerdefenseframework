--!strict
--[[
	The custom player list, replacing the Roblox default in both places.

	One shared component because it IS the same panel twice; each place's
	client feeds it that place's roster atom through props, so this module
	knows no atoms and both places cannot drift apart visually.

	Collapsed: a small emblem button under the wallet/cash panel. Expanded:
	a panel of rows - avatar headshot (the rbxthumb protocol, no async), a
	name, a level badge. Tab toggles it too, PC-standard for a player list.

	Art comes from Config/RosterArt.luau and every piece is optional: a
	missing asset renders the text fallback, never a broken image.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
}

local TOGGLE_KEY = Enum.KeyCode.Tab

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={math.floor(userId)}&w=48&h=48`
end

type RowProps = {
	entry: Entry,
	order: number,
}

local function Row(props: RowProps)
	local badge = RosterArt.badgeFor(props.entry.level)

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
			Position = UDim2.fromOffset(50, 0),
			Size = UDim2.new(1, -110, 1, 0),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = props.entry.name,
			TextColor3 = Theme.TEXT,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		badge = badgeElement,
	})
end

--- The panel plus its toggle. Mount once per place, fed by props.
function PlayerRoster.Panel(props: Props)
	local open, setOpen = React.useState(false)

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

	local rows: { [string]: any } = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	}

	for order, entry in props.roster do
		rows[`u{entry.userId}`] = e(Row, { entry = entry, order = order })
	end

	local headerElement
	if RosterArt.HEADER ~= "" then
		headerElement = e("ImageLabel", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundTransparency = 1,
			Image = RosterArt.HEADER,
			ScaleType = Enum.ScaleType.Crop,
			LayoutOrder = 0,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			caption = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = "DEFENDERS",
				TextColor3 = Theme.TEXT,
				TextSize = 16,
				TextStrokeTransparency = 0.5,
			}),
		})
	else
		headerElement = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = "DEFENDERS",
			TextColor3 = Theme.ACCENT,
			TextSize = 15,
			LayoutOrder = 0,
		})
	end

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

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 86),
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
		panel = if open
			then e(UiFx.PopIn, {
				frame = {
					Size = UDim2.fromOffset(240, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				},
				children = {
					-- The generated steel frame IS the panel: 9-sliced so it
					-- stretches to however many rows are on the server.
					art = if RosterArt.FRAME ~= ""
						then e("ImageLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Image = RosterArt.FRAME,
							ScaleType = Enum.ScaleType.Slice,
							SliceCenter = RosterArt.FRAME_SLICE,
							SliceScale = 0.25,
							ZIndex = 0,
						})
						else nil,
					fallback = if RosterArt.FRAME == ""
						then e("Frame", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Theme.PANEL,
							BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
							BorderSizePixel = 0,
							ZIndex = 0,
						}, { corner = e("UICorner", { CornerRadius = Theme.CORNER }) })
						else nil,
					padding = e("UIPadding", {
						PaddingTop = UDim.new(0, 18),
						PaddingBottom = UDim.new(0, 18),
						PaddingLeft = UDim.new(0, 18),
						PaddingRight = UDim.new(0, 18),
					}),
					list = e("Frame", {
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						LayoutOrder = 1,
					}, rows),
					header = headerElement,
					stack = e("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 6),
					}),
				},
			})
			else nil,
	})
end

return PlayerRoster

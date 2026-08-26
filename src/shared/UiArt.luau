--!strict
--[[
	The generated material system as React components, so a panel or a
	button is skinned in ONE place and every surface in both places moves
	together. Companion to UiFx (motion) the way Theme is to colour.

	Every component degrades to the flat themed surface when its art id is
	empty - the same tolerance rule the sounds and the roster follow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudArt = require(script.Parent.Config.HudArt)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Theme)

local UiArt = {}

local e = React.createElement

export type SurfaceProps = {
	--- Host props, exactly as they would go on the Frame/ImageLabel.
	frame: { [string]: any },
	children: { [string]: any }?,
}

local function surface(art: string, slice: Rect, props: SurfaceProps, sliceScale: number?)
	local merged: { [string]: any } = table.clone(props.frame)

	if art ~= "" then
		merged.BackgroundTransparency = 1
		merged.Image = art
		merged.ScaleType = Enum.ScaleType.Slice
		merged.SliceCenter = slice

		if sliceScale ~= nil then
			merged.SliceScale = sliceScale
		end

		return e("ImageLabel", merged, props.children)
	end

	-- Fallback: the flat themed panel this art replaced.
	if merged.BackgroundColor3 == nil then
		merged.BackgroundColor3 = Theme.PANEL
	end
	if merged.BackgroundTransparency == nil then
		merged.BackgroundTransparency = Theme.PANEL_TRANSPARENCY
	end
	merged.BorderSizePixel = 0

	local children: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
	}

	if props.children ~= nil then
		for key, value in props.children do
			children[key] = value
		end
	end

	return e("Frame", merged, children)
end

--- A compact HUD chip (health, wave, cash, wallet).
function UiArt.Plate(props: SurfaceProps)
	return surface(HudArt.PLATE, HudArt.PLATE_SLICE, props)
end

--- The big riveted frame as the panel HOST rather than an underlay - for
--- AutomaticSize panels, where a scale-sized underlay child inflates the
--- auto-size into a screen-height void (measured live twice: the roster,
--- then the inspector). The image IS the panel, so it tracks whatever
--- height the content resolves. No interior texture for the same reason.
function UiArt.Frame(props: SurfaceProps)
	return surface(HudArt.FRAME, HudArt.FRAME_SLICE, props, 0.18)
end

--- A generated interior weave for a panel's flat centre, or nil when the
--- texture id is missing. A child of the art element (never a sibling in
--- a layout - see the rule in PlayerRoster) so it always sits behind the
--- content and inside the frame's border.
function UiArt.texture(name: string, transparency: number?, inset: number?, zindex: number?)
	local id = HudArt.texture(name)

	if id == "" then
		return nil
	end

	local pad = inset or 0

	return e("ImageLabel", {
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.new(1, -pad * 2, 1, -pad * 2),
		BackgroundTransparency = 1,
		Image = id,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = transparency or 0.45,
		ZIndex = zindex or 0,
	})
end

--- The big panel skin, as a fill-parent underlay: mount FIRST inside any
--- panel whose background should be the riveted frame, with the panel
--- itself left transparent. An underlay rather than the host, because
--- most panels are CanvasGroups (UiFx.PopIn) and a CanvasGroup cannot be
--- an ImageLabel. `textureName` names a HudArt.TEXTURES weave to lay
--- into the flat centre.
function UiArt.frameUnderlay(textureName: string?)
	if HudArt.FRAME == "" then
		return e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		})
	end

	return e("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = HudArt.FRAME,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = HudArt.FRAME_SLICE,
		SliceScale = 0.18,
		ZIndex = 0,
	}, {
		texture = if textureName ~= nil then UiArt.texture(textureName, 0.45, 14) else nil,
	})
end

export type ButtonProps = {
	text: string,
	--- Tint multiplied into the steel bar. White leaves it as generated.
	tint: Color3,
	textColor: Color3,
	textSize: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	autoButtonColor: boolean?,
	onActivated: () -> (),
	children: { [string]: any }?,
}

--- A CTA on the steel bar, tinted per state through ImageColor3 - one
--- material, every colour.
function UiArt.Button(props: ButtonProps)
	local children: { [string]: any } = {
		label = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = props.text,
			TextColor3 = props.textColor,
			TextSize = props.textSize or 14,
		}),
	}

	if props.children ~= nil then
		for key, value in props.children do
			children[key] = value
		end
	end

	if HudArt.BUTTON ~= "" then
		return e("ImageButton", {
			Size = props.size,
			Position = props.position,
			AnchorPoint = props.anchorPoint,
			LayoutOrder = props.layoutOrder,
			BackgroundTransparency = 1,
			Image = HudArt.BUTTON,
			ImageColor3 = props.tint,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = HudArt.BUTTON_SLICE,
			AutoButtonColor = props.autoButtonColor ~= false,
			[React.Event.Activated] = props.onActivated,
		}, children)
	end

	children.corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL })

	return e("TextButton", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = props.tint,
		BorderSizePixel = 0,
		AutoButtonColor = props.autoButtonColor ~= false,
		Text = "",
		[React.Event.Activated] = props.onActivated,
	}, children)
end

--- A stat icon beside a number, or nothing when the art is missing.
function UiArt.icon(name: string, position: UDim2, size: number)
	local id = HudArt.icon(name)

	if id == "" then
		return nil
	end

	return e("ImageLabel", {
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = id,
	})
end

return UiArt

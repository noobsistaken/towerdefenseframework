--!strict
--[[
	Placeholder visual tokens.

	Every value here is an asset-manifest slot. They live in one module so a
	real art pass is a single file to edit rather than a hunt through every
	component.

	What is deliberately NOT placeholder is the information architecture the
	components build with these - what is shown, where, and when. That part
	should survive the art pass unchanged.
]]

local Theme = {}

Theme.PANEL = Color3.fromRGB(18, 20, 24)
Theme.PANEL_TRANSPARENCY = 0.15
Theme.RAISED = Color3.fromRGB(30, 34, 40)

Theme.TEXT = Color3.fromRGB(236, 240, 246)
Theme.MUTED = Color3.fromRGB(150, 158, 170)
Theme.INVERSE = Color3.fromRGB(10, 14, 20)

Theme.ACCENT = Color3.fromRGB(96, 176, 255)
Theme.HEALTH = Color3.fromRGB(220, 76, 76)
Theme.CASH = Color3.fromRGB(240, 196, 84)
Theme.POSITIVE = Color3.fromRGB(96, 210, 128)
Theme.NEGATIVE = Color3.fromRGB(216, 84, 84)

--- Applied to a button the player cannot currently use. Kept as a colour
--- rather than an unmount so the shop layout does not reflow as cash changes.
Theme.DISABLED = Color3.fromRGB(58, 62, 70)

Theme.CORNER = UDim.new(0, 8)
Theme.CORNER_SMALL = UDim.new(0, 6)

Theme.FONT = Enum.Font.GothamBold
Theme.FONT_BODY = Enum.Font.GothamMedium

--- Human-readable text for each placement refusal. The server sends the
--- reason as an enum, so this is the only place the wording lives.
Theme.REJECTION_TEXT = {
	UnknownTower = "Unknown tower",
	NotUnlocked = "You have not unlocked that tower",
	CannotAfford = "Not enough cash",
	OutOfBounds = "Outside the map",
	NotBuildable = "You cannot build there",
	WrongSurface = "Wrong ground for that tower",
	OverlapsTower = "Too close to another tower",
	BlocksPath = "That would block the path",
	TowerCapReached = "You own too many of those",
	WrongMatchState = "You cannot build right now",
} :: { [string]: string }

return Theme

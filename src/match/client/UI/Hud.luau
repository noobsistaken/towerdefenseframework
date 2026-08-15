--!strict
--[[
	Match HUD.

	Placeholder visuals: solid frames, no images, no custom fonts beyond the
	built-in enum. Every colour and size comes from Theme, so a real art pass
	is one file rather than a hunt through every component.

	What is NOT placeholder is the information architecture - what is shown,
	where, and when - because that is the part an art pass should not have to
	redesign.

	Reads atoms, renders. It holds no state of its own and never writes back:
	the server owns every number on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)

local ShopBar = require(script.Parent.ShopBar)
local Theme = require(script.Parent.Theme)
local TowerInspector = require(script.Parent.TowerInspector)
local atoms = require(script.Parent.Parent.State.atoms)
local useAtom = require(script.Parent.useAtom)

local e = React.createElement

--- Short label for each phase.
---
--- Takes `string`, not Types.MatchState, and that is a real if small loss
--- worth naming. Both React.useState and a generic `useAtom<T>` WIDEN a
--- literal union to plain `string` when they infer T, so a value read out of
--- an atom arrives here already widened. Narrowing it back would take a cast,
--- and a cast that exists only to satisfy the typechecker is exactly what
--- this project's strict-mode rule forbids.
---
--- The union is still enforced where it can do work: Zap generates it on the
--- wire, and atoms.matchState is annotated at its declaration, so the value
--- cannot be wrong by the time it reaches this function. What is lost is
--- catching a typo in the comparisons below - hence the explicit fallback.
local function phaseLabel(state: string): string
	if state == "Loading" then
		return "LOADING"
	elseif state == "Preparing" then
		return "BUILD"
	elseif state == "WaveActive" then
		return "WAVE"
	elseif state == "Intermission" then
		return "CLEARED"
	elseif state == "Victory" then
		return "VICTORY"
	end

	return "DEFEATED"
end

local function panel(props: { [string]: any }, children: { [string]: any }?)
	local merged: { [string]: any } = {
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}

	for key, value in props do
		merged[key] = value
	end

	local content: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
	}

	if children ~= nil then
		for key, value in children do
			content[key] = value
		end
	end

	return e("Frame", merged, content)
end

local function label(props: { [string]: any })
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextColor3 = Theme.TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}

	for key, value in props do
		merged[key] = value
	end

	return e("TextLabel", merged)
end

--- Base health, top left. Shared across the whole team.
local function BaseHealthPanel()
	local current = useAtom(atoms.baseHealth)
	local max = useAtom(atoms.baseHealthMax)
	local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0

	return panel({
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(220, 62),
	}, {
		title = label({
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.fromOffset(190, 16),
			Text = "BASE",
			TextColor3 = Theme.MUTED,
			TextSize = 12,
		}),
		value = label({
			Position = UDim2.fromOffset(14, 22),
			Size = UDim2.fromOffset(190, 20),
			Text = `{current} / {max}`,
			TextSize = 18,
		}),
		track = e("Frame", {
			Position = UDim2.fromOffset(14, 46),
			Size = UDim2.fromOffset(192, 6),
			BackgroundColor3 = Color3.fromRGB(48, 52, 60),
			BorderSizePixel = 0,
		}, {
			corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			fill = e("Frame", {
				Size = UDim2.fromScale(fraction, 1),
				BackgroundColor3 = Theme.HEALTH,
				BorderSizePixel = 0,
			}, {
				corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
		}),
	})
end

--- Wave number and phase countdown, top centre.
local function WavePanel()
	local state = useAtom(atoms.matchState)
	local wave = useAtom(atoms.waveNumber)
	local endsAt = useAtom(atoms.phaseEndsAt)
	local now = useAtom(atoms.clock)
	local endless = useAtom(atoms.endless)

	local remaining = math.max(0, endsAt - now)
	local timerText = if endsAt > 0 then `{remaining}s` else "-"

	-- Endless overrides the phase word rather than adding a fourth line: once
	-- the campaign is cleared, that the run is on borrowed time matters more
	-- than which phase of the cycle it happens to be in.
	local phaseText = if endless and state ~= "Defeat" then "ENDLESS" else phaseLabel(state)

	return panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(200, 62),
	}, {
		phase = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 16),
			Text = phaseText,
			TextColor3 = Theme.ACCENT,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		wave = label({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 22),
			Text = `WAVE {wave}`,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		timer = label({
			Position = UDim2.fromOffset(0, 44),
			Size = UDim2.new(1, 0, 0, 14),
			Text = timerText,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

--- This player's cash, top right.
local function CashPanel()
	local cash = useAtom(atoms.cash)

	return panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(160, 62),
	}, {
		title = label({
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.fromOffset(130, 16),
			Text = "CASH",
			TextColor3 = Theme.MUTED,
			TextSize = 12,
		}),
		value = label({
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.fromOffset(130, 24),
			Text = `${cash}`,
			TextColor3 = Theme.CASH,
			TextSize = 22,
		}),
	})
end

--- Why the last placement was refused. Positioned above the shop, where the
--- player was already looking when they clicked.
local function RejectionToast()
	local reason = useAtom(atoms.placementRejection)

	if reason == nil then
		return nil
	end

	local text = Theme.REJECTION_TEXT[reason] or "You cannot build there"

	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.fromOffset(300, 28),
		BackgroundColor3 = Theme.NEGATIVE,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Theme.FONT,
		Text = text,
		TextColor3 = Theme.TEXT,
		TextSize = 13,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

--- Early start, above the shop. Only meaningful during the build phase, so it
--- is unmounted rather than greyed out at every other time.
local function EarlyStartButton()
	local state = useAtom(atoms.matchState)

	if state ~= "Preparing" then
		return nil
	end

	return e("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.fromOffset(200, 38),
		BackgroundColor3 = Theme.ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT,
		Text = "START WAVE",
		TextColor3 = Theme.INVERSE,
		TextSize = 15,
		[React.Event.Activated] = function()
			Net.RequestEarlyStart.Fire()
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

local function Hud()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		health = e(BaseHealthPanel),
		wave = e(WavePanel),
		cash = e(CashPanel),
		shop = e(ShopBar),
		inspector = e(TowerInspector),
		rejection = e(RejectionToast),
		earlyStart = e(EarlyStartButton),
	})
end

return Hud

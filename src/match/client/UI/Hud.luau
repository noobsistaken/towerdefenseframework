--!strict
--[[
	Match HUD.

	Placeholder visuals: solid frames, no images, no custom fonts beyond the
	built-in enum. Every colour and size here is a slot in the asset manifest.
	What is NOT placeholder is the information architecture - what is shown,
	where, and when - because that is the part a real art pass should not have
	to redesign.

	Reads atoms, renders. It holds no state of its own and never writes back:
	the server owns every number on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)

local atoms = require(script.Parent.Parent.State.atoms)

local e = React.createElement

local PANEL = Color3.fromRGB(18, 20, 24)
local TEXT = Color3.fromRGB(236, 240, 246)
local MUTED = Color3.fromRGB(150, 158, 170)
local ACCENT = Color3.fromRGB(96, 176, 255)
local HEALTH = Color3.fromRGB(220, 76, 76)
local CASH = Color3.fromRGB(240, 196, 84)

--- Subscribes a component to one atom. Charm atoms are callable readers, so
--- this is the whole binding: read once for the initial value, then let
--- Charm.subscribe drive every later render.
local function useAtom<T>(atom: () -> T): T
	local value, setValue = React.useState(atom())

	React.useEffect(function()
		return Charm.subscribe(atom, setValue)
	end, {})

	return value
end

--- Short label for each phase. Deliberately terse: this sits above the wave
--- number and competes with it for attention.
---
--- Takes `string`, not Types.MatchState, and that is a real if small loss
--- worth naming. Both React.useState and a generic `useAtom<T>` WIDEN a
--- literal union to plain `string` when they infer T, so a value read out of
--- an atom arrives here already widened. Narrowing it back would take a
--- cast, and a cast that exists only to satisfy the typechecker is exactly
--- what this project's strict-mode rule forbids.
---
--- The union is still enforced where it can do work: Zap generates it on the
--- wire, and atoms.matchState is annotated at its declaration, so the value
--- cannot be wrong by the time it reaches this function. What is lost is
--- catching a typo in the comparisons BELOW - hence the explicit fallback.
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
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}

	for key, value in props do
		merged[key] = value
	end

	local content: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
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
		Font = Enum.Font.GothamBold,
		TextColor3 = TEXT,
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
			TextColor3 = MUTED,
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
				BackgroundColor3 = HEALTH,
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

	local remaining = math.max(0, endsAt - now)
	local timerText = if endsAt > 0 then `{remaining}s` else "-"

	return panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(200, 62),
	}, {
		phase = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 16),
			Text = phaseLabel(state),
			TextColor3 = ACCENT,
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
			TextColor3 = MUTED,
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
			TextColor3 = MUTED,
			TextSize = 12,
		}),
		value = label({
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.fromOffset(130, 24),
			Text = `${cash}`,
			TextColor3 = CASH,
			TextSize = 22,
		}),
	})
end

--- Early start, bottom centre. Only meaningful during the build phase, so it
--- is unmounted rather than greyed out at every other time.
local function EarlyStartButton()
	local state = useAtom(atoms.matchState)

	if state ~= "Preparing" then
		return nil
	end

	return e("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(200, 42),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "START WAVE",
		TextColor3 = Color3.fromRGB(10, 14, 20),
		TextSize = 16,
		[React.Event.Activated] = function()
			Net.RequestEarlyStart.Fire()
		end,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
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
		earlyStart = e(EarlyStartButton),
	})
end

return Hud

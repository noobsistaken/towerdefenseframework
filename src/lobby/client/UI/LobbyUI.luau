--!strict
--[[
	Lobby UI.

	Placeholder visuals from the shared Theme, same as the match HUD. What is
	not placeholder is the information architecture: which vote is winning, how
	long is left, and how many players have readied - because those are the
	three things a player in a lobby actually needs, and an art pass should not
	have to redesign them.

	Reads atoms, fires requests. It holds no authoritative state: pressing a
	vote button highlights it locally AND sends a request, and the server's
	tally overwrites the display either way.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Theme)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local atoms = require(script.Parent.Parent.State.atoms)

local e = React.createElement

local function label(props: { [string]: any })
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextColor3 = Theme.TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
	}

	for key, value in props do
		merged[key] = value
	end

	return e("TextLabel", merged)
end

local function Header()
	local state = useAtom(atoms.lobbyState)
	local seconds = useAtom(atoms.secondsRemaining)
	local players = useAtom(atoms.playerCount)
	local ready = useAtom(atoms.readyCount)

	local headline: string

	if state == "Gathering" then
		headline = "WAITING FOR PLAYERS"
	elseif state == "Voting" then
		headline = `LAUNCHING IN {seconds}s`
	else
		headline = "LAUNCHING"
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(420, 76),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		headline = label({
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.new(1, 0, 0, 26),
			Text = headline,
			TextColor3 = Theme.ACCENT,
			TextSize = 22,
		}),
		counts = label({
			Position = UDim2.fromOffset(0, 44),
			Size = UDim2.new(1, 0, 0, 18),
			Text = `{players} in lobby  ·  {ready} ready`,
			TextColor3 = Theme.MUTED,
			TextSize = 13,
		}),
	})
end

local function ReadyButton()
	local isReady = useAtom(atoms.isReady)
	local state = useAtom(atoms.lobbyState)

	-- Unmounted rather than greyed out once the teleport is in flight: there
	-- is nothing left to decide, so a disabled button is just noise.
	if state == "Launching" then
		return nil
	end

	return e("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(220, 48),
		BackgroundColor3 = if isReady then Theme.POSITIVE else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = if isReady then "READY" else "READY UP",
		TextColor3 = if isReady then Theme.INVERSE else Theme.TEXT,
		TextSize = 18,
		[React.Event.Activated] = function()
			local next = not atoms.isReady()
			atoms.isReady(next)
			Net.SetReady.Fire({ ready = next })
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

local function FailureToast()
	local reason = useAtom(atoms.failureReason)

	if reason == nil then
		return nil
	end

	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(520, 32),
		BackgroundColor3 = Theme.NEGATIVE,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Theme.FONT_BODY,
		Text = reason,
		TextColor3 = Theme.TEXT,
		TextSize = 13,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

--- One line of instruction where two rows of buttons used to be. The vote
--- moved into the WORLD: stand in a map's zone, step onto a difficulty pad.
local function ZoneHint()
	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(480, 22),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BODY,
		Text = "Stand in a map's zone to vote for it - step onto a pad to pick the difficulty",
		TextColor3 = Theme.MUTED,
		TextSize = 14,
	})
end

local function LobbyUI()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		header = e(Header),
		hint = e(ZoneHint),
		ready = e(ReadyButton),
		failure = e(FailureToast),
	})
end

return LobbyUI

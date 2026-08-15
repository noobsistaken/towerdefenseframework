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

local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
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

--- Votes for one option, looked up from a tally list.
local function votesFor(tallies: { atoms.Tally }, option: string): number
	for _, entry in tallies do
		if entry.option == option then
			return entry.votes
		end
	end

	return 0
end

--- One vote button. Highlighted when this player picked it, outlined when it
--- is currently winning - two different facts that need to be separable at a
--- glance, since your pick losing is the interesting case.
local function VoteButton(props: {
	option: string,
	displayName: string,
	votes: number,
	picked: boolean,
	winning: boolean,
	layoutOrder: number,
	onClick: () -> (),
})
	return e("TextButton", {
		Size = UDim2.fromOffset(150, 54),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if props.picked then Theme.ACCENT else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = "",
		[React.Event.Activated] = props.onClick,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		stroke = if props.winning
			then e("UIStroke", {
				Color = Theme.POSITIVE,
				Thickness = 2,
			})
			else nil,
		name = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 20),
			Text = props.displayName,
			TextColor3 = if props.picked then Theme.INVERSE else Theme.TEXT,
			TextSize = 15,
		}),
		votes = label({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 16),
			Text = if props.votes == 1 then "1 vote" else `{props.votes} votes`,
			TextColor3 = if props.picked then Theme.INVERSE else Theme.MUTED,
			TextSize = 12,
		}),
	})
end

--- A titled row of vote buttons.
local function VoteRow(props: {
	title: string,
	y: number,
	options: { string },
	displayNames: { [string]: string },
	tallies: { atoms.Tally },
	picked: string?,
	winning: string,
	onPick: (string) -> (),
})
	local children: { [string]: any } = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, option in props.options do
		children[option] = e(VoteButton, {
			option = option,
			displayName = props.displayNames[option] or option,
			votes = votesFor(props.tallies, option),
			picked = props.picked == option,
			winning = props.winning == option,
			layoutOrder = index,
			onClick = function()
				props.onPick(option)
			end,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, props.y),
		Size = UDim2.fromOffset(700, 84),
		BackgroundTransparency = 1,
	}, {
		title = label({
			Size = UDim2.new(1, 0, 0, 16),
			Text = props.title,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
		}),
		buttons = e("Frame", {
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundTransparency = 1,
		}, children),
	})
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

local function MapVotes()
	local tallies = useAtom(atoms.mapTallies)
	local winning = useAtom(atoms.winningMapId)
	local picked = useAtom(atoms.myMapVote)

	local displayNames: { [string]: string } = {}

	for id, map in MapRegistry.MAPS do
		displayNames[id] = map.displayName
	end

	return e(VoteRow, {
		title = "MAP",
		y = 124,
		options = MapRegistry.IDS,
		displayNames = displayNames,
		tallies = tallies,
		picked = picked,
		winning = winning,
		onPick = function(option: string)
			atoms.myMapVote(option)
			Net.CastVote.Fire({ poll = "Map", option = option })
		end,
	})
end

local function DifficultyVotes()
	local tallies = useAtom(atoms.difficultyTallies)
	local winning = useAtom(atoms.winningDifficultyId)
	local picked = useAtom(atoms.myDifficultyVote)

	local displayNames: { [string]: string } = {}

	for _, id in Difficulty.IDS do
		local preset = Difficulty.find(id)

		if preset ~= nil then
			displayNames[id] = preset.displayName
		end
	end

	return e(VoteRow, {
		title = "DIFFICULTY",
		y = 224,
		options = Difficulty.IDS,
		displayNames = displayNames,
		tallies = tallies,
		picked = picked,
		winning = winning,
		onPick = function(option: string)
			atoms.myDifficultyVote(option)
			Net.CastVote.Fire({ poll = "Difficulty", option = option })
		end,
	})
end

local function LobbyUI()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		header = e(Header),
		maps = e(MapVotes),
		difficulties = e(DifficultyVotes),
		ready = e(ReadyButton),
		failure = e(FailureToast),
	})
end

return LobbyUI

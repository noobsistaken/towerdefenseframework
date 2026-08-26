--!strict
--[[
	End-of-run results.

	Renders only once MatchEnded has arrived, and shows how the run actually
	finished. It can be shown twice in one session, which is deliberate: a run
	that clears the campaign gets a victory card, then carries on into endless
	mode, and if that ends in defeat the card is replaced by the defeat one.

	Deliberately does NOT block input. The match place returns everyone to the
	lobby on its own timer, and a modal overlay would mean a player who cleared
	the campaign could not watch the endless waves they are still playing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Theme = require(ReplicatedStorage.Shared.Theme)
local UiFx = require(ReplicatedStorage.Shared.UiFx)
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

--- One reward figure with its caption. Each stat pops in a beat after
--- the one before it, so the payout reads as a sequence, not a wall.
local function Stat(props: { caption: string, value: string, color: Color3, x: number, order: number })
	return e(UiFx.PopIn, {
		frame = {
			Position = UDim2.fromOffset(props.x, 96),
			Size = UDim2.fromOffset(140, 48),
			BackgroundTransparency = 1,
		},
		delay = 0.12 + props.order * 0.09,
		children = {
			value = label({
				Size = UDim2.new(1, 0, 0, 26),
				Text = props.value,
				TextColor3 = props.color,
				TextSize = 24,
			}),
			caption = label({
				Position = UDim2.fromOffset(0, 28),
				Size = UDim2.new(1, 0, 0, 16),
				Text = props.caption,
				TextColor3 = Theme.MUTED,
				TextSize = 12,
			}),
		},
	})
end

local function ResultsScreen()
	local result = useAtom(atoms.matchResult)

	if result == nil then
		return nil
	end

	local won = result.won
	local headline = if won then "CAMPAIGN CLEARED" else "DEFEATED"

	-- Framed as what happens NEXT rather than as a verdict. After a win the
	-- run continues into endless mode, so "you win" alone would be misleading.
	local subtitle = if won then "Endless mode begins - see how far you can hold." else "Returning to the lobby..."

	local waves = result.wavesCleared
	local wavesText = if waves == 1 then "1 WAVE" else `{waves} WAVES`

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(560, 172),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = 0.05,
		},
		restartKey = if won then "won" else "lost",
		children = {
			corner = e("UICorner", { CornerRadius = Theme.CORNER }),
			stroke = e("UIStroke", {
				Color = if won then Theme.POSITIVE else Theme.NEGATIVE,
				Thickness = 2,
			}),
			headline = label({
				Position = UDim2.fromOffset(0, 20),
				Size = UDim2.new(1, 0, 0, 30),
				Text = headline,
				TextColor3 = if won then Theme.POSITIVE else Theme.NEGATIVE,
				TextSize = 26,
			}),
			subtitle = label({
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, 0, 0, 18),
				Text = subtitle,
				TextColor3 = Theme.MUTED,
				TextSize = 13,
			}),
			waves = e(Stat, {
				caption = "CLEARED",
				value = wavesText,
				color = Theme.TEXT,
				x = 20,
				order = 0,
			}),
			coins = e(Stat, {
				caption = "COINS EARNED",
				value = `+{result.coinsAwarded}`,
				color = Theme.CASH,
				x = 160,
				order = 1,
			}),
			xp = e(Stat, {
				caption = `XP EARNED`,
				value = `+{result.xpAwarded}`,
				color = Theme.ACCENT,
				x = 300,
				order = 2,
			}),
			-- Spent at the lobby's reroll station; earning them HERE is what makes
			-- the results screen the bridge between the two places.
			tokens = e(Stat, {
				caption = "REROLL TOKENS",
				value = `+{result.tokensAwarded}`,
				color = Color3.fromRGB(158, 110, 208),
				x = 420,
				order = 3,
			}),
			-- Shown so the number means something. Level is derived from total XP
			-- on the server, so this is only ever a preview of the gain.
			levels = label({
				Position = UDim2.fromOffset(0, 148),
				Size = UDim2.new(1, 0, 0, 14),
				Text = `worth {Rewards.levelFor(result.xpAwarded) - 1} level(s) from scratch`,
				TextColor3 = Theme.MUTED,
				TextSize = 11,
			}),
		},
	})
end

return ResultsScreen

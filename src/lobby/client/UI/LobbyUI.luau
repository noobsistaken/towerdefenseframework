--!strict
--[[
	Lobby UI.

	Placeholder visuals from the shared Theme, same as the match HUD. What is
	not placeholder is the information architecture: which vote is winning,
	how long is left, how many players have readied, and what your collection
	holds - because those are the things a player in a lobby actually needs,
	and an art pass should not have to redesign them.

	Reads atoms, fires requests. The gacha panels are the one place outside
	init.client that writes replicated atoms, and only with values the SERVER
	just returned: every roll reply carries the post-transaction balances
	precisely so this layer never derives money on its own.

	The panels open by WALKING, not by hotkey: atoms.activeStation follows
	the character across the station pads, so the UI appears where the world
	says it should - same one-layout rule as the vote zones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Net = require(ReplicatedStorage.Net)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Traits = require(ReplicatedStorage.Shared.Config.Traits)
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

--- Display colour for a rarity id, falling back to muted for the empty
--- string a refused roll carries.
local function rarityColor(rarityId: string): Color3
	local tier = Rarity.find(rarityId)

	return if tier ~= nil then tier.color else Theme.MUTED
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
		-- Scale-with-cap rather than fixed 420: at fixed width the header's
		-- right edge crossed the coin strip's left edge on viewports under
		-- ~840px, and the two panels share a y band.
		Size = UDim2.new(0.42, 0, 0, 76),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		limit = e("UISizeConstraint", { MaxSize = Vector2.new(420, 76) }),
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

--- Coins and reroll tokens, top-right. Unmounted until the first profile
--- answer so it cannot flash a zero balance at a player who owns thousands.
local function ProfileStrip()
	local loaded = useAtom(atoms.profileLoaded)
	local coins = useAtom(atoms.coins)
	local tokens = useAtom(atoms.rerollTokens)

	if not loaded then
		return nil
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 24),
		Size = UDim2.fromOffset(170, 58),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		coins = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 22),
			Text = `{coins} coins`,
			TextColor3 = Theme.CASH,
			TextSize = 17,
		}),
		tokens = label({
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 16),
			Text = `{tokens} reroll token{if tokens == 1 then "" else "s"}`,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
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

--- The odds line, straight from the ladder the roll actually uses. One
--- source for the number shown and the number rolled is what keeps the
--- display honest by construction.
local function oddsText(): string
	local parts: { string } = {}

	for _, id in Rarity.IDS do
		table.insert(parts, `{id} {Rarity.get(id).gachaWeight}%`)
	end

	return table.concat(parts, "  ·  ")
end

type RollReply = {
	outcome: "Rolled" | "Duplicate" | "CannotAfford" | "Unavailable",
	towerId: string,
	rarityId: string,
	coins: number,
	refunded: number,
}

--- The gacha station panel. Open while the character stands on the pad.
local function GachaPanel()
	local station = useAtom(atoms.activeStation)
	local coins = useAtom(atoms.coins)
	local busy, setBusy = React.useState(false)
	local lastRoll, setLastRoll = React.useState(nil :: RollReply?)
	-- The real double-fire guard. `busy` is a render-closure value: a second
	-- click landing before the re-render commits still sees busy=false, and
	-- two Calls means paying twice. A ref reads and writes synchronously.
	local rolling = React.useRef(false)

	if station ~= "Gacha" then
		return nil
	end

	local cost = Economy.GACHA_ROLL_COST
	local affordable = coins >= cost

	local resultText = "Walk up, pay, pray."
	local resultColor = Theme.MUTED

	if lastRoll ~= nil then
		local definition = Towers.find(lastRoll.towerId)
		local name = if definition ~= nil then definition.displayName else lastRoll.towerId

		if lastRoll.outcome == "Rolled" then
			resultText = `NEW: {name}  ({lastRoll.rarityId})`
			resultColor = rarityColor(lastRoll.rarityId)
		elseif lastRoll.outcome == "Duplicate" then
			resultText = `Duplicate {name} - {lastRoll.refunded} coins back`
			resultColor = Theme.MUTED
		elseif lastRoll.outcome == "Unavailable" then
			resultText = "Your collection is still loading - try again in a moment"
			resultColor = Theme.MUTED
		else
			resultText = "Not enough coins"
			resultColor = Theme.NEGATIVE
		end
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(400, 190),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 22),
			Text = "TROOP GACHA",
			TextColor3 = Theme.CASH,
			TextSize = 18,
		}),
		odds = label({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, -16, 0, 26),
			AnchorPoint = Vector2.new(0, 0),
			Font = Theme.FONT_BODY,
			Text = oddsText(),
			TextColor3 = Theme.MUTED,
			TextSize = 10,
			TextWrapped = true,
		}),
		result = label({
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 24),
			Text = resultText,
			TextColor3 = resultColor,
			TextSize = 16,
		}),
		roll = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(240, 44),
			BackgroundColor3 = if affordable and not busy then Theme.CASH else Theme.DISABLED,
			BorderSizePixel = 0,
			AutoButtonColor = affordable and not busy,
			Font = Theme.FONT,
			Text = if busy then "ROLLING..." else `ROLL  -  {cost} COINS`,
			TextColor3 = if affordable and not busy then Theme.INVERSE else Theme.MUTED,
			TextSize = 16,
			[React.Event.Activated] = function()
				if rolling.current or not atoms.profileLoaded() then
					return
				end

				rolling.current = true
				setBusy(true)

				task.spawn(function()
					local ok, reply = pcall(function()
						return Net.RollTower.Call({})
					end)

					if ok then
						-- Server-returned balances, never derived locally -
						-- and never from an Unavailable reply, whose zeros
						-- describe a missing session, not this player.
						if reply.outcome ~= "Unavailable" then
							atoms.coins(reply.coins)
						end

						if reply.outcome == "Rolled" then
							local unlocked = table.clone(atoms.unlockedTowers())
							table.insert(unlocked, reply.towerId)
							atoms.unlockedTowers(unlocked)
						end

						setLastRoll(reply)
					end

					rolling.current = false
					setBusy(false)
				end)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
	})
end

type RerollReply = {
	outcome: "Rolled" | "CannotAfford" | "UnknownTower" | "Unavailable",
	traitId: string,
	rarityId: string,
	tokens: number,
}

--- One tower's button in the reroll grid: name in its rarity colour, the
--- current trait underneath.
local function RerollRow(props: { towerId: string, onReroll: (towerId: string) -> (), busy: boolean, order: number })
	local traits = useAtom(atoms.traits)
	local definition = Towers.find(props.towerId)

	if definition == nil then
		return nil
	end

	local traitId: string? = traits[props.towerId]
	local traitText = "no trait"
	local traitColor = Theme.MUTED

	if traitId ~= nil then
		local trait = Traits.find(traitId)

		if trait ~= nil then
			traitText = `{trait.displayName} ({trait.rarity})`
			traitColor = rarityColor(trait.rarity)
		end
	end

	return e("TextButton", {
		Size = UDim2.fromOffset(180, 44),
		BackgroundColor3 = Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = not props.busy,
		Text = "",
		LayoutOrder = props.order,
		[React.Event.Activated] = function()
			if not props.busy then
				props.onReroll(props.towerId)
			end
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		name = label({
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.new(1, 0, 0, 18),
			Text = definition.displayName,
			TextColor3 = rarityColor(definition.rarity),
			TextSize = 14,
		}),
		trait = label({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.FONT_BODY,
			Text = traitText,
			TextColor3 = traitColor,
			TextSize = 11,
		}),
	})
end

--- The reroll station panel: every owned tower, click one to reroll its
--- trait for one token.
local function RerollPanel()
	local station = useAtom(atoms.activeStation)
	local tokens = useAtom(atoms.rerollTokens)
	local unlocked = useAtom(atoms.unlockedTowers)
	local busy, setBusy = React.useState(false)
	local lastReroll, setLastReroll = React.useState(nil :: RerollReply?)
	-- Same synchronous double-fire guard as the gacha's roll button: `busy`
	-- alone is a render-closure value and two fast clicks spend two tokens.
	local rolling = React.useRef(false)

	if station ~= "Reroll" then
		return nil
	end

	local onReroll = function(towerId: string)
		if rolling.current then
			return
		end

		rolling.current = true
		setBusy(true)

		task.spawn(function()
			local ok, reply = pcall(function()
				return Net.RerollTrait.Call({ towerId = towerId })
			end)

			if ok then
				if reply.outcome ~= "Unavailable" then
					atoms.rerollTokens(reply.tokens)
				end

				if reply.outcome == "Rolled" then
					local map = table.clone(atoms.traits())
					map[towerId] = reply.traitId
					atoms.traits(map)
				end

				setLastReroll(reply)
			end

			rolling.current = false
			setBusy(false)
		end)
	end

	local resultText = `1 token per reroll  ·  {tokens} available`
	local resultColor = Theme.MUTED

	if lastReroll ~= nil then
		if lastReroll.outcome == "Rolled" then
			local trait = Traits.find(lastReroll.traitId)
			local name = if trait ~= nil then trait.displayName else lastReroll.traitId

			resultText = `Rolled {name}  ({lastReroll.rarityId})`
			resultColor = rarityColor(lastReroll.rarityId)
		elseif lastReroll.outcome == "CannotAfford" then
			resultText = "Out of reroll tokens - finish a match to earn more"
			resultColor = Theme.NEGATIVE
		elseif lastReroll.outcome == "Unavailable" then
			resultText = "Your collection is still loading - try again in a moment"
			resultColor = Theme.MUTED
		else
			resultText = "You do not own that tower"
			resultColor = Theme.NEGATIVE
		end
	end

	local rows: { [string]: any } = {
		layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(180, 44),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}

	for order, towerId in unlocked do
		rows[towerId] = e(RerollRow, {
			towerId = towerId,
			onReroll = onReroll,
			busy = busy,
			order = order,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(420, 280),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 22),
			Text = "TRAIT REROLL",
			TextColor3 = Color3.fromRGB(158, 110, 208),
			TextSize = 18,
		}),
		result = label({
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Theme.FONT_BODY,
			Text = resultText,
			TextColor3 = resultColor,
			TextSize = 12,
		}),
		grid = e("ScrollingFrame", {
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -24, 1, -78),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, rows),
	})
end

local function LobbyUI()
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		header = e(Header),
		profile = e(ProfileStrip),
		hint = e(ZoneHint),
		ready = e(ReadyButton),
		failure = e(FailureToast),
		gacha = e(GachaPanel),
		reroll = e(RerollPanel),
	})
end

return LobbyUI

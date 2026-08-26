--!strict
--[[
	Lobby hub UI.

	A HUD and four walk-in panels. The HUD is always up: who you are (level,
	coins, tokens), how many are here, and the LOADOUT button. The panels
	appear by WALKING - atoms.activeArea follows the character across the
	area pads, so the UI appears where the world says it should, the same
	one-layout rule the server's occupancy scan uses.

	Nothing here launches anything on a timer. The GAME panel's START button
	is the only path to a match, and it is a request the server re-validates
	against the character position it owns.

	Reads atoms, fires requests. The gacha panels are the one place outside
	init.client that writes replicated atoms, and only with values the
	SERVER just returned in a funct reply.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Loadouts = require(ReplicatedStorage.Shared.Loadouts)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ReplicatedStorage.Net)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Traits = require(ReplicatedStorage.Shared.Config.Traits)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local atoms = require(script.Parent.Parent.State.atoms)

local e = React.createElement

local REROLL_COLOR = Color3.fromRGB(158, 110, 208)

local DIFFICULTY_COLORS: { [string]: Color3 } = {
	Casual = Color3.fromRGB(96, 190, 120),
	Normal = Color3.fromRGB(222, 198, 100),
	Nightmare = Color3.fromRGB(205, 88, 88),
}

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

-- ---------------------------------------------------------------------------
-- Reveal animation
--
-- Both roll buttons share one shape: the reply is already in hand, and the
-- suspense is manufactured on top of it - a fast cycle of names in their
-- rarity colours that slows nothing down server-side and cannot desync,
-- because the outcome was decided before the first flicker.
-- ---------------------------------------------------------------------------

export type Reveal = {
	text: string,
	color: Color3,
}

local REVEAL_TICKS = 14
local REVEAL_TICK_SECONDS = 0.07

--- Runs the cycling reveal, then clears itself. Call from inside the roll
--- task, AFTER the reply arrives; `pick` supplies one random name+colour per
--- flicker frame.
local function runReveal(setReveal: (Reveal?) -> (), pick: () -> Reveal)
	for _ = 1, REVEAL_TICKS do
		setReveal(pick())
		task.wait(REVEAL_TICK_SECONDS)
	end

	setReveal(nil)
end

local towerRng = Random.new()

local function randomTowerReveal(): Reveal
	local id = Towers.IDS[towerRng:NextInteger(1, #Towers.IDS)]
	local definition = Towers.get(id)

	return { text = definition.displayName, color = rarityColor(definition.rarity) }
end

local function randomTraitReveal(): Reveal
	local id = Traits.IDS[towerRng:NextInteger(1, #Traits.IDS)]
	local definition = Traits.get(id)

	return { text = definition.displayName, color = rarityColor(definition.rarity) }
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

local function HudIdentity()
	local players = useAtom(atoms.playerCount)
	local state = useAtom(atoms.lobbyState)

	return e("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(250, 62),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		title = label({
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 24),
			Text = "LOBBY",
			TextColor3 = Theme.ACCENT,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		counts = label({
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -28, 0, 16),
			Font = Theme.FONT_BODY,
			Text = if state == "Launching"
				then "launching a match..."
				else `{players} online  ·  walk into an area to play`,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

--- Level, coins and tokens, top-right. Unmounted until the first real
--- profile answer so it cannot flash a zero balance.
local function HudWallet()
	local loaded = useAtom(atoms.profileLoaded)
	local coins = useAtom(atoms.coins)
	local tokens = useAtom(atoms.rerollTokens)
	local level = useAtom(atoms.level)

	if not loaded then
		return nil
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(180, 62),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		level = label({
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 18),
			Text = `LEVEL {level}`,
			TextColor3 = Theme.ACCENT,
			TextSize = 13,
		}),
		coins = label({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 18),
			Text = `{coins} coins`,
			TextColor3 = Theme.CASH,
			TextSize = 15,
		}),
		tokens = label({
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.FONT_BODY,
			Text = `{tokens} reroll token{if tokens == 1 then "" else "s"}`,
			TextColor3 = REROLL_COLOR,
			TextSize = 11,
		}),
	})
end

local function LoadoutButton()
	local loaded = useAtom(atoms.profileLoaded)
	local loadout = useAtom(atoms.loadout)
	local open = useAtom(atoms.loadoutOpen)

	if not loaded then
		return nil
	end

	return e("TextButton", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(180, 44),
		BackgroundColor3 = if open then Theme.ACCENT else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = `LOADOUT  {#loadout}/{Loadouts.MAX}`,
		TextColor3 = if open then Theme.INVERSE else Theme.TEXT,
		TextSize = 15,
		[React.Event.Activated] = function()
			atoms.loadoutOpen(not atoms.loadoutOpen())
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
		Position = UDim2.new(0.5, 0, 1, -72),
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

-- ---------------------------------------------------------------------------
-- Game panel: the chooser
-- ---------------------------------------------------------------------------

local function votesFor(tallies: { atoms.Tally }, option: string): number
	for _, tally in tallies do
		if tally.option == option then
			return tally.votes
		end
	end

	return 0
end

type MapButtonProps = {
	mapId: string,
	order: number,
}

local function MapButton(props: MapButtonProps)
	local tallies = useAtom(atoms.mapTallies)
	local winning = useAtom(atoms.winningMapId)
	local mine = useAtom(atoms.myMapVote)

	local map = MapRegistry.find(props.mapId)

	if map == nil then
		return nil
	end

	local votes = votesFor(tallies, props.mapId)
	local isMine = mine == props.mapId
	local crown = if winning == props.mapId then " \u{2605}" else ""

	return e("TextButton", {
		Size = UDim2.fromOffset(98, 54),
		BackgroundColor3 = if isMine then Theme.ACCENT else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = props.order,
		[React.Event.Activated] = function()
			atoms.myMapVote(props.mapId)
			Net.CastVote.Fire({ poll = "Map", option = props.mapId })
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		name = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 18),
			Text = `{map.displayName}{crown}`,
			TextColor3 = if isMine then Theme.INVERSE else Theme.TEXT,
			TextSize = 13,
		}),
		votes = label({
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.FONT_BODY,
			Text = `{votes} vote{if votes == 1 then "" else "s"}`,
			TextColor3 = if isMine then Theme.INVERSE else Theme.MUTED,
			TextSize = 11,
		}),
	})
end

type DifficultyButtonProps = {
	difficultyId: string,
	order: number,
}

local function DifficultyButton(props: DifficultyButtonProps)
	local tallies = useAtom(atoms.difficultyTallies)
	local winning = useAtom(atoms.winningDifficultyId)
	local mine = useAtom(atoms.myDifficultyVote)

	local preset = Difficulty.find(props.difficultyId)

	if preset == nil then
		return nil
	end

	local votes = votesFor(tallies, props.difficultyId)
	local isMine = mine == props.difficultyId
	local color = DIFFICULTY_COLORS[props.difficultyId] or Theme.MUTED
	local crown = if winning == props.difficultyId then " \u{2605}" else ""

	return e("TextButton", {
		Size = UDim2.fromOffset(130, 40),
		BackgroundColor3 = if isMine then color else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = `{preset.displayName}{crown}  ·  {votes}`,
		TextColor3 = if isMine then Theme.INVERSE else color,
		TextSize = 13,
		LayoutOrder = props.order,
		[React.Event.Activated] = function()
			atoms.myDifficultyVote(props.difficultyId)
			Net.CastVote.Fire({ poll = "Difficulty", option = props.difficultyId })
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
	})
end

--- The chooser. Opens by standing in the GAME area; START is the only
--- launch path in the whole game, and it takes everyone in the area.
local function GamePanel()
	local area = useAtom(atoms.activeArea)
	local state = useAtom(atoms.lobbyState)
	local winningMap = useAtom(atoms.winningMapId)
	local winningDifficulty = useAtom(atoms.winningDifficultyId)

	if area ~= "Game" then
		return nil
	end

	local launching = state == "Launching"
	local winnerName = winningMap
	local map = MapRegistry.find(winningMap)

	if map ~= nil then
		winnerName = map.displayName
	end

	local mapButtons: { [string]: any } = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}

	for order, mapId in MapRegistry.IDS do
		mapButtons[mapId] = e(MapButton, { mapId = mapId, order = order })
	end

	local difficultyButtons: { [string]: any } = {
		layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}

	for order, difficultyId in Difficulty.IDS do
		difficultyButtons[difficultyId] = e(DifficultyButton, { difficultyId = difficultyId, order = order })
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(580, 290),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 24),
			Text = "CHOOSE YOUR BATTLE",
			TextColor3 = Theme.ACCENT,
			TextSize = 19,
		}),
		hint = label({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.FONT_BODY,
			Text = "Everyone standing in the GAME area comes along when START is pressed",
			TextColor3 = Theme.MUTED,
			TextSize = 12,
		}),
		mapHeader = label({
			Position = UDim2.fromOffset(0, 62),
			Size = UDim2.new(1, 0, 0, 14),
			Text = "MAP",
			TextColor3 = Theme.MUTED,
			TextSize = 11,
		}),
		maps = e("Frame", {
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundTransparency = 1,
		}, mapButtons),
		difficultyHeader = label({
			Position = UDim2.fromOffset(0, 142),
			Size = UDim2.new(1, 0, 0, 14),
			Text = "DIFFICULTY",
			TextColor3 = Theme.MUTED,
			TextSize = 11,
		}),
		difficulties = e("Frame", {
			Position = UDim2.fromOffset(0, 160),
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
		}, difficultyButtons),
		start = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(280, 48),
			BackgroundColor3 = if launching then Theme.DISABLED else Theme.POSITIVE,
			BorderSizePixel = 0,
			AutoButtonColor = not launching,
			Font = Theme.FONT,
			Text = if launching then "LAUNCHING..." else `START  -  {winnerName} · {winningDifficulty}`,
			TextColor3 = if launching then Theme.MUTED else Theme.INVERSE,
			TextSize = 16,
			[React.Event.Activated] = function()
				if not launching then
					Net.RequestLaunch.Fire()
				end
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- Loadout editor
-- ---------------------------------------------------------------------------

type LoadoutRowProps = {
	towerId: string,
	equipped: boolean,
	full: boolean,
	onToggle: (towerId: string) -> (),
	order: number,
}

local function LoadoutRow(props: LoadoutRowProps)
	local definition = Towers.find(props.towerId)

	if definition == nil then
		return nil
	end

	local blocked = not props.equipped and props.full

	return e("TextButton", {
		Size = UDim2.fromOffset(136, 44),
		BackgroundColor3 = if props.equipped then Theme.ACCENT elseif blocked then Theme.DISABLED else Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = not blocked,
		Text = "",
		LayoutOrder = props.order,
		[React.Event.Activated] = function()
			if not blocked then
				props.onToggle(props.towerId)
			end
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		name = label({
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.new(1, 0, 0, 18),
			Text = definition.displayName,
			TextColor3 = if props.equipped then Theme.INVERSE else rarityColor(definition.rarity),
			TextSize = 13,
		}),
		tag = label({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.FONT_BODY,
			Text = if props.equipped then "EQUIPPED" else definition.rarity,
			TextColor3 = if props.equipped then Theme.INVERSE else Theme.MUTED,
			TextSize = 10,
		}),
	})
end

--- Pick the six you bring. A DRAFT edited locally and saved whole through
--- SetLoadout - the server applies it all or not at all, and echoes the
--- deck as it stands either way.
local function LoadoutPanel()
	local open = useAtom(atoms.loadoutOpen)
	local owned = useAtom(atoms.unlockedTowers)
	local saved = useAtom(atoms.loadout)
	local draft, setDraft = React.useState({} :: { string })
	local status, setStatus = React.useState("")
	local saving = React.useRef(false)

	-- Re-seed the draft from the saved deck each time the panel opens. The
	-- boolean dep is deliberate: open/close is exactly when to reset.
	React.useEffect(function()
		if open then
			setDraft(table.clone(atoms.loadout()))
			setStatus("")
		end
	end, { open })

	if not open then
		return nil
	end

	local full = #draft >= Loadouts.MAX

	local onToggle = function(towerId: string)
		local next = table.clone(draft)
		local index = table.find(next, towerId)

		if index ~= nil then
			table.remove(next, index)
		elseif #next < Loadouts.MAX then
			table.insert(next, towerId)
		end

		setDraft(next)
		setStatus("")
	end

	local rows: { [string]: any } = {
		layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(136, 44),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}

	for order, towerId in owned do
		rows[towerId] = e(LoadoutRow, {
			towerId = towerId,
			equipped = table.find(draft, towerId) ~= nil,
			full = full,
			onToggle = onToggle,
			order = order,
		})
	end

	local dirty = #draft ~= #saved

	if not dirty then
		for index, id in draft do
			if saved[index] ~= id then
				dirty = true
				break
			end
		end
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 380),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 22),
			Text = `LOADOUT  {#draft}/{Loadouts.MAX}`,
			TextColor3 = Theme.ACCENT,
			TextSize = 18,
		}),
		hint = label({
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.FONT_BODY,
			Text = if status ~= "" then status else "The six you bring to every match. Tap to equip.",
			TextColor3 = if status ~= "" then Theme.NEGATIVE else Theme.MUTED,
			TextSize = 12,
		}),
		grid = e("ScrollingFrame", {
			Position = UDim2.fromOffset(12, 58),
			Size = UDim2.new(1, -24, 1, -122),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, rows),
		save = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(0.5, -6, 1, -14),
			Size = UDim2.fromOffset(150, 40),
			BackgroundColor3 = if dirty and #draft > 0 then Theme.POSITIVE else Theme.DISABLED,
			BorderSizePixel = 0,
			AutoButtonColor = dirty and #draft > 0,
			Font = Theme.FONT,
			Text = "SAVE",
			TextColor3 = if dirty and #draft > 0 then Theme.INVERSE else Theme.MUTED,
			TextSize = 15,
			[React.Event.Activated] = function()
				if saving.current or not dirty or #draft == 0 then
					return
				end

				saving.current = true

				task.spawn(function()
					local ok, reply = pcall(function()
						return Net.SetLoadout.Call({ towerIds = draft })
					end)

					if ok then
						-- The echo is the deck as the server now holds it,
						-- accepted or refused - never guess from `ok` alone.
						atoms.loadout(reply.loadout)

						if reply.ok then
							atoms.loadoutOpen(false)
						else
							setStatus("That loadout was refused - it may hold towers you no longer own.")
						end
					end

					saving.current = false
				end)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
		cancel = e("TextButton", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, 6, 1, -14),
			Size = UDim2.fromOffset(150, 40),
			BackgroundColor3 = Theme.RAISED,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			Text = "CLOSE",
			TextColor3 = Theme.TEXT,
			TextSize = 15,
			[React.Event.Activated] = function()
				atoms.loadoutOpen(false)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- Gacha panel
-- ---------------------------------------------------------------------------

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

local function GachaPanel()
	local area = useAtom(atoms.activeArea)
	local coins = useAtom(atoms.coins)
	local busy, setBusy = React.useState(false)
	local lastRoll, setLastRollRaw = React.useState(nil :: RollReply?)
	local reveal, setRevealRaw = React.useState(nil :: Reveal?)
	-- useState's inference over an optional initial is unreliable in the old
	-- solver - it lands on `nil` or on the non-optional half depending on
	-- the call site (TowerInspector's InfoState note documents the same
	-- gotcha). One cast per setter, and nothing else widens.
	local setLastRoll = setLastRollRaw :: (RollReply?) -> ()
	local setReveal = setRevealRaw :: (Reveal?) -> ()
	-- The real double-fire guard. `busy` is a render-closure value: a second
	-- click landing before the re-render commits still sees busy=false, and
	-- two Calls means paying twice. A ref reads and writes synchronously.
	local rolling = React.useRef(false)

	if area ~= "Gacha" then
		return nil
	end

	local cost = Economy.GACHA_ROLL_COST
	local affordable = coins >= cost

	local resultText = "Walk up, pay, pray."
	local resultColor = Theme.MUTED

	if reveal ~= nil then
		resultText = reveal.text
		resultColor = reveal.color
	elseif lastRoll ~= nil then
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
			Position = UDim2.fromOffset(8, 38),
			Size = UDim2.new(1, -16, 0, 26),
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
						-- The outcome is already decided; the flicker is
						-- theatre, run only for a roll that actually rolled.
						if reply.outcome == "Rolled" or reply.outcome == "Duplicate" then
							setLastRoll(nil)
							runReveal(setReveal, randomTowerReveal)
						end

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

-- ---------------------------------------------------------------------------
-- Reroll panel
-- ---------------------------------------------------------------------------

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
	local area = useAtom(atoms.activeArea)
	local tokens = useAtom(atoms.rerollTokens)
	local unlocked = useAtom(atoms.unlockedTowers)
	local busy, setBusy = React.useState(false)
	local lastReroll, setLastRerollRaw = React.useState(nil :: RerollReply?)
	local reveal, setRevealRaw = React.useState(nil :: Reveal?)
	-- Same optional-initial inference gotcha as GachaPanel; same one cast
	-- per setter.
	local setLastReroll = setLastRerollRaw :: (RerollReply?) -> ()
	local setReveal = setRevealRaw :: (Reveal?) -> ()
	-- Same synchronous double-fire guard as the gacha's roll button: `busy`
	-- alone is a render-closure value and two fast clicks spend two tokens.
	local rolling = React.useRef(false)

	if area ~= "Reroll" then
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
				if reply.outcome == "Rolled" then
					setLastReroll(nil)
					runReveal(setReveal, randomTraitReveal)
				end

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

	if reveal ~= nil then
		resultText = reveal.text
		resultColor = reveal.color
	elseif lastReroll ~= nil then
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
			TextColor3 = REROLL_COLOR,
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
		identity = e(HudIdentity),
		wallet = e(HudWallet),
		loadoutButton = e(LoadoutButton),
		failure = e(FailureToast),
		game = e(GamePanel),
		loadout = e(LoadoutPanel),
		gacha = e(GachaPanel),
		reroll = e(RerollPanel),
	})
end

return LobbyUI

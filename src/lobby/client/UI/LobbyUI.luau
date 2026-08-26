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
local UiFx = require(ReplicatedStorage.Shared.UiFx)
local useAtom = require(ReplicatedStorage.Shared.useAtom)

local AdminConsole = require(ReplicatedStorage.Shared.AdminConsole)

local EggReveal = require(script.Parent.EggReveal)

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
	local coinsTarget = useAtom(atoms.coins)
	local tokensTarget = useAtom(atoms.rerollTokens)
	local level = useAtom(atoms.level)
	-- The numbers CHASE their targets - a gacha refund or an admin grant
	-- rolls in instead of snapping.
	local coins = math.floor(UiFx.useSmoothedNumber(coinsTarget) + 0.5)
	local tokens = math.floor(UiFx.useSmoothedNumber(tokensTarget) + 0.5)

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

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -72),
			Size = UDim2.fromOffset(520, 32),
			BackgroundColor3 = Theme.NEGATIVE,
			BackgroundTransparency = 0.1,
		},
		restartKey = reason,
		children = {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			text = label({
				Size = UDim2.fromScale(1, 1),
				Font = Theme.FONT_BODY,
				Text = reason,
				TextSize = 13,
			}),
		},
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
	local startScale = React.useRef(nil :: UIScale?)

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

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -110),
			Size = UDim2.fromOffset(580, 290),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		},
		children = {
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
					UiFx.pressPop(startScale.current)
					Net.RequestLaunch.Fire()
				end
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			pressScale = e("UIScale", { ref = startScale }),
		}),
		},
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
	local saveScale = React.useRef(nil :: UIScale?)

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

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(480, 380),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = 0.05,
		},
		children = {
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

				UiFx.pressPop(saveScale.current)
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
			pressScale = e("UIScale", { ref = saveScale }),
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
		},
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
	-- useState's inference over an optional initial is unreliable in the old
	-- solver - it lands on `nil` or on the non-optional half depending on
	-- the call site (TowerInspector's InfoState note documents the same
	-- gotcha). One cast per setter, and nothing else widens.
	local setLastRoll = setLastRollRaw :: (RollReply?) -> ()
	-- The real double-fire guard. `busy` is a render-closure value: a second
	-- click landing before the re-render commits still sees busy=false, and
	-- two Calls means paying twice. A ref reads and writes synchronously.
	local rolling = React.useRef(false)
	local rollScale = React.useRef(nil :: UIScale?)

	if area ~= "Gacha" then
		return nil
	end

	local cost = Economy.GACHA_ROLL_COST
	local affordable = coins >= cost

	local resultText = "Walk up, pay, pray."
	local resultColor = Theme.MUTED

	if busy then
		resultText = "..."
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

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -110),
			Size = UDim2.fromOffset(400, 190),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = Theme.PANEL_TRANSPARENCY,
		},
		children = {
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

				UiFx.pressPop(rollScale.current)
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

						-- A roll that rolled gets the egg. The guard stays
						-- held until the cinematic dismisses, so eggs can
						-- never stack; refusals skip straight to the text.
						if reply.outcome == "Rolled" or reply.outcome == "Duplicate" then
							EggReveal.play({
								towerId = reply.towerId,
								rarityId = reply.rarityId,
								duplicate = reply.outcome == "Duplicate",
								refunded = reply.refunded,
							}, function()
								setLastRoll(reply)
								rolling.current = false
								setBusy(false)
							end)

							return
						end

						setLastRoll(reply)
					end

					rolling.current = false
					setBusy(false)
				end)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			pressScale = e("UIScale", { ref = rollScale }),
		}),
		},
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

--- The odds of landing one trait: its tier's ladder weight split evenly
--- across the tier's traits - exactly how Gacha.roll draws, so the chances
--- table shows the numbers the roll actually uses.
local function traitChance(traitId: string): number
	local definition = Traits.get(traitId)
	local inTier = 0

	for _, id in Traits.IDS do
		if Traits.get(id).rarity == definition.rarity then
			inTier += 1
		end
	end

	return Rarity.get(definition.rarity).gachaWeight / inTier
end

--- "13.33%", "8%", "0.7%" - two decimals with the noise trimmed.
local function formatChance(percent: number): string
	local text = string.format("%.2f", percent)
	text = text:gsub("%.?0+$", "")

	return text .. "%"
end

--- The featured unit, standing in a viewport on a slow pedestal spin - the
--- same presentation the egg reveal ends on, through the same model
--- builder, so the reroll screen and the hatch can never disagree about
--- what a unit looks like.
local function UnitPortrait(props: { towerId: string? })
	local viewportRef = React.useRef(nil :: ViewportFrame?)

	React.useEffect(function(): () -> ()
		local viewport = viewportRef.current
		local towerId = props.towerId

		if viewport == nil or towerId == nil then
			return function() end
		end

		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local unit = EggReveal.buildUnit(Towers.find(towerId))
		unit.Parent = viewport

		local _, extents = unit:GetBoundingBox()
		camera.CFrame = CFrame.lookAt(
			Vector3.new(0, extents.Y * 0.15, extents.Magnitude * 0.85 + 2),
			Vector3.new(0, 0, 0)
		)

		local alive = true

		task.spawn(function()
			while alive do
				unit:PivotTo(unit:GetPivot() * CFrame.Angles(0, math.rad(0.8), 0))
				task.wait(0.03)
			end
		end)

		return function()
			alive = false
			unit:Destroy()
			camera:Destroy()
		end
	end, { props.towerId or "" })

	return e("ViewportFrame", {
		ref = viewportRef,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(190, 190),
		BackgroundColor3 = Theme.INVERSE,
		BackgroundTransparency = 0.25,
		Ambient = Color3.fromRGB(185, 185, 195),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		stroke = e("UIStroke", { Color = REROLL_COLOR, Thickness = 1.5, Transparency = 0.4 }),
	})
end

--- Shared scaffolding for the reroll screen's overlays: a full-screen
--- dimmer that swallows clicks (and closes on one), with a fully OPAQUE
--- panel on top. Mounted at the UI root, above every panel - the first
--- chances popup lived inside the panel and z-fought it into
--- unreadability.
local function overlay(onClose: () -> (), size: UDim2, children: { [string]: any }): any
	-- The panel pops on mount through a function-ref UIScale: overlays
	-- render conditionally, so a hook here would break the rules of hooks.
	children.uiFxScale = e("UIScale", { ref = UiFx.popScale })

	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 10,
		[React.Event.Activated] = onClose,
	}, {
		panel = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = size,
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 11,
			-- Swallows the click so tapping the panel does not close it.
			[React.Event.Activated] = function() end,
		}, children),
	})
end

local function closeButton(onClose: () -> ())
	return e("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.NEGATIVE,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT,
		Text = "X",
		TextColor3 = Theme.TEXT,
		TextSize = 15,
		ZIndex = 12,
		[React.Event.Activated] = onClose,
	}, {
		corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
end

--- The odds table, genre-standard: every trait, rarity-coloured, with the
--- true percentage beside it. Its own overlay, opaque, readable.
local function TraitChancesOverlay()
	local area = useAtom(atoms.activeArea)
	local open = useAtom(atoms.traitChancesOpen)

	if not open or area ~= "Reroll" then
		return nil
	end

	local close = function()
		atoms.traitChancesOpen(false)
	end

	local ordered: { string } = {}

	for _, id in Traits.IDS do
		table.insert(ordered, id)
	end

	table.sort(ordered, function(a, b)
		local orderA = Rarity.get(Traits.get(a).rarity).order
		local orderB = Rarity.get(Traits.get(b).rarity).order

		if orderA ~= orderB then
			return orderA < orderB
		end

		return a < b
	end)

	local rows: { [string]: any } = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	}

	for index, id in ordered do
		local definition = Traits.get(id)
		local color = rarityColor(definition.rarity)

		rows[id] = e("Frame", {
			Size = UDim2.fromOffset(300, 36),
			BackgroundColor3 = Theme.RAISED,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 12,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			stroke = e("UIStroke", { Color = color, Thickness = 1.2, Transparency = 0.25 }),
			name = label({
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -100, 1, 0),
				Text = definition.displayName,
				TextColor3 = color,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 12,
			}),
			chance = label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 0),
				Size = UDim2.fromOffset(84, 36),
				Text = formatChance(traitChance(id)),
				TextColor3 = color,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 12,
			}),
		})
	end

	return overlay(close, UDim2.fromOffset(360, 480), {
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 26),
			Text = "TRAIT CHANCES",
			TextColor3 = Theme.CASH,
			TextSize = 20,
			ZIndex = 12,
		}),
		close = closeButton(close),
		list = e("ScrollingFrame", {
			Position = UDim2.fromOffset(16, 50),
			Size = UDim2.new(1, -32, 1, -66),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ZIndex = 12,
		}, rows),
	})
end

type InventoryCellProps = {
	towerId: string,
	picked: boolean,
	traitId: string?,
	onPick: (towerId: string) -> (),
	order: number,
}

local function InventoryCell(props: InventoryCellProps)
	local definition = Towers.find(props.towerId)

	if definition == nil then
		return nil
	end

	local traitText = "no trait"
	local traitColor = Theme.MUTED

	if props.traitId ~= nil then
		local trait = Traits.find(props.traitId)

		if trait ~= nil then
			traitText = trait.displayName
			traitColor = rarityColor(trait.rarity)
		end
	end

	return e("TextButton", {
		Size = UDim2.fromOffset(150, 56),
		BackgroundColor3 = Theme.RAISED,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = props.order,
		ZIndex = 12,
		[React.Event.Activated] = function()
			props.onPick(props.towerId)
		end,
	}, {
		corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		stroke = e("UIStroke", {
			Color = if props.picked then Theme.ACCENT else rarityColor(definition.rarity),
			Thickness = if props.picked then 2.5 else 1,
			Transparency = if props.picked then 0 else 0.55,
		}),
		name = label({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 20),
			Text = definition.displayName,
			TextColor3 = rarityColor(definition.rarity),
			TextSize = 14,
			ZIndex = 12,
		}),
		trait = label({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.FONT_BODY,
			Text = traitText,
			TextColor3 = traitColor,
			TextSize = 11,
			ZIndex = 12,
		}),
	})
end

--- The inventory: opened by SELECT UNIT on the reroll screen, on top of
--- it. Click a unit to highlight it, then SELECT to make it the featured
--- one - two deliberate steps, so a stray tap can never switch the unit
--- a reroll is about to spend a token on.
local function UnitInventoryOverlay()
	local area = useAtom(atoms.activeArea)
	local open = useAtom(atoms.unitPickerOpen)
	local unlocked = useAtom(atoms.unlockedTowers)
	local traits = useAtom(atoms.traits)
	local picked, setPickedRaw = React.useState(nil :: string?)
	-- Same optional-initial inference gotcha as the panels; same cast.
	local setPicked = setPickedRaw :: (string?) -> ()

	-- A fresh visit starts with nothing highlighted. The boolean dep is the
	-- point: open/close is exactly when to reset.
	React.useEffect(function()
		if open then
			setPicked(nil)
		end
	end, { open })

	if not open or area ~= "Reroll" then
		return nil
	end

	local close = function()
		atoms.unitPickerOpen(false)
	end

	local cells: { [string]: any } = {
		layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 56),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}

	for order, towerId in unlocked do
		cells[towerId] = e(InventoryCell, {
			towerId = towerId,
			picked = towerId == picked,
			traitId = traits[towerId],
			onPick = setPicked,
			order = order,
		})
	end

	local canSelect = picked ~= nil

	return overlay(close, UDim2.fromOffset(540, 440), {
		title = label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 26),
			Text = "SELECT A UNIT",
			TextColor3 = Theme.ACCENT,
			TextSize = 20,
			ZIndex = 12,
		}),
		close = closeButton(close),
		grid = e("ScrollingFrame", {
			Position = UDim2.fromOffset(16, 50),
			Size = UDim2.new(1, -32, 1, -122),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ZIndex = 12,
		}, cells),
		select = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(220, 46),
			BackgroundColor3 = if canSelect then Theme.POSITIVE else Theme.DISABLED,
			BorderSizePixel = 0,
			AutoButtonColor = canSelect,
			Font = Theme.FONT,
			Text = "SELECT",
			TextColor3 = if canSelect then Theme.INVERSE else Theme.MUTED,
			TextSize = 17,
			ZIndex = 12,
			[React.Event.Activated] = function()
				if picked ~= nil then
					atoms.rerollUnit(picked)
					close()
				end
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
	})
end

--- The reroll station: the featured unit standing as a model, SELECT UNIT
--- to swap it through the inventory overlay, REROLL to spend a token, and
--- TRAIT CHANCES for the true odds.
local function RerollPanel()
	local area = useAtom(atoms.activeArea)
	local tokens = useAtom(atoms.rerollTokens)
	local unlocked = useAtom(atoms.unlockedTowers)
	local traits = useAtom(atoms.traits)
	local featured = useAtom(atoms.rerollUnit)
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
	local rerollScale = React.useRef(nil :: UIScale?)

	if area ~= "Reroll" then
		return nil
	end

	local currentId: string? = featured or unlocked[1]
	local currentDefinition = if currentId ~= nil then Towers.find(currentId) else nil

	local onReroll = function()
		if rolling.current or currentId == nil then
			return
		end

		local towerId = currentId

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

	-- The line under the portrait: the current trait, the live reveal
	-- flicker, or the refusal - whichever is the truth right now.
	local traitLine = "No trait"
	local traitColor = Theme.MUTED
	local currentTraitId: string? = if currentId ~= nil then traits[currentId] else nil

	if currentTraitId ~= nil then
		local trait = Traits.find(currentTraitId)

		if trait ~= nil then
			traitLine = `{trait.displayName}  ({trait.rarity})`
			traitColor = rarityColor(trait.rarity)
		end
	end

	if reveal ~= nil then
		traitLine = reveal.text
		traitColor = reveal.color
	elseif lastReroll ~= nil and lastReroll.outcome ~= "Rolled" then
		if lastReroll.outcome == "CannotAfford" then
			traitLine = "Out of tokens - finish a match to earn more"
			traitColor = Theme.NEGATIVE
		elseif lastReroll.outcome == "Unavailable" then
			traitLine = "Collection still loading..."
			traitColor = Theme.MUTED
		end
	end

	local affordable = tokens >= 1 and currentId ~= nil

	return e(UiFx.PopIn, {
		frame = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -100),
			Size = UDim2.fromOffset(520, 380),
			BackgroundColor3 = Theme.PANEL,
			BackgroundTransparency = 0.06,
		},
		children = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		panelStroke = e("UIStroke", { Color = REROLL_COLOR, Thickness = 1.5, Transparency = 0.45 }),
		title = e("TextLabel", {
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = "TRAIT REROLL",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 22,
		}, {
			gradient = e("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(236, 110, 170), Color3.fromRGB(150, 110, 236)),
			}),
		}),
		tokensLine = label({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.FONT_BODY,
			Text = `{tokens} reroll token{if tokens == 1 then "" else "s"}  -  rerolling replaces the current trait`,
			TextColor3 = Theme.MUTED,
			TextSize = 12,
		}),
		portrait = e(UnitPortrait, { towerId = currentId }),
		unitName = label({
			Position = UDim2.fromOffset(16, 258),
			Size = UDim2.fromOffset(190, 22),
			Text = if currentDefinition ~= nil then currentDefinition.displayName else "-",
			TextColor3 = if currentDefinition ~= nil then rarityColor(currentDefinition.rarity) else Theme.MUTED,
			TextSize = 17,
		}),
		traitName = label({
			Position = UDim2.fromOffset(16, 280),
			Size = UDim2.fromOffset(190, 34),
			Font = Theme.FONT_BODY,
			Text = traitLine,
			TextColor3 = traitColor,
			TextSize = 12,
			TextWrapped = true,
		}),
		selectUnit = e("TextButton", {
			Position = UDim2.fromOffset(240, 100),
			Size = UDim2.fromOffset(240, 52),
			BackgroundColor3 = Theme.ACCENT,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			Text = "SELECT UNIT",
			TextColor3 = Theme.INVERSE,
			TextSize = 17,
			[React.Event.Activated] = function()
				atoms.unitPickerOpen(true)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		}),
		selectHint = label({
			Position = UDim2.fromOffset(240, 156),
			Size = UDim2.fromOffset(240, 30),
			Font = Theme.FONT_BODY,
			Text = "Pick which unit the reroll applies to",
			TextColor3 = Theme.MUTED,
			TextSize = 11,
			TextWrapped = true,
		}),
		chances = e("TextButton", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.fromOffset(170, 44),
			BackgroundColor3 = Theme.CASH,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			Text = "TRAIT CHANCES",
			TextColor3 = Theme.INVERSE,
			TextSize = 14,
			[React.Event.Activated] = function()
				atoms.traitChancesOpen(true)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			gradient = e("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(255, 214, 120), Color3.fromRGB(236, 160, 70)),
				Rotation = 90,
			}),
		}),
		reroll = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -16),
			Size = UDim2.fromOffset(240, 44),
			BackgroundColor3 = if affordable and not busy then Color3.fromRGB(236, 110, 170) else Theme.DISABLED,
			BorderSizePixel = 0,
			AutoButtonColor = affordable and not busy,
			Font = Theme.FONT,
			Text = if busy then "REROLLING..." else "REROLL  -  1 TOKEN",
			TextColor3 = if affordable and not busy then Theme.INVERSE else Theme.MUTED,
			TextSize = 16,
			[React.Event.Activated] = function()
				if affordable and not busy then
					UiFx.pressPop(rerollScale.current)
					onReroll()
				end
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			pressScale = e("UIScale", { ref = rerollScale }),
			gradient = if affordable and not busy
				then e("UIGradient", {
					Color = ColorSequence.new(Color3.fromRGB(255, 150, 200), Color3.fromRGB(190, 120, 255)),
					Rotation = 10,
				})
				else nil,
		}),
		},
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
		unitPicker = e(UnitInventoryOverlay),
		traitChances = e(TraitChancesOverlay),
		-- F2. No Cash here - there is no match to be cash in - and grants
		-- patch the same atoms the roll replies do, from the same kind of
		-- server-returned balance.
		admin = e(AdminConsole, {
			showCash = false,
			onGranted = function(currency: AdminConsole.Currency, balance: number)
				if currency == "Coins" then
					atoms.coins(balance)
				elseif currency == "Tokens" then
					atoms.rerollTokens(balance)
				end
			end,
		}),
	})
end

return LobbyUI

--!strict
--[[
	The admin console. F2 toggles it; it renders at all only for accounts in
	Config/Admins.luau (or in Studio), and that client-side check is purely
	cosmetic - the server re-checks the allowlist on every call, so a forged
	mount earns a silent refusal.

	Shared between the two places because it is the same console twice. The
	match mounts it with the sandbox verbs that need a match to act on (spawn
	an enemy, clear the field, skip a wave, heal the base) and with Cash,
	which only exists there. The lobby mounts it with the collection verb
	instead.

	WHAT THIS IS FOR: making a state reachable in seconds that play would
	take twenty minutes to reach. Wave 30 with four Zeppelins in the air is a
	thirty-second job here and a long grind otherwise, and a bug you cannot
	reach is a bug you cannot fix.

	Every verb routes through the SAME systems ordinary play uses rather than
	writing state directly, so what the console produces is a real match
	state and not a lookalike that diverges the moment it is touched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Admins = require(script.Parent.Config.Admins)
local Enemies = require(script.Parent.Config.Enemies)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Theme)

local e = React.createElement

export type Currency = "Cash" | "Coins" | "Tokens"

export type Action = "SpawnEnemy" | "KillEnemies" | "SkipWave" | "HealBase" | "UnlockAll"

export type Props = {
	--- Whether to offer Cash and the match sandbox. Only the match place has
	--- a match to be cash in, or enemies to spawn into.
	showCash: boolean,
	--- Called with every successful grant's currency and new balance, so the
	--- lobby can patch its profile atoms. The match needs nothing: its cash
	--- replicates through CashChanged regardless of why it changed.
	onGranted: ((currency: Currency, balance: number) -> ())?,
	--- Called after any successful non-grant action, so a place that caches
	--- state the action changed can refresh it. The lobby uses this to
	--- re-read its profile after UnlockAll.
	onActed: ((action: Action) -> ())?,
}

local TOGGLE_KEY = Enum.KeyCode.F2

local PANEL_WIDTH = 300
local ROW_HEIGHT = 30

type Row = {
	currency: Currency,
	--- True for currencies that only exist inside a match. Filtered on this
	--- flag rather than on `currency == "Cash"`, because the old solver
	--- mangles a negated singleton refinement into `string | string` and the
	--- zap call then refuses the widened value.
	matchOnly: boolean,
	color: Color3,
	amounts: { number },
}

local ROWS: { Row } = {
	{
		currency = "Cash" :: Currency,
		matchOnly = true,
		color = Color3.fromRGB(120, 210, 140),
		amounts = { 1000, 10000 },
	},
	{
		currency = "Coins" :: Currency,
		matchOnly = false,
		color = Theme.CASH,
		amounts = { 1000, 10000 },
	},
	{
		currency = "Tokens" :: Currency,
		matchOnly = false,
		color = Color3.fromRGB(158, 110, 208),
		amounts = { 10, 100 },
	},
}

--- How many of an enemy one press spawns. Capped at the wire's own 0..50.
local SPAWN_COUNTS = { 1, 5, 10 }

local function sectionLabel(text: string, y: number)
	return e("TextLabel", {
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.new(1, -24, 0, 14),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BODY,
		Text = text,
		TextColor3 = Theme.MUTED,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function AdminConsole(props: Props)
	local visible, setVisible = React.useState(false)
	local status, setStatus = React.useState("F2 hides this console")
	local spawnCount, setSpawnCount = React.useState(1)
	-- Synchronous guard, not the render-closure `busy` pattern: two fast
	-- presses would otherwise both see the old value and fire twice.
	local busy = React.useRef(false)

	React.useEffect(function(): () -> ()
		local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode == TOGGLE_KEY then
				setVisible(function(current)
					return not current
				end)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	-- After the hooks, never before: hook order must not depend on props.
	if not Admins.isAdmin(Players.LocalPlayer.UserId, RunService:IsStudio()) then
		return nil
	end

	if not visible then
		return nil
	end

	local grant = function(currency: Currency, amount: number)
		if busy.current then
			return
		end

		busy.current = true

		task.spawn(function()
			local ok, reply = pcall(function()
				return Net.AdminGrant.Call({ currency = currency, amount = amount })
			end)

			if ok and reply.ok then
				setStatus(`+{amount} {currency}  ->  {reply.balance}`)

				local onGranted = props.onGranted

				if onGranted ~= nil then
					onGranted(currency, reply.balance)
				end
			else
				setStatus(`{currency} grant refused`)
			end

			busy.current = false
		end)
	end

	local act = function(action: Action, id: string, amount: number)
		if busy.current then
			return
		end

		busy.current = true
		setStatus("...")

		task.spawn(function()
			local ok, reply = pcall(function()
				return Net.AdminAction.Call({ action = action, id = id, amount = amount })
			end)

			-- The server's message is the status line either way: it knows
			-- what it did, and a client guess would be a second source of
			-- truth about the same event.
			if ok then
				setStatus(reply.message)

				local onActed = props.onActed

				if reply.ok and onActed ~= nil then
					onActed(action)
				end
			else
				setStatus("Action failed")
			end

			busy.current = false
		end)
	end

	local children: { [string]: any } = {
		corner = e("UICorner", { CornerRadius = Theme.CORNER }),
		stroke = e("UIStroke", { Color = Theme.NEGATIVE, Thickness = 1 }),
		title = e("TextLabel", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = "ADMIN",
			TextColor3 = Theme.NEGATIVE,
			TextSize = 14,
		}),
		statusLine = e("TextLabel", {
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.new(1, -20, 0, 14),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = status,
			TextColor3 = Theme.MUTED,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	}

	local y = 46

	-- ---------------------------------------------------------------------
	-- Currency
	-- ---------------------------------------------------------------------

	children.currencyHeader = sectionLabel("CURRENCY", y)
	y += 16

	for _, row in ROWS do
		if row.matchOnly and not props.showCash then
			continue
		end

		children[`label{row.currency}`] = e("TextLabel", {
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(60, ROW_HEIGHT),
			BackgroundTransparency = 1,
			Font = Theme.FONT,
			Text = row.currency:upper(),
			TextColor3 = row.color,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		for index, amount in row.amounts do
			-- Typed capture: a loop local read inside a closure widens its
			-- singleton union in the old solver (same trap as the IsA
			-- refinements in Bursts); the annotation pins what the closure sees.
			local currency: Currency = row.currency

			children[`grant{row.currency}{amount}`] = e("TextButton", {
				Position = UDim2.fromOffset(76 + (index - 1) * 104, y),
				Size = UDim2.fromOffset(98, ROW_HEIGHT),
				BackgroundColor3 = Theme.RAISED,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Font = Theme.FONT,
				Text = `+{amount}`,
				TextColor3 = row.color,
				TextSize = 13,
				[React.Event.Activated] = function()
					grant(currency, amount)
				end,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			})
		end

		y += ROW_HEIGHT + 6
	end

	-- ---------------------------------------------------------------------
	-- Verbs
	-- ---------------------------------------------------------------------

	y += 6
	children.actionHeader = sectionLabel(if props.showCash then "MATCH" else "COLLECTION", y)
	y += 16

	local verbs: { { label: string, action: Action } } = if props.showCash
		then {
			{ label = "KILL ALL", action = "KillEnemies" :: Action },
			{ label = "SKIP WAVE", action = "SkipWave" :: Action },
			{ label = "HEAL BASE", action = "HealBase" :: Action },
		}
		else {
			{ label = "UNLOCK ALL TOWERS", action = "UnlockAll" :: Action },
		}

	local verbWidth = (PANEL_WIDTH - 24 - (#verbs - 1) * 6) / #verbs

	for index, verb in verbs do
		local action: Action = verb.action

		children[`verb{verb.label}`] = e("TextButton", {
			Position = UDim2.fromOffset(12 + (index - 1) * (verbWidth + 6), y),
			Size = UDim2.fromOffset(verbWidth, ROW_HEIGHT),
			BackgroundColor3 = Theme.RAISED,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.FONT,
			Text = verb.label,
			TextColor3 = Theme.TEXT,
			TextSize = 11,
			[React.Event.Activated] = function()
				act(action, "", 1)
			end,
		}, {
			corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
		})
	end

	y += ROW_HEIGHT + 6

	-- ---------------------------------------------------------------------
	-- Spawning. Match only: the lobby has no simulation to spawn into.
	-- ---------------------------------------------------------------------

	if props.showCash then
		y += 6
		children.spawnHeader = sectionLabel("SPAWN", y)
		y += 16

		for index, count in SPAWN_COUNTS do
			local selected = spawnCount == count
			local value = count

			children[`count{count}`] = e("TextButton", {
				Position = UDim2.fromOffset(12 + (index - 1) * 48, y),
				Size = UDim2.fromOffset(42, 24),
				BackgroundColor3 = if selected then Theme.ACCENT else Theme.RAISED,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Font = Theme.FONT,
				Text = `x{count}`,
				TextColor3 = if selected then Theme.INVERSE else Theme.TEXT,
				TextSize = 12,
				[React.Event.Activated] = function()
					setSpawnCount(value)
				end,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			})
		end

		y += 30

		-- One button per enemy in the roster, two to a row, so adding an
		-- enemy type to config adds it here with no edit.
		for index, enemyId in Enemies.IDS do
			local definition = Enemies.get(enemyId)
			local column = (index - 1) % 2
			local rowIndex = math.floor((index - 1) / 2)
			local id: string = enemyId

			children[`spawn{enemyId}`] = e("TextButton", {
				Position = UDim2.fromOffset(12 + column * 141, y + rowIndex * 30),
				Size = UDim2.fromOffset(135, 26),
				BackgroundColor3 = Theme.RAISED,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Font = Theme.FONT,
				Text = definition.displayName,
				-- Air enemies read in their own colour, because "did the
				-- flyer spawn" is the question this button usually answers.
				TextColor3 = if definition.category == "Air" then Color3.fromRGB(126, 196, 214) else Theme.TEXT,
				TextSize = 12,
				[React.Event.Activated] = function()
					act("SpawnEnemy", id, spawnCount)
				end,
			}, {
				corner = e("UICorner", { CornerRadius = Theme.CORNER_SMALL }),
			})
		end

		y += math.ceil(#Enemies.IDS / 2) * 30
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -76),
		Size = UDim2.fromOffset(PANEL_WIDTH, y + 8),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, children)
end

return AdminConsole

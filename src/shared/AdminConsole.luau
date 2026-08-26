--!strict
--[[
	The admin console. F2 toggles it; it renders at all only for accounts in
	Config/Admins.luau (or in Studio), and that client-side check is purely
	cosmetic - the server re-checks the allowlist on every AdminGrant call,
	so a forged mount earns a silent { ok = false }.

	Shared between the two places because it is the same console twice: the
	match mounts it with showCash = true (Cash is per-match currency and
	only exists there), the lobby without. `onGranted` lets the lobby patch
	its profile atoms from the reply; the match passes nil because
	CashChanged already replicates the new balance on its own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Admins = require(script.Parent.Config.Admins)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Theme)

local e = React.createElement

export type Currency = "Cash" | "Coins" | "Tokens"

export type Props = {
	--- Whether to offer Cash. Only the match place has a match to be cash in.
	showCash: boolean,
	--- Called with every successful grant's currency and new balance, so the
	--- lobby can patch its profile atoms. The match needs nothing: its cash
	--- replicates through CashChanged regardless of why it changed.
	onGranted: ((currency: Currency, balance: number) -> ())?,
}

local TOGGLE_KEY = Enum.KeyCode.F2

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

local function AdminConsole(props: Props)
	local visible, setVisible = React.useState(false)
	local status, setStatus = React.useState("F2 hides this console")
	local granting = React.useRef(false)

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
		if granting.current then
			return
		end

		granting.current = true

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

			granting.current = false
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
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Font = Theme.FONT_BODY,
			Text = status,
			TextColor3 = Theme.MUTED,
			TextSize = 11,
		}),
	}

	local rowY = 48

	for _, row in ROWS do
		if row.matchOnly and not props.showCash then
			continue
		end

		children[`label{row.currency}`] = e("TextLabel", {
			Position = UDim2.fromOffset(12, rowY),
			Size = UDim2.fromOffset(56, 30),
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
				Position = UDim2.fromOffset(72 + (index - 1) * 74, rowY),
				Size = UDim2.fromOffset(68, 30),
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

		rowY += 38
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -76),
		Size = UDim2.fromOffset(228, rowY + 8),
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, children)
end

return AdminConsole

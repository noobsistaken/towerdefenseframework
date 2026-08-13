--!strict
--[[
	Server entry point.

	Responsibilities, in order:
	  1. Own player data sessions (ProfileStore).
	  2. Bind the networking schema's server handlers (net/schema.zap).
	  3. Nothing else. Feature logic goes in modules under src/server/.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSchema = require(ReplicatedStorage.Shared.DataSchema)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ServerScriptService.Net)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerStore = ProfileStore.New("PlayerData_v1", DataSchema.TEMPLATE)

--[[
	GOTCHA - read this before writing `SomePackage.SomeType`.

	Wally installs each package behind a one-line link file:
	    return require(script.Parent._Index["scope_name@1.2.3"]["name"])

	Luau does not re-export TYPES through a re-export like that, only values.
	So `ProfileStore.Profile` and `Janitor.Janitor` do not exist from here,
	even though both libraries export them.

	Derive the type from a value instead. It stays correct automatically when
	the package updates, which a hand-copied type definition does not.
]]
type Profile = typeof(PlayerStore:StartSessionAsync("", {}))
type JanitorInstance = typeof(Janitor.new())

local profiles: { [Player]: Profile } = {}
local janitors: { [Player]: JanitorInstance? } = {}

local function onPlayerAdded(player: Player)
	--[[
		ProfileStore's published type for `params` is `{ Steal: boolean? }`,
		but its documented API also accepts `Cancel`. The cast is deliberate
		and narrow: it covers exactly this known gap between the library's
		annotation and its real signature. Do not widen it, and do not copy
		this pattern to silence an error you have not read the source for.
	]]
	local sessionParams = {
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	} :: any

	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, sessionParams)

	if profile == nil then
		player:Kick("Could not load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	DataSchema.migrate(profile.Data)

	local janitor = Janitor.new()

	janitor:Add(
		profile.OnSessionEnd:Connect(function()
			profiles[player] = nil
			player:Kick("Your data session ended. Please rejoin.")
		end),
		"Disconnect"
	)

	-- The player may have left while StartSessionAsync was yielding.
	if player.Parent ~= Players then
		janitor:Destroy()
		profile:EndSession()
		return
	end

	profiles[player] = profile
	janitors[player] = janitor
end

local function onPlayerRemoving(player: Player)
	local janitor = janitors[player]
	if janitor ~= nil then
		janitor:Destroy()
		janitors[player] = nil
	end

	local profile = profiles[player]
	if profile ~= nil then
		profile:EndSession()
		profiles[player] = nil
	end
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- ---------------------------------------------------------------------------
-- Networking. Every handler below is generated from net/schema.zap.
-- To add a message, edit the schema and regenerate - never create a
-- RemoteEvent by hand.
-- ---------------------------------------------------------------------------

Net.RequestPurchase.On(function(player: Player, value: { itemId: string, quantity: number })
	local profile = profiles[player]
	if profile == nil then
		return
	end

	-- Zap already validated the shape and the 1..99 range. What it cannot
	-- know is whether this player can afford it - that check is ours.
	local cost = 10 * value.quantity
	if profile.Data.Coins < cost then
		return
	end

	profile.Data.Coins -= cost
	table.insert(profile.Data.Inventory, value.itemId)

	Net.PlayerScoreChanged.FireAll({ player = player, score = profile.Data.Coins })
end)

Net.ReportInput.On(function(_player: Player, _value: { moveDirection: vector })
	-- Unreliable, high frequency. Keep this handler cheap.
end)

Net.GetLeaderboard.SetCallback(function(_player: Player, _value: { page: number })
	local entries: { Types.LeaderboardEntry } = {}
	return { entries = entries }
end)

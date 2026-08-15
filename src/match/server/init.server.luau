--!strict
--[[
	Match place server entry point.

	Responsibilities, in order:
	  1. Own player data sessions (ProfileStore).
	  2. Boot the match.
	  3. Bind the networking schema's server handlers (net/schema.zap).
	  4. Nothing else. Feature logic goes in modules under src/match/server/.

	This is the MATCH place. The lobby place is a separate build target with
	its own entry point (Phase 4). Both share src/shared/ and one generated
	networking module.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSchema = require(ReplicatedStorage.Shared.DataSchema)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ServerScriptService.Net)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Types = require(ReplicatedStorage.Shared.Types)
local Wire = require(ReplicatedStorage.Shared.Wire)

local MatchController = require(script.Match.MatchController)

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

-- ---------------------------------------------------------------------------
-- Match
--
-- Built before the first player is handled, so nobody can arrive into a
-- server with no map and no state to report.
-- ---------------------------------------------------------------------------

--- Which towers a player owns. Passed into the controller rather than let it
--- reach into ProfileStore itself: profiles are this file's concern, and the
--- controller stays testable without a data layer behind it.
---
--- Returns an empty list for a player with no loaded profile, which is the
--- safe answer - a request arriving before or after a session owns nothing.
--- A copy, so a caller cannot mutate persisted data through it.
local function unlockedTowersOf(player: Player): { string }
	local profile = profiles[player]

	if profile == nil then
		return {}
	end

	return table.clone(profile.Data.UnlockedTowers)
end

--- Writes a finished match's payout into persistent data.
---
--- The only place in the codebase that mutates Coins, XP, Level or the
--- lifetime Stats, which is what makes "where did this number come from"
--- answerable by reading one function.
---
--- Silently does nothing for a player with no live session. That is correct
--- rather than lazy: a player who left during the results screen has already
--- had their profile released, and writing to a released profile is how you
--- corrupt the next session.
local function awardRewards(player: Player, coins: number, xp: number)
	local profile = profiles[player]

	if profile == nil then
		return
	end

	local data = profile.Data

	data.Coins += coins
	data.XP += xp

	-- Derived from XP rather than incremented, so the two can never disagree
	-- and a curve change re-levels everyone correctly on their next match.
	data.Level = Rewards.levelFor(data.XP)
end

local match = MatchController.new(unlockedTowersOf, awardRewards)
match:start()

-- ---------------------------------------------------------------------------
-- Data sessions
-- ---------------------------------------------------------------------------

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

	match:addPlayer(player)
end

local function onPlayerRemoving(player: Player)
	match:removePlayer(player)

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
--
-- Zap has already validated the SHAPE of anything arriving here. What it
-- cannot know is whether this player is allowed to do it, so that check is
-- always ours.
-- ---------------------------------------------------------------------------

Net.RequestPlaceTower.On(function(player: Player, value: { towerDefId: string, position: vector, rotationY: number })
	if profiles[player] == nil then
		return
	end

	-- The Y in `position` is ignored by the validator; the surface decides it.
	local reason: Types.PlacementRejectReason? =
		match:placeTower(player, value.towerDefId, Wire.toVector3(value.position), value.rotationY)

	if reason ~= nil then
		-- Told only to the requester. Broadcasting refusals would leak other
		-- players' build attempts and their balances.
		Net.PlacementRejected.Fire(player, { reason = reason })
	end
end)

Net.RequestUpgradeTower.On(function(player: Player, value: { towerId: number })
	if profiles[player] == nil then
		return
	end

	-- Ownership, affordability and max-level are all checked inside. A
	-- refusal is silent: the client already knows the button was disabled,
	-- and a forged request deserves no feedback.
	match:upgradeTower(player, value.towerId)
end)

Net.RequestSellTower.On(function(player: Player, value: { towerId: number })
	if profiles[player] == nil then
		return
	end

	match:sellTower(player, value.towerId)
end)

Net.RequestSetTargeting.On(
	function(player: Player, value: { towerId: number, mode: "First" | "Last" | "Strongest" | "Closest" })
		if profiles[player] == nil then
			return
		end

		match:setTargeting(player, value.towerId, value.mode)
	end
)

Net.RequestEarlyStart.On(function(player: Player)
	-- Any player in the match may start the wave early; the bonus is shared,
	-- so there is nothing to gain by racing. The controller re-checks the
	-- phase, which is the check that actually matters.
	if profiles[player] == nil then
		return
	end

	match:requestEarlyStart()
end)

Net.GetMatchSnapshot.SetCallback(function(player: Player, _value: {})
	return match:snapshot(player)
end)

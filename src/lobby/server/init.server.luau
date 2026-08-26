--!strict
--[[
	Lobby entry point.

	Responsibilities, in order:
	  1. Decide whether this place should run a lobby at all.
	  2. Own lobby-side player data sessions (ProfileStore).
	  3. Build the lobby world.
	  4. Own the LobbyController and bind its networking.
	  5. Nothing else.

	The lobby holds REAL data sessions now - the gacha spends Coins and
	RerollTokens here, and spending demands the same session safety as
	earning. This used to be forbidden ("two servers racing to write one
	profile"), and the reason it is safe anyway is ProfileStore's session
	lock: a profile has at most ONE live session across the whole universe.
	A player is in one place at a time; leaving here releases the session on
	PlayerRemoving, and the match's StartSessionAsync waits for that release.
	The two servers never hold the same profile - they queue for it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Admins = require(ReplicatedStorage.Shared.Config.Admins)
local DataSchema = require(ReplicatedStorage.Shared.DataSchema)
local GachaFlow = require(ReplicatedStorage.Shared.GachaFlow)
local Loadouts = require(ReplicatedStorage.Shared.Loadouts)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ServerScriptService.Net)
local Places = require(ReplicatedStorage.Shared.Config.Places)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

-- `script` IS ServerScriptService.Lobby: Rojo turns src/lobby/server's
-- init.server.luau into the Script at that path, so the other modules in this
-- folder are its CHILDREN, not its siblings.
local LobbyBuilder = require(script.LobbyBuilder)
local LobbyController = require(script.LobbyController)
local TeleportGate = require(script.TeleportGate)

-- The test place mounts BOTH the match and lobby trees so that luau-lsp can
-- resolve every require from one sourcemap. Without this guard, opening it
-- would boot a match and a lobby into the same world. In production the place
-- id decides instead, so publishing the superset anywhere stays harmless.
if not Places.shouldBoot("Lobby", RunService:IsStudio(), game.PlaceId) then
	return
end

-- The SAME store name as the match place. One universe, one DataStore, one
-- profile per player - the session lock is what arbitrates, not the name.
local PlayerStore = ProfileStore.New("PlayerData_v1", DataSchema.TEMPLATE)

-- See the identical note in src/match/server/init.server.luau: wally link
-- files do not re-export types, so Profile is derived from a value.
type Profile = typeof(PlayerStore:StartSessionAsync("", {}))
type JanitorInstance = typeof(Janitor.new())

local profiles: { [Player]: Profile } = {}
local janitors: { [Player]: JanitorInstance? } = {}

--- One server-owned RNG for every roll. The client never contributes a bit
--- of entropy, which is the entire anti-forgery story: there is no request
--- field to tamper with.
local rollRng = Random.new()

-- ---------------------------------------------------------------------------
-- Data sessions
--
-- Same shape as the match entry, one deliberate difference: NO KICK on a
-- failed load. The lobby's core loop - stand in a zone, vote, teleport -
-- works without data; only the gacha needs it, and the gacha functs answer
-- "cannot afford" for a missing profile. Kicking would trade a broken shop
-- button for a broken game.
-- ---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Cast documented in the match entry: ProfileStore's published param type
	-- omits Cancel, which its real API accepts.
	local sessionParams = {
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	} :: any

	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, sessionParams)

	if profile == nil then
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	DataSchema.migrate(profile.Data)

	local janitor = Janitor.new()

	janitor:Add(
		profile.OnSessionEnd:Connect(function()
			-- Another server claimed the session - almost always the match
			-- place mid-teleport. Drop the local handle and let them keep it;
			-- the gacha functs answer Unavailable from here on, which the
			-- client shows as "not loaded" rather than as a zero balance.
			profiles[player] = nil

			local owned = janitors[player]
			janitors[player] = nil

			if owned ~= nil then
				owned:Destroy()
			end
		end),
		"Disconnect"
	)

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
		-- The release the match place's StartSessionAsync is waiting on.
		profile:EndSession()
		profiles[player] = nil
	end
end

--- Bounded wait for this player's session, for the one funct a client calls
--- the instant it loads. Same rationale and bound as the match snapshot's.
local PROFILE_WAIT_SECONDS = 10

local function waitForProfile(player: Player)
	local deadline = os.clock() + PROFILE_WAIT_SECONDS

	while profiles[player] == nil and os.clock() < deadline do
		if player.Parent ~= Players then
			return
		end

		task.wait(0.1)
	end
end

-- ---------------------------------------------------------------------------
-- World and controller
-- ---------------------------------------------------------------------------

local lobby = LobbyBuilder.build()

LobbyBuilder.buildAreas(lobby.folder)

local controller = LobbyController.new()

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerAdded:Connect(function(player: Player)
	controller:addPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	controller:removePlayer(player)
	onPlayerRemoving(player)
end)

-- ---------------------------------------------------------------------------
-- Networking. Every handler is generated from net/schema.zap.
--
-- All of these are REQUESTS. The controller and GachaFlow decide; Zap has
-- proved only the SHAPE. The gacha functs run against the live profile and
-- mutate it in place - ProfileStore persists whatever Data holds, so there
-- is no separate save step to forget.
-- ---------------------------------------------------------------------------

--- Same cap and same gate as the match entry's handler.
local MAX_ADMIN_GRANT = 100000

Net.AdminGrant.SetCallback(function(player: Player, value: { currency: "Cash" | "Coins" | "Tokens", amount: number })
	if not Admins.isAdmin(player.UserId, RunService:IsStudio()) then
		return { ok = false, balance = 0 }
	end

	-- Cash is per-match currency; there is no match here to be cash in.
	if value.currency == "Cash" then
		return { ok = false, balance = 0 }
	end

	local profile = profiles[player]

	if profile == nil then
		return { ok = false, balance = 0 }
	end

	local amount = math.clamp(value.amount, 1, MAX_ADMIN_GRANT)

	if value.currency == "Coins" then
		profile.Data.Coins += amount

		return { ok = true, balance = profile.Data.Coins }
	end

	profile.Data.RerollTokens += amount

	return { ok = true, balance = profile.Data.RerollTokens }
end)

Net.CastVote.On(function(player: Player, value: { poll: "Map" | "Difficulty", option: string })
	controller:castVote(player, value.poll, value.option)
end)

Net.RequestLaunch.On(function(player: Player)
	-- The ONLY path to a teleport. The controller re-resolves the sender's
	-- position from the character the server owns; a refused launch is
	-- silent, because the button only shows inside the area anyway.
	controller:requestLaunch(player)
end)

Net.SetLoadout.SetCallback(function(player: Player, value: { towerIds: { string } })
	local profile = profiles[player]

	if profile == nil then
		return { ok = false, loadout = {} }
	end

	-- Loadouts.apply is the whole rulebook: size, ownership, reality,
	-- duplicates. A refusal writes nothing, and either way the reply
	-- carries the deck as it now stands.
	local ok = Loadouts.apply(profile.Data, value.towerIds)

	return { ok = ok, loadout = Loadouts.resolve(profile.Data) }
end)

Net.RollTower.SetCallback(function(player: Player, _value: {})
	local profile = profiles[player]

	if profile == nil then
		-- No session is NOT "broke": the client must neither scold the
		-- player nor believe the zeros.
		return { outcome = "Unavailable" :: "Unavailable", towerId = "", rarityId = "", coins = 0, refunded = 0 }
	end

	local result = GachaFlow.rollTower(profile.Data, rollRng)

	return {
		outcome = result.outcome,
		towerId = result.towerId,
		rarityId = result.rarityId,
		coins = profile.Data.Coins,
		refunded = result.refunded,
	}
end)

Net.RerollTrait.SetCallback(function(player: Player, value: { towerId: string })
	local profile = profiles[player]

	if profile == nil then
		return { outcome = "Unavailable" :: "Unavailable", traitId = "", rarityId = "", tokens = 0 }
	end

	local result = GachaFlow.rerollTrait(profile.Data, value.towerId, rollRng)

	return {
		outcome = result.outcome,
		traitId = result.traitId,
		rarityId = result.rarityId,
		tokens = profile.Data.RerollTokens,
	}
end)

Net.GetLobbyProfile.SetCallback(function(player: Player, _value: {})
	-- Bounded block, like the match snapshot: this is fetched at join, and
	-- answering early would render a shop that owns nothing.
	waitForProfile(player)

	local profile = profiles[player]

	if profile == nil then
		-- loaded=false marks every zero below as meaningless. Without it this
		-- reply was byte-identical to a fresh account, and the client latched
		-- an empty collection for the whole session whenever the session
		-- handoff outran the wait above.
		return {
			loaded = false,
			coins = 0,
			level = 0,
			xp = 0,
			rerollTokens = 0,
			unlockedTowers = {},
			loadout = {},
			traits = {},
		}
	end

	local data = profile.Data
	local traits: { { towerId: string, traitId: string } } = {}

	for towerId, rolled in data.Traits do
		-- SLOTS is 1; the first entry is the whole loadout.
		if #rolled > 0 then
			table.insert(traits, { towerId = towerId, traitId = rolled[1] })
		end
	end

	return {
		loaded = true,
		coins = data.Coins,
		level = data.Level,
		xp = data.XP,
		rerollTokens = data.RerollTokens,
		unlockedTowers = table.clone(data.UnlockedTowers),
		loadout = Loadouts.resolve(data),
		traits = traits,
	}
end)

-- A player whose teleport fails in flight is left standing in the lobby with
-- no idea why. Tell them.
TeleportGate.onFailure(function(player: Player, reason: string)
	warn(`[lobby] teleport failed for {player.Name}: {reason}`)
	Net.MatchmakingFailed.Fire(player, { reason = reason })
end)

controller:start()

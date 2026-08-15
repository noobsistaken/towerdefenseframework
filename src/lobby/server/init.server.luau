--!strict
--[[
	Lobby entry point.

	Responsibilities, in order:
	  1. Decide whether this place should run a lobby at all.
	  2. Build the lobby world.
	  3. Own the LobbyController and bind its networking.
	  4. Nothing else.

	Player data is deliberately NOT loaded here. Rewards are earned and
	persisted in the match place, which is where the numbers are produced; a
	second ProfileStore session in the lobby would mean two servers holding
	the same profile and racing each other to write it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ServerScriptService.Net)
local Places = require(ReplicatedStorage.Shared.Config.Places)

-- `script` IS ServerScriptService.Lobby: Rojo turns src/lobby/server's
-- init.server.luau into the Script at that path, so the other modules in this
-- folder are its CHILDREN, not its siblings.
local LobbyBuilder = require(script.LobbyBuilder)
local LobbyController = require(script.LobbyController)
local TeleportGate = require(script.TeleportGate)

-- The test place mounts BOTH the match and lobby trees so that luau-lsp can
-- resolve every require from one sourcemap. Without this guard, opening it
-- would boot a match and a lobby into the same world. In a published place
-- only one of the two entry scripts exists, so this always passes there.
if not Places.shouldBoot("Lobby", RunService:IsStudio()) then
	return
end

local lobby = LobbyBuilder.build()
LobbyBuilder.buildMapPlinths(MapRegistry.IDS, MapRegistry.MAPS, lobby.folder)

local controller = LobbyController.new()

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	controller:addPlayer(player)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	controller:removePlayer(player)
end)

-- ---------------------------------------------------------------------------
-- Networking. Every handler is generated from net/schema.zap.
--
-- All three are REQUESTS. The controller decides, and validates the option
-- against its own allowlist - Zap proves the payload is a short string, it
-- cannot prove the string names a real map.
-- ---------------------------------------------------------------------------

Net.CastVote.On(function(player: Player, value: { poll: "Map" | "Difficulty", option: string })
	controller:castVote(player, value.poll, value.option)
end)

Net.SetReady.On(function(player: Player, value: { ready: boolean })
	controller:setReady(player, value.ready)
end)

-- A player whose teleport fails in flight is left standing in the lobby with
-- no idea why. Tell them.
TeleportGate.onFailure(function(player: Player, reason: string)
	warn(`[lobby] teleport failed for {player.Name}: {reason}`)
	Net.MatchmakingFailed.Fire(player, { reason = reason })
end)

controller:start()

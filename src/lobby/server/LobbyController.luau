--!strict
--[[
	Lobby hub state machine.

	    Gathering  --(a player in the GAME area presses START)-->  Launching
	    Launching  --(teleport sent)-->  the area's occupants leave
	               --(teleport simulated or failed)-->  Gathering

	There is NO countdown and NO minimum-players trigger, on purpose: the
	lobby launches nothing until somebody standing in the GAME area presses
	START. Until then it is a place - gacha, rerolls, loadouts, standing
	around - and a player who never touches the GAME area is never teleported
	anywhere.

	Votes are scoped to the GAME area: only its occupants may cast, and
	walking out withdraws yours. The launch takes everyone standing in the
	area at that moment, with the area's winning map and difficulty.

	Everything a client sends is a REQUEST. Votes are checked against the
	server's allowlists, and the launch checks the sender's CHARACTER
	POSITION - which the server owns - rather than anything the client
	claims. Zap proves shapes; standing somewhere is proved by standing there.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ServerScriptService.Net)
local Poll = require(ReplicatedStorage.Shared.Poll)
local Types = require(ReplicatedStorage.Shared.Types)

local TeleportGate = require(script.Parent.TeleportGate)

local LobbyController = {}
LobbyController.__index = LobbyController

export type Controller = typeof(setmetatable(
	{} :: {
		state: Types.LobbyState,
		mapPoll: Poll.Poll,
		difficultyPoll: Poll.Poll,
		--- Which players stood in the GAME area at the last scan. Change
		--- detection only: entering does nothing (you vote through the
		--- chooser, not by standing), leaving withdraws your votes.
		inGameArea: { [Player]: boolean },
		heartbeat: thread?,
	},
	LobbyController
))

-- ---------------------------------------------------------------------------
-- Position checks
--
-- Always resolved FRESH from the character the server owns, never from the
-- scan cache: a player can enter the area and press START inside the same
-- second, and refusing them over a stale cache reads as a broken button.
-- ---------------------------------------------------------------------------

local function isInGameArea(player: Player): boolean
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil

	if root == nil then
		return false
	end

	return LobbyZones.resolveArea(root.Position) == "Game"
end

--- Everyone currently standing in the GAME area. The launch list.
local function gameAreaOccupants(): { Player }
	local occupants: { Player } = {}

	for _, player in Players:GetPlayers() do
		if isInGameArea(player) then
			table.insert(occupants, player)
		end
	end

	return occupants
end

-- ---------------------------------------------------------------------------
-- Replication
-- ---------------------------------------------------------------------------

local function broadcastState(self: Controller)
	Net.LobbyStateChanged.FireAll({
		state = self.state,
		playerCount = #Players:GetPlayers(),
	})
end

local function broadcastTally(self: Controller)
	Net.VoteTallyChanged.FireAll({
		mapTallies = self.mapPoll:tally(),
		difficultyTallies = self.difficultyPoll:tally(),
		-- Computed once on the server so every client agrees. Recomputing it
		-- per client would mean reimplementing the tie-break, twice.
		winningMapId = self.mapPoll:winner(),
		winningDifficultyId = self.difficultyPoll:winner(),
	})
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function LobbyController.new(): Controller
	local self = setmetatable({
		state = "Gathering" :: Types.LobbyState,
		-- The allowlists. A vote for anything not in these is dropped.
		mapPoll = Poll.new(MapRegistry.IDS, MapRegistry.DEFAULT_ID),
		difficultyPoll = Poll.new(Difficulty.IDS, Difficulty.DEFAULT_ID),
		inGameArea = {},
		heartbeat = nil,
	}, LobbyController)

	return self
end

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------

function LobbyController.addPlayer(self: Controller, _player: Player)
	broadcastState(self)
	broadcastTally(self)
end

function LobbyController.removePlayer(self: Controller, player: Player)
	-- A departed player's vote must stop counting, or an empty GAME area
	-- can keep voting for a map nobody is standing for.
	self.mapPoll:remove(player.UserId)
	self.difficultyPoll:remove(player.UserId)
	self.inGameArea[player] = nil

	broadcastState(self)
	broadcastTally(self)
end

-- ---------------------------------------------------------------------------
-- Player actions
-- ---------------------------------------------------------------------------

function LobbyController.castVote(self: Controller, player: Player, kind: string, option: string)
	if self.state == "Launching" then
		return
	end

	-- Votes belong to the GAME area. A well-formed vote from the gacha pad
	-- is a forged message, not a UI state that exists.
	if not isInGameArea(player) then
		return
	end

	local poll = if kind == "Map" then self.mapPoll else self.difficultyPoll

	-- Poll.cast is the allowlist check. It returns false for anything not in
	-- the option list, which is exactly what a forged option looks like.
	if not poll:cast(player.UserId, option) then
		return
	end

	broadcastTally(self)
end

--- The only path to a teleport. Takes everyone standing in the GAME area,
--- with the area's winning votes; players elsewhere in the hub stay.
function LobbyController.requestLaunch(self: Controller, player: Player): boolean
	if self.state == "Launching" then
		return false
	end

	if not isInGameArea(player) then
		return false
	end

	local occupants = gameAreaOccupants()

	if #occupants == 0 then
		return false
	end

	self.state = "Launching"
	broadcastState(self)

	local launch: Types.MatchLaunchData = {
		mapId = self.mapPoll:winner(),
		difficultyId = self.difficultyPoll:winner(),
	}

	task.spawn(function()
		local outcome = TeleportGate.send(occupants, launch)

		if not outcome.ok then
			Net.MatchmakingFailed.FireAll({ reason = outcome.reason or "Unknown teleport failure." })
			self.state = "Gathering"
			broadcastState(self)
			return
		end

		if outcome.simulated then
			-- Studio. Nobody actually went anywhere, so reopen the hub
			-- rather than wedging in Launching - and SAY SO. Silence here
			-- reads exactly like the vote being broken: the button is
			-- pressed, the hub comes back, and the map never changes, so
			-- the natural conclusion is that picking a map does nothing.
			-- It does; TeleportService simply cannot run in Studio. The
			-- reason names the pair that WOULD have loaded, which is also
			-- the fastest way to see the vote is being counted.
			task.wait(Constants.LOBBY_RELAUNCH_SECONDS)
			self.state = "Gathering"
			broadcastState(self)

			-- AFTER the state broadcast, deliberately. The client clears a
			-- stale failure whenever the lobby leaves Launching, so sending
			-- this first would have it wiped by the very message that ends
			-- the simulated launch - which is how the first attempt at this
			-- notice managed to fire twice and never appear on screen.
			Net.MatchmakingFailed.FireAll({
				reason = `Studio cannot teleport - {launch.mapId} / {launch.difficultyId} would have loaded. `
					.. `Press Play in the Game place to test the match itself.`,
			})
		else
			-- The occupants are gone; whoever stayed gets their hub back.
			self.state = "Gathering"
			broadcastState(self)
		end
	end)

	return true
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

local function scanGameArea(self: Controller)
	local changed = false

	for _, player in Players:GetPlayers() do
		local inside = isInGameArea(player)

		if inside ~= (self.inGameArea[player] == true) then
			if not inside then
				-- Walking out withdraws your votes. Walking IN grants only
				-- the right to cast; the chooser is where you actually do.
				self.mapPoll:remove(player.UserId)
				self.difficultyPoll:remove(player.UserId)
				changed = true
			end

			-- Branch rather than `inside or nil`: booleans widen to
			-- `boolean?` and refuse the `{ [Player]: boolean }` index.
			if inside then
				self.inGameArea[player] = true
			else
				self.inGameArea[player] = nil
			end
		end
	end

	if changed then
		broadcastTally(self)
	end
end

function LobbyController.start(self: Controller)
	for _, player in Players:GetPlayers() do
		self:addPlayer(player)
	end

	self.heartbeat = task.spawn(function()
		while true do
			task.wait(1)

			if self.state ~= "Launching" then
				scanGameArea(self)
			end
		end
	end)
end

function LobbyController.stop(self: Controller)
	local heartbeat = self.heartbeat

	if heartbeat ~= nil then
		task.cancel(heartbeat)
		self.heartbeat = nil
	end
end

--- Snapshot for a client that just joined.
function LobbyController.snapshotFor(self: Controller, _player: Player)
	broadcastState(self)
	broadcastTally(self)
end

return LobbyController

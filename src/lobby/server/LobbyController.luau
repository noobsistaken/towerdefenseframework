--!strict
--[[
	Lobby state machine.

	    Gathering  --(enough players)-->  Voting
	    Voting     --(countdown hits 0)-->  Launching
	    Launching  --(teleport sent)-->  players leave the server
	               --(teleport simulated or failed)-->  Gathering

	The last transition is what keeps the lobby usable in Studio. A real
	teleport ends with everyone gone and the server empty, so there is nothing
	to return to; a simulated one leaves everybody standing here, and without
	a way back the lobby would wedge in Launching forever.

	Votes stay open for the whole of Voting and close on entering Launching.
	Closing them earlier would mean a player who joined late could not vote at
	all, and the countdown is short enough that a last-second switch is a
	legitimate move rather than an exploit.

	Everything a client sends is a REQUEST. Vote options are checked against
	the server's own allowlists - Zap proves `option` is a short string, it
	cannot prove it names a real map.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
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
		--- os.time() at which the current phase ends. 0 when untimed.
		phaseEndsAt: number,
		mapPoll: Poll.Poll,
		difficultyPoll: Poll.Poll,
		ready: { [Player]: boolean },
		heartbeat: thread?,
	},
	LobbyController
))

-- ---------------------------------------------------------------------------
-- Replication
-- ---------------------------------------------------------------------------

local function readyCount(self: Controller): number
	local count = 0

	for _ in self.ready do
		count += 1
	end

	return count
end

local function broadcastState(self: Controller)
	local remaining = if self.phaseEndsAt > 0 then math.max(0, self.phaseEndsAt - os.time()) else 0

	Net.LobbyStateChanged.FireAll({
		state = self.state,
		secondsRemaining = math.floor(remaining),
		playerCount = #Players:GetPlayers(),
		readyCount = readyCount(self),
	})
end

local function broadcastTally(self: Controller)
	Net.VoteTallyChanged.FireAll({
		mapTallies = self.mapPoll:tally(),
		difficultyTallies = self.difficultyPoll:tally(),
		-- Computed once on the server so every client agrees. Recomputing it
		-- per client would mean reimplementing the tie-break rule, twice.
		winningMapId = self.mapPoll:winner(),
		winningDifficultyId = self.difficultyPoll:winner(),
	})
end

--- Single entry point for state changes, so a transition can never forget to
--- tell the clients about itself.
local function setState(self: Controller, state: Types.LobbyState, duration: number)
	self.state = state
	self.phaseEndsAt = if duration > 0 then os.time() + duration else 0
	broadcastState(self)
end

-- ---------------------------------------------------------------------------
-- Phases
-- ---------------------------------------------------------------------------

local function beginGathering(self: Controller)
	self.ready = {}
	setState(self, "Gathering", 0)
end

local function beginVoting(self: Controller)
	setState(self, "Voting", Constants.LOBBY_COUNTDOWN_SECONDS)
end

--- Closes voting and hands off to the teleport.
local function beginLaunching(self: Controller)
	setState(self, "Launching", 0)

	local launch: Types.MatchLaunchData = {
		mapId = self.mapPoll:winner(),
		difficultyId = self.difficultyPoll:winner(),
	}

	-- Snapshotted before yielding: TeleportGate.send yields, and the player
	-- list can change underneath it.
	local players = Players:GetPlayers()

	task.spawn(function()
		local outcome = TeleportGate.send(players, launch)

		if not outcome.ok then
			Net.MatchmakingFailed.FireAll({ reason = outcome.reason or "Unknown teleport failure." })
			beginGathering(self)
			return
		end

		if outcome.simulated then
			-- Studio. Nobody actually went anywhere, so give the lobby a way
			-- back rather than wedging in Launching.
			task.wait(Constants.LOBBY_RELAUNCH_SECONDS)
			beginGathering(self)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function LobbyController.new(): Controller
	local self = setmetatable({
		state = "Gathering" :: Types.LobbyState,
		phaseEndsAt = 0,
		-- The allowlists. A vote for anything not in these is dropped.
		mapPoll = Poll.new(MapRegistry.IDS, MapRegistry.DEFAULT_ID),
		difficultyPoll = Poll.new(Difficulty.IDS, Difficulty.DEFAULT_ID),
		ready = {},
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
	-- A departed player's vote and ready flag must stop counting, or a lobby
	-- can sit waiting on someone who left.
	self.mapPoll:remove(player.UserId)
	self.difficultyPoll:remove(player.UserId)
	self.ready[player] = nil

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

	local poll = if kind == "Map" then self.mapPoll else self.difficultyPoll

	-- Poll.cast is the allowlist check. It returns false for anything not in
	-- the option list, which is exactly what a forged option looks like.
	if not poll:cast(player.UserId, option) then
		return
	end

	broadcastTally(self)
end

function LobbyController.setReady(self: Controller, player: Player, ready: boolean)
	if self.state == "Launching" then
		return
	end

	-- Written as a branch rather than `if ready then true else nil`, which
	-- types as `boolean?` and will not assign into `{ [Player]: boolean }`.
	if ready then
		self.ready[player] = true
	else
		self.ready[player] = nil
	end

	broadcastState(self)
end

--- True when everyone present has readied up, and there is at least one of
--- them. The emptiness guard matters: without it an empty lobby is trivially
--- "all ready" and launches into nothing.
local function everyoneReady(self: Controller): boolean
	local present = Players:GetPlayers()

	if #present < Constants.LOBBY_MIN_PLAYERS then
		return false
	end

	for _, player in present do
		if not self.ready[player] then
			return false
		end
	end

	return true
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

local function tick(self: Controller)
	local present = #Players:GetPlayers()

	if self.state == "Gathering" then
		if present >= Constants.LOBBY_MIN_PLAYERS then
			beginVoting(self)
		end

		return
	end

	if self.state == "Voting" then
		if present < Constants.LOBBY_MIN_PLAYERS then
			beginGathering(self)
			return
		end

		-- Readying up shortens the wait rather than skipping it, so there is
		-- still a moment to see the winning map and to un-ready.
		if everyoneReady(self) then
			local shortened = os.time() + Constants.LOBBY_READY_SECONDS

			if shortened < self.phaseEndsAt then
				self.phaseEndsAt = shortened
			end
		end

		if os.time() >= self.phaseEndsAt then
			beginLaunching(self)
			return
		end

		-- Cheap enough to send every second, and it keeps the countdown on
		-- every client honest without a second clock to drift.
		broadcastState(self)
	end
end

function LobbyController.start(self: Controller)
	for _, player in Players:GetPlayers() do
		self:addPlayer(player)
	end

	self.heartbeat = task.spawn(function()
		while true do
			task.wait(1)
			tick(self)
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

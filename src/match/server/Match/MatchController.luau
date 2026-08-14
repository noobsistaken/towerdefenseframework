--!strict
--[[
	The match lifecycle.

	Owns the state machine and nothing else's rules. It wires together the
	map, the simulation, the view, the wave director and base health, and it
	is the only module allowed to change `state`.

	    Loading -> Preparing -> WaveActive -> Intermission -> Preparing ...
	                                                       -> Victory
	    (any) -> Defeat, when base health reaches zero

	Transition invariants worth stating, because they are the bugs this kind
	of loop actually has:

	  * A wave is over when the director has released every planned spawn AND
	    the simulation is empty. Checking only one of those ends the wave
	    while enemies are still walking, or never ends it at all.
	  * Defeat is latched. Several enemies can leak in one simulation step, so
	    BaseHealth.damage reports the transition rather than the value, and
	    the match ends exactly once.
	  * Victory is checked at the END of intermission, not on wave clear, so
	    the last wave's payout and the results screen do not race.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DevMatch = require(ReplicatedStorage.Shared.Config.DevMatch)
local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ServerScriptService.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)
local BaseHealth = require(script.Parent.Parent.Systems.BaseHealth)
local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)
local EnemyView = require(script.Parent.Parent.Simulation.EnemyView)
local MapBuilder = require(script.Parent.MapBuilder)
local WaveDirector = require(script.Parent.Parent.Systems.WaveDirector)

local MatchController = {}
MatchController.__index = MatchController

export type Controller = typeof(setmetatable(
	{} :: {
		state: Types.MatchState,
		waveNumber: number,
		--- os.time() at which the current phase ends. 0 when untimed.
		phaseEndsAt: number,
		map: MapBuilder.BuiltMap,
		difficulty: Types.DifficultyConfig,
		simulation: EnemySimulation.Simulation,
		view: EnemyView.View,
		director: WaveDirector.Director,
		health: BaseHealth.Health,
		--- Per-player match cash. Phase 2 moves this into EconomyService
		--- together with the bounty split; Phase 1 only needs the starting
		--- balance so the HUD has something true to show.
		cash: { [Player]: number },
		heartbeat: RBXScriptConnection?,
		--- Set once the match is over, so a late leak cannot resurrect it.
		finished: boolean,
	},
	MatchController
))

-- ---------------------------------------------------------------------------
-- Configuration resolution
-- ---------------------------------------------------------------------------

--- Which map and difficulty this server should run.
---
--- Phase 4 adds the real path: read Player:GetJoinData().TeleportData and
--- validate every field against the config allowlists. That validation is
--- already the reason MapRegistry.find and Difficulty.find are non-throwing.
--- Until then, and always in Studio, the match boots from DevMatch (D1).
local function resolveMatchConfig(): (Types.MapConfig, Types.DifficultyConfig)
	local mapId = if RunService:IsStudio() then DevMatch.MAP_ID else MapRegistry.DEFAULT_ID
	local difficultyId = if RunService:IsStudio() then DevMatch.DIFFICULTY_ID else Difficulty.DEFAULT_ID

	local map = MapRegistry.find(mapId) or MapRegistry.get(MapRegistry.DEFAULT_ID)
	local difficulty = Difficulty.find(difficultyId) or Difficulty.get(Difficulty.DEFAULT_ID)

	return map, difficulty
end

-- ---------------------------------------------------------------------------
-- Replication
-- ---------------------------------------------------------------------------

local function broadcastState(self: Controller)
	Net.MatchStateChanged.FireAll({
		state = self.state,
		waveNumber = self.waveNumber,
		phaseEndsAt = self.phaseEndsAt,
	})
end

local function broadcastHealth(self: Controller)
	Net.BaseHealthChanged.FireAll({
		current = math.floor(self.health.current),
		max = math.floor(self.health.max),
	})
end

local function sendCash(self: Controller, player: Player)
	Net.CashChanged.Fire(player, {
		cash = math.floor(self.cash[player] or 0),
	})
end

--- Single entry point for every state change, so broadcasting can never be
--- forgotten at a call site.
local function setState(self: Controller, state: Types.MatchState, duration: number)
	self.state = state
	self.phaseEndsAt = if duration > 0 then os.time() + duration else 0
	broadcastState(self)
end

-- ---------------------------------------------------------------------------
-- Phases
-- ---------------------------------------------------------------------------

local function prepareSeconds(self: Controller): number
	if RunService:IsStudio() and DevMatch.SHORTEN_FIRST_PREPARE then
		return DevMatch.SHORTENED_PREPARE_SECONDS
	end

	return if self.waveNumber <= 1 then Constants.FIRST_PREPARE_SECONDS else Constants.PREPARE_SECONDS
end

local function beginPreparing(self: Controller)
	setState(self, "Preparing", prepareSeconds(self))
end

local function beginWave(self: Controller)
	self.director:beginWave(self.waveNumber)
	setState(self, "WaveActive", 0)
end

local function endMatch(self: Controller, won: boolean)
	if self.finished then
		return
	end

	self.finished = true
	self.simulation:reset()
	setState(self, if won then "Victory" else "Defeat", Constants.RESULTS_SECONDS)

	-- Phase 5 pays real rewards through RewardService and persists them.
	Net.MatchEnded.FireAll({
		won = won,
		wavesCleared = if won then self.waveNumber else math.max(0, self.waveNumber - 1),
		coinsAwarded = 0,
		xpAwarded = 0,
	})
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function MatchController.new(): Controller
	local mapConfig, difficulty = resolveMatchConfig()
	local map = MapBuilder.build(mapConfig)
	local simulation = EnemySimulation.new(map.paths)

	local self: Controller = setmetatable({
		state = "Loading" :: Types.MatchState,
		waveNumber = 0,
		phaseEndsAt = 0,
		map = map,
		difficulty = difficulty,
		simulation = simulation,
		view = EnemyView.new(simulation, workspace),
		director = WaveDirector.new(simulation, difficulty),
		health = BaseHealth.new(difficulty.baseHealth),
		cash = {},
		heartbeat = nil,
		finished = false,
	}, MatchController)

	simulation:onEnemyLeaked(function(_enemy: BaseEnemy.Enemy, baseDamage: number)
		-- `damage` reports the transition, not the value, so several leaks in
		-- one step still end the match exactly once.
		if self.health:damage(baseDamage) then
			endMatch(self, false)
		end
	end)

	self.health:onChanged(function()
		broadcastHealth(self)
	end)

	return self
end

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

--- Gives a player their starting balance and brings them up to date.
function MatchController.addPlayer(self: Controller, player: Player)
	if self.cash[player] == nil then
		self.cash[player] = self.difficulty.startingCash
	end

	sendCash(self, player)
	broadcastHealth(self)
	broadcastState(self)
end

function MatchController.removePlayer(self: Controller, player: Player)
	self.cash[player] = nil
end

function MatchController.snapshot(self: Controller, player: Player): Types.MatchSnapshot
	return {
		state = self.state,
		mapId = self.map.config.id,
		waveNumber = self.waveNumber,
		baseHealth = math.floor(self.health.current),
		baseHealthMax = math.floor(self.health.max),
		cash = math.floor(self.cash[player] or 0),
		phaseEndsAt = self.phaseEndsAt,
	}
end

-- ---------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------

local function tick(self: Controller, deltaTime: number)
	if self.finished then
		return
	end

	if self.state == "Preparing" then
		if os.time() >= self.phaseEndsAt then
			beginWave(self)
		end
		return
	end

	if self.state == "WaveActive" then
		self.director:update(deltaTime)
		self.simulation:update(deltaTime)
		self.view:sync()

		-- Both conditions, deliberately. Either alone is a real bug: the
		-- director being done says nothing about enemies still walking, and
		-- an empty simulation is trivially true before the first spawn.
		if self.director:isSpawningComplete() and self.simulation:count() == 0 then
			setState(self, "Intermission", Constants.INTERMISSION_SECONDS)
		end

		return
	end

	if self.state == "Intermission" then
		if os.time() >= self.phaseEndsAt then
			if self.waveNumber >= self.difficulty.finalWave then
				endMatch(self, true)
			else
				self.waveNumber += 1
				beginPreparing(self)
			end
		end

		return
	end
end

--- Ends the build phase early. Phase 3 adds the remaining-time cash bonus;
--- the server reads its own clock for that and never trusts a client value.
function MatchController.requestEarlyStart(self: Controller): boolean
	if self.state ~= "Preparing" or self.finished then
		return false
	end

	beginWave(self)
	return true
end

function MatchController.start(self: Controller)
	self.waveNumber = 1
	beginPreparing(self)

	for _, player in Players:GetPlayers() do
		self:addPlayer(player)
	end

	self.heartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
		tick(self, deltaTime)
	end)
end

function MatchController.destroy(self: Controller)
	local heartbeat = self.heartbeat

	if heartbeat ~= nil then
		heartbeat:Disconnect()
		self.heartbeat = nil
	end

	self.view:destroy()
	self.simulation:destroy()
	MapBuilder.clear()
end

return MatchController

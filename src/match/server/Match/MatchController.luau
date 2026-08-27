--!strict
--[[
	The match lifecycle.

	Owns the state machine and nothing else's rules. It wires together the
	map, the simulation, the view, the towers, the economy, the wave director
	and base health, and it is the only module allowed to change `state`.

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

	Every player-initiated action below re-validates on the server. Zap has
	already proved the SHAPE of the request; ownership, affordability, caps
	and legality are proved here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DevMatch = require(ReplicatedStorage.Shared.Config.DevMatch)
local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local Footprint = require(ReplicatedStorage.Shared.Footprint)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Net = require(ServerScriptService.Net)
local Placement = require(ReplicatedStorage.Shared.Placement)
local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Scaling = require(ReplicatedStorage.Shared.Scaling)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Towers = require(ReplicatedStorage.Shared.Config.Towers)
local Types = require(ReplicatedStorage.Shared.Types)
local Wire = require(ReplicatedStorage.Shared.Wire)

local ArrivalGate = require(script.Parent.ArrivalGate)
local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)
local BaseHealth = require(script.Parent.Parent.Systems.BaseHealth)
local EconomyService = require(script.Parent.Parent.Systems.EconomyService)
local EnemyBehaviors = require(script.Parent.Parent.Entities.EnemyBehaviors)
local EnemySimulation = require(script.Parent.Parent.Simulation.EnemySimulation)
local EnemyView = require(script.Parent.Parent.Simulation.EnemyView)
local MapBuilder = require(script.Parent.MapBuilder)
local ReturnGate = require(script.Parent.ReturnGate)
local TowerSystem = require(script.Parent.Parent.Systems.TowerSystem)
local WaveDirector = require(script.Parent.Parent.Systems.WaveDirector)

local MatchController = {}
MatchController.__index = MatchController

--- Returns the tower ids a player owns. Supplied by the entry point, which
--- owns the profiles; the controller must not reach into ProfileStore itself.
---
--- A list rather than a per-tower predicate, because the snapshot has to send
--- the whole set anyway and two sources for the same fact would drift.
export type UnlockedResolver = (player: Player) -> { string }

--- Writes a finished match's payout into persistent player data.
---
--- Supplied by the entry point, which owns the ProfileStore sessions, for the
--- same reason as UnlockedResolver: the controller must not reach into
--- persistence itself. It is also what keeps the controller testable in
--- principle - the reward path can be observed without a DataStore.
export type RewardAwarder = (player: Player, coins: number, xp: number, tokens: number) -> ()

--- This player's persisted audio setting. Injected for the same reason as the
--- two above: profiles belong to the entry point.
export type SettingsResolver = (player: Player) -> boolean

--- The trait ids this player has rolled for one tower type. Injected for
--- the same reason as the three above. Read once per PLACEMENT - the tower
--- snapshots the answer, so a lobby reroll applies from the next placement
--- rather than mutating towers already standing.
export type TraitsResolver = (player: Player, towerDefId: string) -> { string }

--- The towers this player BROUGHT - at most Loadouts.MAX of what they own.
--- The shop renders this and placement enforces it; owning a tower that
--- stayed home places nothing.
export type LoadoutResolver = (player: Player) -> { string }

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
		towers: TowerSystem.System,
		economy: EconomyService.Service,
		director: WaveDirector.Director,
		health: BaseHealth.Health,
		isUnlocked: UnlockedResolver,
		awardRewards: RewardAwarder,
		sfxEnabledFor: SettingsResolver,
		traitsOf: TraitsResolver,
		loadoutOf: LoadoutResolver,
		--- Highest wave already paid for. Settlement is INCREMENTAL - every
		--- intermission pays the waves cleared since the last one - and this
		--- ledger is what makes each wave payable exactly once across that.
		paidThroughWave: number,
		--- Cumulative amounts actually persisted this run, for MatchEnded:
		--- with incremental settlement, the terminal slice alone would report
		--- "+0 coins" after a 29-wave run.
		paidCoins: number,
		paidXp: number,
		paidTokens: number,
		--- Set once the return teleport has been fired, so the results phase
		--- ticking repeatedly cannot fire it again.
		returning: boolean,
		heartbeat: RBXScriptConnection?,
		--- Set once the match is over, so a late leak cannot resurrect it.
		--- Only Defeat sets this: clearing the campaign is a milestone, not
		--- an ending.
		finished: boolean,
		--- Set once the campaign's final wave has been cleared. Everything
		--- after it is endless mode, which is a MODIFIER on the normal phase
		--- cycle rather than a phase of its own - endless waves still run
		--- Preparing -> WaveActive -> Intermission.
		campaignCleared: boolean,
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
--- already why MapRegistry.find and Difficulty.find are non-throwing. Until
--- then, and always in Studio, the match boots from DevMatch (D1).
local function resolveMatchConfig(): (Types.MapConfig, Types.DifficultyConfig)
	local mapId: string
	local difficultyId: string

	if RunService:IsStudio() then
		-- Studio never arrives by teleport, so there is no join data to read.
		-- Config/DevMatch.luau is how you pick what to playtest.
		mapId = DevMatch.MAP_ID
		difficultyId = DevMatch.DIFFICULTY_ID
	else
		-- Live: the lobby's vote, arriving as untrusted TeleportData.
		-- ArrivalGate validates it against the same allowlists the lobby
		-- voted over and falls back to defaults, so the ids below are always
		-- real and the `find` calls that follow always succeed.
		--
		-- resolveOnArrival, not resolveFrom: this runs at server boot, which
		-- on a reserved server happens BEFORE the teleporting party joins.
		-- Reading the player list here found it empty every time and quietly
		-- took the default map.
		local launch = ArrivalGate.resolveOnArrival(Constants.ARRIVAL_WAIT_SECONDS)
		mapId = launch.mapId
		difficultyId = launch.difficultyId
	end

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
		endless = self.campaignCleared,
	})
end

local function broadcastHealth(self: Controller)
	Net.BaseHealthChanged.FireAll({
		current = math.floor(self.health.current),
		max = math.floor(self.health.max),
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
	Net.PlaySound.FireAll({ soundKey = "WaveStart", position = nil })
end

--- Pays the coins and XP for every wave cleared through `throughWave` that
--- has not been paid yet. Called at EVERY intermission, not only at the end
--- of the run: settlement that waits for a terminal event holds the whole
--- payout in this server's memory, and a deploy or crash at wave 29 would
--- destroy the entire run's earnings for everyone in it. Paying per wave
--- bounds that loss to one wave.
---
--- Persistence goes through the injected awarder rather than being done here:
--- the controller owns the match, the entry point owns the profiles.
local function settleWaves(self: Controller, throughWave: number)
	local unpaid = math.max(0, throughWave - self.paidThroughWave)

	if unpaid <= 0 then
		return
	end

	self.paidThroughWave = math.max(self.paidThroughWave, throughWave)

	local payout = Rewards.forMatch(unpaid, false, self.difficulty)

	self.paidCoins += payout.coins
	self.paidXp += payout.xp

	for _, player in Players:GetPlayers() do
		self.awardRewards(player, payout.coins, payout.xp, 0)
	end
end

--- The end-of-run settlement: any waves still unpaid, the win bonus when
--- won, and the tokens - which flow ONLY here, once per ending, because a
--- token per intermission would put a reroll in every pocket by wave ten.
local function settleTerminal(self: Controller, throughWave: number, won: boolean)
	settleWaves(self, throughWave)

	local bonus: Rewards.Payout = if won then Rewards.forMatch(0, true, self.difficulty) else { coins = 0, xp = 0 }
	local tokens = Rewards.tokensFor(won)

	self.paidCoins += bonus.coins
	self.paidXp += bonus.xp
	self.paidTokens += tokens

	for _, player in Players:GetPlayers() do
		self.awardRewards(player, bonus.coins, bonus.xp, tokens)
	end
end

--- Terminal. Only defeat ends a run: clearing the campaign is a milestone,
--- and the match carries on into endless mode from there.
local function endMatchInDefeat(self: Controller)
	if self.finished then
		return
	end

	self.finished = true
	self.simulation:reset()

	-- The wave they died on does not count as cleared.
	local cleared = math.max(0, self.waveNumber - 1)
	settleTerminal(self, cleared, false)

	setState(self, "Defeat", Constants.RESULTS_SECONDS)

	-- Cumulative for the run, not the terminal slice - with incremental
	-- settlement the final slice is usually zero.
	Net.MatchEnded.FireAll({
		won = false,
		wavesCleared = cleared,
		coinsAwarded = self.paidCoins,
		xpAwarded = self.paidXp,
		tokensAwarded = self.paidTokens,
	})
end

--- The campaign's final wave has been cleared. Plays a short Victory phase
--- and then rolls into endless mode.
---
--- Deliberately does NOT set `finished`, reset the simulation, or stop the
--- heartbeat. Victory is a transient interlude here, which is also what keeps
--- the state meaningful rather than a value nothing ever sets.
local function beginVictoryInterlude(self: Controller)
	self.campaignCleared = true

	settleTerminal(self, self.waveNumber, true)

	Net.MatchEnded.FireAll({
		won = true,
		wavesCleared = self.waveNumber,
		coinsAwarded = self.paidCoins,
		xpAwarded = self.paidXp,
		tokensAwarded = self.paidTokens,
	})

	setState(self, "Victory", Constants.RESULTS_SECONDS)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function MatchController.new(
	isUnlocked: UnlockedResolver,
	awardRewards: RewardAwarder,
	sfxEnabledFor: SettingsResolver,
	traitsOf: TraitsResolver,
	loadoutOf: LoadoutResolver
): Controller
	local mapConfig, difficulty = resolveMatchConfig()
	local map = MapBuilder.build(mapConfig)
	local simulation = EnemySimulation.new(map.paths)

	local self: Controller = setmetatable({
		state = "Loading" :: Types.MatchState,
		waveNumber = 0,
		campaignCleared = false,
		phaseEndsAt = 0,
		map = map,
		difficulty = difficulty,
		simulation = simulation,
		view = EnemyView.new(simulation, workspace),
		towers = TowerSystem.new(simulation, workspace),
		economy = EconomyService.new(difficulty),
		director = WaveDirector.new(simulation, difficulty),
		health = BaseHealth.new(difficulty.baseHealth),
		isUnlocked = isUnlocked,
		awardRewards = awardRewards,
		sfxEnabledFor = sfxEnabledFor,
		traitsOf = traitsOf,
		loadoutOf = loadoutOf,
		paidThroughWave = 0,
		paidCoins = 0,
		paidXp = 0,
		paidTokens = 0,
		returning = false,
		heartbeat = nil,
		finished = false,
	}, MatchController)

	simulation:onEnemyLeaked(function(_enemy: BaseEnemy.Enemy, baseDamage: number)
		-- `damage` reports the transition, not the value, so several leaks in
		-- one step still end the match exactly once.
		-- Fired for every leak, not only the fatal one: the cue is how a
		-- player notices a leak they were not watching.
		Net.PlaySound.FireAll({ soundKey = "BaseDamaged", position = nil })

		if self.health:damage(baseDamage) then
			endMatchInDefeat(self)
		end
	end)

	simulation:onEnemyDied(function(enemy: BaseEnemy.Enemy)
		self.economy:payBounty(enemy)
	end)

	self.health:onChanged(function()
		broadcastHealth(self)
	end)

	self.economy:onChanged(function(player: Player, balance: number)
		Net.CashChanged.Fire(player, { cash = math.floor(balance) })
	end)

	return self
end

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

function MatchController.addPlayer(self: Controller, player: Player)
	self.economy:addPlayer(player)
	broadcastHealth(self)
	broadcastState(self)
end

function MatchController.removePlayer(self: Controller, player: Player)
	-- A disconnected player's towers stop fighting. Leaving them would let a
	-- team bank permanent free DPS by having one member place and leave.
	self.towers:removeAllFor(player)
	self.economy:removePlayer(player)
end

function MatchController.snapshot(self: Controller, player: Player): Types.MatchSnapshot
	return {
		state = self.state,
		mapId = self.map.config.id,
		waveNumber = self.waveNumber,
		baseHealth = math.floor(self.health.current),
		baseHealthMax = math.floor(self.health.max),
		cash = math.floor(self.economy:balance(player)),
		phaseEndsAt = self.phaseEndsAt,
		endless = self.campaignCleared,
		sfxEnabled = self.sfxEnabledFor(player),
		unlockedTowers = self.isUnlocked(player),
		loadout = self.loadoutOf(player),
	}
end

-- ---------------------------------------------------------------------------
-- Player actions
--
-- Building is allowed during both the build phase and an active wave, TDS
-- style: reacting to what a wave actually contains is a large part of the
-- game. It is refused once the match is over.
-- ---------------------------------------------------------------------------

function MatchController.canBuildNow(self: Controller): boolean
	if self.finished then
		return false
	end

	return self.state == "Preparing" or self.state == "WaveActive"
end

local function existingTowers(self: Controller): { Placement.ExistingTower }
	local list: { Placement.ExistingTower } = {}

	for _, tower in self.towers.towers do
		table.insert(list, {
			position = tower.position,
			radius = Footprint.radius(tower.definition.footprint),
		})
	end

	return list
end

--- Attempts a placement. Returns the rejection reason, or nil on success.
function MatchController.placeTower(
	self: Controller,
	player: Player,
	towerDefId: string,
	position: Vector3,
	rotationY: number
): Types.PlacementRejectReason?
	local definition = Towers.find(towerDefId)

	if definition == nil then
		return "UnknownTower"
	end

	local result = Placement.validate({
		definition = definition,
		position = position,
		map = self.map.config,
		existing = existingTowers(self),
		unlocked = table.find(self.isUnlocked(player), towerDefId) ~= nil,
		inLoadout = table.find(self.loadoutOf(player), towerDefId) ~= nil,
		cash = self.economy:balance(player),
		ownedOfType = self.towers:countFor(player, towerDefId),
		canBuildNow = self:canBuildNow(),
	})

	if not result.ok or result.position == nil then
		-- Two returns rather than `result.reason or "NotBuildable"`. The `or`
		-- widens the literal union to plain `string`, which then fails to
		-- satisfy the enum Zap generated for PlacementRejected.
		if result.reason ~= nil then
			return result.reason
		end

		return "NotBuildable"
	end

	local cost = definition.levels[1].cost

	-- Charge last, and only once every rule has passed, so a rejected
	-- placement can never take money.
	if not self.economy:charge(player, cost) then
		return "CannotAfford"
	end

	self.towers:place({
		definition = definition,
		owner = player,
		position = result.position,
		rotationY = rotationY,
		traits = self.traitsOf(player, towerDefId),
	})

	-- To the acting player only. Everyone hearing every placement in a
	-- four-player match is noise, not feedback.
	Net.PlaySound.Fire(player, { soundKey = "TowerPlaced", position = Wire.toWire(result.position) })

	return nil
end

function MatchController.upgradeTower(self: Controller, player: Player, towerId: number): boolean
	local tower = self.towers:get(towerId)

	if tower == nil or tower.owner ~= player or not self:canBuildNow() then
		return false
	end

	local cost = tower:upgradeCost()

	if cost == nil then
		return false
	end

	if not self.economy:charge(player, cost) then
		return false
	end

	self.towers:upgrade(tower, cost)
	Net.PlaySound.Fire(player, { soundKey = "TowerUpgraded", position = Wire.toWire(tower.position) })

	return true
end

function MatchController.sellTower(self: Controller, player: Player, towerId: number): boolean
	local tower = self.towers:get(towerId)

	if tower == nil or tower.owner ~= player or not self:canBuildNow() then
		return false
	end

	-- Read the refund before removing: sellValue depends on state that
	-- `remove` is about to drop.
	local refund = tower:sellValue()
	local position = tower.position

	self.towers:remove(towerId)
	self.economy:credit(player, refund)

	Net.PlaySound.Fire(player, { soundKey = "TowerSold", position = Wire.toWire(position) })

	return true
end

function MatchController.setTargeting(
	self: Controller,
	player: Player,
	towerId: number,
	mode: Types.TargetingMode
): boolean
	local tower = self.towers:get(towerId)

	if tower == nil or tower.owner ~= player then
		return false
	end

	if not Targeting.isValid(mode) then
		return false
	end

	self.towers:setTargeting(tower, mode)

	return true
end

--- Admin grant of match cash. Routed through the same EconomyService
--- credit every legitimate payment uses, so CashChanged replicates it and
--- no second bookkeeping path exists to drift. Returns the new balance.
function MatchController.grantCash(self: Controller, player: Player, amount: number): number
	self.economy:credit(player, amount)

	return math.floor(self.economy:balance(player))
end

-- ---------------------------------------------------------------------------
-- Admin sandbox
--
-- Every function below is a DEBUG affordance, reachable only through the
-- admin console and gated by Config/Admins.luau at the network handler. They
-- deliberately route through the same systems ordinary play uses - the
-- simulation's spawn, the director's beginWave, the same BaseHealth - rather
-- than writing state directly, so what the console produces is a real match
-- state and not a lookalike that behaves differently the moment it is
-- touched.
-- ---------------------------------------------------------------------------

--- Spawns `count` of an enemy onto a live lane, scaled to the current wave.
---
--- Scaled rather than at base values on purpose: a Zombie summoned at wave
--- 30 with wave-1 health would evaporate and teach nothing about wave 30.
--- Returns a message for the console either way.
function MatchController.adminSpawn(self: Controller, enemyId: string, count: number): (boolean, string)
	local definition = Enemies.find(enemyId)

	if definition == nil then
		return false, `No enemy called "{enemyId}"`
	end

	if self.state ~= "Preparing" and self.state ~= "WaveActive" and self.state ~= "Intermission" then
		return false, "The match is not running"
	end

	local laneCount = #self.map.paths

	if laneCount < 1 then
		return false, "This map has no lanes"
	end

	local relativeWave = math.max(1, self.waveNumber - definition.introducesAtWave + 1)
	local endless = Scaling.endlessFactor(self.waveNumber, self.difficulty.finalWave)
	local health = Scaling.enemyHealth(definition.baseHealth, relativeWave, self.difficulty.healthMultiplier * endless)
	local bounty = Scaling.bounty(definition.baseBounty, relativeWave, self.difficulty.rewardMultiplier)

	for index = 1, count do
		self.simulation:spawn({
			definition = definition,
			behavior = EnemyBehaviors.find(enemyId),
			-- Spread across lanes, so spawning six on Bastion exercises both
			-- pincers rather than stacking one.
			pathIndex = ((index - 1) % laneCount) + 1,
			health = health,
			speed = definition.baseSpeed,
			bounty = bounty,
		})
	end

	return true, `Spawned {count} x {definition.displayName}`
end

--- Kills everything currently walking, paying no bounty.
---
--- Damage rather than a silent removal, so death listeners, rewards
--- bookkeeping and the view all see exactly what they see in play.
function MatchController.adminKillEnemies(self: Controller): (boolean, string)
	local ids = self.simulation:liveIds()

	for _, id in ids do
		self.simulation:damage(id, math.huge, nil)
	end

	return true, `Killed {#ids} enem{if #ids == 1 then "y" else "ies"}`
end

--- Ends the current wave and moves to the next build phase.
---
--- Clears the field first: a skipped wave that left its enemies walking
--- would pile them into the next one, which is a different bug wearing the
--- console's clothes.
function MatchController.adminSkipWave(self: Controller): (boolean, string)
	if self.state == "Victory" or self.state == "Defeat" then
		return false, "The match is already over"
	end

	for _, id in self.simulation:liveIds() do
		self.simulation:damage(id, math.huge, nil)
	end

	local from = self.waveNumber

	-- Exactly the transition a natural completion makes at the end of an
	-- intermission, rather than a bespoke one.
	self.waveNumber += 1
	beginPreparing(self)

	return true, `Wave {from} -> {self.waveNumber}`
end

--- Refills the base.
function MatchController.adminHealBase(self: Controller): (boolean, string)
	local restored = math.floor(self.health.max - self.health.current)

	self.health.current = self.health.max
	broadcastHealth(self)

	return true, `Base restored (+{restored})`
end

--- Fires a tower's active ability. Ownership, existence, match state and
--- cooldown are all validated HERE, from state the server owns - the button
--- being lit client-side is a hint, not a lock.
---
--- Executed in the controller rather than TowerSystem because two of the
--- four kinds reach outside the tower system: Payday touches the economy,
--- and every kind reports through the AbilityUsed cue.
function MatchController.useAbility(self: Controller, player: Player, towerId: number): boolean
	local tower = self.towers:get(towerId)

	if tower == nil or tower.owner ~= player or not self:canBuildNow() then
		return false
	end

	local ability = tower.definition.ability

	if ability == nil then
		return false
	end

	local now = os.time()

	if now < tower.abilityReadyAt then
		return false
	end

	tower.abilityReadyAt = now + ability.cooldownSeconds

	local cueRadius = 0

	if ability.kind == "Barrage" then
		-- The closest-to-leaking enemies, exactly the ones a panic button
		-- is pressed about.
		local ids = self.towers:enemiesInRange(tower)

		for index = 1, math.min(ability.strikes, #ids) do
			self.simulation:damage(ids[index], ability.power, player)
		end

		cueRadius = tower:range()
	elseif ability.kind == "Overcharge" then
		tower:beginBoost(ability.power, ability.durationSeconds)
	elseif ability.kind == "FreezeBurst" then
		local effectId = ability.effectId

		if effectId ~= nil then
			for _, id in self.towers:enemiesInRange(tower) do
				self.simulation:applyEffect(
					id,
					{ effectId = effectId, duration = ability.durationSeconds, power = 0 },
					player
				)
			end
		end

		cueRadius = tower:range()
	elseif ability.kind == "Payday" then
		-- Scaled by the wave so the button stays worth its cooldown in the
		-- late game without being a printing press in the early one.
		local amount = math.floor(ability.power * (1 + self.waveNumber / 10) + 0.5)
		self.economy:credit(player, amount)
	end

	-- The attribute refresh is what restarts every client's cooldown ring.
	self.towers:refreshAbility(tower)

	Net.AbilityUsed.FireAll({
		towerId = tower.id,
		abilityId = ability.id,
		position = Wire.toWire(tower.position),
		radius = cueRadius,
	})

	return true
end

--- Ends the build phase early, paying everyone for the time skipped. The
--- server reads its own clock: a client-supplied duration would be free cash.
function MatchController.requestEarlyStart(self: Controller): boolean
	if self.state ~= "Preparing" or self.finished then
		return false
	end

	local remaining = math.max(0, self.phaseEndsAt - os.time())
	self.economy:creditAll(Economy.earlyStartBonus(remaining, self.difficulty.rewardMultiplier))

	beginWave(self)

	return true
end

-- ---------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------

local function tick(self: Controller, deltaTime: number)
	if self.finished then
		-- The results screen has had its time. Send everyone back to the
		-- lobby, once: `returning` guards it because this branch runs on
		-- every heartbeat for as long as the server survives.
		if not self.returning and self.phaseEndsAt > 0 and os.time() >= self.phaseEndsAt then
			self.returning = true
			task.spawn(ReturnGate.send)
		end

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
		self.towers:update(deltaTime)
		self.view:sync()

		-- Both conditions, deliberately. Either alone is a real bug: the
		-- director being done says nothing about enemies still walking, and
		-- an empty simulation is trivially true before the first spawn.
		if self.director:isSpawningComplete() and self.simulation:count() == 0 then
			self.economy:creditAll(Scaling.waveBonus(self.waveNumber, self.difficulty.rewardMultiplier))
			-- Settle the cleared wave into persistence NOW, not at the end of
			-- the run - see settleWaves for why the difference matters.
			settleWaves(self, self.waveNumber)
			setState(self, "Intermission", Constants.INTERMISSION_SECONDS)
			Net.PlaySound.FireAll({ soundKey = "WaveCleared", position = nil })
		end

		return
	end

	if self.state == "Intermission" then
		if os.time() >= self.phaseEndsAt then
			-- The campaign is cleared exactly once. After that this branch
			-- stops firing and the run cycles through endless waves, whose
			-- extra scaling WaveGenerator applies from difficulty.finalWave.
			if not self.campaignCleared and self.waveNumber >= self.difficulty.finalWave then
				beginVictoryInterlude(self)
			else
				self.waveNumber += 1
				beginPreparing(self)
			end
		end

		return
	end

	-- A transient celebration between the campaign and endless mode, not an
	-- ending. Defeat is the only terminal state, and it returns above via
	-- `finished`.
	if self.state == "Victory" then
		if os.time() >= self.phaseEndsAt then
			self.waveNumber += 1
			beginPreparing(self)
		end

		return
	end
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

	self.towers:destroy()
	self.view:destroy()
	self.simulation:destroy()
	MapBuilder.clear()
end

return MatchController

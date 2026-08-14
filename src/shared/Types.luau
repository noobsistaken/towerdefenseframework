--!strict
--[[
	Shared type definitions.

	Types live here so the server, the client and the tests all agree on the
	same shapes. In strict mode a mismatch here is a build failure, not a
	runtime surprise - which is the entire reason this project runs strict.

	Two rules for this file:

	  * Only PlayerData and its children must be DataStore-safe. Everything
	    else describes live state or map configuration and may hold userdata
	    (Vector3, CFrame, Color3) freely.
	  * No requires. This is a leaf module so that every other module can
	    depend on it without creating a cycle.
]]

-- ===========================================================================
-- Persisted player data
-- ===========================================================================

--- Lifetime counters. Match-local numbers never live here.
export type PlayerStats = {
	MatchesPlayed: number,
	MatchesWon: number,
	HighestWave: number,
	EnemiesKilled: number,
}

export type PlayerSettings = {
	MusicEnabled: boolean,
	SfxEnabled: boolean,
}

--- Persisted player data. Every field must be DataStore-safe:
--- no Instances, no userdata (Vector3/CFrame/Color3), no functions,
--- no mixed or sparse arrays. Serialise before storing.
---
--- Match currency is deliberately absent: it is per-match server state and
--- persisting it would let a player carry cash between runs.
export type PlayerData = {
	--- Bumped whenever the shape below changes. See ARCHITECTURE.md.
	Version: number,
	--- Meta-currency, earned at match end. Not the in-match cash.
	Coins: number,
	XP: number,
	Level: number,
	UnlockedTowers: { string },
	Stats: PlayerStats,
	Settings: PlayerSettings,
}

-- ===========================================================================
-- Identifiers
--
-- Distinct aliases rather than bare `number` so a function taking an EnemyId
-- reads unambiguously. Luau aliases are not nominal, so this is documentation
-- the compiler happens to understand - it will not catch passing a TowerId
-- where an EnemyId belongs.
-- ===========================================================================

export type EnemyId = number
export type TowerId = number
export type PathIndex = number

-- ===========================================================================
-- Map configuration
-- ===========================================================================

--- Where a tower is allowed to stand. `Elevated` is what makes the Hillside
--- tower category meaningful; the surface carries the tag, so map authors
--- never hand-place per-tower slots.
export type SurfaceType = "Ground" | "Elevated"

--- An axis-aligned buildable region, described in world space.
export type BuildableSurface = {
	position: Vector3,
	size: Vector3,
	surfaceType: SurfaceType,
}

--- Purely cosmetic geometry. MapBuilder spawns these and nothing reads them.
export type DecorPart = {
	position: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
}

--- A lane enemies walk. Enemies are assigned one path at spawn and never
--- change lanes, which is what keeps `distanceToBase` a total ordering.
export type MapPath = {
	--- World-space waypoints, start first, base last. At least two.
	waypoints: { Vector3 },
}

export type MapConfig = {
	id: string,
	displayName: string,
	--- One or more independent lanes. Lengths may differ freely; ordering
	--- across lanes uses distance remaining, not raw progress. See D8.
	paths: { MapPath },
	--- Where leaked enemies are considered to have arrived. Cosmetic marker
	--- position; the authoritative leak test is reaching the path end.
	basePosition: Vector3,
	buildableSurfaces: { BuildableSurface },
	decor: { DecorPart },
	--- Ground plane extents, used to build the floor and to reject placement
	--- requests pointing outside the map.
	groundSize: Vector3,
	groundColor: Color3,
}

-- ===========================================================================
-- Enemy configuration
-- ===========================================================================

--- Ground enemies can be hit by every tower. Air enemies can only be hit by
--- towers whose definition targets air, which is the entire reason the
--- Hillside category exists.
export type EnemyCategory = "Ground" | "Air"

export type EnemyDefinition = {
	id: string,
	displayName: string,
	category: EnemyCategory,
	--- Wave-1 values. `Scaling` applies the wave curve on top of these.
	baseHealth: number,
	--- Studs per second along the path, before status effects.
	baseSpeed: number,
	baseBounty: number,
	--- Base HP removed when this enemy reaches the end of its lane.
	leakDamage: number,
	isBoss: boolean,
	--- Earliest wave this enemy may appear in.
	introducesAtWave: number,
	--- Placeholder visual. Replaced from the asset manifest later.
	hitboxSize: Vector3,
	color: Color3,
	--- Height of the model's centre above the path line.
	hoverHeight: number,
	--- Multiplier applied to incoming effect duration, keyed by effect id.
	--- 0 means immune, 0.5 means half duration, absent means 1.
	resistances: { [string]: number },
}

-- ===========================================================================
-- Match state
-- ===========================================================================

--- The match lifecycle. Transitions are owned solely by MatchController.
---
---   Loading      building the map, nobody can act
---   Preparing    pre-wave build time; early start is offered here
---   WaveActive   enemies alive or still to spawn
---   Intermission wave cleared, short breather, then back to Preparing
---   Victory      final wave cleared and endless mode declined
---   Defeat       base health reached zero
export type MatchState = "Loading" | "Preparing" | "WaveActive" | "Intermission" | "Victory" | "Defeat"

--- Everything a joining client needs to render the match immediately.
export type MatchSnapshot = {
	state: MatchState,
	mapId: string,
	waveNumber: number,
	baseHealth: number,
	baseHealthMax: number,
	cash: number,
	--- Unix time the current phase ends. 0 when the phase has no timer.
	phaseEndsAt: number,
	--- Tower ids this player owns. Advisory only - it drives which shop
	--- buttons are enabled, and the server re-checks on every placement.
	unlockedTowers: { string },
}

-- ===========================================================================
-- Status effects
--
-- Generic by design. Bleed is the only effect Phase 2 ships, but it is built
-- on the kinds below so poison, burn and slow are one config entry each with
-- no new code.
-- ===========================================================================

--- What an effect actually does.
---   DamageOverTime          periodic damage, `power` per tick
---   SpeedMultiplier         scales movement; 0.7 is a 30% slow
---   DamageTakenMultiplier   scales incoming damage; 1.25 is +25% vulnerability
---   Stun                    speed forced to zero for the duration
export type StatusEffectKind = "DamageOverTime" | "SpeedMultiplier" | "DamageTakenMultiplier" | "Stun"

--- What a second application of an already-active effect does.
---   Refresh       resets the timer, stack count stays at 1
---   Stack         adds a stack up to maxStacks, refreshes the timer
---   Independent   each application expires on its own schedule
export type StatusStacking = "Refresh" | "Stack" | "Independent"

export type StatusEffectDefinition = {
	id: string,
	displayName: string,
	kind: StatusEffectKind,
	--- Seconds between ticks. Only meaningful for DamageOverTime.
	tickInterval: number,
	stacking: StatusStacking,
	--- Ignored unless stacking is "Stack".
	maxStacks: number,
	--- Per-stack multiplier for SpeedMultiplier and DamageTakenMultiplier.
	--- Unused by DamageOverTime, whose magnitude comes from the application.
	magnitude: number,
	--- Placeholder tint applied to an affected enemy.
	color: Color3,
}

--- One effect a tower level applies on hit.
export type StatusApplication = {
	effectId: string,
	duration: number,
	--- Damage per tick for DamageOverTime. Unused by the other kinds.
	power: number,
}

--- One live instance of an effect on one enemy.
---
--- All times are SIMULATION time, not os.clock. The simulation advances its
--- own clock in fixed steps, so effects expire and tick identically at any
--- server frame rate, and a test can drive them exactly.
export type ActiveStatusEffect = {
	effectId: string,
	--- Always 1 except under "Stack" stacking.
	stacks: number,
	expiresAt: number,
	--- Next simulation time this instance deals its damage. Meaningless for
	--- kinds other than DamageOverTime.
	nextTickAt: number,
	--- Damage per tick, carried from the application that created this.
	power: number,
	--- Who gets credited for the damage this deals, for the bounty split.
	source: Player?,
}

--- Damage produced by an effect tick, waiting to be applied through the
--- simulation so that a kill fires the normal death path.
export type DamageTick = {
	amount: number,
	source: Player?,
}

-- ===========================================================================
-- Tower configuration
-- ===========================================================================

--- Where a tower may stand.
---   Ground     only on surfaces tagged Ground
---   Hillside   only on surfaces tagged Elevated
---   Hybrid     either
export type TowerCategory = "Ground" | "Hillside" | "Hybrid"

--- What a tower may shoot.
export type TargetClass = "Ground" | "Air" | "Both"

export type TargetingMode = "First" | "Last" | "Strongest" | "Closest"

--- Why a placement request was refused. Mirrors the PlacementRejectReason
--- enum in net/schema.zap - if you add one, add it in both places.
export type PlacementRejectReason =
	"UnknownTower"
	| "NotUnlocked"
	| "CannotAfford"
	| "OutOfBounds"
	| "NotBuildable"
	| "WrongSurface"
	| "OverlapsTower"
	| "BlocksPath"
	| "TowerCapReached"
	| "WrongMatchState"

export type TowerLevel = {
	--- Cost to REACH this level. Index 1 is the purchase price; later indices
	--- are upgrade costs, not cumulative totals.
	cost: number,
	damage: number,
	--- Shots per second.
	fireRate: number,
	--- Studs.
	range: number,
	--- 0 means single target.
	splashRadius: number,
	--- Effects applied on hit.
	applies: { StatusApplication },
	--- Placeholder visual.
	modelSize: Vector3,
	color: Color3,
}

export type TowerDefinition = {
	id: string,
	displayName: string,
	description: string,
	category: TowerCategory,
	targets: TargetClass,
	--- Ground footprint in studs, X by Z. Drives overlap and path clearance.
	footprint: Vector2,
	defaultTargeting: TargetingMode,
	--- Maximum this player may own. 0 means unlimited.
	perPlayerCap: number,
	--- At least three, per the brief. Index is the tower's level.
	levels: { TowerLevel },
}

-- ===========================================================================
-- Difficulty
-- ===========================================================================

export type DifficultyConfig = {
	id: string,
	displayName: string,
	startingCash: number,
	baseHealth: number,
	--- Multiplies enemy health on top of the wave curve.
	healthMultiplier: number,
	--- Multiplies kill bounty and wave bonuses.
	rewardMultiplier: number,
	--- Wave at which Victory is offered and endless mode begins.
	finalWave: number,
}

return {}

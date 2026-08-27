--!strict
--[[
	Tuning constants that are not per-map, per-enemy or per-difficulty.

	Anything that belongs to a piece of content lives in Config/. What is here
	is the shape of the match loop itself.
]]

local Constants = {}

-- ===========================================================================
-- Simulation
-- ===========================================================================

--- The enemy simulation runs on a FIXED timestep, accumulating real frame
--- time and stepping in whole ticks.
---
--- Fixed rather than variable for two reasons, both load-bearing:
---   * Determinism. The same inputs produce the same result regardless of
---     server frame rate, which is what lets a test step the simulation by
---     hand and assert on exact positions.
---   * Fairness. Enemy speed and damage-over-time tick rates stop depending
---     on how busy the server happens to be.
Constants.SIMULATION_HZ = 30
Constants.SIMULATION_STEP = 1 / Constants.SIMULATION_HZ

--- Ceiling on how many fixed steps one frame may run. Without it, a server
--- hitch produces a spiral of death: the accumulator grows, the catch-up
--- steps take longer than real time, and the accumulator grows further.
--- Hitting this ceiling means the simulation falls behind wall-clock, which
--- is strictly better than locking the server.
Constants.MAX_STEPS_PER_FRAME = 5

-- ===========================================================================
-- Match loop
-- ===========================================================================

--- Build time before the first wave. Longer than later phases because the
--- player starts with nothing placed.
Constants.FIRST_PREPARE_SECONDS = 25

--- Build time before every subsequent wave.
Constants.PREPARE_SECONDS = 15

--- Breather after a wave is cleared, before the next prepare phase.
Constants.INTERMISSION_SECONDS = 3

--- How long the results screen shows before players are returned to lobby.
Constants.RESULTS_SECONDS = 12

-- ===========================================================================
-- World
-- ===========================================================================

--- CollectionService tag on every buildable pad, so placement validation can
--- find them by query rather than by walking the map model.
Constants.BUILDABLE_TAG = "TDBuildable"

-- ===========================================================================
-- Lobby
-- ===========================================================================

-- No countdown constants, deliberately: the hub launches nothing on a
-- timer. A match starts when someone in the GAME area presses START, and
-- everyone standing there goes along - see LobbyController.

--- How long the lobby sits in Launching before returning to Gathering when
--- the teleport was only simulated, as it always is in Studio. Without this
--- the lobby would wedge in Launching forever during a Studio playtest.
Constants.LOBBY_RELAUNCH_SECONDS = 6

--- How long a booting match server waits for its teleporting party to
--- arrive with the lobby's vote. A reserved server's scripts run before
--- anyone has joined, so this window is the difference between reading the
--- vote and silently defaulting. Generous because the cost of waiting is a
--- few seconds on the loading screen, and the cost of not waiting is the
--- map vote appearing not to work at all.
Constants.ARRIVAL_WAIT_SECONDS = 10

-- ===========================================================================
-- Placement
-- ===========================================================================

--- Minimum studs from the lane centre line to any part of a tower.
--- MapBuilder draws the walkway 16 wide, so 8 is flush with its edge and this
--- leaves a stud of margin. This is the number that stops a player walling
--- the lane shut, which is the placement bug that turns a tower defense into
--- a maze game.
Constants.PATH_CLEARANCE = 9

--- How far above a surface a placement raycast starts, and how far it
--- travels. Generous enough to cope with a client aiming at a pad from an
--- odd angle, short enough that it cannot find a pad on the far side of the
--- map.
Constants.PLACEMENT_RAY_HEIGHT = 200
Constants.PLACEMENT_RAY_LENGTH = 400

--- Attribute names written on server-owned instances. These are the
--- replication channel for per-entity state (ARCHITECTURE.md D5), so a typo
--- here is a silent client-side failure - reference the constant, never the
--- literal.
Constants.ATTR_HEALTH = "Health"
Constants.ATTR_MAX_HEALTH = "MaxHealth"
Constants.ATTR_ENEMY_ID = "EnemyId"
Constants.ATTR_STATUS_EFFECTS = "StatusEffects"
Constants.ATTR_ENRAGED = "Enraged"

--- Rig height as a fraction of the host part's height. Shared because the
--- server fits real rigs with it and the client fits the placement ghost's
--- preview rig with it - if the two disagree, the ghost lies about the size
--- of what will be built.
Constants.RIG_SCALE = 0.5
Constants.ATTR_SURFACE_TYPE = "SurfaceType"

--- Folder names inside workspace. MapBuilder owns these and clears them
--- between matches.
Constants.MAP_FOLDER = "TDMap"
Constants.ENEMY_FOLDER = "TDEnemies"
Constants.TOWER_FOLDER = "TDTowers"

return Constants

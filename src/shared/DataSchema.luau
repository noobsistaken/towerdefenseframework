--!strict
--[[
	Player data schema, its current version, and the migration ladder.

	Rules:
	  * Never change the meaning of an existing field. Add a new one.
	  * Every shape change bumps CURRENT_VERSION and adds exactly one
	    migration step below.
	  * Migrations run oldest -> newest, one version at a time, so a profile
	    saved three versions ago walks forward through every step.

	Version 1 was replaced wholesale rather than migrated, because the shape
	it replaced was the template's placeholder and had never reached a live
	player. That is a one-time licence and it is now spent: from here on, a
	shape change means a version bump and a ladder rung.
]]

local Types = require(script.Parent.Types)

local DataSchema = {}

DataSchema.CURRENT_VERSION = 5

--- Towers every account owns from the start. Currently ALL of them, by
--- request - the Coins sink this leaves behind is a design decision waiting
--- for a real unlock ladder. Ids must exist in Config/Towers.luau.
local STARTING_TOWERS: { string } = { "Rifleman", "Ranger", "Mortar", "Marksman", "Flak", "Lacerator" }

DataSchema.TEMPLATE = {
	Version = DataSchema.CURRENT_VERSION,
	Coins = 0,
	XP = 0,
	Level = 1,
	UnlockedTowers = STARTING_TOWERS,
	-- The whole starting roster happens to be exactly one loadout's worth.
	Loadout = STARTING_TOWERS,
	Traits = {},
	RerollTokens = 0,
	RollsSinceSecret = 0,
	Stats = {
		MatchesPlayed = 0,
		MatchesWon = 0,
		HighestWave = 0,
		EnemiesKilled = 0,
	},
	Settings = {
		MusicEnabled = true,
		SfxEnabled = true,
	},
} :: Types.PlayerData

--- One entry per version transition. Key N migrates version N -> N + 1.
--- Add to this table, never edit a shipped entry.
---
--- Note for whoever adds rung 1: ProfileStore's Reconcile fills in missing
--- TOP-LEVEL keys from the template. Do not assume it back-fills a new field
--- inside Stats or Settings - add those explicitly in the migration step.
local MIGRATIONS: { [number]: (Types.PlayerData) -> () } = {
	-- v1 -> v2: every tower became a starting tower. Union rather than
	-- replace, so an account that somehow owns something beyond the roster
	-- keeps it, and running twice cannot duplicate an entry.
	[1] = function(data)
		for _, id in STARTING_TOWERS do
			if table.find(data.UnlockedTowers, id) == nil then
				table.insert(data.UnlockedTowers, id)
			end
		end

		data.Version = 2
	end,

	-- v2 -> v3: the gacha arrives. Rolled traits per tower and the tokens
	-- that reroll them. Reconcile only fills missing TOP-LEVEL keys on new
	-- profiles, so a v2 profile needs both added here explicitly.
	[2] = function(data)
		data.Traits = {}
		data.RerollTokens = 0
		data.Version = 3
	end,

	-- v3 -> v4: the loadout. A v3 account owned everything it could place,
	-- so its first deck is simply the first six things it owns - stable
	-- order, no judgement call baked into a migration.
	[3] = function(data)
		local loadout: { string } = {}

		for index = 1, math.min(6, #data.UnlockedTowers) do
			loadout[index] = data.UnlockedTowers[index]
		end

		data.Loadout = loadout
		data.Version = 4
	end,

	-- v4 -> v5: the Secret pity counter. Existing accounts start at zero
	-- rather than at their true lifetime roll count, which is not
	-- recoverable - the rolls were never counted. Starting fresh is the
	-- generous direction only in that it cannot mistakenly fire the
	-- guarantee on someone who just had one.
	[4] = function(data)
		data.RollsSinceSecret = 0
		data.Version = 5
	end,
}

--- Walks `data` forward to CURRENT_VERSION in place.
--- Returns the number of migration steps applied.
function DataSchema.migrate(data: Types.PlayerData): number
	local applied = 0

	while data.Version < DataSchema.CURRENT_VERSION do
		local step = MIGRATIONS[data.Version]

		if step == nil then
			-- No ladder rung. Refuse to guess at the shape: a wrong guess
			-- silently corrupts live player data.
			error(`DataSchema: no migration from version {data.Version}`)
		end

		local before = data.Version
		step(data)
		applied += 1

		if data.Version <= before then
			error(`DataSchema: migration {before} did not advance Version`)
		end
	end

	return applied
end

return DataSchema

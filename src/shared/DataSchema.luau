--!strict
--[[
	Player data schema, its current version, and the migration ladder.

	Rules:
	  * Never change the meaning of an existing field. Add a new one.
	  * Every shape change bumps CURRENT_VERSION and adds exactly one
	    migration step below.
	  * Migrations run oldest -> newest, one version at a time, so a profile
	    saved three versions ago walks forward through every step.
]]

local Types = require(script.Parent.Types)

local DataSchema = {}

DataSchema.CURRENT_VERSION = 1

DataSchema.TEMPLATE = {
	Version = DataSchema.CURRENT_VERSION,
	Coins = 0,
	Level = 1,
	Inventory = {},
} :: Types.PlayerData

--- One entry per version transition. Key N migrates version N -> N + 1.
--- Add to this table, never edit a shipped entry.
local MIGRATIONS: { [number]: (Types.PlayerData) -> () } = {
	-- [1] = function(data)
	-- 	data.Prestige = 0
	-- 	data.Version = 2
	-- end,
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

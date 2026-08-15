--!strict
--[[
	Map registry.

	The single place that knows which maps exist. Map ids arrive from the
	lobby over TeleportData, which is untrusted, so `find` is the allowlist
	the arrival gate validates against.
]]

local Types = require(script.Parent.Parent.Types)

local Crossroads = require(script.Parent.Maps.Crossroads)
local Fork = require(script.Parent.Maps.Fork)
local Switchback = require(script.Parent.Maps.Switchback)

local MapRegistry = {}

MapRegistry.DEFAULT_ID = "Crossroads"

MapRegistry.MAPS = {
	Crossroads = Crossroads,
	Switchback = Switchback,
	Fork = Fork,
} :: { [string]: Types.MapConfig }

--- Sorted for stable iteration - vote tallies and map lists must not reorder
--- themselves between servers.
local sortedIds: { string } = {}

for id in MapRegistry.MAPS do
	table.insert(sortedIds, id)
end

table.sort(sortedIds)

MapRegistry.IDS = table.freeze(sortedIds)

--- Non-throwing lookup, for untrusted input.
function MapRegistry.find(id: string): Types.MapConfig?
	return MapRegistry.MAPS[id]
end

--- Throwing lookup, for ids the caller already validated.
function MapRegistry.get(id: string): Types.MapConfig
	local map = MapRegistry.MAPS[id]

	if map == nil then
		error(`MapRegistry.get: no map with id "{id}"`)
	end

	return map
end

return MapRegistry

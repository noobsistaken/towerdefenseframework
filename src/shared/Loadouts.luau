--!strict
--[[
	Loadout rules: which towers a player BRINGS to a match, out of what they
	own. The collection can grow to the whole roster through the gacha; the
	deck stays at most MAX, which is what makes owning a twentieth tower a
	choice rather than a longer shop bar.

	Pure over PlayerData, like GachaFlow, and for the same reason: the lobby
	entry point owns the session, this owns the rules, and a spec drives the
	whole thing with a table.
]]

local Towers = require(script.Parent.Config.Towers)
local Types = require(script.Parent.Types)

local Loadouts = {}

--- Deck size. Six, per the brief: enough for a real composition, few
--- enough that the match shop reads at a glance.
Loadouts.MAX = 6

--- Validates and applies a requested loadout to `data`. Returns false and
--- writes nothing when the request is invalid - a loadout is replaced whole
--- or not at all, so no partial deck can ever persist.
---
--- Rules, each of which a forged request would otherwise break:
---   * 1 to MAX entries - an empty deck would render an empty shop.
---   * every id names a real tower AND one this player owns.
---   * no duplicates - one Godslayer is one shop button, not six.
function Loadouts.apply(data: Types.PlayerData, towerIds: { string }): boolean
	if #towerIds < 1 or #towerIds > Loadouts.MAX then
		return false
	end

	local seen: { [string]: boolean } = {}

	for _, id in towerIds do
		if seen[id] then
			return false
		end

		if Towers.find(id) == nil then
			return false
		end

		if table.find(data.UnlockedTowers, id) == nil then
			return false
		end

		seen[id] = true
	end

	data.Loadout = table.clone(towerIds)

	return true
end

--- The loadout to actually fight with: the persisted one, with anything no
--- longer owned or no longer real filtered out, topped up from the owned
--- roster if that left it empty. Degradation, not validation - persisted
--- data outlives rosters, and a renamed tower must not brick the shop.
function Loadouts.resolve(data: Types.PlayerData): { string }
	local deck: { string } = {}

	for _, id in data.Loadout do
		if #deck < Loadouts.MAX and Towers.find(id) ~= nil and table.find(data.UnlockedTowers, id) ~= nil then
			table.insert(deck, id)
		end
	end

	if #deck == 0 then
		for _, id in data.UnlockedTowers do
			if #deck < Loadouts.MAX and Towers.find(id) ~= nil then
				table.insert(deck, id)
			end
		end
	end

	return deck
end

return Loadouts

--!strict
--[[
	Target selection.

	Pure: it takes a list of already-filtered candidates and picks one. It
	knows nothing about the simulation, towers, or Instances, which is what
	makes every mode testable in isolation.

	Filtering - range, air/ground eligibility, liveness - happens before this
	is called. Mixing the filter into the selection is how "my anti-air tower
	sometimes shoots ground units" happens.

	No sorting anywhere. Every mode is an argmin or argmax, so selection is a
	single pass whatever the enemy count. That is also why EnemySimulation does
	not keep its list ordered: nothing needs it to be.

	Ties break on the lowest id, always. Without an explicit tie-break the
	winner depends on table order, and a tower would visibly flicker between
	two equidistant targets.
]]

local Types = require(script.Parent.Types)

local Targeting = {}

--- What selection needs to know about one eligible enemy. Deliberately a
--- flat record of numbers rather than the live enemy: it keeps this module
--- pure, and it documents exactly which four quantities the modes use.
export type Candidate = {
	id: Types.EnemyId,
	--- Studs remaining before it leaks. The universal ordering key (D8),
	--- which is what makes First and Last correct across lanes of different
	--- lengths.
	distanceToBase: number,
	health: number,
	maxHealth: number,
	--- Studs from the tower. Only Closest uses it.
	distanceToTower: number,
}

--- Every mode, in cycling order. The client's targeting button walks this.
local MODES: { Types.TargetingMode } = { "First", "Last", "Strongest", "Closest" }

Targeting.MODES = table.freeze(MODES)

--- True if `challenger` should displace `leader` under `mode`.
--- Split out so each mode is one readable line and the tie-break is written
--- exactly once.
local function beats(mode: Types.TargetingMode, challenger: Candidate, leader: Candidate): boolean
	if mode == "First" then
		if challenger.distanceToBase ~= leader.distanceToBase then
			return challenger.distanceToBase < leader.distanceToBase
		end
	elseif mode == "Last" then
		if challenger.distanceToBase ~= leader.distanceToBase then
			return challenger.distanceToBase > leader.distanceToBase
		end
	elseif mode == "Strongest" then
		-- Max health, not current: "strongest" should mean the Tank, and stay
		-- meaning the Tank after it has been chipped down.
		if challenger.maxHealth ~= leader.maxHealth then
			return challenger.maxHealth > leader.maxHealth
		end
	else
		if challenger.distanceToTower ~= leader.distanceToTower then
			return challenger.distanceToTower < leader.distanceToTower
		end
	end

	return challenger.id < leader.id
end

--- Picks one candidate, or nil if there are none.
function Targeting.select(mode: Types.TargetingMode, candidates: { Candidate }): Candidate?
	local leader: Candidate? = nil

	for _, candidate in candidates do
		if leader == nil or beats(mode, candidate, leader) then
			leader = candidate
		end
	end

	return leader
end

--- The next mode in cycling order, wrapping. Used by the inspector button.
--- Falls back to the first mode if handed something unrecognised, so a stale
--- client value can never leave a tower with no valid mode.
function Targeting.cycle(mode: Types.TargetingMode): Types.TargetingMode
	local index = table.find(MODES, mode)

	if index == nil then
		return MODES[1]
	end

	return MODES[(index % #MODES) + 1]
end

--- Whether a string names a real mode. The server validates client-supplied
--- modes with this before storing one.
function Targeting.isValid(mode: string): boolean
	return table.find(MODES, mode :: any) ~= nil
end

return Targeting

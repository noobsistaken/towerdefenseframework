--!strict
--[[
	Maps tower ids to their behaviour override, where they have one.

	A tower absent from this table uses BaseTower's defaults, which is the
	expected case: four of the six in the roster appear nowhere here.

	Adding a tower that needs custom behaviour is two steps - write the module
	under Towers/, add a line here - and adding one that does not is zero.
]]

local Splash = require(script.Parent.Towers.Splash)

local BaseTower = require(script.Parent.BaseTower)

local TowerBehaviors = {}

local BY_ID: { [string]: BaseTower.TowerBehavior } = {
	-- Both splash towers share one implementation; the radius that
	-- distinguishes them lives in Config/Towers.luau, not here.
	Mortar = Splash,
	Flak = Splash,
}

TowerBehaviors.BY_ID = BY_ID

--- Behaviour for a tower id, or nil to use BaseTower's defaults.
function TowerBehaviors.find(id: string): BaseTower.TowerBehavior?
	return BY_ID[id]
end

return TowerBehaviors

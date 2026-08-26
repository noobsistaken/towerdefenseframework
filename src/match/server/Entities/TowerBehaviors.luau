--!strict
--[[
	Maps tower ids to their behaviour override, where they have one.

	A tower absent from this table uses BaseTower's defaults, which is the
	expected case: four of the six in the roster appear nowhere here.

	Adding a tower that needs custom behaviour is two steps - write the module
	under Towers/, add a line here - and adding one that does not is zero.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local Splash = require(script.Parent.Towers.Splash)

local BaseTower = require(script.Parent.BaseTower)

local TowerBehaviors = {}

--- Only towers whose behaviour cannot be DERIVED from their config need
--- a line here. Splash is not one of them any more - see `find`.
local BY_ID: { [string]: BaseTower.TowerBehavior } = {}

TowerBehaviors.BY_ID = BY_ID

--- Behaviour for a tower, or nil to use BaseTower's defaults.
---
--- Splash is derived from the definition rather than listed by id:
--- with a twenty-six tower roster, a hand-kept list's failure mode is a
--- new splash tower silently single-targeting because someone forgot
--- the registry line. Config that already says splashRadius > 0 IS the
--- registration.
function TowerBehaviors.find(definition: Types.TowerDefinition): BaseTower.TowerBehavior?
	local override = BY_ID[definition.id]

	if override ~= nil then
		return override
	end

	for _, level in definition.levels do
		if level.splashRadius > 0 then
			return Splash
		end
	end

	return nil
end

return TowerBehaviors

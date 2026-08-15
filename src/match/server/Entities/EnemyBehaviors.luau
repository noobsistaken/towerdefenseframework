--!strict
--[[
	Maps enemy ids to their behaviour override, where they have one.

	Three of the five enemies appear nowhere here - Zombie, Tank and Drifter
	differ from the baseline only in their numbers, so they are pure config.
	That ratio is the D4 claim holding: a behaviour module exists only when
	the value depends on the enemy's own live state, which config cannot
	express.

	Adding an enemy that needs custom behaviour is two steps - write the
	module under Enemies/, add a line here - and adding one that does not is
	zero.
]]

local Runner = require(script.Parent.Enemies.Runner)
local Titan = require(script.Parent.Enemies.Titan)

local BaseEnemy = require(script.Parent.BaseEnemy)

local EnemyBehaviors = {}

local BY_ID: { [string]: BaseEnemy.EnemyBehavior } = {
	Runner = Runner,
	Titan = Titan,
}

EnemyBehaviors.BY_ID = BY_ID

--- Behaviour for an enemy id, or nil to use BaseEnemy's defaults.
function EnemyBehaviors.find(id: string): BaseEnemy.EnemyBehavior?
	return BY_ID[id]
end

return EnemyBehaviors

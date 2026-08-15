--!strict
--[[
	Runner behaviour: accelerates the deeper it gets.

	A Runner that moved at a constant speed is just a Zombie with different
	numbers, which config alone can already express. What config cannot
	express is a speed that depends on the enemy's own state - so this is a
	behaviour module, and the two enemies that need one are the only two that
	have one.

	The threat curve is the point: a Runner is catchable early in the lane and
	very hard to stop near the base, which rewards defending in depth rather
	than stacking everything at the spawn.
]]

local BaseEnemy = require(script.Parent.Parent.BaseEnemy)

--- Extra speed at the very end of the lane. 0.6 means 60% faster arriving at
--- the base than it was leaving the spawn.
local SPRINT_BONUS = 0.6

local Runner: BaseEnemy.EnemyBehavior = {
	id = "Runner",

	speedMultiplier = function(enemy: BaseEnemy.Enemy): number
		-- Normalised against lane length rather than raw studs walked, so a
		-- Runner behaves identically on a 300-stud map and a 900-stud one.
		if enemy.pathLength <= 0 then
			return 1
		end

		local fraction = math.clamp(enemy.progress / enemy.pathLength, 0, 1)

		return 1 + SPRINT_BONUS * fraction
	end,
}

return Runner

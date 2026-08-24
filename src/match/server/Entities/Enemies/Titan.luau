--!strict
--[[
	Titan behaviour: enrages when badly hurt.

	Below the threshold it speeds up sharply. The effect is that chipping a
	Titan down is not the same as killing it - a boss left at 20% health is
	more dangerous than one at 60%, so a defence that can nearly kill one is
	not good enough.

	Like Runner, this is a behaviour rather than config because the value
	depends on the enemy's own live state. A flat speed bonus would be a
	number in Config/Enemies.luau and would need no code at all.
]]

local BaseEnemy = require(script.Parent.Parent.BaseEnemy)

--- Fraction of max health below which the Titan enrages.
local ENRAGE_BELOW = 0.35

--- Speed multiplier once enraged.
local ENRAGE_SPEED = 1.5

--- The one place the threshold is tested. The speed bonus and the visual
--- tell must agree exactly: a boss that looks calm while moving at 1.5x -
--- or glows while moving at baseline - is worse than having no tell.
local function isEnraged(enemy: BaseEnemy.Enemy): boolean
	return enemy:healthFraction() <= ENRAGE_BELOW
end

local Titan: BaseEnemy.EnemyBehavior = {
	id = "Titan",

	speedMultiplier = function(enemy: BaseEnemy.Enemy): number
		return if isEnraged(enemy) then ENRAGE_SPEED else 1
	end,

	enraged = isEnraged,
}

return Titan

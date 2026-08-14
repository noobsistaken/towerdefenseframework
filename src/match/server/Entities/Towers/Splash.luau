--!strict
--[[
	Splash damage behaviour.

	Shared by Mortar and Flak. It reads `splashRadius` off the current level,
	so both towers - and any future one - get splash purely by putting a
	non-zero radius in Config/Towers.luau.

	This is the whole point of D4: six towers in the roster, and exactly one
	behaviour module between them. Lacerator's bleed needs none, because
	applying an effect list is something BaseTower already does.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local BaseTower = require(script.Parent.Parent.BaseTower)
local EnemySimulation = require(script.Parent.Parent.Parent.Simulation.EnemySimulation)

--- Damage retained at the very edge of the blast. Full damage at the centre
--- falling to this at the rim, so positioning a mortar still matters.
local EDGE_DAMAGE = 0.5

local Splash: BaseTower.TowerBehavior = {
	id = "Splash",

	onFire = function(
		tower: BaseTower.Tower,
		simulation: EnemySimulation.Simulation,
		targetId: Types.EnemyId,
		targetPosition: Vector3
	)
		-- The primary target always takes a full hit, even if the radius is
		-- zero, so a mis-configured level degrades to single target rather
		-- than to nothing.
		tower:dealDamage(simulation, targetId, 1)

		local radius = tower:currentLevel().splashRadius

		if radius <= 0 then
			return
		end

		local radiusSquared = radius * radius

		-- Iterating simulation.enemies while dealing damage is safe: damage
		-- only flips the `alive` flag, and the array is not compacted until
		-- collectDead runs at the end of the step.
		for _, enemy in simulation.enemies do
			if enemy.id == targetId or not enemy.alive then
				continue
			end

			-- Splash respects air/ground eligibility. A ground-only mortar
			-- landing splash on aircraft would quietly undo the whole reason
			-- the Hillside category exists.
			if not tower:canTarget(enemy.definition.category) then
				continue
			end

			local offset = simulation:positionOf(enemy) - targetPosition
			local distanceSquared = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z

			if distanceSquared > radiusSquared then
				continue
			end

			local falloff = math.sqrt(distanceSquared) / radius
			tower:dealDamage(simulation, enemy.id, 1 - (1 - EDGE_DAMAGE) * falloff)
		end
	end,
}

return Splash

--!strict
--[[
	Turns a tower's rolled trait ids into the stat multipliers they grant.

	Pure on purpose, like Gacha: a list of ids in, three numbers out, no
	Instances and no player anywhere near it. BaseTower applies the result at
	READ time - range(), beginReload(), dealDamage() - and never writes into
	the shared definition, so a trait cannot corrupt the config every other
	tower reads. That rule lives in Config/Traits.luau; this module is its
	enforcement point.

	Unknown ids multiply by 1 rather than erroring. Trait ids come out of
	persisted player data, and a trait deleted from the roster must degrade a
	saved loadout to "no effect", never crash the placement path.
]]

local Traits = require(script.Parent.Config.Traits)

local TraitEffects = {}

export type Multipliers = {
	damage: number,
	range: number,
	fireRate: number,
}

--- The identity. Shared so "no traits" allocates nothing per tower.
TraitEffects.NONE = table.freeze({
	damage = 1,
	range = 1,
	fireRate = 1,
}) :: Multipliers

--- Combined multipliers for a trait list. Products, so the maths stays right
--- if Traits.SLOTS ever grows past one.
function TraitEffects.multipliers(traitIds: { string }): Multipliers
	if #traitIds == 0 then
		return TraitEffects.NONE
	end

	local damage = 1
	local range = 1
	local fireRate = 1

	for _, id in traitIds do
		local definition = Traits.find(id)

		if definition ~= nil then
			damage *= definition.damage
			range *= definition.range
			fireRate *= definition.fireRate
		end
	end

	return {
		damage = damage,
		range = range,
		fireRate = fireRate,
	}
end

return TraitEffects

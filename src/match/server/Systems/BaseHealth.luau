--!strict
--[[
	The base the players are defending.

	Shared across the whole team - per-player currency, shared base health, as
	specified. Deliberately a separate module from MatchController so that the
	defeat condition has exactly one definition and one place to test.
]]

local BaseHealth = {}
BaseHealth.__index = BaseHealth

export type ChangedListener = (current: number, max: number) -> ()

export type Health = typeof(setmetatable(
	{} :: {
		current: number,
		max: number,
		listeners: { ChangedListener },
	},
	BaseHealth
))

function BaseHealth.new(max: number): Health
	if max <= 0 then
		error(`BaseHealth.new: max must be positive, got {max}`)
	end

	return setmetatable({
		current = max,
		max = max,
		listeners = {},
	}, BaseHealth)
end

function BaseHealth.onChanged(self: Health, listener: ChangedListener): () -> ()
	table.insert(self.listeners, listener)

	return function()
		local index = table.find(self.listeners, listener)

		if index ~= nil then
			table.remove(self.listeners, index)
		end
	end
end

local function notify(self: Health)
	for _, listener in self.listeners do
		listener(self.current, self.max)
	end
end

--- Removes `amount` health. Returns true if this call is what caused defeat,
--- so the caller can end the match exactly once no matter how many enemies
--- leak in the same simulation step.
function BaseHealth.damage(self: Health, amount: number): boolean
	if amount <= 0 or self.current <= 0 then
		return false
	end

	local wasAlive = self.current > 0
	self.current = math.max(0, self.current - amount)

	notify(self)

	return wasAlive and self.current <= 0
end

function BaseHealth.isDefeated(self: Health): boolean
	return self.current <= 0
end

--- Fraction remaining, in [0, 1]. Drives the HUD bar.
function BaseHealth.fraction(self: Health): number
	return math.clamp(self.current / self.max, 0, 1)
end

return BaseHealth

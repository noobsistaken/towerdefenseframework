--!strict
--[[
	A recycling pool of Parts.

	Enemies are created and destroyed constantly - a 40-wave run churns
	thousands - and Instance.new/Destroy is one of the more expensive things
	a Roblox server can do in a loop. Pooling turns that into a table pop and
	a reparent.

	Deliberately dumb: the pool knows nothing about enemies. It hands out
	blank anchored parts and takes them back. Configuring one for a particular
	enemy is EnemyView's job.
]]

local PartPool = {}
PartPool.__index = PartPool

export type Pool = typeof(setmetatable(
	{} :: {
		--- Parts currently checked out, parented into the world.
		--- Kept only so `destroy` can clean up everything.
		active: { [Part]: true },
		--- Parts available for reuse, parented to nil.
		free: { Part },
		--- Where acquired parts are parented.
		container: Instance,
		--- Hard ceiling on retained free parts. Without it, one 500-enemy
		--- boss wave permanently holds 500 parts for the rest of the match.
		maxFree: number,
	},
	PartPool
))

local DEFAULT_MAX_FREE = 128

function PartPool.new(container: Instance, maxFree: number?): Pool
	return setmetatable({
		active = {},
		free = {},
		container = container,
		maxFree = maxFree or DEFAULT_MAX_FREE,
	}, PartPool)
end

local function newPooledPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	-- Enemies must never push players, towers or each other.
	part.CanCollide = false
	part.CanTouch = false
	-- Queryable: tower splash uses GetPartBoundsInRadius against these.
	part.CanQuery = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

--- Hands out a part, reusing a free one when possible.
function PartPool.acquire(self: Pool): Part
	-- An if-expression rather than reassigning the nilable local: Luau does
	-- not refine a variable's declared type through an assignment inside a
	-- branch, so the reassigning form stays `Part?` and fails strict mode.
	local pooled = table.remove(self.free)
	local acquired: Part = if pooled ~= nil then pooled else newPooledPart()

	acquired.Parent = self.container
	self.active[acquired] = true

	return acquired
end

--- Takes a part back. Beyond `maxFree` the part is destroyed rather than
--- retained, so a single huge wave does not pin memory for the whole match.
function PartPool.release(self: Pool, part: Part)
	if self.active[part] == nil then
		return
	end

	self.active[part] = nil

	if #self.free >= self.maxFree then
		part:Destroy()
		return
	end

	-- Clear per-enemy state so a recycled part cannot leak the previous
	-- occupant's attributes to a client watching for them.
	for name in part:GetAttributes() do
		part:SetAttribute(name, nil)
	end

	part.Parent = nil
	table.insert(self.free, part)
end

function PartPool.freeCount(self: Pool): number
	return #self.free
end

function PartPool.destroy(self: Pool)
	for part in self.active do
		part:Destroy()
	end

	for _, part in self.free do
		part:Destroy()
	end

	self.active = {}
	self.free = {}
end

return PartPool

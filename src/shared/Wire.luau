--!strict
--[[
	Conversions between Roblox's Vector3 and the native `vector` that Zap uses
	on the wire.

	These are the same thing at runtime - Roblox's Vector3 IS the native
	vector, and zap's generated code reads `.x`/`.y`/`.z` off values it was
	handed - but luau-lsp models them as distinct types. Without a conversion,
	passing a Vector3 into a zap struct fails with:

	    Expected this to be exactly 'vector', but got 'Vector3'

	Two one-line functions, in one place, so that the boilerplate does not get
	copied into every handler that touches a position. If Luau ever unifies
	the two types, this module is the only thing to delete.
]]

local Wire = {}

--- Roblox Vector3 -> wire vector, for anything going into a Zap struct.
function Wire.toWire(value: Vector3): vector
	return vector.create(value.X, value.Y, value.Z)
end

--- Wire vector -> Roblox Vector3, for anything arriving from a Zap handler.
function Wire.toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

return Wire

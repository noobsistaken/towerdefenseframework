--!strict
--[[
	Binds a component to a Charm atom.

	Charm atoms are callable readers, so this is the whole binding: read once
	for the initial value, then let Charm.subscribe drive every later render.

	KNOWN LIMITATION, and it has bitten twice already. Inferring T through a
	function-typed parameter WIDENS a literal union - `Types.MatchState`
	arrives as plain `string`. React.useState widens it identically, so
	writing the hook out by hand does not help either. Consumers comparing
	against state names therefore take `string`, and the union stays enforced
	where it can do work: on the wire, where Zap generates it, and at the atom
	declaration, where it is annotated.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local React = require(ReplicatedStorage.Packages.React)

local function useAtom<T>(atom: () -> T): T
	local value, setValue = React.useState(atom())

	React.useEffect(function()
		return Charm.subscribe(atom, setValue)
	end, {})

	return value
end

return useAtom

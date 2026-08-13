--!strict
--[[
	Shared type definitions.

	Types live here so the server, the client and the tests all agree on the
	same shapes. In strict mode a mismatch here is a build failure, not a
	runtime surprise - which is the entire reason this project runs strict.
]]

--- Persisted player data. Every field must be DataStore-safe:
--- no Instances, no userdata (Vector3/CFrame/Color3), no functions,
--- no mixed or sparse arrays. Serialise before storing.
export type PlayerData = {
	--- Bumped whenever the shape below changes. See ARCHITECTURE.md.
	Version: number,
	Coins: number,
	Level: number,
	Inventory: { string },
}

export type LeaderboardEntry = {
	name: string,
	score: number,
}

return {}

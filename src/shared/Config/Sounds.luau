--!strict
--[[
	Sound registry.

	EVERY assetId below is deliberately empty. This is the API in place with
	nothing behind it: the server names a sound by key, the client looks it up
	here, and an entry with no asset id plays nothing and logs nothing. Filling
	one in is a one-line change with no code around it.

	That shape is the point. A game that plays no sound because the slots are
	empty is a game waiting for audio; a game that plays no sound because
	nothing calls the sound system is a game that needs the feature building.
	This is the former, and the difference is visible by grepping for
	Net.PlaySound on the server.

	Every key here is a slot in docs/ASSET-MANIFEST.md.
]]

local Sounds = {}

export type SoundDefinition = {
	--- Roblox asset id, as "rbxassetid://123". Empty means silent.
	assetId: string,
	volume: number,
	--- Playback speed is randomised within +/- this each time, so a tower
	--- firing four times a second does not sound like a machine. 0 disables.
	pitchVariance: number,
	--- True to play at a world position, false for a flat 2D cue. Combat
	--- sounds want the former; UI feedback wants the latter, or a click
	--- sounds quiet because the camera happens to be far from the button.
	spatial: boolean,
}

local function definition(volume: number, pitchVariance: number, spatial: boolean): SoundDefinition
	return {
		assetId = "",
		volume = volume,
		pitchVariance = pitchVariance,
		spatial = spatial,
	}
end

local DEFINITIONS: { [string]: SoundDefinition } = {
	-- UI feedback. Flat, because these are about the button not the world.
	TowerPlaced = definition(0.5, 0.05, false),
	TowerUpgraded = definition(0.5, 0.05, false),
	TowerSold = definition(0.45, 0.05, false),
	PlacementRejected = definition(0.4, 0, false),
	ButtonClick = definition(0.3, 0.04, false),

	-- Per-tower fire cues. One key each rather than a shared "tower fired",
	-- because a mortar and a rifle wanting different sounds is the whole
	-- reason a sound system exists.
	Fire_Rifleman = definition(0.25, 0.08, true),
	Fire_Mortar = definition(0.45, 0.06, true),
	Fire_Marksman = definition(0.4, 0.05, true),
	Fire_Flak = definition(0.3, 0.08, true),
	Fire_Ranger = definition(0.28, 0.08, true),
	Fire_Lacerator = definition(0.28, 0.1, true),

	-- Combat.
	EnemyDeath = definition(0.3, 0.12, true),
	BossDeath = definition(0.7, 0, true),
	Splash = definition(0.4, 0.08, true),

	-- Match lifecycle.
	WaveStart = definition(0.6, 0, false),
	WaveCleared = definition(0.55, 0, false),
	BaseDamaged = definition(0.6, 0.05, false),
	Victory = definition(0.8, 0, false),
	Defeat = definition(0.8, 0, false),

	-- Lobby.
	VoteCast = definition(0.35, 0.06, false),
	MatchLaunching = definition(0.7, 0, false),
}

Sounds.DEFINITIONS = DEFINITIONS

--- Key for a tower's fire cue. Centralised so the server and the manifest
--- cannot disagree about the naming convention.
function Sounds.fireKey(towerId: string): string
	return `Fire_{towerId}`
end

--- Non-throwing: an unknown key is silence, never an error. A sound is the
--- least important thing in a frame, and a missing one must never be able to
--- take down a handler that was also doing something that mattered.
function Sounds.find(key: string): SoundDefinition?
	return DEFINITIONS[key]
end

--- Whether a key has real audio behind it yet. The client uses this to skip
--- creating a Sound instance at all for an unfilled slot.
function Sounds.isFilled(key: string): boolean
	local found = DEFINITIONS[key]

	return found ~= nil and found.assetId ~= ""
end

--- Every key, sorted. Used to generate the asset manifest.
local sortedKeys: { string } = {}

for key in DEFINITIONS do
	table.insert(sortedKeys, key)
end

table.sort(sortedKeys)

Sounds.KEYS = table.freeze(sortedKeys)

return Sounds

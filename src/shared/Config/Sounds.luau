--!strict
--[[
	Sound registry.

	Every asset here was PROBED in this experience before being written
	down - audio permissions make an unverified id a silent failure, so the
	rule is: nothing enters this file without a load check. The rbxasset://
	entries ship with the client itself and can never be revoked; the
	rbxassetid:// music tracks are Roblox-published and verified loading.

	An entry with an empty assetId plays nothing and logs nothing - the
	system tolerates silence by design, so removing a sound is deleting a
	string, never touching code.
]]

local Sounds = {}

export type SoundDefinition = {
	--- "rbxasset://..." or "rbxassetid://...". Empty means silent.
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

local function definition(assetId: string, volume: number, pitchVariance: number, spatial: boolean): SoundDefinition
	return {
		assetId = assetId,
		volume = volume,
		pitchVariance = pitchVariance,
		spatial = spatial,
	}
end

-- The probed palette, named once so a swap is one edit.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local SNAP = "rbxasset://sounds/snap.mp3"
local SPLAT = "rbxasset://sounds/splat.wav"
local SLASH = "rbxasset://sounds/swordslash.wav"
local LUNGE = "rbxasset://sounds/swordlunge.wav"
local UNSHEATH = "rbxasset://sounds/unsheath.wav"
local COLLIDE = "rbxasset://sounds/collide.wav"
local BASS = "rbxasset://sounds/bass.wav"
local METAL = "rbxasset://sounds/metal.mp3"
local FLASH = "rbxasset://sounds/flashbulb.wav"
local GLASS = "rbxasset://sounds/glassbreak.wav"
local SPRING = "rbxasset://sounds/short spring sound.wav"
local WATER = "rbxasset://sounds/impact_water.mp3"
local OOF = "rbxasset://sounds/uuhhh.mp3"
local FANFARE = "rbxasset://sounds/victory.wav"

local DEFINITIONS: { [string]: SoundDefinition } = {
	-- UI feedback. Flat, because these are about the button not the world.
	TowerPlaced = definition(SNAP, 0.5, 0.05, false),
	TowerUpgraded = definition(SPRING, 0.5, 0.05, false),
	TowerSold = definition(METAL, 0.45, 0.05, false),
	PlacementRejected = definition(FLASH, 0.4, 0, false),
	ButtonClick = definition(BUTTON, 0.3, 0.04, false),

	-- Per-tower fire cues, one key per tower in the roster. Assigned by
	-- archetype: cracks for rifles, booms for artillery, slashes for the
	-- light stuff, water for the casters.
	Fire_Rifleman = definition(SNAP, 0.2, 0.1, true),
	Fire_Mortar = definition(BASS, 0.5, 0.06, true),
	Fire_Marksman = definition(LUNGE, 0.35, 0.05, true),
	Fire_Flak = definition(COLLIDE, 0.3, 0.08, true),
	Fire_Ranger = definition(SLASH, 0.22, 0.08, true),
	Fire_Lacerator = definition(UNSHEATH, 0.3, 0.1, true),
	Fire_Scout = definition(SNAP, 0.18, 0.12, true),
	Fire_Shotgunner = definition(BASS, 0.3, 0.1, true),
	Fire_Slinger = definition(SLASH, 0.2, 0.1, true),
	Fire_Watchman = definition(LUNGE, 0.25, 0.06, true),
	Fire_Grenadier = definition(BASS, 0.35, 0.08, true),
	Fire_Gunner = definition(SNAP, 0.18, 0.14, true),
	Fire_Frostcaster = definition(WATER, 0.3, 0.08, true),
	Fire_Skirmisher = definition(SLASH, 0.24, 0.08, true),
	Fire_Flaresman = definition(FLASH, 0.3, 0.08, true),
	Fire_Autocannon = definition(COLLIDE, 0.28, 0.1, true),
	Fire_Hexer = definition(PING, 0.25, 0.08, true),
	Fire_Marauder = definition(LUNGE, 0.32, 0.06, true),
	Fire_Longbow = definition(SLASH, 0.28, 0.05, true),
	Fire_Pyromancer = definition(FLASH, 0.32, 0.08, true),
	Fire_Railgunner = definition(BASS, 0.45, 0.04, true),
	Fire_Warden = definition(METAL, 0.35, 0.06, true),
	Fire_Stormcaller = definition(WATER, 0.4, 0.06, true),
	Fire_Executioner = definition(UNSHEATH, 0.35, 0.05, true),
	Fire_Annihilator = definition(BASS, 0.55, 0.04, true),
	Fire_Godhand = definition(LUNGE, 0.45, 0.04, true),

	-- Combat.
	EnemyDeath = definition(SPLAT, 0.3, 0.12, true),
	BossDeath = definition(BASS, 0.7, 0, true),
	Splash = definition(COLLIDE, 0.4, 0.08, true),
	AbilityUsed = definition(COLLIDE, 0.5, 0.05, true),

	-- Match lifecycle.
	WaveStart = definition(UNSHEATH, 0.6, 0, false),
	WaveCleared = definition(FANFARE, 0.5, 0, false),
	BaseDamaged = definition(OOF, 0.6, 0.05, false),
	Victory = definition(FANFARE, 0.8, 0, false),
	Defeat = definition(GLASS, 0.8, 0, false),

	-- Lobby.
	VoteCast = definition(PING, 0.35, 0.06, false),
	MatchLaunching = definition(PING, 0.7, 0, false),
	GachaRoll = definition(SPRING, 0.5, 0.05, false),
	Reroll = definition(SPRING, 0.5, 0.08, false),
	EggShake = definition(FLASH, 0.35, 0.1, false),
	EggCrack = definition(GLASS, 0.7, 0, false),
	EggReveal = definition(FANFARE, 0.6, 0, false),
}

Sounds.DEFINITIONS = DEFINITIONS

--- Looping background music, one track per place. Roblox-published,
--- verified loading here. Started by each place's client entry; swap a
--- track by swapping an id.
Sounds.LOBBY_MUSIC = "rbxassetid://1848354536"
Sounds.MATCH_MUSIC = "rbxassetid://1837879082"
Sounds.MUSIC_VOLUME = 0.12

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

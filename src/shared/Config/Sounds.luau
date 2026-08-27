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
local METAL = "rbxasset://sounds/metal.mp3"
local FLASH = "rbxasset://sounds/flashbulb.wav"
local GLASS = "rbxasset://sounds/glassbreak.wav"
local SPRING = "rbxasset://sounds/short spring sound.wav"
local FANFARE = "rbxasset://sounds/victory.wav"

-- Combat audio, from the catalogue rather than the client bundle. The
-- built-ins contain no firearm at all, so gunfire was a sword swing and a
-- bullet landing was the "oof" - which is exactly what it sounded like.
-- Every id below was probed in this experience before being written down
-- (17 of 17 candidates loaded; the durations in the comments are the
-- measured ones), which is the same rule the rest of this file follows.
--
-- DURATION IS A GAMEPLAY CONSTRAINT here, not trivia. An Autocannon fires
-- several times a second, so its cue has to finish before its next shot or
-- the reports pile into a drone. The 0.43s crack goes on everything fast;
-- the 2.25s rifle report only goes on towers slow enough to let it end.
local GUN_CRACK = "rbxassetid://113450029049580" -- 0.43s, semi-auto rifle
local GUN_RIFLE = "rbxassetid://107440232498563" -- 1.12s, full-bodied rifle
local GUN_HEAVY = "rbxassetid://6975483207" -- 0.62s, .50 Beowulf
local GUN_PISTOL = "rbxassetid://116795388931136" -- 1.27s, indoor Glock
local GUN_SNIPER = "rbxassetid://85038368926762" -- 2.25s, bolt-action
local GUN_SHOTGUN = "rbxassetid://101853572584972" -- 1.78s
local GUN_REVOLVER = "rbxassetid://3810332201" -- 1.52s, S&W M66
local BOOM = "rbxassetid://138533090376585" -- 3.06s, blast
local BOOM_ROCKET = "rbxassetid://70690086887976" -- 3.14s, rocket
local BOOM_MINE = "rbxassetid://101613205127381" -- 2.41s, detonation
local SHOCKWAVE = "rbxassetid://113437569668587" -- 2.89s
local HIT_FLESH = "rbxassetid://133794731281686" -- 0.61s, bullet into a body
local HIT_BODY = "rbxassetid://75492070005287" -- 0.54s, heavier
local HIT_BLUNT = "rbxassetid://94957229024343" -- 0.50s, blunt

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
	-- Fast repeaters take the 0.43s crack, so rapid fire reads as rapid fire
	-- rather than as one continuous noise.
	Fire_Rifleman = definition(GUN_CRACK, 0.18, 0.1, true),
	Fire_Scout = definition(GUN_CRACK, 0.15, 0.14, true),
	Fire_Gunner = definition(GUN_CRACK, 0.15, 0.16, true),
	Fire_Autocannon = definition(GUN_CRACK, 0.16, 0.12, true),
	Fire_Skirmisher = definition(GUN_CRACK, 0.17, 0.1, true),
	Fire_Watchman = definition(GUN_CRACK, 0.18, 0.08, true),

	-- Measured single shots.
	Fire_Ranger = definition(GUN_RIFLE, 0.2, 0.08, true),
	Fire_Longbow = definition(GUN_RIFLE, 0.22, 0.06, true),
	Fire_Slinger = definition(GUN_PISTOL, 0.18, 0.1, true),
	Fire_Hexer = definition(GUN_PISTOL, 0.18, 0.1, true),
	Fire_Flaresman = definition(GUN_REVOLVER, 0.22, 0.08, true),
	Fire_Lacerator = definition(GUN_HEAVY, 0.24, 0.1, true),
	Fire_Marauder = definition(GUN_HEAVY, 0.26, 0.08, true),
	Fire_Warden = definition(GUN_HEAVY, 0.26, 0.06, true),

	-- Slow and heavy: these fire rarely enough to let a long report finish.
	Fire_Marksman = definition(GUN_SNIPER, 0.28, 0.04, true),
	Fire_Railgunner = definition(GUN_SNIPER, 0.34, 0.03, true),
	Fire_Executioner = definition(GUN_SNIPER, 0.3, 0.04, true),
	Fire_Shotgunner = definition(GUN_SHOTGUN, 0.26, 0.08, true),
	Fire_Flak = definition(GUN_SHOTGUN, 0.24, 0.08, true),

	-- Artillery, and the casters that land like it.
	Fire_Mortar = definition(BOOM_ROCKET, 0.3, 0.06, true),
	Fire_Grenadier = definition(BOOM_MINE, 0.28, 0.08, true),
	Fire_Annihilator = definition(BOOM, 0.34, 0.04, true),
	Fire_Godhand = definition(BOOM, 0.32, 0.04, true),
	Fire_Pyromancer = definition(BOOM_MINE, 0.24, 0.08, true),
	Fire_Stormcaller = definition(SHOCKWAVE, 0.26, 0.06, true),
	Fire_Frostcaster = definition(SHOCKWAVE, 0.22, 0.08, true),

	-- Combat. A bullet arriving is a bullet arriving: the splat and the
	-- "oof" doing this job are what made every exchange sound like a
	-- playground rather than a firefight.
	EnemyDeath = definition(HIT_FLESH, 0.26, 0.12, true),
	BossDeath = definition(BOOM, 0.5, 0, true),
	Splash = definition(BOOM_MINE, 0.3, 0.08, true),
	AbilityUsed = definition(SHOCKWAVE, 0.4, 0.05, true),

	-- Match lifecycle.
	WaveStart = definition(HIT_BLUNT, 0.5, 0, false),
	WaveCleared = definition(FANFARE, 0.5, 0, false),
	BaseDamaged = definition(HIT_BODY, 0.55, 0.05, false),
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

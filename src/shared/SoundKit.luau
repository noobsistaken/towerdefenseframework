--!strict
--[[
	Plays the sounds the game asks for. Shared by both places' clients -
	the match place forwards its old Audio/SoundController path here, and
	the lobby (egg cracks, roll springs, button clicks) calls it directly.

	The server names a key, this resolves it against Config/Sounds.luau,
	and an unfilled slot does nothing at all - no Sound instance, no
	warning, no cost. Silence is the correct behaviour for an unfilled
	slot: warning on every unfilled key would produce a console full of
	noise and train whoever reads it to ignore it.

	Client-only by contract: everything here touches SoundService, and the
	server must never require it.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local SoundKit = {}

--- How long a played Sound lingers before cleanup. Longer than any plausible
--- cue, since Debris only bounds the worst case - a finished Sound is
--- inaudible either way.
local CLEANUP_SECONDS = 6

--- Emitter parts are anchored and collision-free, so a spatial cue cannot
--- push a player around or fall through the world.
local function newEmitter(position: Vector3): Part
	local emitter = Instance.new("Part")
	emitter.Name = "SoundEmitter"
	emitter.Size = Vector3.one
	emitter.CFrame = CFrame.new(position)
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Parent = workspace

	return emitter
end

local sfxEnabled = true

--- Mirrors the player's setting. Held here rather than read from a profile
--- because the client cannot see profiles, and a sound decision has to be
--- made without a round trip. Music is deliberately NOT gated by this: the
--- setting is named Sfx, and muting the soundtrack under it would be the
--- setting lying about its own name.
function SoundKit.setEnabled(enabled: boolean)
	sfxEnabled = enabled
end

--- Plays `key`, optionally at a world position.
---
--- Never raises and never yields. It is called from network handlers that are
--- also doing work that matters, and a sound must not be able to interrupt
--- them.
function SoundKit.play(key: string, position: Vector3?)
	if not sfxEnabled then
		return
	end

	local definition = Sounds.find(key)

	if definition == nil or definition.assetId == "" then
		-- Unfilled slot. Silence, by design.
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = definition.assetId
	sound.Volume = definition.volume

	if definition.pitchVariance > 0 then
		-- Varied per play so a tower firing several times a second does not
		-- sound mechanical.
		sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * definition.pitchVariance
	end

	if definition.spatial and position ~= nil then
		local emitter = newEmitter(position)
		sound.Parent = emitter
		Debris:AddItem(emitter, CLEANUP_SECONDS)
	else
		-- SoundService, not PlayerGui: a 2D cue should not be affected by
		-- where the camera is or whether a GUI got destroyed mid-playback.
		sound.Parent = SoundService
		Debris:AddItem(sound, CLEANUP_SECONDS)
	end

	sound:Play()
end

local music: Sound? = nil

--- Starts (or swaps) the looping background track. One at a time, quiet by
--- config, and restart-safe: starting the track that is already playing is
--- a no-op rather than a stutter.
function SoundKit.playMusic(assetId: string)
	local current = music

	if current ~= nil and current.SoundId == assetId and current.IsPlaying then
		return
	end

	if current ~= nil then
		current:Destroy()
		music = nil
	end

	if assetId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = assetId
	sound.Volume = Sounds.MUSIC_VOLUME
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()

	music = sound
end

return SoundKit

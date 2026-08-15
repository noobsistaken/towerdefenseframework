--!strict
--[[
	Plays the sounds the server asks for.

	The whole client half of the audio system. The server names a key, this
	resolves it against Config/Sounds.luau, and an unfilled slot does nothing
	at all - no Sound instance, no warning, no cost.

	Silence is the correct behaviour for an unfilled slot, and it is worth
	saying why rather than treating it as a stub. The alternative - warning on
	every unfilled key - would produce a console full of noise on every frame
	of a game whose audio has not been recorded yet, and would train whoever
	is reading that console to ignore it.

	Respects the player's SFX setting, which is the one thing here the server
	does not decide.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local SoundController = {}

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
--- made without a round trip.
function SoundController.setEnabled(enabled: boolean)
	sfxEnabled = enabled
end

--- Plays `key`, optionally at a world position.
---
--- Never raises and never yields. It is called from network handlers that are
--- also doing work that matters, and a sound must not be able to interrupt
--- them.
function SoundController.play(key: string, position: Vector3?)
	if not sfxEnabled then
		return
	end

	local definition = Sounds.find(key)

	if definition == nil or definition.assetId == "" then
		-- Unfilled slot. This is the expected path until audio is recorded.
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

return SoundController

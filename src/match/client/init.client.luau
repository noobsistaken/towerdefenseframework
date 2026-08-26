--!strict
--[[
	Match place client entry point.

	Responsibilities, in order:
	  1. Hold client state in Charm atoms.
	  2. Bind the networking schema's client handlers (net/schema.zap).
	  3. Start the placement controller.
	  4. Mount the React tree.

	Feature logic goes in modules under src/match/client/.

	The client renders and takes input. It holds no authoritative state: every
	replicated atom below is a copy the server owns, and nothing here decides
	anything the server has not already decided.
]]

local RunService = game:GetService("RunService")

local Places = require(game:GetService("ReplicatedStorage").Shared.Config.Places)

-- The same gate the lobby entries carry, for the same reason: the dev window
-- syncs the full test superset, so BOTH entries exist in one tree and only
-- the role - or in production, the place id - may decide which one runs.
if not Places.shouldBoot("Match", RunService:IsStudio(), game.PlaceId) then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Wire = require(ReplicatedStorage.Shared.Wire)

local Bursts = require(script.Effects.Bursts)
local EnemyVisuals = require(script.Effects.EnemyVisuals)
local Hud = require(script.UI.Hud)
local PlacementController = require(script.Placement.PlacementController)
local SoundController = require(script.Audio.SoundController)
local Tracers = require(script.Effects.Tracers)
local atoms = require(script.State.atoms)

local localPlayer = Players.LocalPlayer
local janitor = Janitor.new()

--- How long a placement refusal stays on screen.
local REJECTION_SECONDS = 2

-- ---------------------------------------------------------------------------
-- Networking
--
-- These handlers are the ONLY writers to the replicated atoms. Keeping every
-- write in one place is what makes "the client holds a replica" checkable by
-- reading a single file rather than auditing the whole tree.
-- ---------------------------------------------------------------------------

janitor:Add(
	Net.MatchStateChanged.On(function(value)
		atoms.matchState(value.state)
		atoms.waveNumber(value.waveNumber)
		atoms.phaseEndsAt(value.phaseEndsAt)
		atoms.endless(value.endless)
	end),
	true
)

janitor:Add(
	Net.BaseHealthChanged.On(function(value)
		atoms.baseHealth(value.current)
		atoms.baseHealthMax(value.max)
	end),
	true
)

janitor:Add(
	Net.CashChanged.On(function(value)
		atoms.cash(value.cash)
	end),
	true
)

janitor:Add(
	Net.PlacementRejected.On(function(value)
		atoms.placementRejection(value.reason)

		-- Cleared by whichever refusal is newest. Comparing before clearing
		-- stops an older timer from wiping a fresher message.
		local shown = value.reason

		task.delay(REJECTION_SECONDS, function()
			if atoms.placementRejection() == shown then
				atoms.placementRejection(nil)
			end
		end)
	end),
	true
)

janitor:Add(
	Net.TowerFired.On(function(value)
		Tracers.draw(value.towerId, Wire.toVector3(value.targetPosition))
	end),
	true
)

janitor:Add(
	Net.MatchEnded.On(function(value)
		atoms.matchResult({
			won = value.won,
			wavesCleared = value.wavesCleared,
			coinsAwarded = value.coinsAwarded,
			xpAwarded = value.xpAwarded,
		})

		SoundController.play(if value.won then "Victory" else "Defeat")
	end),
	true
)

janitor:Add(
	Net.PlaySound.On(function(value)
		-- The position is optional on the wire: a 2D cue like a wave start
		-- has nowhere to be.
		local position = if value.position ~= nil then Wire.toVector3(value.position) else nil

		SoundController.play(value.soundKey, position)
	end),
	true
)

-- ---------------------------------------------------------------------------
-- Clock
--
-- One shared ticking atom rather than a timer inside the countdown component.
-- A per-component timer would re-render on its own schedule and drift out of
-- step with every other countdown on screen.
-- ---------------------------------------------------------------------------

task.spawn(function()
	while true do
		atoms.clock(os.time())
		task.wait(1)
	end
end)

-- ---------------------------------------------------------------------------
-- Initial state
--
-- Fetched rather than waited for. A player joining mid-match would otherwise
-- see an empty HUD until the next broadcast, which for an untimed phase could
-- be a whole wave away.
-- ---------------------------------------------------------------------------

task.spawn(function()
	local snapshot = Net.GetMatchSnapshot.Call({})

	atoms.matchState(snapshot.state)
	atoms.mapId(snapshot.mapId)
	atoms.waveNumber(snapshot.waveNumber)
	atoms.phaseEndsAt(snapshot.phaseEndsAt)
	atoms.endless(snapshot.endless)
	atoms.baseHealth(snapshot.baseHealth)
	atoms.baseHealthMax(snapshot.baseHealthMax)
	atoms.cash(snapshot.cash)
	atoms.unlockedTowers(snapshot.unlockedTowers)
	SoundController.setEnabled(snapshot.sfxEnabled)
end)

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

PlacementController.start()
janitor:Add(PlacementController.stop, true)

-- Health bars and damage numbers. Driven entirely by the Health attribute on
-- each enemy part, so this needs no network messages of its own (D5).
janitor:Add(EnemyVisuals.start(), true)
janitor:Add(Bursts.start(), true)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui
janitor:Add(screenGui, "Destroy")

local root = ReactRoblox.createRoot(Instance.new("Folder"))
root:render(ReactRoblox.createPortal(React.createElement(Hud), screenGui))

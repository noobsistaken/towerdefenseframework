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
local Theme = require(ReplicatedStorage.Shared.Theme)
local Wire = require(ReplicatedStorage.Shared.Wire)

local Bursts = require(script.Effects.Bursts)
local EnemyVisuals = require(script.Effects.EnemyVisuals)
local AdminConsole = require(ReplicatedStorage.Shared.AdminConsole)
local PlayerRoster = require(ReplicatedStorage.Shared.PlayerRoster)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local useAtom = require(ReplicatedStorage.Shared.useAtom)
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
			tokensAwarded = value.tokensAwarded,
		})

		SoundController.play(if value.won then "Victory" else "Defeat")
	end),
	true
)

janitor:Add(
	Net.RosterChanged.On(function(value)
		atoms.roster(value.entries)
	end),
	true
)

janitor:Add(
	Net.AbilityUsed.On(function(value)
		local position = Wire.toVector3(value.position)

		SoundController.play("AbilityUsed", position)
		Bursts.emit(position + Vector3.new(0, 3, 0), Theme.ACCENT, 24)

		-- The expanding ring, when the ability has an area to show.
		if value.radius > 0 then
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Ball
			ring.Size = Vector3.new(1, 1, 1)
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Material = Enum.Material.Neon
			ring.Color = Theme.ACCENT
			ring.Transparency = 0.5
			ring.CFrame = CFrame.new(position)
			ring.Parent = workspace

			local tween = game:GetService("TweenService"):Create(
				ring,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(value.radius * 2, value.radius * 2, value.radius * 2), Transparency = 1 }
			)
			tween:Play()
			tween.Completed:Once(function()
				ring:Destroy()
			end)
		end
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
	atoms.loadout(snapshot.loadout)
	SoundController.setEnabled(snapshot.sfxEnabled)
end)

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

PlacementController.start()
janitor:Add(PlacementController.stop, true)

-- The battle soundtrack, quiet and looping. Not gated by the SFX setting:
-- that setting is named Sfx, and muting the soundtrack under it would be
-- the setting lying about its own name.
SoundController.playMusic(Sounds.MATCH_MUSIC)

-- The custom player list replaces the Roblox one. pcall because the core
-- gui registry can refuse very early in a session's life.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local function RosterMount()
	return React.createElement(PlayerRoster.Panel, { roster = useAtom(atoms.roster) })
end

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
root:render(ReactRoblox.createPortal(
	React.createElement(React.Fragment, nil, {
		hud = React.createElement(Hud),
		roster = React.createElement(RosterMount),
		-- F2. Renders only for Config/Admins.luau accounts; the server
		-- re-checks regardless. Cash exists only here, so it is offered.
		admin = React.createElement(AdminConsole, { showCash = true, onGranted = nil }),
	}),
	screenGui
))

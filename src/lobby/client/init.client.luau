--!strict
--[[
	Lobby client entry point.

	Responsibilities, in order:
	  1. Decide whether this place should run a lobby client at all.
	  2. Bind the networking schema's client handlers.
	  3. Mount the React tree.

	The net handlers below are the ONLY writers to the replicated atoms.
	Keeping every write in one place is what makes "the client holds a replica"
	checkable by reading a single file rather than auditing the whole tree.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local Places = require(ReplicatedStorage.Shared.Config.Places)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local LobbyUI = require(script.UI.LobbyUI)
local atoms = require(script.State.atoms)

-- Mirrors the guard in the lobby server entry. The test place mounts both
-- clients so luau-lsp can resolve every require from one sourcemap; without
-- this, opening it would mount the lobby UI on top of the match HUD.
if not Places.shouldBoot("Lobby", RunService:IsStudio()) then
	return
end

local localPlayer = Players.LocalPlayer
local janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Networking
-- ---------------------------------------------------------------------------

janitor:Add(
	Net.LobbyStateChanged.On(function(value)
		atoms.lobbyState(value.state)
		atoms.secondsRemaining(value.secondsRemaining)
		atoms.playerCount(value.playerCount)
		atoms.readyCount(value.readyCount)

		-- A fresh state change means the lobby recovered, so a stale failure
		-- message would be actively misleading.
		if value.state ~= "Launching" then
			atoms.failureReason(nil)
		end
	end),
	true
)

janitor:Add(
	Net.VoteTallyChanged.On(function(value)
		atoms.mapTallies(value.mapTallies)
		atoms.difficultyTallies(value.difficultyTallies)
		atoms.winningMapId(value.winningMapId)
		atoms.winningDifficultyId(value.winningDifficultyId)
	end),
	true
)

janitor:Add(
	Net.MatchmakingFailed.On(function(value)
		atoms.failureReason(value.reason)

		-- The lobby is going back to Gathering, so this player is no longer
		-- ready. Leaving the button lit would misrepresent the server.
		atoms.isReady(false)
	end),
	true
)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Lobby"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui
janitor:Add(screenGui, "Destroy")

local root = ReactRoblox.createRoot(Instance.new("Folder"))
janitor:Add(function()
	root:unmount()
end, true)

root:render(ReactRoblox.createPortal(React.createElement(LobbyUI), screenGui))

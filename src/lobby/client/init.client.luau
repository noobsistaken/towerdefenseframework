--!strict
--[[
	Lobby client entry point.

	Responsibilities, in order:
	  1. Decide whether this place should run a lobby client at all.
	  2. Bind the networking schema's client handlers.
	  3. Mount the React tree.

	The net handlers below write the replicated atoms; the one sanctioned
	exception is the gacha panels in LobbyUI, which patch the profile atoms
	with balances the server just RETURNED from a funct call - still server
	data, just arriving as a reply rather than an event.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)
local Net = require(ReplicatedStorage.Net)
local Places = require(ReplicatedStorage.Shared.Config.Places)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local LobbyUI = require(script.UI.LobbyUI)
local atoms = require(script.State.atoms)

-- Mirrors the guard in the lobby server entry. The test place mounts both
-- clients so luau-lsp can resolve every require from one sourcemap; without
-- this, opening it would mount the lobby UI on top of the match HUD.
if not Places.shouldBoot("Lobby", RunService:IsStudio(), game.PlaceId) then
	return
end

local localPlayer = Players.LocalPlayer
local janitor = Janitor.new()

-- The hub soundtrack, quiet and looping, from the first frame.
SoundKit.playMusic(Sounds.LOBBY_MUSIC)

-- ---------------------------------------------------------------------------
-- Networking
-- ---------------------------------------------------------------------------

janitor:Add(
	Net.LobbyStateChanged.On(function(value)
		atoms.lobbyState(value.state)
		atoms.playerCount(value.playerCount)

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
	end),
	true
)

-- Profile fetch, retried until a REAL profile answers. The server's reply
-- says loaded=false when the ProfileStore session was not up in time - a
-- slow handoff from a match server can outrun its bounded wait - and
-- treating that as data would latch an empty collection for the whole
-- session. Afterwards the roll replies keep the hot numbers current.
task.spawn(function()
	while true do
		local profile = Net.GetLobbyProfile.Call({})

		if profile.loaded then
			atoms.coins(profile.coins)
			atoms.rerollTokens(profile.rerollTokens)
			atoms.level(profile.level)
			atoms.xp(profile.xp)
			atoms.unlockedTowers(profile.unlockedTowers)
			atoms.loadout(profile.loadout)

			local map: { [string]: string } = {}

			for _, pair in profile.traits do
				map[pair.towerId] = pair.traitId
			end

			atoms.traits(map)
			atoms.profileLoaded(true)

			return
		end

		-- Unbounded on purpose: the session can arrive minutes late after a
		-- crashed match server, and a poll this slow costs nothing.
		task.wait(5)
	end
end)

-- ---------------------------------------------------------------------------
-- Areas
--
-- The client tracks which walk-in area its OWN character stands in, from
-- the same shared layout the server built the pads from. Purely
-- presentational: the panels it opens send requests the server
-- re-validates against positions IT owns, so lying here earns nothing.
-- ---------------------------------------------------------------------------

local SCAN_INTERVAL = 0.15
local scanAccumulator = 0

janitor:Add(
	RunService.Heartbeat:Connect(function(deltaTime: number)
		scanAccumulator += deltaTime

		if scanAccumulator < SCAN_INTERVAL then
			return
		end

		scanAccumulator = 0

		local character = localPlayer.Character
		local root = if character ~= nil then character.PrimaryPart else nil
		local area = if root ~= nil then LobbyZones.resolveArea(root.Position) else nil

		if area ~= atoms.activeArea() then
			atoms.activeArea(area)

			-- Walking out of the game area withdraws your votes server-side;
			-- the local highlights must not outlive them.
			if area ~= "Game" then
				atoms.myMapVote(nil)
				atoms.myDifficultyVote(nil)
			end
		end
	end),
	"Disconnect"
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

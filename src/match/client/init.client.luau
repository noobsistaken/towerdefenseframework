--!strict
--[[
	Match place client entry point.

	Responsibilities, in order:
	  1. Hold client state in Charm atoms.
	  2. Bind the networking schema's client handlers (net/schema.zap).
	  3. Mount the React tree.

	Feature logic goes in modules under src/match/client/.

	The client renders and takes input. It holds no authoritative state: every
	atom below is a replica the server owns, and nothing here decides anything
	the server has not already decided.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local Hud = require(script.UI.Hud)
local atoms = require(script.State.atoms)

local localPlayer = Players.LocalPlayer
local janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Networking
--
-- These handlers are the ONLY writers to the atoms. Keeping every write in
-- one place is what makes "the client holds a replica" checkable by reading
-- a single file rather than auditing the whole tree.
-- ---------------------------------------------------------------------------

janitor:Add(
	Net.MatchStateChanged.On(function(value)
		atoms.matchState(value.state)
		atoms.waveNumber(value.waveNumber)
		atoms.phaseEndsAt(value.phaseEndsAt)
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
	atoms.waveNumber(snapshot.waveNumber)
	atoms.phaseEndsAt(snapshot.phaseEndsAt)
	atoms.baseHealth(snapshot.baseHealth)
	atoms.baseHealthMax(snapshot.baseHealthMax)
	atoms.cash(snapshot.cash)
end)

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

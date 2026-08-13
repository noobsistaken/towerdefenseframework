--!strict
--[[
	Client entry point.

	Responsibilities, in order:
	  1. Hold client state in Charm atoms.
	  2. Bind the networking schema's client handlers (net/schema.zap).
	  3. Mount the React tree.

	Feature logic goes in modules under src/client/.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local localPlayer = Players.LocalPlayer
local janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- State. Charm atoms are the single source of truth on the client; React
-- reads them, nothing else stores a second copy.
-- ---------------------------------------------------------------------------

local scoreAtom = Charm.atom(0)

-- ---------------------------------------------------------------------------
-- Networking
-- ---------------------------------------------------------------------------

janitor:Add(
	Net.PlayerScoreChanged.On(function(value: { player: Player, score: number })
		if value.player == localPlayer then
			scoreAtom(value.score)
		end
	end),
	true
)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

-- No return annotation: `React.ReactNode` does not survive Wally's re-export
-- link file (see the GOTCHA note in src/server/init.server.luau). Strict mode
-- infers the element type here, so nothing is lost.
local function ScoreLabel()
	local score, setScore = React.useState(scoreAtom())

	React.useEffect(function()
		return Charm.subscribe(scoreAtom, setScore)
	end, {})

	return React.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = `Coins: {score}`,
		TextScaled = true,
	})
end

local root = ReactRoblox.createRoot(Instance.new("Folder"))
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Main"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui
janitor:Add(screenGui, "Destroy")

root:render(ReactRoblox.createPortal(React.createElement(ScoreLabel), screenGui))

--!strict
--[[
	Builds the lobby world at runtime.

	Same approach as MapBuilder and for the same reason: geometry as code is
	diffable and agent-editable, where a committed .rbxmx is neither.

	Deliberately plain. The lobby is a room with a floor, a spawn and a sign;
	everything a player actually does here happens in the UI. Every part is a
	placeholder and appears in the asset manifest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Config.Difficulty)
local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)
local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)
local Poll = require(ReplicatedStorage.Shared.Poll)

local LobbyBuilder = {}

--- Vote boards by map id, for updateZoneBoards.
export type ZoneBoards = { [string]: TextLabel }

export type BuiltLobby = {
	folder: Folder,
	spawn: SpawnLocation,
}

--- The fixed 120-stud floor predates the zone row. Five maps of zones
--- outspan it, and a zone the resolver counts but the floor does not
--- cover would be a vote you fall off the world to cast - so the width
--- derives from the zones the floor exists to hold.
local FLOOR_MARGIN = 12

local function floorSize(): Vector3
	local width = 120

	for _, zone in LobbyZones.zones() do
		width = math.max(width, 2 * (math.abs(zone.center.X) + zone.size.X / 2 + FLOOR_MARGIN))
	end

	return Vector3.new(width, 4, 120)
end
local FLOOR_COLOR = Color3.fromRGB(64, 70, 82)
local TRIM_COLOR = Color3.fromRGB(96, 104, 120)

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

--- Clears any previous build, so a hot reload in Studio does not stack two
--- lobbies on top of each other.
local function clear(name: string)
	local existing = workspace:FindFirstChild(name)

	if existing ~= nil then
		existing:Destroy()
	end
end

function LobbyBuilder.build(): BuiltLobby
	clear("Lobby")

	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- Floor, top surface at y = 0 to match the convention every map uses.
	local size = floorSize()

	newPart("Floor", size, CFrame.new(0, -size.Y / 2, 0), FLOOR_COLOR, folder)

	-- Low walls, purely so the space reads as a room rather than a slab.
	local halfX = size.X / 2
	local halfZ = size.Z / 2
	local wall = Vector3.new(size.X, 8, 2)

	newPart("WallNorth", wall, CFrame.new(0, 4, -halfZ), TRIM_COLOR, folder)
	newPart("WallSouth", wall, CFrame.new(0, 4, halfZ), TRIM_COLOR, folder)
	newPart("WallEast", Vector3.new(2, 8, size.Z), CFrame.new(halfX, 4, 0), TRIM_COLOR, folder)
	newPart("WallWest", Vector3.new(2, 8, size.Z), CFrame.new(-halfX, 4, 0), TRIM_COLOR, folder)

	-- An explicit SpawnLocation rather than relying on Roblox's fallback.
	-- Without one, characters spawn at the origin - which on some maps is on
	-- the lane itself.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 30)
	spawn.Color = Color3.fromRGB(120, 160, 200)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	return {
		folder = folder,
		spawn = spawn,
	}
end

--- Colour per difficulty pad. Indexed by id with a grey fallback so an
--- unknown difficulty still renders rather than erroring the build.
local PAD_COLORS: { [string]: Color3 } = {
	Casual = Color3.fromRGB(96, 190, 120),
	Normal = Color3.fromRGB(222, 198, 100),
	Nightmare = Color3.fromRGB(205, 88, 88),
}

local PAD_FALLBACK = Color3.fromRGB(140, 144, 152)

--- The walk-in vote zones, from the shared layout the resolver uses - build
--- and resolution reading the SAME data is what makes "the floor you stand
--- on is your vote" true rather than approximately true.
---
--- Each zone: a raised pad in the map's ground colour, a billboard naming
--- the map and counting its votes (the returned labels; LobbyController
--- updates them through updateZoneBoards), and one small pad per
--- difficulty along the near edge.
function LobbyBuilder.buildZones(parent: Instance): ZoneBoards
	local folder = Instance.new("Folder")
	folder.Name = "Zones"
	folder.Parent = parent

	local boards: ZoneBoards = {}

	for _, zone in LobbyZones.zones() do
		local map = MapRegistry.find(zone.mapId)
		local color = if map ~= nil then map.groundColor else PAD_FALLBACK

		-- Slightly proud of the floor so the zone reads as a place, and thin
		-- enough that walking on feels flat.
		local pad = newPart(
			`Zone_{zone.mapId}`,
			Vector3.new(zone.size.X, 0.4, zone.size.Z),
			CFrame.new(zone.center.X, 0.2, zone.center.Z),
			color,
			folder
		)
		pad.CanQuery = false

		local sign = Instance.new("BillboardGui")
		sign.Name = "Board"
		sign.Size = UDim2.fromScale(14, 4)
		sign.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
		sign.AlwaysOnTop = false
		sign.MaxDistance = 220
		sign.Adornee = pad
		sign.Parent = pad

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = if map ~= nil then map.displayName else zone.mapId
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(240, 240, 240)
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.6
		label.Parent = sign

		boards[zone.mapId] = label

		for _, zonePad in zone.pads do
			local difficultyPad = newPart(
				`Pad_{zone.mapId}_{zonePad.difficultyId}`,
				Vector3.new(zonePad.size.X, 0.5, zonePad.size.Z),
				CFrame.new(zonePad.center.X, 0.45, zonePad.center.Z),
				PAD_COLORS[zonePad.difficultyId] or PAD_FALLBACK,
				folder
			)
			difficultyPad.CanQuery = false

			local preset = Difficulty.find(zonePad.difficultyId)

			local padSign = Instance.new("BillboardGui")
			padSign.Size = UDim2.fromScale(6, 1.6)
			padSign.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
			padSign.MaxDistance = 120
			padSign.Adornee = difficultyPad
			padSign.Parent = difficultyPad

			local padLabel = Instance.new("TextLabel")
			padLabel.Size = UDim2.fromScale(1, 1)
			padLabel.BackgroundTransparency = 1
			padLabel.Text = if preset ~= nil then preset.displayName else zonePad.difficultyId
			padLabel.TextScaled = true
			padLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
			padLabel.Font = Enum.Font.GothamMedium
			padLabel.TextStrokeTransparency = 0.6
			padLabel.Parent = padSign
		end
	end

	return boards
end

--- Repaints every zone board with its live vote count, marking the winner.
--- Server-side text on server-built boards: it replicates for free, and the
--- client needs no vote UI at all.
function LobbyBuilder.updateZoneBoards(boards: ZoneBoards, tallies: { Poll.Tally }, winningId: string)
	for _, tally in tallies do
		-- Annotated optional: indexing a map type yields the value type, not
		-- an optional, so the nil guard below needs the honest annotation.
		local label: TextLabel? = boards[tally.option]

		if label ~= nil then
			local map = MapRegistry.find(tally.option)
			local name = if map ~= nil then map.displayName else tally.option
			local crown = if tally.option == winningId then " \u{2605}" else ""

			label.Text = `{name}{crown}\n{tally.votes} vote{if tally.votes == 1 then "" else "s"}`
		end
	end
end

return LobbyBuilder

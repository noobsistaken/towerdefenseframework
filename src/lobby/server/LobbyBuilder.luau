--!strict
--[[
	Builds the lobby world at runtime.

	Same approach as MapBuilder and for the same reason: geometry as code is
	diffable and agent-editable, where a committed .rbxmx is neither.

	Deliberately plain. The lobby is a room with a floor, a spawn and a sign;
	everything a player actually does here happens in the UI. Every part is a
	placeholder and appears in the asset manifest.
]]

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local LobbyBuilder = {}

export type BuiltLobby = {
	folder: Folder,
	spawn: SpawnLocation,
}

local FLOOR_SIZE = Vector3.new(120, 4, 120)
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
	newPart("Floor", FLOOR_SIZE, CFrame.new(0, -FLOOR_SIZE.Y / 2, 0), FLOOR_COLOR, folder)

	-- Low walls, purely so the space reads as a room rather than a slab.
	local half = FLOOR_SIZE.X / 2
	local wall = Vector3.new(FLOOR_SIZE.X, 8, 2)

	newPart("WallNorth", wall, CFrame.new(0, 4, -half), TRIM_COLOR, folder)
	newPart("WallSouth", wall, CFrame.new(0, 4, half), TRIM_COLOR, folder)
	newPart("WallEast", Vector3.new(2, 8, FLOOR_SIZE.Z), CFrame.new(half, 4, 0), TRIM_COLOR, folder)
	newPart("WallWest", Vector3.new(2, 8, FLOOR_SIZE.Z), CFrame.new(-half, 4, 0), TRIM_COLOR, folder)

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

--- A plinth per map, so the lobby shows what is being voted on in the world
--- as well as in the UI. Cosmetic only - the vote lives in LobbyController.
function LobbyBuilder.buildMapPlinths(mapIds: { string }, registry: { [string]: Types.MapConfig }, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MapPlinths"
	folder.Parent = parent

	local spacing = 22
	local startX = -((#mapIds - 1) * spacing) / 2

	for index, id in mapIds do
		local map = registry[id]

		if map == nil then
			continue
		end

		local x = startX + (index - 1) * spacing
		local plinth = newPart(`Plinth_{id}`, Vector3.new(16, 6, 16), CFrame.new(x, 3, -30), map.groundColor, folder)

		local sign = Instance.new("SurfaceGui")
		sign.Face = Enum.NormalId.Top
		sign.CanvasSize = Vector2.new(200, 200)
		sign.Parent = plinth

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = map.displayName
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(240, 240, 240)
		label.Font = Enum.Font.GothamBold
		label.Parent = sign
	end
end

return LobbyBuilder

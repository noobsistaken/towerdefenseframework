--!strict
--[[
	Builds the lobby hub at runtime.

	Same approach as MapBuilder and for the same reason: geometry as code is
	diffable and agent-editable, where a committed .rbxmx is neither.

	The hub is a room with a central spawn and three walk-in areas drawn
	from the SAME shared layout the server scans and the client's panels
	key off (LobbyZones) - build and detection reading one table is what
	makes "the pad you stand on is the panel you see" true rather than
	approximately true.

	Store-bought dressing: each area may have a prop model waiting in
	ServerStorage.StationProps named by area id (inserted through the usual
	quarantine pipeline - scripts stripped before they ever enter the
	place). Props are cloned onto the area if present and skipped if not,
	so a fresh clone of the repo still builds a working, plainer hub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LobbyZones = require(ReplicatedStorage.Shared.LobbyZones)

local LobbyBuilder = {}

export type BuiltLobby = {
	folder: Folder,
	spawn: SpawnLocation,
}

local FLOOR_SIZE = Vector3.new(140, 4, 120)
local FLOOR_COLOR = Color3.fromRGB(64, 70, 82)
local TRIM_COLOR = Color3.fromRGB(96, 104, 120)

--- Colour per area, so the three read differently from across the room and
--- the panels can echo the same identity on screen.
local AREA_COLORS: { [string]: Color3 } = {
	Game = Color3.fromRGB(96, 176, 255),
	Gacha = Color3.fromRGB(214, 172, 84),
	Reroll = Color3.fromRGB(158, 110, 208),
}

local AREA_FALLBACK = Color3.fromRGB(140, 144, 152)

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

--- The prop model for one area, cloned from the quarantined store assets in
--- ServerStorage.StationProps. Nil when the place has none - a fresh clone
--- of the repo builds a plainer hub, never a broken one.
local function propFor(areaId: string): Model?
	local folder = ServerStorage:FindFirstChild("StationProps")

	if folder == nil then
		return nil
	end

	local template = folder:FindFirstChild(areaId)

	if template == nil or not template:IsA("Model") then
		return nil
	end

	return template:Clone()
end

function LobbyBuilder.build(): BuiltLobby
	clear("Lobby")

	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- Floor, top surface at y = 0 to match the convention every map uses.
	newPart("Floor", FLOOR_SIZE, CFrame.new(0, -FLOOR_SIZE.Y / 2, 0), FLOOR_COLOR, folder)

	-- Low walls, purely so the space reads as a room rather than a slab.
	local halfX = FLOOR_SIZE.X / 2
	local halfZ = FLOOR_SIZE.Z / 2
	local wall = Vector3.new(FLOOR_SIZE.X, 8, 2)

	newPart("WallNorth", wall, CFrame.new(0, 4, -halfZ), TRIM_COLOR, folder)
	newPart("WallSouth", wall, CFrame.new(0, 4, halfZ), TRIM_COLOR, folder)
	newPart("WallEast", Vector3.new(2, 8, FLOOR_SIZE.Z), CFrame.new(halfX, 4, 0), TRIM_COLOR, folder)
	newPart("WallWest", Vector3.new(2, 8, FLOOR_SIZE.Z), CFrame.new(-halfX, 4, 0), TRIM_COLOR, folder)

	-- Spawn in the CENTRE, per the sketch: the hub radiates around you and
	-- every area is a short, visible walk.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
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

--- The three walk-in areas, from the shared layout the resolver reads.
--- Each: a glowing pad, a billboard, and - when the place carries one - a
--- store prop standing behind it.
function LobbyBuilder.buildAreas(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Areas"
	folder.Parent = parent

	for _, area in LobbyZones.AREAS do
		local color = AREA_COLORS[area.id] or AREA_FALLBACK

		-- Slightly proud of the floor so the area reads as a place, and thin
		-- enough that walking on feels flat.
		local pad = newPart(
			`Area_{area.id}`,
			Vector3.new(area.size.X, 0.4, area.size.Z),
			CFrame.new(area.center.X, 0.2, area.center.Z),
			color,
			folder
		)
		pad.CanQuery = false
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.35

		local sign = Instance.new("BillboardGui")
		sign.Name = "Sign"
		sign.Size = UDim2.fromScale(14, 3.5)
		sign.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
		sign.MaxDistance = 240
		sign.Adornee = pad
		sign.Parent = pad

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = area.displayName
		label.TextScaled = true
		label.TextColor3 = color
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.5
		label.Parent = sign

		local prop = propFor(area.id)

		if prop ~= nil then
			-- Behind the pad, facing the room's centre, feet on the floor.
			local direction = if area.center.Magnitude > 0 then area.center.Unit else Vector3.zAxis
			local position = area.center + direction * (math.max(area.size.X, area.size.Z) / 2 + 4)
			local _, extents = prop:GetBoundingBox()

			prop.Name = `Prop_{area.id}`
			prop:PivotTo(
				CFrame.lookAt(Vector3.new(position.X, extents.Y / 2, position.Z), Vector3.new(0, extents.Y / 2, 0))
			)
			prop.Parent = folder
		else
			-- No prop in this place: a plain plinth keeps the silhouette.
			newPart(
				`Plinth_{area.id}`,
				Vector3.new(6, 7, 3),
				CFrame.new(area.center.X + math.sign(area.center.X) * (area.size.X / 2 + 2.5), 3.5, area.center.Z),
				color,
				folder
			)
		end
	end
end

return LobbyBuilder

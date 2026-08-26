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
local FLOOR_COLOR = Color3.fromRGB(88, 92, 102)
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
	local floor = newPart("Floor", FLOOR_SIZE, CFrame.new(0, -FLOOR_SIZE.Y / 2, 0), FLOOR_COLOR, folder)
	floor.Material = Enum.Material.Concrete

	-- A darker inlaid ring around the spawn, so the centre reads as the
	-- heart of the hub rather than more of the same slab.
	local inlay =
		newPart("FloorInlay", Vector3.new(26, 0.2, 26), CFrame.new(0, 0.1, 0), Color3.fromRGB(54, 60, 74), folder)
	inlay.Material = Enum.Material.Concrete
	inlay.CanQuery = false

	-- Low walls, purely so the space reads as a room rather than a slab.
	local halfX = FLOOR_SIZE.X / 2
	local halfZ = FLOOR_SIZE.Z / 2
	local wall = Vector3.new(FLOOR_SIZE.X, 8, 2)

	local wallSpecs = {
		{ name = "WallNorth", size = wall, cframe = CFrame.new(0, 4, -halfZ) },
		{ name = "WallSouth", size = wall, cframe = CFrame.new(0, 4, halfZ) },
		{ name = "WallEast", size = Vector3.new(2, 8, FLOOR_SIZE.Z), cframe = CFrame.new(halfX, 4, 0) },
		{ name = "WallWest", size = Vector3.new(2, 8, FLOOR_SIZE.Z), cframe = CFrame.new(-halfX, 4, 0) },
	}

	for _, spec in wallSpecs do
		local built = newPart(spec.name, spec.size, spec.cframe, TRIM_COLOR, folder)
		built.Material = Enum.Material.Slate

		-- A neon cap strip along the top of each wall: the hub's horizon
		-- line, and the same blue the Game area wears.
		local capSize = if spec.size.X > spec.size.Z
			then Vector3.new(spec.size.X, 0.4, 0.6)
			else Vector3.new(0.6, 0.4, spec.size.Z)
		local cap = newPart(
			spec.name .. "Cap",
			capSize,
			spec.cframe * CFrame.new(0, 4.2, 0),
			Color3.fromRGB(96, 176, 255),
			folder
		)
		cap.Material = Enum.Material.Neon
		cap.Transparency = 0.25
		cap.CanQuery = false
	end

	-- Spawn in the CENTRE, per the sketch: the hub radiates around you and
	-- every area is a short, visible walk.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(120, 160, 200)
	spawn.Material = Enum.Material.Concrete
	spawn.TopSurface = Enum.SurfaceType.Smooth
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

		-- Light pillars flanking the pad, in the area's colour: visible
		-- across the hub, so each area advertises itself from the spawn.
		for _, side in { -1, 1 } do
			local pillar = newPart(
				`Pillar_{area.id}_{side}`,
				Vector3.new(1.2, 9, 1.2),
				CFrame.new(area.center.X + side * (area.size.X / 2 + 1.5), 4.5, area.center.Z + area.size.Z / 2 + 1),
				color,
				folder
			)
			pillar.Material = Enum.Material.Neon
			pillar.Transparency = 0.15
			pillar.CanQuery = false

			local glow = Instance.new("PointLight")
			glow.Color = color
			glow.Brightness = 1.4
			glow.Range = 14
			glow.Parent = pillar
		end

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

--- The hub's dusk: low sun, cool ambient, a touch of atmosphere and
--- bloom. Server-side at boot so every client sees the same evening.
--- Deliberately NOT applied in the match place, where flat neutral light
--- keeps enemies and ranges readable - the hub can afford a mood.
function LobbyBuilder.setLighting()
	local lighting = game:GetService("Lighting")

	lighting.ClockTime = 17.15
	lighting.Brightness = 3
	lighting.Ambient = Color3.fromRGB(88, 96, 114)
	lighting.OutdoorAmbient = Color3.fromRGB(118, 126, 148)

	if lighting:FindFirstChild("HubAtmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "HubAtmosphere"
		atmosphere.Density = 0.24
		atmosphere.Offset = 0.4
		atmosphere.Color = Color3.fromRGB(150, 170, 205)
		atmosphere.Decay = Color3.fromRGB(60, 70, 95)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.2
		atmosphere.Parent = lighting
	end

	if lighting:FindFirstChild("HubBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "HubBloom"
		bloom.Intensity = 0.6
		bloom.Size = 32
		bloom.Threshold = 1.1
		bloom.Parent = lighting
	end
end

return LobbyBuilder

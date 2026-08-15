--!strict
--[[
	Difficulty presets.

	These are the coarse knobs a player picks before a run. Fine tuning lives
	in Scaling (the wave curve) and Enemies (wave-1 baselines).

	`finalWave` is where Victory is offered and endless mode begins, so it also
	sets how long a run is. The design target is 30-50 waves.
]]

local Types = require(script.Parent.Parent.Types)

local Difficulty = {}

Difficulty.DEFAULT_ID = "Normal"

Difficulty.PRESETS = {
	Casual = {
		id = "Casual",
		displayName = "Casual",
		startingCash = 750,
		baseHealth = 150,
		healthMultiplier = 0.75,
		rewardMultiplier = 0.85,
		finalWave = 30,
	},

	Normal = {
		id = "Normal",
		displayName = "Normal",
		startingCash = 550,
		baseHealth = 100,
		healthMultiplier = 1,
		rewardMultiplier = 1,
		finalWave = 40,
	},

	Nightmare = {
		id = "Nightmare",
		displayName = "Nightmare",
		startingCash = 400,
		baseHealth = 60,
		healthMultiplier = 1.6,
		-- Deliberately above 1: the run is harder, so the income has to keep
		-- pace or the difficulty comes from being unable to build anything,
		-- which is not the same thing as being challenging.
		rewardMultiplier = 1.25,
		finalWave = 50,
	},
} :: { [string]: Types.DifficultyConfig }

--- Preset ids in ascending order of difficulty, which is also the order the
--- lobby renders them in.
---
--- Written out rather than derived by sorting the table, because the useful
--- order here is Casual -> Normal -> Nightmare and alphabetical order would
--- put Nightmare in the middle. A pairs() order would be worse still: vote
--- tallies must not reorder themselves between servers.
local IDS: { string } = { "Casual", "Normal", "Nightmare" }

Difficulty.IDS = table.freeze(IDS)

--- Throws on an unknown id. Difficulty arrives over the wire from the lobby,
--- so this doubles as the allowlist check described in the design doc: an
--- exploiter cannot invent a preset with a million starting cash.
function Difficulty.get(id: string): Types.DifficultyConfig
	local preset = Difficulty.PRESETS[id]

	if preset == nil then
		error(`Difficulty.get: no difficulty preset with id "{id}"`)
	end

	return preset
end

--- Non-throwing lookup for untrusted input. Returns nil rather than erroring
--- so the arrival gate can fall back to the default without a pcall.
function Difficulty.find(id: string): Types.DifficultyConfig?
	return Difficulty.PRESETS[id]
end

return Difficulty

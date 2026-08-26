--!strict
--[[
	Jest test runner.

	This Script exists only in the test place (test.project.json), never in
	default.project.json, so it can never ship to production.

	Run the suite:
	    rojo build test.project.json --output build/test.rbxl
	    # open build/test.rbxl in Studio, press Run, read the Output window

	Jest-Lua executes inside a Roblox VM. There is no supported way to run it
	on a GitHub-hosted runner, because that needs a Roblox Studio install.
	See AGENTS.md -> "Tests" and SETUP-LOG.md for exactly what CI does instead
	and what it therefore does not prove.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jest = require(ReplicatedStorage.DevPackages.Jest)

--- Jest cannot run from a playtest, so do not try and do not spam the Output
--- window with twelve identical stack traces when someone presses Play.
---
--- jest-runtime loads a module by reading its `Source`, which needs the
--- `PluginOrOpenCloud` capability. A plugin thread has it; a Script running
--- under Play does not, so every suite dies with "cannot read 'Source'" before
--- collecting a single test.
---
--- That failure is easy to misread as a pass: this file computes
--- `passed = numFailedTests == 0`, and when nothing runs, nothing fails.
--- Bailing out with one honest line is better than a red wall that reports
--- zero failures.
local canReadSource = pcall(function()
	return (script :: any).Source
end)

if not canReadSource then
	print(
		"[tests] Skipped - Jest needs a plugin context to read module Source, "
			.. "which a playtest does not have. Run it from the command bar or "
			.. "the Studio MCP instead; see AGENTS.md -> Tests."
	)

	return
end

-- ProcessService is a Studio-internal service, so it is absent from selene's
-- Roblox standard library and from the published type definitions. It only
-- exists under `run-in-roblox`; in normal Studio the pcall below fails and we
-- fall through to reporting results in the Output window.
-- selene: allow(incorrect_standard_library_use)
local hasProcessService, ProcessService = pcall(function()
	return (game :: any):GetService("ProcessService")
end)

local status, result = Jest.runCLI(script, {
	verbose = true,
	ci = false,
}, { script }):awaitStatus()

if status ~= "Resolved" then
	warn(`[tests] Jest failed to run: {result}`)

	if hasProcessService then
		(ProcessService :: any):ExitAsync(1)
	end

	return
end

local failedSuites = result.results.numFailedTestSuites
local failedTests = result.results.numFailedTests
local passed = failedSuites == 0 and failedTests == 0

if passed then
	print("[tests] All suites passed.")
else
	warn(`[tests] {failedTests} failing test(s) across {failedSuites} suite(s).`)
end

if hasProcessService then
	(ProcessService :: any):ExitAsync(if passed then 0 else 1)
end

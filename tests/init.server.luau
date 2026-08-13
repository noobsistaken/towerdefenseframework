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

--!strict
--[[
	Jest project config.

	The suite cannot run without this file, and its absence is the entire
	reason this project reported "253 assertions, zero runs" for as long as it
	did. jest-config's resolveConfigPath searches each project root for a
	ModuleScript named exactly `jest.config` and throws

	    Could not find a config file based on provided values: path: "Tests"

	when there is none. It fails before collecting a single spec, so the count
	of assertions was never evidence that any of them had executed.

	`tests/init.server.luau` passes `script` - ServerScriptService.Tests - as
	the only project root, so this has to sit beside it rather than at the
	repo root. Rojo names a module after its file without the extension, so
	`jest.config.luau` arrives as `jest.config`, which is the name the resolver
	matches on.
]]

return {
	--- Every spec in this folder, and nothing else.
	---
	--- Jest's default would also match a `__tests__` directory and a `.test`
	--- suffix, neither of which this project uses. Naming the one convention
	--- we do use means a file that is not a spec cannot be collected by
	--- accident, and it documents the convention for the next person adding
	--- a test.
	testMatch = { "**/*.spec" },
}

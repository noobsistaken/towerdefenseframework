--!strict
--[[
	Tests for the lobby's vote tallying.

	Two properties carry real weight here. The allowlist, because `cast` is
	what stands between a client-supplied string and the map a whole server
	gets sent to. And determinism, because two clients rendering the same vote
	in different orders - or an exact tie resolving differently on two servers
	- are bugs that only show up with several people in a lobby, which is the
	hardest state to reproduce deliberately.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local Poll = require(ReplicatedStorage.Shared.Poll)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local OPTIONS = { "Alpha", "Bravo", "Charlie" }

local function newPoll(): Poll.Poll
	return Poll.new(OPTIONS, "Bravo")
end

--- Votes for one option, read out of a tally list.
local function votesFor(poll: Poll.Poll, option: string): number
	for _, entry in poll:tally() do
		if entry.option == option then
			return entry.votes
		end
	end

	return -1
end

describe("Poll.new", function()
	it("refuses an empty option list", function()
		expect(function()
			Poll.new({}, "Alpha")
		end).toThrow()
	end)

	it("refuses a fallback that is not an option", function()
		-- Otherwise `winner` could return something no caller can handle,
		-- and it would only surface on a lobby where nobody voted.
		expect(function()
			Poll.new(OPTIONS, "Delta")
		end).toThrow()
	end)

	it("does not alias the caller's option table", function()
		local options = { "Alpha", "Bravo" }
		local poll = Poll.new(options, "Alpha")

		options[2] = "Mutated"

		expect(votesFor(poll, "Bravo")).toBe(0)
	end)
end)

describe("Poll.cast", function()
	it("is the allowlist", function()
		-- The security property. `option` arrives from a client, and Zap can
		-- only prove it is a short string.
		local poll = newPoll()

		expect(poll:cast(1, "Delta")).toBe(false)
		expect(poll:cast(1, "")).toBe(false)
		expect(poll:cast(1, "alpha")).toBe(false)
		expect(poll:voterCount()).toBe(0)
	end)

	it("accepts a legitimate option", function()
		local poll = newPoll()

		expect(poll:cast(1, "Charlie")).toBe(true)
		expect(votesFor(poll, "Charlie")).toBe(1)
	end)

	it("replaces a voter's previous choice rather than adding one", function()
		local poll = newPoll()

		poll:cast(1, "Alpha")
		poll:cast(1, "Charlie")

		expect(votesFor(poll, "Alpha")).toBe(0)
		expect(votesFor(poll, "Charlie")).toBe(1)
		expect(poll:voterCount()).toBe(1)
	end)
end)

describe("Poll.remove", function()
	it("stops a departed voter counting", function()
		-- A lobby that kept counting votes from players who left could sit
		-- waiting on someone who is not there.
		local poll = newPoll()

		poll:cast(1, "Alpha")
		poll:cast(2, "Alpha")
		poll:remove(1)

		expect(votesFor(poll, "Alpha")).toBe(1)
		expect(poll:voterCount()).toBe(1)
	end)

	it("is harmless for a voter who never voted", function()
		local poll = newPoll()

		poll:remove(99)

		expect(poll:voterCount()).toBe(0)
	end)
end)

describe("Poll.tally", function()
	it("lists every option in order, including unvoted ones", function()
		-- Both halves matter for rendering: a missing option would make the
		-- button list reflow as votes arrive, and iteration order would make
		-- two clients disagree about the layout.
		local poll = newPoll()
		poll:cast(1, "Charlie")

		local tally = poll:tally()

		expect(#tally).toBe(3)
		expect(tally[1].option).toBe("Alpha")
		expect(tally[2].option).toBe("Bravo")
		expect(tally[3].option).toBe("Charlie")
		expect(tally[1].votes).toBe(0)
		expect(tally[3].votes).toBe(1)
	end)

	it("is stable across repeated calls", function()
		local poll = newPoll()
		poll:cast(1, "Bravo")

		local first = poll:tally()
		local second = poll:tally()

		for index, entry in first do
			expect(entry.option).toBe(second[index].option)
			expect(entry.votes).toBe(second[index].votes)
		end
	end)
end)

describe("Poll.winner", function()
	it("returns the fallback when nobody has voted", function()
		-- The common case: a lobby that launches on its timer with nobody
		-- having touched the buttons.
		expect(newPoll():winner()).toBe("Bravo")
	end)

	it("returns the option with the most votes", function()
		local poll = newPoll()

		poll:cast(1, "Charlie")
		poll:cast(2, "Charlie")
		poll:cast(3, "Alpha")

		expect(poll:winner()).toBe("Charlie")
	end)

	it("breaks ties toward the earlier option, always", function()
		-- Determinism. Two servers counting identical votes must reach the
		-- same answer, and a hash-order tie-break would not.
		for _ = 1, 20 do
			local poll = newPoll()

			poll:cast(1, "Charlie")
			poll:cast(2, "Alpha")

			expect(poll:winner()).toBe("Alpha")
		end
	end)

	it("falls back again once every vote is withdrawn", function()
		local poll = newPoll()

		poll:cast(1, "Charlie")
		poll:remove(1)

		expect(poll:winner()).toBe("Bravo")
	end)
end)

describe("Poll.clear", function()
	it("drops every vote", function()
		local poll = newPoll()

		poll:cast(1, "Alpha")
		poll:cast(2, "Charlie")
		poll:clear()

		expect(poll:voterCount()).toBe(0)
		expect(poll:winner()).toBe("Bravo")
	end)
end)

--!strict
--[[
	A vote over a fixed set of options.

	Generic because the lobby runs two of these - map and difficulty - and two
	hand-written tally implementations would drift. Pure: it knows nothing
	about Players, only about opaque numeric voter ids, so the whole thing is
	testable without a running game.

	Determinism is the property that matters most here, and it takes explicit
	work. A tally built by iterating a hash table comes out in an arbitrary
	order, so two clients would render the same vote in different orders, and
	an exact tie would resolve differently depending on which server counted
	it. Both are fixed by ordering on the option list rather than on iteration.
]]

local Poll = {}
Poll.__index = Poll

export type Tally = {
	option: string,
	votes: number,
}

export type Poll = typeof(setmetatable(
	{} :: {
		--- Legal options, in display order. Also the tie-break order.
		options: { string },
		--- Fast membership test, so casting does not scan the option list.
		valid: { [string]: boolean },
		--- Winner when nobody has voted.
		fallback: string,
		--- voterId -> option.
		votes: { [number]: string },
	},
	Poll
))

--- `fallback` must be one of `options`; it is what `winner` returns when no
--- votes have been cast, which is the common case for a lobby that launches
--- on a timer with nobody having touched the buttons.
function Poll.new(options: { string }, fallback: string): Poll
	if #options == 0 then
		error("Poll.new: needs at least one option")
	end

	local valid: { [string]: boolean } = {}

	for _, option in options do
		valid[option] = true
	end

	if not valid[fallback] then
		error(`Poll.new: fallback "{fallback}" is not one of the options`)
	end

	return setmetatable({
		options = table.clone(options),
		valid = valid,
		fallback = fallback,
		votes = {},
	}, Poll)
end

--- Records a vote, replacing whatever this voter chose before. Returns false
--- for an option that is not on the list, which is the allowlist check for a
--- value that arrived from a client.
function Poll.cast(self: Poll, voterId: number, option: string): boolean
	if not self.valid[option] then
		return false
	end

	self.votes[voterId] = option

	return true
end

--- Drops a voter, for when someone leaves. Their vote must not keep counting.
function Poll.remove(self: Poll, voterId: number)
	self.votes[voterId] = nil
end

function Poll.clear(self: Poll)
	self.votes = {}
end

--- Vote counts for every option, always in option order and always including
--- options with zero votes. Both properties are what let the client render a
--- stable list rather than one that reshuffles as votes arrive.
function Poll.tally(self: Poll): { Tally }
	local counts: { [string]: number } = {}

	for _, option in self.options do
		counts[option] = 0
	end

	for _, option in self.votes do
		-- Guard rather than assume: an option could have been removed from
		-- config while a vote for it was still held.
		if counts[option] ~= nil then
			counts[option] += 1
		end
	end

	local result: { Tally } = {}

	for _, option in self.options do
		table.insert(result, { option = option, votes = counts[option] })
	end

	return result
end

--- The winning option. Ties break toward whichever comes first in the option
--- list, so the result is identical on every server that counted the same
--- votes. Returns the fallback when nothing has been voted for.
function Poll.winner(self: Poll): string
	local best = self.fallback
	local bestVotes = 0

	for _, entry in self:tally() do
		if entry.votes > bestVotes then
			best = entry.option
			bestVotes = entry.votes
		end
	end

	return best
end

--- How many voters have cast a vote. Used for the lobby's "3/5 voted" line.
function Poll.voterCount(self: Poll): number
	local count = 0

	for _ in self.votes do
		count += 1
	end

	return count
end

return Poll

--!strict
--[[
	Per-player match cash.

	Per-player rather than shared, TDS style: your kills fund your towers, and
	one player cannot spend the team's money.

	Deliberately knows nothing about networking. It reports changes through a
	listener and MatchController turns those into CashChanged messages, which
	keeps the whole thing testable and stops cash arithmetic from being
	entangled with the wire format.

	Cash is never persisted. It exists for the length of one match, so a
	player cannot carry a balance between runs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseEnemy = require(script.Parent.Parent.Entities.BaseEnemy)

local EconomyService = {}
EconomyService.__index = EconomyService

export type ChangedListener = (player: Player, balance: number) -> ()

export type Service = typeof(setmetatable(
	{} :: {
		difficulty: Types.DifficultyConfig,
		balances: { [Player]: number },
		listeners: { ChangedListener },
	},
	EconomyService
))

function EconomyService.new(difficulty: Types.DifficultyConfig): Service
	return setmetatable({
		difficulty = difficulty,
		balances = {},
		listeners = {},
	}, EconomyService)
end

function EconomyService.onChanged(self: Service, listener: ChangedListener): () -> ()
	table.insert(self.listeners, listener)

	return function()
		local index = table.find(self.listeners, listener)

		if index ~= nil then
			table.remove(self.listeners, index)
		end
	end
end

local function notify(self: Service, player: Player)
	local balance = self.balances[player]

	if balance == nil then
		return
	end

	for _, listener in self.listeners do
		listener(player, balance)
	end
end

--- Gives a player their starting balance. Idempotent: rejoining mid-match
--- must not hand out a second starting stack.
function EconomyService.addPlayer(self: Service, player: Player)
	if self.balances[player] ~= nil then
		return
	end

	self.balances[player] = self.difficulty.startingCash
	notify(self, player)
end

function EconomyService.removePlayer(self: Service, player: Player)
	self.balances[player] = nil
end

function EconomyService.balance(self: Service, player: Player): number
	return self.balances[player] or 0
end

function EconomyService.canAfford(self: Service, player: Player, amount: number): boolean
	return self:balance(player) >= amount
end

--- Takes payment. Returns false and changes nothing if the player cannot
--- afford it, so callers can treat this as the commit step of a purchase.
function EconomyService.charge(self: Service, player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local balance = self.balances[player]

	if balance == nil or balance < amount then
		return false
	end

	self.balances[player] = balance - amount
	notify(self, player)

	return true
end

function EconomyService.credit(self: Service, player: Player, amount: number)
	if amount <= 0 then
		return
	end

	local balance = self.balances[player]

	if balance == nil then
		return
	end

	self.balances[player] = balance + amount
	notify(self, player)
end

--- Pays everyone the same amount. Used for wave-clear and early-start
--- bonuses, which are team-wide by design: a shared bonus removes any reason
--- to race a team-mate to the button.
function EconomyService.creditAll(self: Service, amount: number)
	if amount <= 0 then
		return
	end

	for player in self.balances do
		self:credit(player, amount)
	end
end

--- Splits a kill bounty across whoever damaged the enemy, in proportion to
--- how much they dealt (ARCHITECTURE.md D6).
---
--- Last-hit bounty is the obvious implementation and the wrong one in co-op:
--- the tower that did 95% of the work loses the whole payout to whoever
--- landed the final tick, which in practice means whoever built the fastest
--- firing tower collects for everyone else's damage.
function EconomyService.payBounty(self: Service, enemy: BaseEnemy.Enemy)
	local shares = Economy.splitByContribution(enemy.damageByPlayer, enemy.bounty)

	for player, amount in shares do
		-- A player who left mid-flight has no balance; their share is simply
		-- not paid rather than resurrecting their entry.
		if self.balances[player] ~= nil then
			self:credit(player, amount)
		end
	end
end

return EconomyService

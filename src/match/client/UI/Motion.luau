--!strict
--[[
	The one place a UI tween is created.

	The world-space effects create a tween, play it and forget it - a tracer
	never changes its mind halfway through. UI motion does: a hover can reverse
	before it lands, and starting a second tween without cancelling the first
	leaves two writers on one property, where the winner is whichever happens
	to finish last. So this hands back a handle and takes the previous one.

	Client-only, and beside its consumers rather than in src/shared/: the
	server has no reason to load a tween.

	THE RULE THAT MAKES THIS SAFE, and it is not obvious. Only ever animate a
	property the React element does NOT declare. react-roblox writes a host
	property whenever it is present and changed, so a re-render mid-tween would
	snap an animated value back to whatever the last render passed. Declaring a
	CONSTANT is fine - it is written once at mount and never again - but the
	moment a declared value can change, React and TweenService are fighting
	over the same field and React wins on the next render.
]]

local TweenService = game:GetService("TweenService")

local Motion = {}

--- A running tween, or nil if nothing is in flight.
export type Handle = Tween?

--- Cancels `previous` if one is still running, then plays a new tween toward
--- `goal` and returns its handle.
---
--- Cancel rather than Pause: a new tween samples its start value off the
--- instance as it stands, so the reversal begins from wherever the interrupted
--- one had reached. That is what makes a half-open panel close smoothly
--- instead of jumping to fully open first.
function Motion.retarget(previous: Handle, instance: Instance, info: TweenInfo, goal: { [string]: any }): Handle
	if previous ~= nil then
		previous:Cancel()
	end

	local tween = TweenService:Create(instance, info, goal)
	tween:Play()

	return tween
end

--- Cancels a handle without starting anything.
---
--- For unmount. A Tween holds a strong reference to its target, so one left
--- running against a destroyed Instance keeps it alive until the tween ends.
function Motion.stop(handle: Handle)
	if handle ~= nil then
		handle:Cancel()
	end
end

return Motion

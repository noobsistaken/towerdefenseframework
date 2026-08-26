--!strict
--[[
	Forwards to the shared SoundKit. The implementation moved to shared/
	the day the LOBBY grew sounds - egg cracks, roll springs, clicks - and
	two copies of an audio system is one bug filed twice. This shim keeps
	every existing require path working.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(ReplicatedStorage.Shared.SoundKit)

--!strict
--[[
	The UI's shared motion vocabulary: three effects, used everywhere, so
	every surface moves the same way.

	  * PopIn - a panel entrance: scale 94% -> 100% with a fade, run on
	    mount (and again when `restartKey` changes). Optionally delayed,
	    which is what the results screen's stagger is made of.
	  * useSmoothedNumber - a displayed number that CHASES its target
	    instead of snapping, for money and health.
	  * pressPop / popScale - the squash-and-spring a big button plays on
	    press, and a function-ref that pops a UIScale on mount for places
	    where hooks cannot reach (conditionally-rendered overlays).

	THE SAFETY RULE, inherited from Motion.luau: only animate properties the
	React element never declares as a CHANGING value. PopIn animates
	GroupTransparency and a UIScale's Scale - neither appears in any
	component's props. useSmoothedNumber does not animate an instance at
	all: it smooths the VALUE and lets React declare from it, so React and
	TweenService never share a pen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local SoundKit = require(script.Parent.SoundKit)

local UiFx = {}

local e = React.createElement

local POP_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

export type PopInProps = {
	--- Host props for the CanvasGroup, exactly as they would go on a Frame.
	frame: { [string]: any },
	children: { [string]: any }?,
	--- Re-runs the entrance when this changes. Mount alone covers panels
	--- that unmount between appearances; this covers ones that stay.
	restartKey: string?,
	--- Seconds to hold, invisible, before the entrance - the stagger knob.
	delay: number?,
}

--- A panel that pops into place. Renders a CanvasGroup so the WHOLE
--- subtree fades as one, with a UIScale for the pop.
function UiFx.PopIn(props: PopInProps)
	local groupRef = React.useRef(nil :: CanvasGroup?)
	local scaleRef = React.useRef(nil :: UIScale?)

	React.useEffect(function(): () -> ()
		local group = groupRef.current
		local scale = scaleRef.current

		if group == nil or scale == nil then
			return function() end
		end

		group.GroupTransparency = 1
		scale.Scale = 0.94

		local tweens: { Tween } = {}
		local delayed: thread? = nil

		local function run()
			local fade = TweenService:Create(group, FADE_INFO, { GroupTransparency = 0 })
			local pop = TweenService:Create(scale, POP_INFO, { Scale = 1 })

			table.insert(tweens, fade)
			table.insert(tweens, pop)
			fade:Play()
			pop:Play()
		end

		if props.delay ~= nil and props.delay > 0 then
			delayed = task.delay(props.delay, run)
		else
			run()
		end

		return function()
			if delayed ~= nil then
				task.cancel(delayed)
			end

			for _, tween in tweens do
				tween:Cancel()
			end
		end
	end, { props.restartKey or "" })

	local merged: { [string]: any } = {
		-- Declared as a CONSTANT, which the safety rule allows: React writes
		-- it once at mount and never again, so the first frame is invisible
		-- rather than flashing fully-drawn before the effect runs.
		GroupTransparency = 1,
		BorderSizePixel = 0,
		ref = groupRef,
	}

	for key, value in props.frame do
		merged[key] = value
	end

	local children: { [string]: any } = {
		uiFxScale = e("UIScale", { ref = scaleRef }),
	}

	if props.children ~= nil then
		for key, value in props.children do
			children[key] = value
		end
	end

	return e("CanvasGroup", merged, children)
end

--- A number that chases `target` over `seconds` (default 0.35) with an
--- ease-out, re-aimed whenever the target moves. Round before display.
function UiFx.useSmoothedNumber(target: number, seconds: number?): number
	local shown, setShown = React.useState(target)
	local shownRef = React.useRef(target)

	React.useEffect(function(): () -> ()
		local from = shownRef.current :: number

		if from == target then
			return function() end
		end

		local duration = seconds or 0.35
		local started = os.clock()
		local alive = true

		task.spawn(function()
			while alive do
				local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
				local eased = 1 - (1 - alpha) * (1 - alpha)
				local value = from + (target - from) * eased

				shownRef.current = value
				setShown(value)

				if alpha >= 1 then
					break
				end

				task.wait()
			end
		end)

		return function()
			alive = false
		end
	end, { target })

	return shown
end

--- Squash-and-spring on a UIScale, for a button press. Imperative on
--- purpose: it fires from an Activated handler, not from a render.
function UiFx.pressPop(scale: UIScale?)
	SoundKit.play("ButtonClick")

	if scale == nil then
		return
	end

	scale.Scale = 0.92
	TweenService:Create(scale, PRESS_INFO, { Scale = 1 }):Play()
end

--- A function-ref that pops its UIScale the moment it mounts. For overlays
--- built by plain helper functions, where a hook would break the rules the
--- moment the overlay renders conditionally.
function UiFx.popScale(instance: UIScale?)
	if instance == nil then
		return
	end

	instance.Scale = 0.94
	TweenService:Create(instance, POP_INFO, { Scale = 1 }):Play()
end

return UiFx

--!strict
--[[
	Who may use the admin console.

	A UserId allowlist, checked SERVER-SIDE on every admin request - the
	client-side check only decides whether to render the console, and a
	client that renders it anyway earns a silent refusal.

	Studio always counts as admin: playtests run under whatever account is
	logged in, and a grant there touches nothing live.
]]

local Admins = {}

--- Alexei (noobsv8). Add ids here, never usernames - names change hands.
local ADMIN_USER_IDS: { [number]: boolean } = {
	[289104678] = true,
}

--- Pure, so the spec can drive both flags without a Players service.
function Admins.isAdmin(userId: number, isStudio: boolean): boolean
	if isStudio then
		return true
	end

	return ADMIN_USER_IDS[userId] == true
end

return Admins

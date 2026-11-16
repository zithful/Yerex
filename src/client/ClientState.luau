--!strict
-- Tiny shared state between client controllers (input writes, HUD reads).

local ClientState = {
	chargeStart = nil :: number?, -- os.clock() when a shot charge began
	chargeKind = nil :: string?,
	showHelp = true,
}

return ClientState

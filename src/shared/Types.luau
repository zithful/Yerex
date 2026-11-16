--!strict
-- Shared type definitions. Types that cross the client/server boundary live
-- here so both sides agree.

export type TeamId = "Home" | "Away"

-- One value per side, e.g. scores.
export type TeamMap<T> = { Home: T, Away: T }

export type MatchPhase = "Warmup" | "Kickoff" | "Playing" | "Goal" | "FullTime"

-- Every action a client can request. The server validates each one.
export type ActionKind =
	"Pass" -- ground pass, auto-targets a teammate in the aim cone
	| "Through" -- ground pass played into space ahead of a running teammate
	| "Lob" -- lofted pass
	| "Shoot" -- power-charged driven shot
	| "Finesse" -- placed, curling shot
	| "LowDriven" -- hard, low shot that stays under the keeper's hands
	| "Tackle" -- standing tackle
	| "Slide" -- slide tackle
	| "KnockOn" -- skill: push the ball into space and chase it
	| "DragBack" -- skill: roll the ball back under the sole
	| "Sprint" -- toggles sprinting; uses `flag`

-- Payload of the Action remote. Everything here is untrusted on the server.
export type ActionPayload = {
	kind: ActionKind,
	dir: Vector3, -- desired horizontal aim direction
	power: number, -- 0..1, from the charge bar where relevant
	flag: boolean?, -- Sprint on/off
}

return nil

--!strict
-- Pitch geometry shared by server (building, goal detection, AI) and client (HUD).
-- The pitch runs along the X axis. Home defends the goal at -X and attacks +X.

local Types = require(script.Parent.Types)

type TeamId = Types.TeamId

-- Typed constants: the type checker widens bare string literals in
-- if-expressions to `string`, so TeamId values come from here.
local HOME: TeamId = "Home"
local AWAY: TeamId = "Away"

local LENGTH = 220
local WIDTH = 140
local GOAL_WIDTH = 24
local GOAL_HEIGHT = 8
local GOAL_DEPTH = 6
local BOX_DEPTH = 36
local BOX_WIDTH = 80

local Pitch = {
	LENGTH = LENGTH,
	WIDTH = WIDTH,
	HALF_LENGTH = LENGTH / 2,
	HALF_WIDTH = WIDTH / 2,
	GOAL_WIDTH = GOAL_WIDTH,
	GOAL_HEIGHT = GOAL_HEIGHT,
	GOAL_DEPTH = GOAL_DEPTH,
	BOX_DEPTH = BOX_DEPTH,
	BOX_WIDTH = BOX_WIDTH,
	CENTER_CIRCLE_RADIUS = 26,
	GROUND_Y = 0, -- top surface of the grass
	ORIGIN = Vector3.zero,
	HOME = HOME,
	AWAY = AWAY,
	TEAMS = table.freeze({ HOME, AWAY }) :: { TeamId },
}

-- X coordinate of the goal line a team defends.
function Pitch.goalLineX(defending: TeamId): number
	return if defending == "Home" then -Pitch.HALF_LENGTH else Pitch.HALF_LENGTH
end

-- +1 if the team attacks toward +X, -1 otherwise.
function Pitch.attackSign(team: TeamId): number
	return if team == "Home" then 1 else -1
end

function Pitch.opponent(team: TeamId): TeamId
	if team == HOME then
		return AWAY
	end
	return HOME
end

-- Centre of the goal mouth (on the goal line, ground level) that a team defends.
function Pitch.goalCenter(defending: TeamId): Vector3
	return Vector3.new(Pitch.goalLineX(defending), Pitch.GROUND_Y, 0)
end

-- Returns the team whose goal the point is inside, or nil.
-- A goal counts only when the whole ball is over the line, so callers pass the
-- ball centre plus its radius as margin.
function Pitch.goalScoredIn(position: Vector3, margin: number): TeamId?
	local halfGoal = GOAL_WIDTH / 2
	if math.abs(position.Z) > halfGoal or position.Y > Pitch.GROUND_Y + GOAL_HEIGHT then
		return nil
	end
	if position.X < -Pitch.HALF_LENGTH - margin then
		return HOME
	elseif position.X > Pitch.HALF_LENGTH + margin then
		return AWAY
	end
	return nil
end

function Pitch.isInsideBox(position: Vector3, defending: TeamId): boolean
	local lineX = Pitch.goalLineX(defending)
	local intoPitch = (position.X - lineX) * Pitch.attackSign(defending)
	return intoPitch >= 0 and intoPitch <= BOX_DEPTH and math.abs(position.Z) <= BOX_WIDTH / 2
end

-- Kickoff formation slots, as fractions of the team's own half.
-- x: 0 = halfway line, 1 = own goal line. z: -1..1 across the width.
local FORMATION: { Vector2 } = {
	Vector2.new(0.3, 0.0), -- outside the centre circle at kickoff
	Vector2.new(0.25, -0.45),
	Vector2.new(0.25, 0.45),
	Vector2.new(0.55, -0.25),
	Vector2.new(0.55, 0.25),
	Vector2.new(0.45, 0.0),
	Vector2.new(0.3, -0.8),
	Vector2.new(0.3, 0.8),
	Vector2.new(0.75, -0.5),
	Vector2.new(0.75, 0.5),
}

function Pitch.formationSpot(team: TeamId, index: number): Vector3
	local slot = FORMATION[((index - 1) % #FORMATION) + 1]
	local sign = Pitch.attackSign(team)
	local x = -sign * (slot.X * (Pitch.HALF_LENGTH - 10) + 6)
	local z = slot.Y * (Pitch.HALF_WIDTH - 12)
	return Vector3.new(x, Pitch.GROUND_Y + 3, z)
end

return table.freeze(Pitch)

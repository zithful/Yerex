--!strict
-- Pure kick/trajectory maths. No instances, no side effects, so every function
-- here can be unit-tested and reused by server validation and client previews.

local Config = require(script.Parent.Parent.Config)
local Pitch = require(script.Parent.Parent.Pitch)
local Types = require(script.Parent.Parent.Types)

local KickMath = {}

local GRAVITY = Config.BALL_GRAVITY
local BALL_RADIUS = Config.BALL_DIAMETER / 2

function KickMath.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Horizontal unit vector, or `fallback` when the input has no horizontal length.
function KickMath.flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback
	end
	return f.Unit
end

function KickMath.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Angle in degrees between two horizontal directions.
function KickMath.angleBetween(a: Vector3, b: Vector3): number
	local fa, fb = KickMath.flatUnit(a, Vector3.xAxis), KickMath.flatUnit(b, Vector3.xAxis)
	return math.deg(math.acos(math.clamp(fa:Dot(fb), -1, 1)))
end

function KickMath.rotateYaw(v: Vector3, degrees: number): Vector3
	return CFrame.fromAxisAngle(Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(v)
end

-- Velocity that sends the ball from `from` to `to` with the given horizontal
-- speed, solving the vertical component so it arrives at the target height.
function KickMath.ballisticTo(from: Vector3, to: Vector3, horizontalSpeed: number): Vector3
	local delta = to - from
	local flat = KickMath.flat(delta)
	local distance = flat.Magnitude
	if distance < 1e-3 then
		return Vector3.new(0, horizontalSpeed * 0.2, 0)
	end
	local t = distance / horizontalSpeed
	local vy = delta.Y / t + 0.5 * GRAVITY * t
	return flat.Unit * horizontalSpeed + Vector3.new(0, vy, 0)
end

-- Ground pass: firm enough to arrive quickly, softer over short distances.
function KickMath.groundPass(from: Vector3, to: Vector3): Vector3
	local flat = KickMath.flat(to - from)
	local distance = flat.Magnitude
	local speed = math.clamp(
		Config.GROUND_PASS_BASE + distance * Config.GROUND_PASS_PER_STUD,
		Config.GROUND_PASS_BASE,
		Config.GROUND_PASS_MAX
	)
	local dir = KickMath.flatUnit(flat, Vector3.xAxis)
	return dir * speed + Vector3.new(0, 2, 0)
end

-- Lofted pass that lands at `to` (ground level).
function KickMath.lob(from: Vector3, to: Vector3): Vector3
	local distance = KickMath.flat(to - from).Magnitude
	local flightTime = math.clamp(distance / Config.LOB_SPEED, 0.55, 1.7)
	local horizontalSpeed = math.max(distance / flightTime, 10)
	local landing = Vector3.new(to.X, Pitch.GROUND_Y + BALL_RADIUS, to.Z)
	return KickMath.ballisticTo(from, landing, horizontalSpeed)
end

-- Where a team's lead receiver will be after `leadTime` seconds.
function KickMath.leadTarget(position: Vector3, velocity: Vector3, leadTime: number): Vector3
	return position + KickMath.flat(velocity) * leadTime
end

export type ShotKind = "Shoot" | "Finesse" | "LowDriven" | "Header"

-- Projects an aim direction onto the opponent goal line. Returns nil when the
-- player is not facing the goal closely enough for aim assist.
function KickMath.shotTarget(
	from: Vector3,
	dir: Vector3,
	attacking: Types.TeamId,
	kind: ShotKind,
	power: number
): Vector3?
	local defending = Pitch.opponent(attacking)
	local goalX = Pitch.goalLineX(defending)
	local sign = Pitch.attackSign(attacking)
	local aim = KickMath.flatUnit(dir, Vector3.new(sign, 0, 0))

	if (goalX - from.X) * sign <= 0 or aim.X * sign <= 0.05 then
		return nil
	end
	local toGoal = Pitch.goalCenter(defending) - from
	if KickMath.angleBetween(aim, toGoal) > Config.SHOT_AIM_ASSIST_ANGLE then
		return nil
	end

	local t = (goalX - from.X) / aim.X
	local halfGoal = Pitch.GOAL_WIDTH / 2
	-- Slightly past the posts is allowed so a bad aim can still miss.
	local z = math.clamp(from.Z + aim.Z * t, -halfGoal - 3, halfGoal + 3)

	local topCorner = Pitch.GOAL_HEIGHT - 1.2
	local height: number
	if kind == "LowDriven" then
		height = 0.9
	elseif kind == "Finesse" then
		height = KickMath.lerp(1.5, topCorner, power)
	elseif kind == "Header" then
		height = KickMath.lerp(0.8, 3, power)
	else
		height = KickMath.lerp(1.0, topCorner, power ^ 1.6)
		if power > Config.SHOT_OVERPOWER_START then
			local over = (power - Config.SHOT_OVERPOWER_START) / (1 - Config.SHOT_OVERPOWER_START)
			height += over * 6
		end
	end
	-- Aim a little past the goal line so the ball crosses it at the chosen height.
	return Vector3.new(goalX + sign * 2, Pitch.GROUND_Y + BALL_RADIUS + height, z)
end

function KickMath.shotSpeed(kind: ShotKind, power: number): number
	if kind == "Finesse" then
		return KickMath.lerp(Config.FINESSE_MIN_SPEED, Config.FINESSE_MAX_SPEED, power)
	elseif kind == "LowDriven" then
		return KickMath.lerp(Config.LOW_DRIVEN_MIN_SPEED, Config.LOW_DRIVEN_MAX_SPEED, power)
	elseif kind == "Header" then
		return KickMath.lerp(45, 80, power)
	end
	return KickMath.lerp(Config.SHOT_MIN_SPEED, Config.SHOT_MAX_SPEED, power)
end

export type ErrorInputs = {
	kind: ShotKind,
	power: number,
	distanceToGoal: number,
	sprinting: boolean,
	offBalanceDegrees: number, -- angle between body facing and aim
}

-- Spread in degrees. Mirrors the usual football-game rules: distance, sprinting,
-- shooting across the body and over-hitting the power bar all cost accuracy.
function KickMath.shotError(inputs: ErrorInputs): number
	local err = Config.SHOT_BASE_ERROR + inputs.distanceToGoal * Config.SHOT_DISTANCE_ERROR
	if inputs.sprinting then
		err += Config.SHOT_SPRINT_ERROR
	end
	if inputs.offBalanceDegrees > 60 then
		err += Config.SHOT_OFFBALANCE_ERROR * math.clamp((inputs.offBalanceDegrees - 60) / 60, 0, 1)
	end
	if inputs.power > Config.SHOT_OVERPOWER_START then
		local over = (inputs.power - Config.SHOT_OVERPOWER_START)
			/ (1 - Config.SHOT_OVERPOWER_START)
		err += over * Config.SHOT_OVERPOWER_ERROR
	end
	if inputs.kind == "Finesse" then
		err *= 0.75
	elseif inputs.kind == "LowDriven" then
		err *= 1.1
	elseif inputs.kind == "Header" then
		err *= 1.4
	end
	return err
end

-- Rotates a velocity by a random yaw/pitch within `degrees`. Two averaged
-- samples bias results toward the centre, like a real spread.
function KickMath.applyError(velocity: Vector3, degrees: number, rng: Random): Vector3
	local function sample(): number
		return (rng:NextNumber(-1, 1) + rng:NextNumber(-1, 1)) / 2
	end
	local yaw = sample() * degrees
	local pitch = sample() * degrees * 0.5
	local flatDir = KickMath.flatUnit(velocity, Vector3.xAxis)
	local right = flatDir:Cross(Vector3.yAxis)
	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(yaw))
		* CFrame.fromAxisAngle(right, math.rad(pitch))
	return rotation:VectorToWorldSpace(velocity)
end

-- Finesse: start the ball wide of the target and spin it so it bends back in.
-- Returns the launch velocity and the spin (rad/s about +Y) for the ball.
function KickMath.curlShot(from: Vector3, target: Vector3, velocity: Vector3): (Vector3, number)
	local flatTarget = KickMath.flat(target - from)
	local distance = flatTarget.Magnitude
	if distance < 5 then
		return velocity, 0
	end
	local goalCenterZ = 0
	-- Bend around the outside: open the angle away from the goal centre.
	local sideSign = if target.Z >= goalCenterZ then 1 else -1
	local candidateA = KickMath.rotateYaw(velocity, Config.FINESSE_CURL_ANGLE)
	local candidateB = KickMath.rotateYaw(velocity, -Config.FINESSE_CURL_ANGLE)
	local launch = if candidateA.Z * sideSign > candidateB.Z * sideSign
		then candidateA
		else candidateB

	-- Spin needed to recover the lateral offset over the flight.
	-- Lateral accel a = k*w*v, flight time t = d/v, offset L = a*t^2/2
	-- => w = 2*L*v / (k*d^2). Drag makes this approximate; tune CURL_STRENGTH.
	local horizontalSpeed = KickMath.flat(launch).Magnitude
	local offset = distance * math.tan(math.rad(Config.FINESSE_CURL_ANGLE))
	local magnitude = 2 * offset * horizontalSpeed / (Config.CURL_STRENGTH * distance * distance)

	-- With spin w about +Y, Magnus acceleration points along (vz, 0, -vx) * w.
	local lateral = Vector3.new(launch.Z, 0, -launch.X)
	local desired = KickMath.flat(target - from).Unit - KickMath.flatUnit(launch, Vector3.xAxis)
	local spinSign = if lateral:Dot(desired) >= 0 then 1 else -1
	return launch, magnitude * spinSign
end

return KickMath

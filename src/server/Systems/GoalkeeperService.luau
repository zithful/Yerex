--!strict
-- AI goalkeepers, one per goal. They track the ball across the goal mouth,
-- come off the line to narrow angles, react (with a delay) to shots, dive,
-- catch slower shots, parry faster ones by body collision, and distribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BallService = require(script.Parent.BallService)
local Characters = require(script.Parent.Parent.Util.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local KickMath = require(ReplicatedStorage.Shared.Util.KickMath)
local Pitch = require(ReplicatedStorage.Shared.Pitch)
local TeamService = require(script.Parent.TeamService)
local Types = require(ReplicatedStorage.Shared.Types)

type TeamId = Types.TeamId

type Keeper = {
	team: TeamId,
	model: Model,
	body: Part,
	position: Vector3, -- body centre
	lean: number, -- radians, for the dive pose
	reactAt: number?, -- when the keeper starts reacting to the current shot
	holdingSince: number?,
	ignoreBallUntil: number,
	nextSmotherAt: number,
}

local BODY_SIZE = Vector3.new(3, 5.5, 1.6)
local BODY_HALF_HEIGHT = BODY_SIZE.Y / 2
local LINE_OFFSET = 2.5
local MAX_ADVANCE = 9

local GoalkeeperService = {}

local keepers: { Keeper } = {}
local rng = Random.new()

local function homeSpot(team: TeamId): Vector3
	local x = Pitch.goalLineX(team) + Pitch.attackSign(team) * LINE_OFFSET
	return Vector3.new(x, Pitch.GROUND_Y + BODY_HALF_HEIGHT, 0)
end

local function createKeeper(team: TeamId): Keeper
	local model = Instance.new("Model")
	model.Name = team .. "Keeper"

	local color = TeamService.color(team):Lerp(Color3.new(1, 1, 0.3), 0.45)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = BODY_SIZE
	body.Anchored = true
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.25, 1, 1)
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.one * 1.8
	head.Anchored = true
	head.Color = Color3.fromRGB(234, 184, 146)
	head.Parent = model

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(60, 22)
	label.StudsOffset = Vector3.new(0, 2, 0)
	label.AlwaysOnTop = true
	label.Adornee = head
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "GK"
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Parent = label
	label.Parent = head

	model.PrimaryPart = body
	model.Parent = Workspace

	return {
		team = team,
		model = model,
		body = body,
		position = homeSpot(team),
		lean = 0,
		reactAt = nil,
		holdingSince = nil,
		ignoreBallUntil = 0,
		nextSmotherAt = 0,
	}
end

local function render(keeper: Keeper)
	local sign = Pitch.attackSign(keeper.team)
	local facing = CFrame.lookAt(keeper.position, keeper.position + Vector3.new(sign, 0, 0))
	local bodyCFrame = facing * CFrame.Angles(0, 0, keeper.lean)
	keeper.body.CFrame = bodyCFrame
	local head = keeper.model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.CFrame = bodyCFrame * CFrame.new(0, BODY_HALF_HEIGHT + 0.9, 0)
	end
end

local function nearestTeammate(keeper: Keeper): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, player in TeamService.getPlayers(keeper.team) do
		local root = Characters.getRoot(player)
		if root then
			local distance = (root.Position - keeper.position).Magnitude
			if distance < bestDistance and distance > 8 then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

local function distribute(keeper: Keeper)
	local sign = Pitch.attackSign(keeper.team)
	local from = BallService.getBall().Position
	local target = nearestTeammate(keeper)
	local velocity: Vector3
	if target then
		local lead = KickMath.leadTarget(target.Position, target.AssemblyLinearVelocity, 0.6)
		if KickMath.flat(lead - from).Magnitude < 45 then
			velocity = KickMath.groundPass(from, lead)
		else
			velocity = KickMath.lob(from, lead)
		end
	else
		local landing =
			Vector3.new(keeper.position.X + sign * 70, Pitch.GROUND_Y, rng:NextNumber(-30, 30))
		velocity = KickMath.lob(from, landing)
	end
	keeper.holdingSince = nil
	keeper.ignoreBallUntil = os.clock() + 1
	BallService.kick(nil, velocity, 0)
end

local function moveToward(keeper: Keeper, target: Vector3, speed: number, dt: number)
	local delta = target - keeper.position
	local maxStep = speed * dt
	if delta.Magnitude <= maxStep then
		keeper.position = target
	else
		keeper.position += delta.Unit * maxStep
	end
end

local function updateKeeper(keeper: Keeper, dt: number)
	local now = os.clock()
	local ball = BallService.getBall()
	local sign = Pitch.attackSign(keeper.team)
	local home = homeSpot(keeper.team)
	local halfGoal = Pitch.GOAL_WIDTH / 2

	-- Holding: carry the ball, then release it to a teammate.
	if keeper.holdingSince then
		if not BallService.isHeld() then
			keeper.holdingSince = nil -- reset by a kickoff or goal
		else
			BallService.hold(keeper.body.CFrame * CFrame.new(0, 0.5, -1.6))
			keeper.lean = 0
			if now - keeper.holdingSince >= Config.KEEPER_HOLD_TIME then
				distribute(keeper)
			end
			render(keeper)
			return
		end
	end

	local ballPos = ball.Position
	local ballVel = ball.AssemblyLinearVelocity
	local owner = BallService.getOwner()
	local target = home
	local speed = Config.KEEPER_SPEED

	local towardGoal = ballVel.X * sign < -20
	local inOwnHalf = ballPos.X * sign < 0
	local shotIncoming = false
	if towardGoal and inOwnHalf and owner == nil and not BallService.isHeld() then
		local t = (keeper.position.X - ballPos.X) / ballVel.X
		if t > 0 and t < 1.8 then
			local predictedZ = ballPos.Z + ballVel.Z * t
			local predictedY = ballPos.Y + ballVel.Y * t - 0.5 * Config.BALL_GRAVITY * t * t
			if math.abs(predictedZ) < halfGoal + 4 then
				shotIncoming = true
				keeper.reactAt = keeper.reactAt or (now + Config.KEEPER_REACTION)
				if now >= (keeper.reactAt :: number) then
					local lift = math.clamp(predictedY - (Pitch.GROUND_Y + BODY_HALF_HEIGHT), 0, 3)
					target = Vector3.new(
						keeper.position.X,
						Pitch.GROUND_Y + BODY_HALF_HEIGHT + lift,
						math.clamp(predictedZ, -halfGoal - 1, halfGoal + 1)
					)
					speed = Config.KEEPER_DIVE_SPEED
				else
					target = keeper.position
				end
			end
		end
	end

	if not shotIncoming then
		keeper.reactAt = nil
		local toGoal = KickMath.flat(ballPos - Pitch.goalCenter(keeper.team))
		local distance = toGoal.Magnitude
		local inBox = Pitch.isInsideBox(ballPos, keeper.team)
		local opponentOwner = owner ~= nil and TeamService.getTeamId(owner) ~= keeper.team
		if inBox and owner == nil and ballVel.Magnitude < 25 and now >= keeper.ignoreBallUntil then
			-- Loose ball in the box: go and claim it.
			target = Vector3.new(ballPos.X, home.Y, ballPos.Z)
			speed = Config.KEEPER_SPEED * 1.3
		else
			-- Stand on the line between ball and goal centre, stepping out to narrow the angle.
			local advance = math.clamp((Config.KEEPER_RUSH_DISTANCE + 20 - distance) / 30, 0, 1)
				* MAX_ADVANCE
			if opponentOwner and inBox then
				advance = MAX_ADVANCE
			end
			local dir = if distance > 1e-3 then toGoal.Unit else Vector3.new(sign, 0, 0)
			local spot = home + dir * advance
			target =
				Vector3.new(spot.X, home.Y, math.clamp(spot.Z, -halfGoal + 1.5, halfGoal - 1.5))
		end
		-- Never wander far from goal.
		local maxX = Pitch.goalLineX(keeper.team) + sign * Pitch.BOX_DEPTH
		local minX = Pitch.goalLineX(keeper.team) + sign * 1
		local lo, hi = math.min(minX, maxX), math.max(minX, maxX)
		target = Vector3.new(
			math.clamp(target.X, lo, hi),
			target.Y,
			math.clamp(target.Z, -Pitch.BOX_WIDTH / 2, Pitch.BOX_WIDTH / 2)
		)
	end

	local before = keeper.position
	moveToward(keeper, target, speed, dt)
	-- Lean into dives: lateral speed tips the body sideways for extra reach.
	local lateral = (keeper.position.Z - before.Z) / math.max(dt, 1e-3)
	local targetLean = if speed == Config.KEEPER_DIVE_SPEED
		then math.clamp(lateral / Config.KEEPER_DIVE_SPEED, -1, 1) * math.rad(70) * sign
		else 0
	keeper.lean += (targetLean - keeper.lean) * math.min(1, dt * 12)
	render(keeper)

	-- Catching and smothering.
	if now < keeper.ignoreBallUntil or BallService.isHeld() then
		return
	end
	local offset = ballPos - keeper.position
	local reach = Config.KEEPER_CATCH_RADIUS + math.abs(keeper.lean) * 1.5
	if offset.Magnitude <= reach then
		if owner == nil and ballVel.Magnitude <= Config.KEEPER_CATCH_SPEED then
			keeper.holdingSince = now
			BallService.hold(keeper.body.CFrame * CFrame.new(0, 0.5, -1.6))
		elseif
			owner
			and TeamService.getTeamId(owner) ~= keeper.team
			and now >= keeper.nextSmotherAt
		then
			keeper.nextSmotherAt = now + 0.8
			if rng:NextNumber() < 0.45 then
				BallService.blockPickup(owner, 0.6)
				keeper.holdingSince = now
				BallService.hold(keeper.body.CFrame * CFrame.new(0, 0.5, -1.6))
			end
		end
	end
end

function GoalkeeperService.init()
	table.insert(keepers, createKeeper(Pitch.HOME))
	table.insert(keepers, createKeeper(Pitch.AWAY))
	for _, keeper in keepers do
		render(keeper)
	end
end

function GoalkeeperService.start()
	RunService.Heartbeat:Connect(function(dt)
		for _, keeper in keepers do
			updateKeeper(keeper, dt)
		end
	end)
end

-- Back to the line, hands empty. Called at every kickoff.
function GoalkeeperService.reset()
	for _, keeper in keepers do
		keeper.position = homeSpot(keeper.team)
		keeper.lean = 0
		keeper.reactAt = nil
		keeper.holdingSince = nil
		keeper.ignoreBallUntil = 0
		render(keeper)
	end
end

return GoalkeeperService

--!strict
-- Receives action requests from clients and turns them into ball physics.
-- Every request is untrusted: types, ranges, rate, possession, distance and
-- cooldowns are all checked here before anything happens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AthleteService = require(script.Parent.AthleteService)
local BallService = require(script.Parent.BallService)
local Characters = require(script.Parent.Parent.Util.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local KickMath = require(ReplicatedStorage.Shared.Util.KickMath)
local MatchService = require(script.Parent.MatchService)
local Net = require(ReplicatedStorage.Shared.Net)
local Pitch = require(ReplicatedStorage.Shared.Pitch)
local TeamService = require(script.Parent.TeamService)
local Types = require(ReplicatedStorage.Shared.Types)

type ActionKind = Types.ActionKind
type ActionPayload = Types.ActionPayload
type TeamId = Types.TeamId

type Slide = {
	endsAt: number,
	dir: Vector3,
	resolved: boolean,
}

local VALID_KINDS: { [string]: boolean } = {
	Pass = true,
	Through = true,
	Lob = true,
	Shoot = true,
	Finesse = true,
	LowDriven = true,
	Tackle = true,
	Slide = true,
	KnockOn = true,
	DragBack = true,
	Sprint = true,
}

local ActionService = {}

local rng = Random.new()
local feedback: RemoteEvent
local tokens: { [Player]: number } = {}
local lastRefill: { [Player]: number } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local slides: { [Player]: Slide } = {}

-- Token bucket: ACTIONS_PER_SECOND sustained, small burst allowed.
local function allowRate(player: Player): boolean
	local now = os.clock()
	local last = lastRefill[player] or now
	local available = math.min(
		Config.ACTIONS_PER_SECOND,
		(tokens[player] or Config.ACTIONS_PER_SECOND) + (now - last) * Config.ACTIONS_PER_SECOND
	)
	lastRefill[player] = now
	if available < 1 then
		tokens[player] = available
		return false
	end
	tokens[player] = available - 1
	return true
end

local function onCooldown(player: Player, key: string, seconds: number): boolean
	local map = cooldowns[player]
	if not map then
		map = {}
		cooldowns[player] = map
	end
	local now = os.clock()
	if (map[key] or 0) > now then
		return true
	end
	map[key] = now + seconds
	return false
end

local function isFiniteVector(v: Vector3): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < 1e6
		and math.abs(v.Y) < 1e6
		and math.abs(v.Z) < 1e6
end

local function parsePayload(raw: unknown): ActionPayload?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [any]: any }
	local kind, dir, power, flag = data.kind, data.dir, data.power, data.flag
	if typeof(kind) ~= "string" or not VALID_KINDS[kind] then
		return nil
	end
	if typeof(dir) ~= "Vector3" or not isFiniteVector(dir) then
		return nil
	end
	if typeof(power) ~= "number" or power ~= power then
		return nil
	end
	if flag ~= nil and typeof(flag) ~= "boolean" then
		return nil
	end
	return {
		kind = kind :: ActionKind,
		dir = dir,
		power = math.clamp(power, 0, 1),
		flag = flag,
	}
end

local function toast(player: Player, message: string)
	feedback:FireClient(player, "Toast", message)
end

-- Picks the teammate best placed to receive a pass aimed along `dir`.
local function findReceiver(player: Player, team: TeamId, from: Vector3, dir: Vector3): BasePart?
	local best: BasePart? = nil
	local bestScore = math.huge
	for _, mate in TeamService.getPlayers(team) do
		if mate == player then
			continue
		end
		local root = Characters.getRoot(mate)
		if not root then
			continue
		end
		local offset = KickMath.flat(root.Position - from)
		local distance = offset.Magnitude
		if distance < 4 or distance > Config.PASS_MAX_RANGE then
			continue
		end
		local angle = KickMath.angleBetween(dir, offset)
		if angle > Config.PASS_ASSIST_ANGLE then
			continue
		end
		local score = angle + distance * 0.12
		if score < bestScore then
			best, bestScore = root, score
		end
	end
	return best
end

local function handlePass(player: Player, team: TeamId, kind: ActionKind, aim: Vector3)
	local ball = BallService.getBall()
	local from = ball.Position
	local receiver = findReceiver(player, team, from, aim)
	local velocity: Vector3

	if kind == "Pass" then
		local target = if receiver
			then KickMath.leadTarget(receiver.Position, receiver.AssemblyLinearVelocity, 0.25)
			else from + aim * Config.PASS_DEFAULT_DISTANCE
		velocity = KickMath.groundPass(from, target)
	elseif kind == "Through" then
		local target: Vector3
		if receiver then
			local runDir = KickMath.flatUnit(receiver.AssemblyLinearVelocity, aim)
			target = KickMath.leadTarget(
				receiver.Position,
				receiver.AssemblyLinearVelocity,
				Config.THROUGH_LEAD_TIME
			) + runDir * 6
		else
			target = from + aim * (Config.PASS_DEFAULT_DISTANCE + 15)
		end
		velocity = KickMath.groundPass(from, target)
	else -- Lob
		local target = if receiver
			then KickMath.leadTarget(receiver.Position, receiver.AssemblyLinearVelocity, 0.7)
			else from + aim * (Config.PASS_DEFAULT_DISTANCE + 25)
		velocity = KickMath.lob(from, target)
	end

	local spread = 1 + (if AthleteService.isSprinting(player) then 2 else 0)
	BallService.kick(player, KickMath.applyError(velocity, spread, rng), 0)
end

local function handleShot(
	player: Player,
	team: TeamId,
	root: BasePart,
	kind: ActionKind,
	aim: Vector3,
	power: number
)
	local ball = BallService.getBall()
	local owner = BallService.getOwner()
	local shotKind: KickMath.ShotKind = kind :: any

	if owner ~= player then
		-- First-time finish: volley or header on a loose ball within reach.
		if owner ~= nil or BallService.isHeld() then
			return
		end
		if (ball.Position - root.Position).Magnitude > Config.FIRST_TIME_RADIUS then
			return
		end
		if ball.Position.Y > root.Position.Y + 1.2 then
			shotKind = "Header"
		end
	end

	local from = ball.Position
	local speed = KickMath.shotSpeed(shotKind, power)
	local target = KickMath.shotTarget(from, aim, team, shotKind, power)
	local velocity = if target
		then KickMath.ballisticTo(from, target, speed)
		else aim * speed + Vector3.new(0, speed * 0.12, 0)

	local look = root.CFrame.LookVector
	local spread = KickMath.shotError({
		kind = shotKind,
		power = power,
		distanceToGoal = KickMath.flat(from - Pitch.goalCenter(Pitch.opponent(team))).Magnitude,
		sprinting = AthleteService.isSprinting(player),
		offBalanceDegrees = KickMath.angleBetween(look, aim),
	})
	if owner ~= player then
		spread *= 1.35 -- first-time strikes are harder to place
	end

	local spin = 0
	if shotKind == "Finesse" and target then
		velocity, spin = KickMath.curlShot(from, target, velocity)
	end
	velocity = KickMath.applyError(velocity, spread, rng)
	BallService.kick(player, velocity, spin)
end

local function handleTackle(player: Player, team: TeamId, root: BasePart)
	if onCooldown(player, "Tackle", Config.TACKLE_COOLDOWN) then
		return
	end
	local owner = BallService.getOwner()
	if not owner or TeamService.getTeamId(owner) == team then
		return
	end
	local ownerRoot = Characters.getRoot(owner)
	if not ownerRoot then
		return
	end
	local toOwner = KickMath.flat(ownerRoot.Position - root.Position)
	if toOwner.Magnitude > Config.TACKLE_RANGE * 1.6 then
		return -- nowhere near: ignore rather than punish button mashing
	elseif toOwner.Magnitude > Config.TACKLE_RANGE then
		AthleteService.stun(player, Config.TACKLE_MISS_STUN) -- lunged and missed
		return
	end
	local facing = KickMath.flatUnit(root.CFrame.LookVector, Vector3.xAxis):Dot(toOwner.Unit)
	-- Tackling from behind the dribbler is much less effective.
	local fromBehind = KickMath.flatUnit(ownerRoot.CFrame.LookVector, Vector3.xAxis)
		:Dot(-toOwner.Unit) < -0.3
	local chance = if fromBehind then Config.TACKLE_BEHIND_CHANCE else Config.TACKLE_FRONT_CHANCE
	if facing < 0.2 then
		chance *= 0.5
	end
	if AthleteService.isSprinting(owner) then
		chance *= 0.85
	end

	if rng:NextNumber() < chance then
		AthleteService.stun(owner, Config.TACKLED_STUN)
		BallService.blockPickup(owner, Config.TACKLED_STUN + 0.2)
		toast(owner, "Tackled!")
		if rng:NextNumber() < 0.6 then
			BallService.setOwner(player)
		else
			-- Poked loose rather than won cleanly.
			local poke = KickMath.flatUnit(root.CFrame.LookVector, Vector3.xAxis) * 30
				+ Vector3.new(0, 4, 0)
			BallService.kick(player, poke, 0, 0.15)
		end
	else
		AthleteService.stun(player, Config.TACKLE_MISS_STUN)
		toast(player, "Missed tackle")
	end
end

local function handleSlide(player: Player, root: BasePart)
	if onCooldown(player, "Slide", Config.SLIDE_COOLDOWN) then
		return
	end
	slides[player] = {
		endsAt = os.clock() + Config.SLIDE_DURATION,
		dir = KickMath.flatUnit(root.CFrame.LookVector, Vector3.xAxis),
		resolved = false,
	}
end

-- Checks active slides against the ball every frame.
local function updateSlides()
	local now = os.clock()
	local ball = BallService.getBall()
	for player, slide in slides do
		local root = Characters.getRoot(player)
		if not root or now > slide.endsAt then
			slides[player] = nil
			AthleteService.stun(player, Config.SLIDE_RECOVERY)
			continue
		end
		if slide.resolved or BallService.isHeld() then
			continue
		end
		local offset = ball.Position - root.Position
		if KickMath.flat(offset).Magnitude > Config.SLIDE_REACH or offset.Y > 3 then
			continue
		end
		slide.resolved = true
		local victim = BallService.getOwner()
		local team = TeamService.getTeamId(player)
		if victim and victim ~= player and TeamService.getTeamId(victim) ~= team then
			local victimRoot = Characters.getRoot(victim)
			local fromBehind = victimRoot ~= nil
				and KickMath.flatUnit(victimRoot.CFrame.LookVector, Vector3.xAxis)
						:Dot(slide.dir)
					> 0.6
			if fromBehind and rng:NextNumber() < 0.6 then
				-- Foul: through the back of the player. They keep the ball.
				AthleteService.stun(player, Config.SLIDE_FOUL_STUN)
				toast(player, "Foul! Slid in from behind")
				toast(victim, "Fouled!")
				continue
			end
			AthleteService.stun(victim, Config.TACKLED_STUN)
			BallService.blockPickup(victim, Config.TACKLED_STUN + 0.2)
			toast(victim, "Slide tackled!")
		end
		BallService.kick(player, slide.dir * 40 + Vector3.new(0, 5, 0), 0, 0.4)
	end
end

local function handleSkill(player: Player, root: BasePart, kind: ActionKind, aim: Vector3)
	if onCooldown(player, "Skill", Config.SKILL_COOLDOWN) then
		return
	end
	if kind == "KnockOn" then
		BallService.kick(player, aim * Config.KNOCK_ON_SPEED + Vector3.new(0, 3, 0), 0, 0.18)
	else -- DragBack: roll it back under the sole; the client turns the body.
		local back = -KickMath.flatUnit(root.CFrame.LookVector, Vector3.xAxis)
		BallService.kick(player, back * Config.DRAG_BACK_SPEED, 0, 0.22)
	end
end

local function onAction(player: Player, raw: unknown)
	if not allowRate(player) then
		return
	end
	local payload = parsePayload(raw)
	if not payload then
		return
	end

	if payload.kind == "Sprint" then
		AthleteService.setSprint(player, payload.flag == true)
		return
	end
	if not MatchService.isBallLive() or AthleteService.isStunned(player) then
		return
	end
	local team = TeamService.getTeamId(player)
	local root = Characters.getRoot(player)
	if not team or not root then
		return
	end

	-- Aim is the client's stick/movement direction. Only its horizontal heading
	-- is used, so it cannot add power or height.
	local aim =
		KickMath.flatUnit(payload.dir, KickMath.flatUnit(root.CFrame.LookVector, Vector3.xAxis))
	local kind = payload.kind
	local hasBall = BallService.getOwner() == player

	if kind == "Pass" or kind == "Through" or kind == "Lob" then
		if hasBall then
			handlePass(player, team, kind, aim)
		end
	elseif kind == "Shoot" or kind == "Finesse" or kind == "LowDriven" then
		handleShot(player, team, root, kind, aim, payload.power)
	elseif kind == "Tackle" then
		handleTackle(player, team, root)
	elseif kind == "Slide" then
		handleSlide(player, root)
	elseif kind == "KnockOn" or kind == "DragBack" then
		if hasBall then
			handleSkill(player, root, kind, aim)
		end
	end
end

function ActionService.init()
	feedback = Net.feedback()
	Net.action().OnServerEvent:Connect(onAction)
end

function ActionService.start()
	Players.PlayerRemoving:Connect(function(player)
		tokens[player] = nil
		lastRefill[player] = nil
		cooldowns[player] = nil
		slides[player] = nil
	end)
	RunService.Heartbeat:Connect(updateSlides)
end

return ActionService

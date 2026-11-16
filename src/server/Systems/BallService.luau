--!strict
-- The match ball. Server-owned physics: clients never get network ownership,
-- so they cannot teleport the ball into a goal. Possession is a server concept;
-- while a player owns the ball it is steered in front of their feet (dribbling).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Characters = require(script.Parent.Parent.Util.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local Pitch = require(ReplicatedStorage.Shared.Pitch)

local BALL_RADIUS = Config.BALL_DIAMETER / 2

local BallService = {}

local ball: Part
local antiGravity: VectorForce
local owner: Player? = nil
local lastToucher: Player? = nil
local spin = 0 -- rad/s about +Y; drives curl
local held = false -- a goalkeeper is holding the ball
local frozen = false -- kickoff: ball pinned at the spot
local pickupBlockedUntil: { [Player]: number } = {}

local function setOwner(player: Player?)
	if owner == player then
		return
	end
	owner = player
	if player then
		lastToucher = player
		spin = 0
	end
	ball:SetAttribute("OwnerUserId", if player then player.UserId else 0)
end

local function createBall(): Part
	local part = Instance.new("Part")
	part.Name = "MatchBall"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Config.BALL_DIAMETER
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(245, 245, 245)
	part.CustomPhysicalProperties = PhysicalProperties.new(
		Config.BALL_DENSITY,
		Config.BALL_FRICTION,
		Config.BALL_ELASTICITY,
		1,
		1
	)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Position = Vector3.new(0, Pitch.GROUND_Y + BALL_RADIUS + 0.5, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "Center"
	attachment.Parent = part

	-- Reduce effective gravity so flight paths read like a real football.
	local force = Instance.new("VectorForce")
	force.Name = "AntiGravity"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Parent = part
	antiGravity = force

	local trailA = Instance.new("Attachment")
	trailA.Position = Vector3.new(0, 0.4, 0)
	trailA.Parent = part
	local trailB = Instance.new("Attachment")
	trailB.Position = Vector3.new(0, -0.4, 0)
	trailB.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailA
	trail.Attachment1 = trailB
	trail.Lifetime = 0.25
	trail.MinLength = 0.5
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.Parent = part

	part:SetAttribute("OwnerUserId", 0)
	part.Parent = Workspace
	return part
end

-- Anchoring drops network ownership, so re-assert server ownership whenever the
-- ball is released; otherwise Roblox may hand it to a nearby client.
local function setAnchored(value: boolean)
	ball.Anchored = value
	if not value then
		ball:SetNetworkOwner(nil)
	end
end

local function updateAntiGravity()
	antiGravity.Force =
		Vector3.new(0, ball.AssemblyMass * (Workspace.Gravity - Config.BALL_GRAVITY), 0)
end

local function isOnGround(): boolean
	return ball.Position.Y <= Pitch.GROUND_Y + BALL_RADIUS + 0.35
end

-- Keep the ball in front of the owner's feet. Velocity steering (not CFrame
-- writes) keeps collisions and replication smooth.
local function dribble(player: Player)
	local root = Characters.getRoot(player)
	if not root then
		setOwner(nil)
		return
	end
	local rootVelocity = root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(rootVelocity.X, 0, rootVelocity.Z)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.xAxis
	end
	local ahead = Config.DRIBBLE_DISTANCE + flatVelocity.Magnitude * Config.DRIBBLE_SPEED_LEAD
	local target = Vector3.new(root.Position.X, Pitch.GROUND_Y + BALL_RADIUS, root.Position.Z)
		+ look.Unit * ahead
	local delta = target - ball.Position

	if Vector3.new(delta.X, 0, delta.Z).Magnitude > Config.DRIBBLE_LOSE_DISTANCE then
		-- Something knocked the ball away (a body, a post): possession is lost.
		setOwner(nil)
		return
	end

	local steer = delta * Config.DRIBBLE_STIFFNESS
	ball.AssemblyLinearVelocity = Vector3.new(
		flatVelocity.X + steer.X,
		math.min(ball.AssemblyLinearVelocity.Y, 0) + steer.Y,
		flatVelocity.Z + steer.Z
	)
end

-- Loose ball: the closest eligible player within reach takes control, unless
-- it is travelling too fast to trap.
local function tryPickup()
	if ball.Position.Y > Pitch.GROUND_Y + Config.PICKUP_MAX_HEIGHT then
		return
	end
	local now = os.clock()
	local best: Player? = nil
	local bestDistance = Config.PICKUP_RADIUS
	for _, player in Players:GetPlayers() do
		if (pickupBlockedUntil[player] or 0) > now then
			continue
		end
		local root = Characters.getRoot(player)
		if not root then
			continue
		end
		local offset = ball.Position - root.Position
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if distance >= bestDistance then
			continue
		end
		local relative = ball.AssemblyLinearVelocity - root.AssemblyLinearVelocity
		if relative.Magnitude > Config.TRAP_MAX_SPEED then
			continue
		end
		best, bestDistance = player, distance
	end
	if best then
		setOwner(best)
	end
end

local function applyFlightForces(dt: number)
	local velocity = ball.AssemblyLinearVelocity
	if isOnGround() then
		local keep = math.max(0, 1 - Config.ROLL_DRAG * dt)
		velocity = Vector3.new(velocity.X * keep, velocity.Y, velocity.Z * keep)
	else
		velocity *= math.max(0, 1 - Config.AIR_DRAG * dt)
		if math.abs(spin) > 0.01 then
			-- Magnus effect for spin about +Y: accel = k * w * (vz, 0, -vx).
			local curl = Vector3.new(velocity.Z, 0, -velocity.X) * spin * Config.CURL_STRENGTH * dt
			velocity += curl
		end
	end
	spin *= math.max(0, 1 - Config.SPIN_DECAY * dt)
	if isOnGround() then
		spin *= math.max(0, 1 - 4 * dt) -- grass kills spin quickly
	end
	ball.AssemblyLinearVelocity = velocity
end

local function step(dt: number)
	if held or frozen then
		return
	end
	updateAntiGravity()
	if owner then
		dribble(owner)
	else
		tryPickup()
		if not owner then
			applyFlightForces(dt)
		end
	end
end

function BallService.init()
	ball = createBall()
end

function BallService.start()
	ball:SetNetworkOwner(nil)
	ball.Touched:Connect(function(part)
		local player = Characters.playerFromPart(part)
		if player then
			lastToucher = player
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pickupBlockedUntil[player] = nil
		if owner == player then
			setOwner(nil)
		end
		if lastToucher == player then
			lastToucher = nil
		end
	end)
	RunService.Heartbeat:Connect(step)
end

function BallService.getBall(): Part
	return ball
end

function BallService.getOwner(): Player?
	return owner
end

function BallService.setOwner(player: Player?)
	setOwner(player)
end

function BallService.getLastToucher(): Player?
	return lastToucher
end

function BallService.isHeld(): boolean
	return held
end

-- Strikes the ball. `kicker` loses possession and cannot re-collect for
-- `blockSeconds`, so the ball can leave their feet.
function BallService.kick(
	kicker: Player?,
	velocity: Vector3,
	spinRate: number,
	blockSeconds: number?
)
	if frozen then
		return
	end
	setOwner(nil)
	held = false
	if ball.Anchored then
		setAnchored(false)
	end
	if kicker then
		lastToucher = kicker
		pickupBlockedUntil[kicker] = os.clock() + (blockSeconds or Config.KICK_PICKUP_BLOCK)
	end
	-- Lift the ball off the turf so the first frame of flight is not eaten by friction.
	if velocity.Y > 1 and isOnGround() then
		ball.CFrame += Vector3.new(0, 0.15, 0)
	end
	ball.AssemblyLinearVelocity = velocity
	ball.AssemblyAngularVelocity = Vector3.zero
	spin = spinRate
end

-- Stops anyone collecting the ball for a moment (e.g. right after a tackle).
function BallService.blockPickup(player: Player, seconds: number)
	pickupBlockedUntil[player] = math.max(pickupBlockedUntil[player] or 0, os.clock() + seconds)
end

-- Goalkeeper hands: pins the ball to a CFrame until kicked or released.
function BallService.hold(cframe: CFrame)
	setOwner(nil)
	held = true
	spin = 0
	setAnchored(true)
	ball.CFrame = cframe
end

function BallService.release()
	held = false
	setAnchored(frozen)
end

-- Places the ball on a spot, optionally pinned until `setFrozen(false)`.
function BallService.reset(position: Vector3, freeze: boolean)
	setOwner(nil)
	held = false
	spin = 0
	lastToucher = nil
	table.clear(pickupBlockedUntil)
	frozen = freeze
	ball.CFrame = CFrame.new(position)
	setAnchored(freeze)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

function BallService.setFrozen(value: boolean)
	frozen = value
	setAnchored(value or held)
end

return BallService

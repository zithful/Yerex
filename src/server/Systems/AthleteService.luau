--!strict
-- Per-player movement state: sprinting, stamina/fatigue, stuns and kickoff freezes.
-- WalkSpeed is derived here every frame so every speed rule lives in one place.
-- Note: characters are client-owned physics, so a determined exploiter can still
-- move faster than WalkSpeed; ball actions are validated separately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallService = require(script.Parent.BallService)
local Config = require(ReplicatedStorage.Shared.Config)

type State = {
	stamina: number,
	sprintRequested: boolean,
	sprinting: boolean,
	stunUntil: number,
	lastStaminaSent: number,
}

local AthleteService = {}

local states: { [Player]: State } = {}
local frozen = false

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = {
			stamina = Config.STAMINA_MAX,
			sprintRequested = false,
			sprinting = false,
			stunUntil = 0,
			lastStaminaSent = -1,
		}
		states[player] = state
	end
	return state
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function update(dt: number)
	local now = os.clock()
	local owner = BallService.getOwner()
	for _, player in Players:GetPlayers() do
		local state = getState(player)
		local humanoid, root = getHumanoid(player)
		if not humanoid or not root then
			continue
		end

		local moving = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			> 2
		state.sprinting = state.sprintRequested and moving and state.stamina > 0

		if state.sprinting then
			state.stamina = math.max(0, state.stamina - Config.STAMINA_DRAIN * dt)
		else
			state.stamina = math.min(Config.STAMINA_MAX, state.stamina + Config.STAMINA_REGEN * dt)
		end

		local speed: number
		if frozen or now < state.stunUntil then
			speed = 0
		else
			speed = if state.sprinting then Config.SPRINT_SPEED else Config.JOG_SPEED
			if owner == player then
				speed *= Config.DRIBBLE_SPEED_MULT
			end
			-- Fatigue: a tired player loses top speed, not just the sprint button.
			if state.stamina < Config.FATIGUE_THRESHOLD then
				local t = state.stamina / Config.FATIGUE_THRESHOLD
				speed *= Config.FATIGUE_MIN_MULT + (1 - Config.FATIGUE_MIN_MULT) * t
			end
		end
		humanoid.WalkSpeed = speed
		humanoid.JumpHeight = if speed == 0 then 0 else 6

		local rounded = math.floor(state.stamina + 0.5)
		if rounded ~= state.lastStaminaSent then
			state.lastStaminaSent = rounded
			player:SetAttribute("Stamina", rounded)
		end
	end
end

function AthleteService.init() end

function AthleteService.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RunService.Heartbeat:Connect(update)
end

function AthleteService.setSprint(player: Player, enabled: boolean)
	getState(player).sprintRequested = enabled
end

function AthleteService.isSprinting(player: Player): boolean
	return getState(player).sprinting
end

function AthleteService.stun(player: Player, seconds: number)
	local state = getState(player)
	state.stunUntil = math.max(state.stunUntil, os.clock() + seconds)
end

function AthleteService.isStunned(player: Player): boolean
	return frozen or os.clock() < getState(player).stunUntil
end

function AthleteService.setFrozen(value: boolean)
	frozen = value
end

function AthleteService.resetStamina()
	for _, state in states do
		state.stamina = Config.STAMINA_MAX
	end
end

return AthleteService

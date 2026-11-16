--!strict
-- Maps keyboard/mouse, gamepad and touch input to action requests.
-- The client only sends intent (kind, aim, charge); the server decides outcomes.
--
-- Keyboard/mouse            Gamepad                 Action
-- Left click / J (hold)     B (hold)                Shoot (charge)  | Tackle without the ball
-- G (hold)                  R1 + B                  Finesse shot
-- T (hold)                  L1 + B                  Low driven shot
-- E                         A                       Ground pass
-- R                         Y                       Through pass
-- Q                         X                       Lofted pass     | Slide without the ball
-- F                         -                       Standing tackle
-- C                         -                       Slide tackle
-- Left Shift (hold)         RT (hold)               Sprint
-- Z                         R3                      Knock-on
-- X                         L3                      Drag-back
-- H                         -                       Toggle controls help

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)

type ActionKind = Types.ActionKind

local player = Players.LocalPlayer
local actionRemote: RemoteEvent

local InputController = {}

local sprintToggled = false

local function getCharacterParts(): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then
		return root, humanoid
	end
	return nil, nil
end

local function getBall(): BasePart?
	local ball = Workspace:FindFirstChild("MatchBall")
	return if ball and ball:IsA("BasePart") then ball else nil
end

local function hasBall(): boolean
	local ball = getBall()
	return ball ~= nil and ball:GetAttribute("OwnerUserId") == player.UserId
end

-- Loose ball close enough for a volley or header.
local function ballInReach(): boolean
	local ball = getBall()
	local root = getCharacterParts()
	if not ball or not root then
		return false
	end
	return ball:GetAttribute("OwnerUserId") == 0
		and (ball.Position - root.Position).Magnitude <= Config.FIRST_TIME_RADIUS
end

-- Aim follows the movement stick/keys, like a console football game; when
-- standing still it falls back to the way the player is facing.
local function aimDirection(): Vector3
	local root, humanoid = getCharacterParts()
	if not root or not humanoid then
		return Vector3.xAxis
	end
	local move = humanoid.MoveDirection
	if move.Magnitude > 0.1 then
		return Vector3.new(move.X, 0, move.Z).Unit
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function send(kind: ActionKind, power: number?, flag: boolean?)
	local payload: Types.ActionPayload = {
		kind = kind,
		dir = aimDirection(),
		power = power or 0,
		flag = flag,
	}
	actionRemote:FireServer(payload)
end

local function isGamepadDown(key: Enum.KeyCode): boolean
	return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
end

local function beginCharge(kind: string)
	ClientState.chargeStart = os.clock()
	ClientState.chargeKind = kind
end

local function releaseCharge(kind: string)
	if ClientState.chargeKind ~= kind or not ClientState.chargeStart then
		return
	end
	local power = math.clamp((os.clock() - ClientState.chargeStart) / Config.CHARGE_TIME, 0, 1)
	ClientState.chargeStart = nil
	ClientState.chargeKind = nil
	local shot: ActionKind = "Shoot"
	if kind == "Finesse" then
		shot = "Finesse"
	elseif kind == "LowDriven" then
		shot = "LowDriven"
	elseif isGamepadDown(Enum.KeyCode.ButtonR1) then
		shot = "Finesse"
	elseif isGamepadDown(Enum.KeyCode.ButtonL1) then
		shot = "LowDriven"
	end
	send(shot, power)
end

-- Slide tackles are physically driven on the client (it owns its character);
-- the server separately checks whether the slide reaches the ball.
local function slideDash()
	local root, humanoid = getCharacterParts()
	if not root or not humanoid or humanoid.WalkSpeed <= 0 then
		return
	end
	send("Slide")
	local attachment = root:FindFirstChildOfClass("Attachment")
	if not attachment then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	mover.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	mover.VectorVelocity = look * 40
	mover.Parent = root
	task.delay(Config.SLIDE_DURATION, function()
		mover:Destroy()
	end)
end

type Handler = (Enum.UserInputState) -> ()

local function bind(
	name: string,
	handler: Handler,
	touch: boolean,
	...: Enum.KeyCode | Enum.UserInputType
)
	ContextActionService:BindAction(name, function(_, inputState: Enum.UserInputState)
		handler(inputState)
		return Enum.ContextActionResult.Sink
	end, touch, ...)
end

local function onBegin(callback: () -> ()): Handler
	return function(inputState)
		if inputState == Enum.UserInputState.Begin then
			callback()
		end
	end
end

local function chargeHandler(kind: string, contextual: boolean): Handler
	return function(inputState)
		if inputState == Enum.UserInputState.Begin then
			if hasBall() or ballInReach() then
				beginCharge(kind)
			elseif contextual then
				send("Tackle")
			end
		elseif
			inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
		then
			releaseCharge(kind)
		end
	end
end

local function setupTouchButton(name: string, title: string, position: UDim2)
	ContextActionService:SetTitle(name, title)
	ContextActionService:SetPosition(name, position)
end

function InputController.init()
	actionRemote = Net.action()
end

function InputController.start()
	bind(
		"YxShoot",
		chargeHandler("Shoot", true),
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.J,
		Enum.KeyCode.ButtonB
	)
	bind("YxFinesse", chargeHandler("Finesse", false), false, Enum.KeyCode.G)
	bind("YxLowDriven", chargeHandler("LowDriven", false), false, Enum.KeyCode.T)

	bind(
		"YxPass",
		onBegin(function()
			send("Pass")
		end),
		true,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonA
	)
	bind(
		"YxThrough",
		onBegin(function()
			send("Through")
		end),
		true,
		Enum.KeyCode.R,
		Enum.KeyCode.ButtonY
	)
	bind(
		"YxLob",
		onBegin(function()
			if hasBall() then
				send("Lob")
			else
				slideDash()
			end
		end),
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonX
	)

	bind(
		"YxTackle",
		onBegin(function()
			send("Tackle")
		end),
		false,
		Enum.KeyCode.F
	)
	bind("YxSlide", onBegin(slideDash), true, Enum.KeyCode.C)

	bind("YxSprint", function(inputState)
		if inputState == Enum.UserInputState.Begin then
			send("Sprint", 0, true)
		elseif
			inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
		then
			send("Sprint", 0, false)
		end
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)

	bind(
		"YxKnockOn",
		onBegin(function()
			send("KnockOn")
		end),
		false,
		Enum.KeyCode.Z,
		Enum.KeyCode.ButtonR3
	)
	bind(
		"YxDragBack",
		onBegin(function()
			if not hasBall() then
				return
			end
			send("DragBack")
			local root = getCharacterParts()
			if root then
				root.CFrame *= CFrame.Angles(0, math.pi, 0)
			end
		end),
		false,
		Enum.KeyCode.X,
		Enum.KeyCode.ButtonL3
	)

	bind(
		"YxHelp",
		onBegin(function()
			ClientState.showHelp = not ClientState.showHelp
		end),
		false,
		Enum.KeyCode.H
	)

	-- Touch: sprint is a toggle because holding two buttons on a phone is awkward.
	ContextActionService:BindAction("YxSprintToggle", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			sprintToggled = not sprintToggled
			send("Sprint", 0, sprintToggled)
			ContextActionService:SetTitle(
				"YxSprintToggle",
				if sprintToggled then "Jog" else "Sprint"
			)
		end
		return Enum.ContextActionResult.Sink
	end, true)

	if UserInputService.TouchEnabled then
		setupTouchButton("YxShoot", "Shoot", UDim2.new(1, -95, 1, -170))
		setupTouchButton("YxPass", "Pass", UDim2.new(1, -170, 1, -110))
		setupTouchButton("YxThrough", "Thru", UDim2.new(1, -170, 1, -185))
		setupTouchButton("YxSlide", "Slide", UDim2.new(1, -245, 1, -110))
		setupTouchButton("YxSprintToggle", "Sprint", UDim2.new(1, -245, 1, -185))
	end

	-- Losing focus mid-sprint should not leave the server thinking we still sprint.
	UserInputService.WindowFocusReleased:Connect(function()
		send("Sprint", 0, false)
	end)
end

return InputController

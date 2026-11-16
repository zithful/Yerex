--!strict
-- Scoreboard, clock, banners, stamina and shot-power bars, possession cue,
-- toasts and the controls panel. Built in code so it is reviewable as text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer

local HOME_COLOR = Color3.fromRGB(196, 40, 28)
local AWAY_COLOR = Color3.fromRGB(13, 105, 172)
local PANEL = Color3.fromRGB(18, 22, 32)
local TEXT = Color3.fromRGB(240, 242, 248)
local MUTED = Color3.fromRGB(160, 168, 186)

local HELP_TEXT = table.concat({
	"<b>ATTACK</b>",
	"Shoot: hold Left Click / J / B, release",
	"Finesse shot: hold G (pad: R1 + B)",
	"Low driven shot: hold T (pad: L1 + B)",
	"Pass: E / A    Through: R / Y",
	"Lofted pass: Q / X",
	"Knock-on: Z / R3    Drag-back: X / L3",
	"Sprint: hold Shift / RT",
	"",
	"<b>DEFEND</b>",
	"Tackle: F, or shoot button without the ball",
	"Slide: C, or Q / X without the ball",
	"Tackles from behind rarely win the ball.",
	"",
	"Aim with your movement keys or stick. H hides this.",
}, "\n")

local HudController = {}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
	}
	for key, value in props do
		base[key] = value
	end
	return make("TextLabel", base, parent)
end

local function formatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function HudController.start()
	local state = Net.matchState()
	local gui = make("ScreenGui", {
		Name = "YerexHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- Scoreboard
	local board = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(340, 44),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
	}, gui)
	corner(board, 10)
	local homeTag = make("Frame", {
		Size = UDim2.new(0, 96, 1, 0),
		BackgroundColor3 = HOME_COLOR,
	}, board)
	corner(homeTag, 10)
	label(
		homeTag,
		{ Size = UDim2.new(1, -12, 0.6, 0), Position = UDim2.new(0, 6, 0.2, 0), Text = "CRIMSON" }
	)
	local awayTag = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 96, 1, 0),
		BackgroundColor3 = AWAY_COLOR,
	}, board)
	corner(awayTag, 10)
	label(
		awayTag,
		{ Size = UDim2.new(1, -12, 0.6, 0), Position = UDim2.new(0, 6, 0.2, 0), Text = "AZURE" }
	)
	local scoreLabel = label(board, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(0, 130, 0, 24),
		Text = "0 - 0",
	})
	local clockLabel = label(board, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(0, 130, 0, 13),
		Text = "0:00",
		TextColor3 = MUTED,
		Font = Enum.Font.GothamMedium,
	})

	local banner = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.8, 0, 0, 34),
		Text = "",
		TextStrokeTransparency = 0.4,
	})
	make("UITextSizeConstraint", { MaxTextSize = 30 }, banner)

	-- Bottom-centre bars
	local bars = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(260, 40),
		BackgroundTransparency = 1,
	}, gui)
	local function bar(y: number, height: number, color: Color3): (Frame, Frame)
		local back = make("Frame", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.25,
		}, bars)
		corner(back, height // 2)
		local fill = make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
		}, back)
		corner(fill, height // 2)
		return back, fill
	end
	local powerBack, powerFill = bar(0, 14, Color3.fromRGB(255, 196, 0))
	-- Marker where over-hitting starts.
	make("Frame", {
		Position = UDim2.fromScale(Config.SHOT_OVERPOWER_START, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = TEXT,
		BorderSizePixel = 0,
	}, powerBack)
	local _, staminaFill = bar(22, 10, Color3.fromRGB(80, 220, 120))

	local possession = label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -62),
		Size = UDim2.fromOffset(240, 18),
		Text = "YOU HAVE THE BALL",
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextStrokeTransparency = 0.5,
		Visible = false,
	})

	local toast = label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -86),
		Size = UDim2.fromOffset(320, 24),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	local help = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(290, 300),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
	}, gui)
	corner(help, 10)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, help)
	label(help, {
		Size = UDim2.fromScale(1, 1),
		Text = HELP_TEXT,
		RichText = true,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	task.delay(15, function()
		ClientState.showHelp = false
	end)

	-- Match state
	local function refresh()
		local home = state:GetAttribute("HomeScore") or 0
		local away = state:GetAttribute("AwayScore") or 0
		scoreLabel.Text = `{home} - {away}`
		clockLabel.Text = formatClock((state:GetAttribute("TimeLeft") or 0) :: number)
		local bannerText = state:GetAttribute("Banner")
		banner.Text = if typeof(bannerText) == "string" then bannerText else ""
	end
	state.AttributeChanged:Connect(refresh)
	refresh()

	Net.feedback().OnClientEvent:Connect(function(kind: unknown, message: unknown)
		if kind ~= "Toast" or typeof(message) ~= "string" then
			return
		end
		toast.Text = message
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = 0.5
		TweenService:Create(
			toast,
			TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
			{
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		):Play()
	end)

	-- Per-frame bars
	RunService.RenderStepped:Connect(function()
		local stamina = (player:GetAttribute("Stamina") or Config.STAMINA_MAX) :: number
		local ratio = math.clamp(stamina / Config.STAMINA_MAX, 0, 1)
		staminaFill.Size = UDim2.fromScale(ratio, 1)
		staminaFill.BackgroundColor3 = Color3.fromRGB(230, 70, 60)
			:Lerp(Color3.fromRGB(80, 220, 120), ratio)

		local start = ClientState.chargeStart
		if start then
			local power = math.clamp((os.clock() - start) / Config.CHARGE_TIME, 0, 1)
			powerBack.Visible = true
			powerFill.Size = UDim2.fromScale(power, 1)
			powerFill.BackgroundColor3 = if power > Config.SHOT_OVERPOWER_START
				then Color3.fromRGB(235, 70, 50)
				else Color3.fromRGB(255, 196, 0)
		else
			powerBack.Visible = false
		end

		local ball = Workspace:FindFirstChild("MatchBall")
		possession.Visible = ball ~= nil and ball:GetAttribute("OwnerUserId") == player.UserId
		help.Visible = ClientState.showHelp
	end)
end

return HudController

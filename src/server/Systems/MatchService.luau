--!strict
-- Match flow: warm-up, kickoffs, the clock, goals and full time.
-- State is published as attributes on ReplicatedStorage.MatchState for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AthleteService = require(script.Parent.AthleteService)
local BallService = require(script.Parent.BallService)
local Characters = require(script.Parent.Parent.Util.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local GoalkeeperService = require(script.Parent.GoalkeeperService)
local Net = require(ReplicatedStorage.Shared.Net)
local Pitch = require(ReplicatedStorage.Shared.Pitch)
local TeamService = require(script.Parent.TeamService)
local Types = require(ReplicatedStorage.Shared.Types)

type TeamId = Types.TeamId
type MatchPhase = Types.MatchPhase

local BALL_SPOT = Vector3.new(0, Pitch.GROUND_Y + Config.BALL_DIAMETER / 2, 0)

local MatchService = {}

local state: Configuration
local phase: MatchPhase = "Warmup"
local scores: Types.TeamMap<number> = { Home = 0, Away = 0 }

local function setPhase(newPhase: MatchPhase)
	phase = newPhase
	state:SetAttribute("Phase", newPhase)
end

local function setBanner(text: string)
	state:SetAttribute("Banner", text)
end

local function setTime(seconds: number)
	state:SetAttribute("TimeLeft", math.max(0, math.ceil(seconds)))
end

local function publishScores()
	state:SetAttribute("HomeScore", scores.Home)
	state:SetAttribute("AwayScore", scores.Away)
end

-- Ball fell out of the world or escaped the stadium somehow.
local function ballLost(): boolean
	local p = BallService.getBall().Position
	return p.Y < Pitch.GROUND_Y - 10
		or math.abs(p.X) > Pitch.HALF_LENGTH + 30
		or math.abs(p.Z) > Pitch.HALF_WIDTH + 30
end

local function lineUp(kickoffTeam: TeamId)
	for _, team in Pitch.TEAMS do
		local sign = Pitch.attackSign(team)
		for index, player in TeamService.getPlayers(team) do
			local root = Characters.getRoot(player)
			local character = player.Character
			if not root or not character then
				continue
			end
			local spot = Pitch.formationSpot(team, index)
			if team == kickoffTeam and index == 1 then
				spot = Vector3.new(-sign * 3, Pitch.GROUND_Y + 3, 0)
			end
			character:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(sign, 0, 0)))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function kickoff(kickoffTeam: TeamId)
	setPhase("Kickoff")
	BallService.reset(BALL_SPOT, true)
	GoalkeeperService.reset()
	AthleteService.setFrozen(true)
	lineUp(kickoffTeam)
	for i = Config.KICKOFF_FREEZE, 1, -1 do
		setBanner(`{TeamService.displayName(kickoffTeam)} kick off in {i}`)
		task.wait(1)
	end
	setBanner("")
	AthleteService.setFrozen(false)
	BallService.setFrozen(false)
	setPhase("Playing")
end

-- Runs the clock until it expires or a goal is scored.
-- Returns the scoring team, or nil at full time.
local function playUntilGoal(timeLeft: number): (TeamId?, number)
	while timeLeft > 0 do
		local dt = RunService.Heartbeat:Wait()
		timeLeft -= dt
		setTime(timeLeft)
		local ball = BallService.getBall()
		local conceding = Pitch.goalScoredIn(ball.Position, Config.BALL_DIAMETER / 2)
		if conceding then
			return Pitch.opponent(conceding), timeLeft
		end
		if ballLost() then
			BallService.reset(BALL_SPOT, false)
		end
	end
	return nil, 0
end

local function celebrate(scoringTeam: TeamId)
	if scoringTeam == Pitch.HOME then
		scores.Home += 1
	else
		scores.Away += 1
	end
	publishScores()
	local scorer = BallService.getLastToucher()
	local scorerTeam = if scorer then TeamService.getTeamId(scorer) else nil
	local teamName = TeamService.displayName(scoringTeam)
	if scorer and scorerTeam == scoringTeam then
		setBanner(`GOAL! {scorer.DisplayName} scores for {teamName}`)
	elseif scorer then
		setBanner(`OWN GOAL by {scorer.DisplayName}! {teamName} score`)
	else
		setBanner(`GOAL! {teamName} score`)
	end
	setPhase("Goal")
	task.wait(Config.GOAL_CELEBRATION)
end

local function warmup()
	setPhase("Warmup")
	scores = { Home = 0, Away = 0 }
	publishScores()
	BallService.reset(BALL_SPOT, false)
	GoalkeeperService.reset()
	while #Players:GetPlayers() == 0 do
		setBanner("Waiting for players")
		task.wait(1)
	end
	local remaining = Config.WARMUP_TIME
	while remaining > 0 do
		setBanner(`Warm-up: match starts in {math.ceil(remaining)}`)
		setTime(remaining)
		local dt = RunService.Heartbeat:Wait()
		remaining -= dt
		-- Warm-up goals do not count; just reset the ball.
		if
			Pitch.goalScoredIn(BallService.getBall().Position, Config.BALL_DIAMETER / 2)
			or ballLost()
		then
			BallService.reset(BALL_SPOT, false)
			GoalkeeperService.reset()
		end
	end
end

local function fullTime()
	setPhase("FullTime")
	AthleteService.setFrozen(true)
	local home, away = scores.Home, scores.Away
	local result = if home == away
		then "It's a draw"
		elseif home > away then `{TeamService.displayName(Pitch.HOME)} win`
		else `{TeamService.displayName(Pitch.AWAY)} win`
	setBanner(`FULL TIME  {home} - {away}  {result}`)
	task.wait(Config.FULLTIME_PAUSE)
	AthleteService.setFrozen(false)
end

local function runMatches()
	while true do
		warmup()
		AthleteService.resetStamina()
		local timeLeft: number = Config.MATCH_LENGTH
		local kickoffTeam: TeamId = Pitch.HOME
		setTime(timeLeft)
		while timeLeft > 0 do
			kickoff(kickoffTeam)
			local scoringTeam: TeamId?
			scoringTeam, timeLeft = playUntilGoal(timeLeft)
			if scoringTeam then
				celebrate(scoringTeam)
				kickoffTeam = Pitch.opponent(scoringTeam)
			end
		end
		fullTime()
	end
end

function MatchService.init()
	state = Net.matchState()
	setPhase("Warmup")
	setBanner("")
	setTime(0)
	publishScores()
end

function MatchService.start()
	-- Players joining mid-match start in their own half.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.defer(function()
				local team = TeamService.getTeamId(player)
				if not team or phase == "Warmup" then
					return
				end
				local spot = Pitch.formationSpot(team, #TeamService.getPlayers(team))
				character:PivotTo(
					CFrame.lookAt(spot, spot + Vector3.new(Pitch.attackSign(team), 0, 0))
				)
			end)
		end)
	end)
	task.spawn(runMatches)
end

-- True when players may touch the ball (warm-up counts as practice).
function MatchService.isBallLive(): boolean
	return phase == "Playing" or phase == "Warmup"
end

function MatchService.getPhase(): MatchPhase
	return phase
end

return MatchService

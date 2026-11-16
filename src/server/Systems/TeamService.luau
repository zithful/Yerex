--!strict
-- Creates the two sides, balances players between them and tints characters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Pitch = require(ReplicatedStorage.Shared.Pitch)
local Types = require(ReplicatedStorage.Shared.Types)

type TeamId = Types.TeamId

local TEAM_INFO: { [TeamId]: { name: string, color: BrickColor } } = {
	Home = { name = "Crimson", color = BrickColor.new("Really red") },
	Away = { name = "Azure", color = BrickColor.new("Bright blue") },
}

local TeamService = {}

local teamObjects: { Home: Team?, Away: Team? } = {}

local function teamObject(id: TeamId): Team?
	return if id == Pitch.HOME then teamObjects.Home else teamObjects.Away
end

local function countPlayers(team: Team): number
	return #team:GetPlayers()
end

local function assign(player: Player)
	local home, away = teamObjects.Home, teamObjects.Away
	if home and away then
		player.Team = if countPlayers(home) <= countPlayers(away) then home else away
	end
end

local function tintCharacter(player: Player, character: Model)
	local teamId = TeamService.getTeamId(player)
	if not teamId then
		return
	end
	local existing = character:FindFirstChild("TeamHighlight")
	if existing then
		existing:Destroy()
	end
	-- A light highlight keeps avatars recognisable while making sides obvious.
	local highlight = Instance.new("Highlight")
	highlight.Name = "TeamHighlight"
	highlight.FillColor = TEAM_INFO[teamId].color.Color
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = TEAM_INFO[teamId].color.Color
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
end

function TeamService.init()
	for id, info in TEAM_INFO do
		local team = Teams:FindFirstChild(info.name)
		if not (team and team:IsA("Team")) then
			local created = Instance.new("Team")
			created.Name = info.name
			created.TeamColor = info.color
			created.AutoAssignable = false
			created.Parent = Teams
			team = created
		end
		if id == Pitch.HOME then
			teamObjects.Home = team :: Team
		else
			teamObjects.Away = team :: Team
		end
	end
end

function TeamService.start()
	local function onPlayer(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(character)
			tintCharacter(player, character)
		end)
		if player.Character then
			tintCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

function TeamService.getTeamId(player: Player): TeamId?
	if player.Team == teamObjects.Home then
		return Pitch.HOME
	elseif player.Team == teamObjects.Away then
		return Pitch.AWAY
	end
	return nil
end

function TeamService.getPlayers(teamId: TeamId): { Player }
	local team = teamObject(teamId)
	return if team then team:GetPlayers() else {}
end

function TeamService.displayName(teamId: TeamId): string
	return TEAM_INFO[teamId].name
end

function TeamService.color(teamId: TeamId): Color3
	return TEAM_INFO[teamId].color.Color
end

return TeamService

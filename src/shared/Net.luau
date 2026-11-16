--!strict
-- Remote registry. The server creates remotes; clients wait for them.
-- Keeping every remote in one place makes the network surface easy to audit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local MATCH_STATE_NAME = "MatchState"

local Net = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function getRemoteEvent(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Client -> server: gameplay action requests (see Types.ActionPayload).
function Net.action(): RemoteEvent
	return getRemoteEvent("Action")
end

-- Server -> client: short-lived feedback events (kick sounds, banners).
function Net.feedback(): RemoteEvent
	return getRemoteEvent("Feedback")
end

-- Replicated match state. The server writes attributes on this object; clients
-- only read them. Attributes: Phase, TimeLeft, HomeScore, AwayScore, Banner.
function Net.matchState(): Configuration
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(MATCH_STATE_NAME)
		if existing and existing:IsA("Configuration") then
			return existing
		end
		local state = Instance.new("Configuration")
		state.Name = MATCH_STATE_NAME
		state.Parent = ReplicatedStorage
		return state
	end
	return ReplicatedStorage:WaitForChild(MATCH_STATE_NAME) :: Configuration
end

return Net

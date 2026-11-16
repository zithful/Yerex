--!strict
-- Yerex server entry point. Two-phase bootstrap: init() every system (create
-- instances, wire remotes), then start() every system (connect loops/events).

local Systems = script:WaitForChild("Systems")

-- Explicit order keeps startup deterministic; any other module in Systems is
-- loaded afterwards.
local ORDER = {
	"PitchBuilder",
	"TeamService",
	"BallService",
	"AthleteService",
	"GoalkeeperService",
	"MatchService",
	"ActionService",
}

local loaded: { { name: string, module: any } } = {}
local seen: { [string]: boolean } = {}

local function load(child: Instance)
	if child:IsA("ModuleScript") and not seen[child.Name] then
		seen[child.Name] = true
		table.insert(loaded, { name = child.Name, module = require(child) :: any })
	end
end

for _, name in ORDER do
	local child = Systems:FindFirstChild(name)
	if child then
		load(child)
	else
		warn(`[Yerex] missing system {name}`)
	end
end
for _, child in Systems:GetChildren() do
	load(child)
end

for _, entry in loaded do
	if typeof(entry.module.init) == "function" then
		entry.module.init()
	end
end

for _, entry in loaded do
	if typeof(entry.module.start) == "function" then
		task.spawn(entry.module.start)
	end
end

print("[Yerex] server started")

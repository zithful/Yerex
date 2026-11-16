--!strict
-- Builds the stadium from code so the place file stays empty and every
-- dimension comes from shared/Pitch.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Pitch = require(ReplicatedStorage.Shared.Pitch)

local LINE_WIDTH = 0.6
local LINE_THICKNESS = 0.04
local LINE_Y = Pitch.GROUND_Y + LINE_THICKNESS / 2 + 0.01
local WALL_MARGIN = 10
local WALL_HEIGHT = 50
local GRASS_DARK = Color3.fromRGB(58, 125, 52)
local GRASS_LIGHT = Color3.fromRGB(70, 145, 62)
local WHITE = Color3.fromRGB(240, 240, 240)

local PitchBuilder = {}

local root: Folder

local function makePart(props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,
	shape: Enum.PartType?,
	parent: Instance?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Anchored = true
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color or WHITE
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.CanCollide = if props.collide == nil then true else props.collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.shape then
		part.Shape = props.shape
	end
	if not part.CanCollide then
		part.CanQuery = false
		part.CanTouch = false
	end
	part.Parent = props.parent or root
	return part
end

-- Flat painted line between two points on the ground.
local function line(a: Vector3, b: Vector3, parent: Instance)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	makePart({
		name = "Line",
		size = Vector3.new(LINE_WIDTH, LINE_THICKNESS, length + LINE_WIDTH),
		cframe = CFrame.lookAt(Vector3.new(mid.X, LINE_Y, mid.Z), Vector3.new(b.X, LINE_Y, b.Z)),
		collide = false,
		parent = parent,
	})
end

local function circle(
	center: Vector3,
	radius: number,
	segments: number,
	parent: Instance,
	fromAngle: number?,
	toAngle: number?
)
	local startAngle = fromAngle or 0
	local endAngle = toAngle or math.pi * 2
	local previous: Vector3? = nil
	for i = 0, segments do
		local angle = startAngle + (endAngle - startAngle) * (i / segments)
		local point = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if previous then
			line(previous, point, parent)
		end
		previous = point
	end
end

local function rect(minX: number, maxX: number, minZ: number, maxZ: number, parent: Instance)
	line(Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), parent)
	line(Vector3.new(minX, 0, maxZ), Vector3.new(maxX, 0, maxZ), parent)
	line(Vector3.new(minX, 0, minZ), Vector3.new(minX, 0, maxZ), parent)
	line(Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), parent)
end

local function buildGrass()
	local grass = Instance.new("Folder")
	grass.Name = "Grass"
	grass.Parent = root

	local outerLength = Pitch.LENGTH + WALL_MARGIN * 2 + 20
	local outerWidth = Pitch.WIDTH + WALL_MARGIN * 2 + 20
	makePart({
		name = "Turf",
		size = Vector3.new(outerLength, 4, outerWidth),
		cframe = CFrame.new(0, Pitch.GROUND_Y - 2, 0),
		color = GRASS_DARK,
		material = Enum.Material.Grass,
		parent = grass,
	})

	-- Mowing stripes across the pitch.
	local stripes = 14
	local stripeLength = Pitch.LENGTH / stripes
	for i = 0, stripes - 1 do
		if i % 2 == 0 then
			local x = -Pitch.HALF_LENGTH + stripeLength * (i + 0.5)
			makePart({
				name = "Stripe",
				size = Vector3.new(stripeLength, 0.02, Pitch.WIDTH),
				cframe = CFrame.new(x, Pitch.GROUND_Y + 0.01, 0),
				color = GRASS_LIGHT,
				material = Enum.Material.Grass,
				collide = false,
				parent = grass,
			})
		end
	end
end

local function buildMarkings()
	local markings = Instance.new("Folder")
	markings.Name = "Markings"
	markings.Parent = root

	local hl, hw = Pitch.HALF_LENGTH, Pitch.HALF_WIDTH
	rect(-hl, hl, -hw, hw, markings)
	line(Vector3.new(0, 0, -hw), Vector3.new(0, 0, hw), markings)
	circle(Vector3.zero, Pitch.CENTER_CIRCLE_RADIUS, 40, markings)

	for _, sign in { -1, 1 } do
		local goalX = sign * hl
		local boxX = goalX - sign * Pitch.BOX_DEPTH
		rect(
			math.min(goalX, boxX),
			math.max(goalX, boxX),
			-Pitch.BOX_WIDTH / 2,
			Pitch.BOX_WIDTH / 2,
			markings
		)
		local sixX = goalX - sign * 12
		rect(
			math.min(goalX, sixX),
			math.max(goalX, sixX),
			-Pitch.GOAL_WIDTH / 2 - 10,
			Pitch.GOAL_WIDTH / 2 + 10,
			markings
		)
		local spot = Vector3.new(goalX - sign * 24, 0, 0)
		makePart({
			name = "PenaltySpot",
			size = Vector3.new(LINE_THICKNESS, 1.2, 1.2),
			cframe = CFrame.new(spot.X, LINE_Y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			shape = Enum.PartType.Cylinder,
			collide = false,
			parent = markings,
		})
		-- The "D" outside the box.
		local arcCenterAngle = if sign > 0 then math.pi else 0
		circle(spot, 20, 14, markings, arcCenterAngle - 0.93, arcCenterAngle + 0.93)
	end
	makePart({
		name = "CenterSpot",
		size = Vector3.new(LINE_THICKNESS, 1.2, 1.2),
		cframe = CFrame.new(0, LINE_Y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		shape = Enum.PartType.Cylinder,
		collide = false,
		parent = markings,
	})
end

local function buildGoal(sign: number, teamColor: Color3)
	local goal = Instance.new("Model")
	goal.Name = if sign < 0 then "HomeGoal" else "AwayGoal"
	goal.Parent = root

	local x = sign * Pitch.HALF_LENGTH
	local halfGoal = Pitch.GOAL_WIDTH / 2
	local h = Pitch.GOAL_HEIGHT
	local depth = Pitch.GOAL_DEPTH
	local postRadius = 0.6

	for _, z in { -halfGoal - postRadius, halfGoal + postRadius } do
		makePart({
			name = "Post",
			size = Vector3.new(h + postRadius, postRadius * 2, postRadius * 2),
			cframe = CFrame.new(x + sign * postRadius, Pitch.GROUND_Y + (h + postRadius) / 2, z)
				* CFrame.Angles(0, 0, math.rad(90)),
			shape = Enum.PartType.Cylinder,
			parent = goal,
		})
	end
	makePart({
		name = "Crossbar",
		size = Vector3.new(Pitch.GOAL_WIDTH + postRadius * 4, postRadius * 2, postRadius * 2),
		cframe = CFrame.new(x + sign * postRadius, Pitch.GROUND_Y + h + postRadius, 0)
			* CFrame.Angles(0, math.rad(90), 0),
		shape = Enum.PartType.Cylinder,
		parent = goal,
	})

	-- Nets: collidable so the ball nestles in the goal instead of flying through.
	local netProps = {
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.ForceField,
		transparency = 0.35,
	}
	makePart({
		name = "NetBack",
		size = Vector3.new(0.4, h, Pitch.GOAL_WIDTH + 2),
		cframe = CFrame.new(x + sign * (depth + 0.2), Pitch.GROUND_Y + h / 2, 0),
		color = netProps.color,
		material = netProps.material,
		transparency = netProps.transparency,
		parent = goal,
	})
	makePart({
		name = "NetTop",
		size = Vector3.new(depth, 0.4, Pitch.GOAL_WIDTH + 2),
		cframe = CFrame.new(x + sign * depth / 2, Pitch.GROUND_Y + h + 0.2, 0),
		color = netProps.color,
		material = netProps.material,
		transparency = netProps.transparency,
		parent = goal,
	})
	for _, z in { -halfGoal - 1, halfGoal + 1 } do
		makePart({
			name = "NetSide",
			size = Vector3.new(depth, h, 0.4),
			cframe = CFrame.new(x + sign * depth / 2, Pitch.GROUND_Y + h / 2, z),
			color = netProps.color,
			material = netProps.material,
			transparency = netProps.transparency,
			parent = goal,
		})
	end

	-- Team-coloured strip behind the goal so each end is easy to read.
	makePart({
		name = "EndBanner",
		size = Vector3.new(0.5, 4, Pitch.GOAL_WIDTH + 30),
		cframe = CFrame.new(x + sign * (WALL_MARGIN - 0.3), Pitch.GROUND_Y + 2, 0),
		color = teamColor,
		collide = false,
		parent = goal,
	})
end

-- Invisible walls and roof keep the ball in play (no throw-ins yet), with low
-- visible boards so players can see the boundary.
local function buildBoundary()
	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = root

	local hl = Pitch.HALF_LENGTH + WALL_MARGIN
	local hw = Pitch.HALF_WIDTH + WALL_MARGIN
	local thickness = 4
	local walls = {
		{
			Vector3.new(0, 0, -hw - thickness / 2),
			Vector3.new(hl * 2 + thickness * 2, WALL_HEIGHT, thickness),
		},
		{
			Vector3.new(0, 0, hw + thickness / 2),
			Vector3.new(hl * 2 + thickness * 2, WALL_HEIGHT, thickness),
		},
		{ Vector3.new(-hl - thickness / 2, 0, 0), Vector3.new(thickness, WALL_HEIGHT, hw * 2) },
		{ Vector3.new(hl + thickness / 2, 0, 0), Vector3.new(thickness, WALL_HEIGHT, hw * 2) },
	}
	for _, wall in walls do
		local position, size = wall[1], wall[2]
		makePart({
			name = "Wall",
			size = size,
			cframe = CFrame.new(position.X, Pitch.GROUND_Y + WALL_HEIGHT / 2, position.Z),
			transparency = 1,
			parent = boundary,
		})
		makePart({
			name = "Board",
			size = Vector3.new(size.X, 3, size.Z),
			cframe = CFrame.new(position.X, Pitch.GROUND_Y + 1.5, position.Z),
			color = Color3.fromRGB(30, 34, 48),
			collide = false,
			parent = boundary,
		})
	end
	makePart({
		name = "Roof",
		size = Vector3.new(hl * 2, 2, hw * 2),
		cframe = CFrame.new(0, Pitch.GROUND_Y + WALL_HEIGHT + 1, 0),
		transparency = 1,
		parent = boundary,
	})
end

local function buildSpawn()
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "TouchlineSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Size = Vector3.new(12, 0.2, 6)
	spawnLocation.CFrame = CFrame.new(0, Pitch.GROUND_Y + 0.1, -Pitch.HALF_WIDTH - 5)
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Duration = 0
	spawnLocation.Parent = root
end

function PitchBuilder.init()
	-- Shift is sprint; Roblox's default shift-lock binding would steal it.
	StarterPlayer.EnableMouseLockOption = false

	-- A default template Baseplate would z-fight with the turf.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end

	root = Instance.new("Folder")
	root.Name = "Stadium"
	root.Parent = Workspace

	buildGrass()
	buildMarkings()
	buildGoal(-1, Color3.fromRGB(196, 40, 28))
	buildGoal(1, Color3.fromRGB(13, 105, 172))
	buildBoundary()
	buildSpawn()
end

return PitchBuilder

--!strict
-- Small helpers for safely reading a player's live character parts.

local Characters = {}

-- Returns the root part and humanoid of a living character, or nil.
function Characters.getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, nil
end

-- Finds the player whose character contains `part`, if any.
function Characters.playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return game:GetService("Players"):GetPlayerFromCharacter(model)
end

return Characters

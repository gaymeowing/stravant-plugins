--!strict

-- Classify a part's shape for the purposes of material flipping.

export type Shape = "Brick" | "Wedge" | "CornerWedge" | "Round" | "Terrain"

local kUniformScale = Vector3.new(1, 1, 1)

local function getShape(part: BasePart): (Shape, Vector3)
	for _, ch in part:GetChildren() do
		if ch:IsA("SpecialMesh") then
			local scale = ch.Scale
			local meshType = ch.MeshType
			if meshType == Enum.MeshType.Brick or
				meshType == Enum.MeshType.FileMesh or
				meshType == Enum.MeshType.Torso then
				return "Brick", scale
			elseif meshType == Enum.MeshType.CornerWedge then
				return "CornerWedge", scale
			elseif meshType == Enum.MeshType.Wedge then
				return "Wedge", scale
			elseif meshType == Enum.MeshType.Cylinder or
				meshType == Enum.MeshType.Sphere or
				meshType == Enum.MeshType.Head then
				return "Round", scale
			else
				warn("MaterialFlip: Unsupported mesh type, treating as a normal brick.")
				return "Brick", scale
			end
		end
	end
	if part:IsA("WedgePart") then
		return "Wedge", kUniformScale
	elseif part:IsA("CornerWedgePart") then
		return "CornerWedge", kUniformScale
	elseif part:IsA("Terrain") then
		return "Terrain", kUniformScale
	elseif part:IsA("Part") then
		local shape = part.Shape
		if shape == Enum.PartType.Ball or shape == Enum.PartType.Cylinder then
			return "Round", kUniformScale
		elseif shape == Enum.PartType.Wedge then
			return "Wedge", kUniformScale
		elseif shape == Enum.PartType.CornerWedge then
			return "CornerWedge", kUniformScale
		else
			return "Brick", kUniformScale
		end
	else
		-- UnionOperation, MeshPart, etc: treat as a brick
		return "Brick", kUniformScale
	end
end

return getShape

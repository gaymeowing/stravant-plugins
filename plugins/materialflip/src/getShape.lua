--!strict

-- Classify a part's shape for the purposes of material flipping.
-- Note: Balls and Cylinders are distinct because they have different
-- symmetry groups (a cylinder's axis must map to itself, a ball's needn't).
--
-- The third return is whether the classification is an approximation: the
-- part isn't actually the primitive shape and is being treated as a box
-- (unions, file meshes, trusses, etc).

export type Shape = "Brick" | "Wedge" | "CornerWedge" | "Cylinder" | "CylinderY" | "Ball" | "Terrain"

local kUniformScale = Vector3.new(1, 1, 1)

local function getShape(part: BasePart): (Shape, Vector3, boolean)
	for _, ch in part:GetChildren() do
		if ch:IsA("SpecialMesh") then
			local scale = ch.Scale
			local meshType = ch.MeshType
			if meshType == Enum.MeshType.Brick then
				return "Brick", scale, false
			elseif meshType == Enum.MeshType.FileMesh or meshType == Enum.MeshType.Torso then
				return "Brick", scale, true
			elseif meshType == Enum.MeshType.CornerWedge then
				return "CornerWedge", scale, false
			elseif meshType == Enum.MeshType.Wedge then
				return "Wedge", scale, false
			elseif meshType == Enum.MeshType.Cylinder then
				-- SpecialMesh cylinders render with their axis along Y,
				-- unlike cylinder Parts whose axis is X
				return "CylinderY", scale, false
			elseif meshType == Enum.MeshType.Sphere or meshType == Enum.MeshType.Head then
				return "Ball", scale, false
			else
				return "Brick", scale, true
			end
		end
	end
	if part:IsA("WedgePart") then
		return "Wedge", kUniformScale, false
	elseif part:IsA("CornerWedgePart") then
		return "CornerWedge", kUniformScale, false
	elseif part:IsA("Terrain") then
		return "Terrain", kUniformScale, false
	elseif part:IsA("Part") then
		local shape = part.Shape
		if shape == Enum.PartType.Ball then
			return "Ball", kUniformScale, false
		elseif shape == Enum.PartType.Cylinder then
			return "Cylinder", kUniformScale, false
		elseif shape == Enum.PartType.Wedge then
			return "Wedge", kUniformScale, false
		elseif shape == Enum.PartType.CornerWedge then
			return "CornerWedge", kUniformScale, false
		else
			return "Brick", kUniformScale, false
		end
	else
		-- UnionOperation, TrussPart, foreign MeshPart, etc: treat as a box
		return "Brick", kUniformScale, true
	end
end

return getShape

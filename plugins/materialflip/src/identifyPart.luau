-- Reverse lookup: determine the material flip state of a clicked part.
--
-- The state of a part is modeled as:
--   * Shape: which primitive family the region belongs to
--   * ShapeCFrame (P): the pose of the region's canonical shape frame
--   * ShapeSize (s): the size of the region in the shape frame
--   * Orientation (m): the material orientation - the rotation from the shape
--     frame to the part's local (material projection) frame
-- The part occupies region P * S(s), and its material frame is P * m.
-- The pair (P, m) is only defined up to (P*h, h^-1*m) for h in the shape's
-- symmetry group, which never matters: all derived behavior is invariant.
--
-- Primitives always have m = identity. MeshPart representations are
-- identified by the MeshId of the published mesh assets (MeshAssets.lua);
-- their recovered orientation is the class representative, which is
-- equivalent to the placed orientation modulo the shape's symmetry group.

local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local MeshAssets = require("./MeshAssets")
local getShape = require("./getShape")

export type PartState = {
	Part: BasePart,
	Shape: ShapeData.ShapeName,
	Orientation: Orientation.OrientationId,
	ShapeCFrame: CFrame,
	ShapeSize: Vector3,
	IsMeshRepresentation: boolean,
	-- SpecialMesh-bearing parts keep their mesh child, so they can only
	-- take orientations their primitive can represent
	PrimitiveOnly: boolean,
	-- The part isn't really its classified shape (union, foreign mesh,
	-- truss...): it flips with box behavior, which rotates its geometry
	ApproximatedAsBox: boolean,
	-- The part's real geometry can go through the CSG APIs, so the Allow
	-- MeshPart Rotation setting can rotate its material correctly
	CsgRotatable: boolean,
}

local function identifyPart(part: Instance?): PartState?
	if not part or not part:IsA("BasePart") then
		return nil
	end
	assert(part)

	if part:IsA("MeshPart") then
		local info = MeshAssets.fromMeshId(part.MeshId)
		if info then
			local m = info.Orientation
			return {
				Part = part,
				Shape = info.Shape,
				Orientation = m,
				ShapeCFrame = part.CFrame * Orientation.getCFrame(m):Inverse(),
				ShapeSize = Orientation.permuteSize(m, part.Size),
				IsMeshRepresentation = true,
				PrimitiveOnly = false,
				ApproximatedAsBox = false,
				CsgRotatable = false,
			}
		end
		-- Foreign MeshPart: flippable with box behavior
		return {
			Part = part,
			Shape = "Brick" :: ShapeData.ShapeName,
			Orientation = Orientation.Identity,
			ShapeCFrame = part.CFrame,
			ShapeSize = part.Size,
			IsMeshRepresentation = false,
			PrimitiveOnly = true,
			ApproximatedAsBox = true,
			CsgRotatable = true,
		}
	end

	local shape, _scale, approximated = getShape(part)
	if shape == "Terrain" then
		return nil
	end

	return {
		Part = part,
		Shape = shape :: ShapeData.ShapeName,
		Orientation = Orientation.Identity,
		ShapeCFrame = part.CFrame,
		ShapeSize = part.Size,
		IsMeshRepresentation = false,
		PrimitiveOnly = part:FindFirstChildOfClass("SpecialMesh") ~= nil or approximated,
		ApproximatedAsBox = approximated,
		CsgRotatable = approximated and part:IsA("PartOperation"),
	}
end

return identifyPart

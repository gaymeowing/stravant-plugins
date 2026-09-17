-- Per-shape symmetry data.
--
-- For each primitive shape family, the symmetry group H is the set of
-- orientations g such that a primitive of some (possibly axis-permuted) size
-- rotated by g occupies the same region as the unrotated primitive. These are
-- the material orientations representable by the primitive itself; every
-- other orientation needs a MeshPart with the rotation baked into its
-- geometry.
--
-- Orientations are grouped into classes (right cosets H*m): two orientations
-- in the same class are representable by the same baked mesh geometry (via
-- axis-permuted Size and a rotated CFrame), so the class count is the number
-- of distinct meshes a shape needs.

local Orientation = require("./Orientation")

export type ShapeName = "Brick" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"

-- The wedge's one non-trivial symmetry: 180 degrees about the (0, 1, -1)
-- diagonal, realized in part terms as "swap Y/Z sizes and rotate"
local kWedgeFlip = assert(Orientation.fromCFrame(CFrame.fromMatrix(
	Vector3.zero,
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, -1),
	Vector3.new(0, -1, 0)
)))

local function isSymmetryOf(shape: ShapeName, id: Orientation.OrientationId): boolean
	if shape == "Brick" or shape == "Ball" then
		return true
	elseif shape == "Cylinder" then
		-- Anything mapping the X axis line to itself (the cross section is a
		-- circle or an axis-aligned ellipse, handled by Y/Z size swaps)
		local mapped = Orientation.getCFrame(id).XVector
		return math.abs(math.abs(mapped.X) - 1) < 0.01
	elseif shape == "Wedge" then
		return id == Orientation.Identity or id == kWedgeFlip
	elseif shape == "CornerWedge" then
		return id == Orientation.Identity
	end
	error("Unknown shape: " .. tostring(shape))
end

local kShapes: {ShapeName} = {"Brick", "Wedge", "CornerWedge", "Cylinder", "Ball"}

-- Precompute groups and class representatives
local kSymmetryGroup: {[ShapeName]: {Orientation.OrientationId}} = {}
local kClassRep: {[ShapeName]: {Orientation.OrientationId}} = {}
local kClassCount: {[ShapeName]: number} = {}

for _, shape in kShapes do
	local group = {}
	for id = 1, Orientation.Count do
		if isSymmetryOf(shape, id) then
			table.insert(group, id)
		end
	end
	kSymmetryGroup[shape] = group

	-- Class representative of m = the smallest id in the right coset H*m
	local reps = table.create(Orientation.Count)
	local count = 0
	for m = 1, Orientation.Count do
		local best = math.huge
		for _, h in group do
			best = math.min(best, Orientation.compose(h, m))
		end
		reps[m] = best
		if best == m then
			count += 1
		end
	end
	kClassRep[shape] = reps
	kClassCount[shape] = count
end

local ShapeData = {}

ShapeData.WedgeFlip = kWedgeFlip

function ShapeData.isValidShape(name: string): boolean
	return kSymmetryGroup[name :: ShapeName] ~= nil
end

function ShapeData.symmetryGroup(shape: ShapeName): {Orientation.OrientationId}
	return kSymmetryGroup[shape]
end

function ShapeData.isSymmetry(shape: ShapeName, id: Orientation.OrientationId): boolean
	return isSymmetryOf(shape, id)
end

-- The canonical representative of the mesh class that orientation m falls in
function ShapeData.classRepOf(shape: ShapeName, m: Orientation.OrientationId): Orientation.OrientationId
	return kClassRep[shape][m]
end

-- The class containing all primitive-representable orientations
function ShapeData.identityClass(shape: ShapeName): Orientation.OrientationId
	return kClassRep[shape][Orientation.Identity]
end

-- Number of distinct baked meshes needed to cover all 24 orientations
function ShapeData.classCount(shape: ShapeName): number
	return kClassCount[shape]
end

return ShapeData

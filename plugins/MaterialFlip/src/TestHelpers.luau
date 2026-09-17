local Settings = require("./Settings")
local ShapeData = require("./ShapeData")

local function makeTestSettings(): Settings.MaterialFlipSettings
	return {
		WindowPosition = Vector2.new(24, 24),
		WindowAnchor = Vector2.new(0, 0),
		WindowHeightDelta = 0,
		DoneTutorial = true,
		HaveHelp = true,

		RotateDirection = "Clockwise" :: Settings.RotateDirection,
		PreserveAttachments = true,
		PreserveDecals = false,
		PreservePivot = false,
		TargetLocked = false,
		AllowMeshPartRotation = false,
	}
end

-- A characteristic point set for each shape at a given size, in shape-local
-- coordinates. Chosen so that a rotation maps the point set of one family
-- member onto the point set of another exactly when it maps the solids onto
-- each other (for generic sizes).
local function shapePoints(shape: ShapeData.ShapeName, size: Vector3): {Vector3}
	local h = size / 2
	if shape == "Brick" then
		local points = {}
		for _, x in {-h.X, h.X} do
			for _, y in {-h.Y, h.Y} do
				for _, z in {-h.Z, h.Z} do
					table.insert(points, Vector3.new(x, y, z))
				end
			end
		end
		return points
	elseif shape == "Wedge" then
		return {
			Vector3.new(-h.X, -h.Y, -h.Z),
			Vector3.new( h.X, -h.Y, -h.Z),
			Vector3.new( h.X, -h.Y,  h.Z),
			Vector3.new(-h.X, -h.Y,  h.Z),
			Vector3.new(-h.X,  h.Y,  h.Z),
			Vector3.new( h.X,  h.Y,  h.Z),
		}
	elseif shape == "CornerWedge" then
		return {
			Vector3.new(-h.X, -h.Y, -h.Z),
			Vector3.new( h.X, -h.Y, -h.Z),
			Vector3.new(-h.X, -h.Y,  h.Z),
			Vector3.new( h.X, -h.Y,  h.Z),
			Vector3.new( h.X,  h.Y, -h.Z),
		}
	elseif shape == "Cylinder" then
		return {
			Vector3.new(-h.X, -h.Y, 0), Vector3.new(-h.X, h.Y, 0),
			Vector3.new(-h.X, 0, -h.Z), Vector3.new(-h.X, 0, h.Z),
			Vector3.new( h.X, -h.Y, 0), Vector3.new( h.X, h.Y, 0),
			Vector3.new( h.X, 0, -h.Z), Vector3.new( h.X, 0, h.Z),
		}
	elseif shape == "Ball" then
		return {
			Vector3.new(-h.X, 0, 0), Vector3.new(h.X, 0, 0),
			Vector3.new(0, -h.Y, 0), Vector3.new(0, h.Y, 0),
			Vector3.new(0, 0, -h.Z), Vector3.new(0, 0, h.Z),
		}
	end
	error("Unknown shape: " .. tostring(shape))
end

local function samePointSets(a: {Vector3}, b: {Vector3}, tolerance: number?): boolean
	local tol = tolerance or 0.001
	if #a ~= #b then
		return false
	end
	local used = {}
	for _, pa in a do
		local found = false
		for i, pb in b do
			if not used[i] and (pa - pb).Magnitude < tol then
				used[i] = true
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

return {
	makeTestSettings = makeTestSettings,
	shapePoints = shapePoints,
	samePointSets = samePointSets,
}

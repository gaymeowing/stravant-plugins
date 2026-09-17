local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local TestHelpers = require("./TestHelpers")

local kShapes: {ShapeData.ShapeName} = {"Brick", "Wedge", "CornerWedge", "Cylinder", "Ball"}

-- Generic sizes: distinct dimensions where the shape family allows them.
-- Balls are uniform in practice.
local kTestSizes: {[ShapeData.ShapeName]: Vector3} = {
	Brick = Vector3.new(2, 3, 5),
	Wedge = Vector3.new(2, 3, 5),
	CornerWedge = Vector3.new(2, 3, 5),
	Cylinder = Vector3.new(5, 3, 2),
	Ball = Vector3.new(3, 3, 3),
}

return function(t: TestTypes.TestContext)
	t.test("symmetry group sizes match the theory", function()
		t.expect(#ShapeData.symmetryGroup("Brick")).toBe(24)
		t.expect(#ShapeData.symmetryGroup("Ball")).toBe(24)
		t.expect(#ShapeData.symmetryGroup("Cylinder")).toBe(8)
		t.expect(#ShapeData.symmetryGroup("Wedge")).toBe(2)
		t.expect(#ShapeData.symmetryGroup("CornerWedge")).toBe(1)
	end)

	t.test("mesh class counts are 24 / |H|", function()
		t.expect(ShapeData.classCount("Brick")).toBe(1)
		t.expect(ShapeData.classCount("Ball")).toBe(1)
		t.expect(ShapeData.classCount("Cylinder")).toBe(3)
		t.expect(ShapeData.classCount("Wedge")).toBe(12)
		t.expect(ShapeData.classCount("CornerWedge")).toBe(24)
	end)

	t.test("class representatives are canonical", function()
		for _, shape in kShapes do
			for m = 1, Orientation.Count do
				local rep = ShapeData.classRepOf(shape, m)
				t.expect(ShapeData.classRepOf(shape, rep)).toBe(rep)
				for _, h in ShapeData.symmetryGroup(shape) do
					t.expect(ShapeData.classRepOf(shape, Orientation.compose(h, m))).toBe(rep)
				end
			end
		end
	end)

	t.test("symmetry membership matches the geometry", function()
		-- g is a symmetry exactly when rotating the (size-permuted) shape by g
		-- reproduces the original shape's characteristic point set
		for _, shape in kShapes do
			local size = kTestSizes[shape]
			local targetPoints = TestHelpers.shapePoints(shape, size)
			for g = 1, Orientation.Count do
				local cf = Orientation.getCFrame(g)
				local sourceSize = Orientation.permuteSize(Orientation.invert(g), size)
				local rotated = {}
				for _, p in TestHelpers.shapePoints(shape, sourceSize) do
					table.insert(rotated, cf:PointToWorldSpace(p))
				end
				local matches = TestHelpers.samePointSets(rotated, targetPoints)
				if matches ~= ShapeData.isSymmetry(shape, g) then
					t.fail(string.format("Shape %s orientation %d: geometric=%s, declared=%s",
						shape, g, tostring(matches), tostring(ShapeData.isSymmetry(shape, g))))
				end
			end
		end
	end)
end

local TestTypes = require("./TestTypes")
local canFlip = require("./canFlip")

return function(t: TestTypes.TestContext)
	t.test("accepts all primitive shapes", function()
		local brick = Instance.new("Part")
		t.expect(canFlip(brick)).toBeTruthy()
		brick:Destroy()

		local wedge = Instance.new("WedgePart")
		t.expect(canFlip(wedge)).toBeTruthy()
		wedge:Destroy()

		local cornerWedge = Instance.new("CornerWedgePart")
		t.expect(canFlip(cornerWedge)).toBeTruthy()
		cornerWedge:Destroy()

		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		t.expect(canFlip(ball)).toBeTruthy()
		ball:Destroy()

		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		t.expect(canFlip(cylinder)).toBeTruthy()
		cylinder:Destroy()

		-- Foreign MeshParts are flippable with box behavior
		local foreignMesh = Instance.new("MeshPart")
		t.expect(canFlip(foreignMesh)).toBeTruthy()
		foreignMesh:Destroy()
	end)

	t.test("rejects nil, locked parts, and terrain", function()
		t.expect(canFlip(nil)).toBeFalsy()

		local locked = Instance.new("Part")
		locked.Locked = true
		t.expect(canFlip(locked)).toBeFalsy()
		-- Unless the Target Locked setting allows it
		t.expect(canFlip(locked, true)).toBeTruthy()
		locked:Destroy()

		t.expect(canFlip(workspace.Terrain)).toBeFalsy()
		t.expect(canFlip(workspace.Terrain, true)).toBeFalsy()
	end)
end

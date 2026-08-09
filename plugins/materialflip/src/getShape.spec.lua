--!strict

local TestTypes = require("./TestTypes")
local getShape = require("./getShape")

return function(t: TestTypes.TestContext)
	t.test("classifies block parts as Brick", function()
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		t.expect(getShape(part)).toBe("Brick")
		part:Destroy()
	end)

	t.test("distinguishes balls from cylinders", function()
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		t.expect(getShape(ball)).toBe("Ball")
		ball:Destroy()

		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		t.expect(getShape(cylinder)).toBe("Cylinder")
		cylinder:Destroy()
	end)

	t.test("classifies WedgePart as Wedge", function()
		local wedge = Instance.new("WedgePart")
		t.expect(getShape(wedge)).toBe("Wedge")
		wedge:Destroy()
	end)

	t.test("classifies CornerWedgePart as CornerWedge", function()
		local cornerWedge = Instance.new("CornerWedgePart")
		t.expect(getShape(cornerWedge)).toBe("CornerWedge")
		cornerWedge:Destroy()
	end)

	t.test("classifies Terrain as Terrain", function()
		t.expect(getShape(workspace.Terrain)).toBe("Terrain")
	end)

	t.test("classifies by SpecialMesh when present", function()
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Parent = part
		-- SpecialMesh cylinders have their axis along Y, unlike cylinder Parts
		t.expect(getShape(part)).toBe("CylinderY")
		mesh.MeshType = Enum.MeshType.Sphere
		t.expect(getShape(part)).toBe("Ball")
		part:Destroy()
	end)
end

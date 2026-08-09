--!strict

local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")
local identifyPart = require("./identifyPart")

return function(t: TestTypes.TestContext)
	t.test("identifies primitives with identity orientation", function()
		local wedge = Instance.new("WedgePart")
		wedge.Size = Vector3.new(2, 3, 4)
		wedge.CFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0.5, 0, 0)
		local state = identifyPart(wedge)
		assert(state, "expected a state")
		t.expect(state.Shape).toBe("Wedge")
		t.expect(state.Orientation).toBe(Orientation.Identity)
		t.expect(state.IsMeshRepresentation).toBeFalsy()
		t.expect(state.PrimitiveOnly).toBeFalsy()
		t.expect((state.ShapeSize - Vector3.new(2, 3, 4)).Magnitude < 0.001).toBeTruthy()
		wedge:Destroy()
	end)

	t.test("flags SpecialMesh parts as primitive only", function()
		local part = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = part
		local state = identifyPart(part)
		assert(state)
		t.expect(state.Shape).toBe("Wedge")
		t.expect(state.PrimitiveOnly).toBeTruthy()
		part:Destroy()
	end)

	t.test("rejects terrain, foreign mesh parts, and invalid attributes", function()
		t.expect(identifyPart(workspace.Terrain)).toBe(nil)

		local foreign = Instance.new("MeshPart")
		t.expect(identifyPart(foreign)).toBe(nil)

		foreign:SetAttribute("MaterialFlipShape", "NotAShape")
		foreign:SetAttribute("MaterialFlipOrientation", 3)
		t.expect(identifyPart(foreign)).toBe(nil)

		foreign:SetAttribute("MaterialFlipShape", "Wedge")
		foreign:SetAttribute("MaterialFlipOrientation", 99)
		t.expect(identifyPart(foreign)).toBe(nil)
		foreign:Destroy()
	end)
end

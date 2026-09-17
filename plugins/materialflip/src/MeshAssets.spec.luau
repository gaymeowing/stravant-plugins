local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local MeshAssets = require("./MeshAssets")

local kMeshShapes: {ShapeData.ShapeName} = {"Wedge", "CornerWedge", "Cylinder"}
local kPrimShapes: {ShapeData.ShapeName} = {"Brick", "Ball"}

return function(t: TestTypes.TestContext)
	t.test("assets cover exactly the non-identity classes of each shape", function()
		for _, shape in kMeshShapes do
			local identityClass = ShapeData.identityClass(shape)
			for m = 1, Orientation.Count do
				if ShapeData.classRepOf(shape, m) == m then
					local expectMesh = m ~= identityClass
					if MeshAssets.hasMesh(shape, m) ~= expectMesh then
						t.fail(string.format("%s class %d: hasMesh should be %s",
							shape, m, tostring(expectMesh)))
					end
				elseif MeshAssets.hasMesh(shape, m) then
					t.fail(string.format("%s %d is not a class representative but has a mesh", shape, m))
				end
			end
		end
		for _, shape in kPrimShapes do
			for m = 1, Orientation.Count do
				t.expect(MeshAssets.hasMesh(shape, m)).toBeFalsy()
			end
		end
	end)

	t.test("mesh ids are unique and round trip through fromMeshId", function()
		local seen: {[string]: boolean} = {}
		for _, shape in kMeshShapes do
			for m = 1, Orientation.Count do
				if MeshAssets.hasMesh(shape, m) then
					local meshId = MeshAssets.getMeshId(shape, m)
					t.expect(seen[meshId]).toBeFalsy()
					seen[meshId] = true
					local info = MeshAssets.fromMeshId(meshId)
					assert(info, "expected reverse lookup to succeed")
					t.expect(info.Shape).toBe(shape)
					t.expect(info.Orientation).toBe(m)
				end
			end
		end
	end)

	t.test("unknown mesh ids are not identified", function()
		t.expect(MeshAssets.fromMeshId("rbxassetid://12345")).toBe(nil)
		t.expect(MeshAssets.fromMeshId("")).toBe(nil)
	end)
end

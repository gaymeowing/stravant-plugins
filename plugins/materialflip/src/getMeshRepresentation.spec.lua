--!strict

local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")
local MeshAssets = require("./MeshAssets")
local getMeshRepresentation = require("./getMeshRepresentation")

return function(t: TestTypes.TestContext)
	t.test("every mesh class has an embedded template with the right MeshId", function()
		for _, shape in {"Wedge" :: any, "CornerWedge", "Cylinder"} do
			for m = 1, Orientation.Count do
				if MeshAssets.hasMesh(shape, m) then
					local part = getMeshRepresentation(shape, m)
					t.expect(part:IsA("MeshPart")).toBeTruthy()
					if part.MeshId ~= MeshAssets.getMeshId(shape, m) then
						t.fail(string.format("%s %d: MeshId %s, expected %s",
							tostring(shape), m, part.MeshId, MeshAssets.getMeshId(shape, m)))
					end
					if (part.Size - Vector3.new(1, 1, 1)).Magnitude > 0.001 then
						t.fail(string.format("%s %d: template size %s, expected unit",
							tostring(shape), m, tostring(part.Size)))
					end
					part:Destroy()
				end
			end
		end
	end)
end

--!strict

local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")
local buildShapeMesh = require("./buildShapeMesh")

return function(t: TestTypes.TestContext)
	t.test("built meshes have the permuted bounding size", function()
		local size = Vector3.new(2, 3, 4)
		for _, orientation in {
			Orientation.Identity,
			Orientation.quarterTurnAbout(Enum.NormalId.Top, true),
			Orientation.quarterTurnAbout(Enum.NormalId.Right, false),
		} do
			local ok, err = pcall(function()
				local expected = Orientation.permuteSize(orientation, size)
				for _, shape in {"Wedge" :: any, "CornerWedge", "Cylinder"} do
					local part = buildShapeMesh(shape, orientation, size)
					if (part.Size - expected).Magnitude > 0.001 then
						error(string.format("%s orientation mesh size %s, expected %s",
							tostring(shape), tostring(part.Size), tostring(expected)))
					end
					part:Destroy()
				end
			end)
			if not ok then
				t.fail(string.format("orientation=%s (%s): %s",
					tostring(orientation), typeof(orientation), tostring(err)))
			end
		end
	end)
end

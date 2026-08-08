--!strict

local TestTypes = require("./TestTypes")
local canFlip = require("./canFlip")

return function(t: TestTypes.TestContext)
	t.test("accepts bricks, wedges, and balls", function()
		local brick = Instance.new("Part")
		t.expect(canFlip(brick)).toBeTruthy()
		brick:Destroy()

		local wedge = Instance.new("WedgePart")
		t.expect(canFlip(wedge)).toBeTruthy()
		wedge:Destroy()

		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		t.expect(canFlip(ball)).toBeTruthy()
		ball:Destroy()
	end)

	t.test("rejects nil, locked parts, corner wedges, and terrain", function()
		t.expect(canFlip(nil)).toBeFalsy()

		local locked = Instance.new("Part")
		locked.Locked = true
		t.expect(canFlip(locked)).toBeFalsy()
		locked:Destroy()

		local cornerWedge = Instance.new("CornerWedgePart")
		t.expect(canFlip(cornerWedge)).toBeFalsy()
		cornerWedge:Destroy()

		t.expect(canFlip(workspace.Terrain)).toBeFalsy()
	end)
end

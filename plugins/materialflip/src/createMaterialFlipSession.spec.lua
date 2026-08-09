--!strict

local CoreGui = game:GetService("CoreGui")

local TestTypes = require("./TestTypes")
local TestHelpers = require("./TestHelpers")
local createMaterialFlipSession = require("./createMaterialFlipSession")

return function(t: TestTypes.TestContext)
	t.test("creates and destroys cleanly, managing its highlight", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())
		t.expect(session.GetHoverPart()).toBe(nil)
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeTruthy()

		session.Destroy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeFalsy()
	end)

	t.test("TestClick flips a flippable part and skips a locked one", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())

		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.Parent = workspace
		local result = session.TestClick(part, part.Position + Vector3.new(0, 1, 0))
		if result ~= part then
			t.fail("Expected an in-place flip")
		end
		if (part.Size - Vector3.new(3, 2, 1)).Magnitude > 0.001 then
			t.fail(`Expected part to be flipped, size is {part.Size}`)
		end
		part:Destroy()

		local locked = Instance.new("Part")
		locked.Anchored = true
		locked.Locked = true
		locked.Size = Vector3.new(1, 2, 3)
		locked.Parent = workspace
		local lockedResult = session.TestClick(locked, locked.Position + Vector3.new(0, 1, 0))
		if lockedResult ~= nil then
			t.fail("Expected locked part to be skipped")
		end
		if (locked.Size - Vector3.new(1, 2, 3)).Magnitude > 0.001 then
			t.fail(`Expected locked part to be unchanged, size is {locked.Size}`)
		end
		locked:Destroy()

		session.Destroy()
	end)
end

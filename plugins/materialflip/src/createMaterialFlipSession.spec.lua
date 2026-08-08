--!strict

local CoreGui = game:GetService("CoreGui")

local TestTypes = require("./TestTypes")
local createMaterialFlipSession = require("./createMaterialFlipSession")

return function(t: TestTypes.TestContext)
	t.test("creates and destroys cleanly, managing its highlight", function()
		local session = createMaterialFlipSession()
		t.expect(session.GetHoverPart()).toBe(nil)
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeTruthy()

		session.Destroy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeFalsy()
	end)

	t.test("TestClick flips a flippable part and skips a locked one", function()
		local session = createMaterialFlipSession()

		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.Parent = workspace
		session.TestClick(part, part.Position + Vector3.new(0, 1, 0), Enum.NormalId.Top)
		if (part.Size - Vector3.new(3, 2, 1)).Magnitude > 0.001 then
			t.fail(`Expected part to be flipped, size is {part.Size}`)
		end
		part:Destroy()

		local locked = Instance.new("Part")
		locked.Anchored = true
		locked.Locked = true
		locked.Size = Vector3.new(1, 2, 3)
		locked.Parent = workspace
		session.TestClick(locked, locked.Position + Vector3.new(0, 1, 0), Enum.NormalId.Top)
		if (locked.Size - Vector3.new(1, 2, 3)).Magnitude > 0.001 then
			t.fail(`Expected locked part to be unchanged, size is {locked.Size}`)
		end
		locked:Destroy()

		session.Destroy()
	end)
end

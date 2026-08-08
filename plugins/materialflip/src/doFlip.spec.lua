--!strict

local TestTypes = require("./TestTypes")
local doFlip = require("./doFlip")

return function(t: TestTypes.TestContext)
	local function expectVectorNear(actual: Vector3, expected: Vector3)
		if (actual - expected).Magnitude > 0.001 then
			t.fail(`Expected {expected}, got {actual}`)
		end
	end

	t.test("flipping a brick about Top swaps the X/Z dimensions in place", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.CFrame = CFrame.new(10, 20, 30)
		part.Parent = workspace

		doFlip(part, part.Position + Vector3.new(0, 1, 0), Enum.NormalId.Top)

		expectVectorNear(part.Size, Vector3.new(3, 2, 1))
		expectVectorNear(part.Position, Vector3.new(10, 20, 30))
		-- Quarter turn about +Y: +X ends up pointing at -Z
		expectVectorNear(part.CFrame.XVector, Vector3.new(0, 0, -1))
		expectVectorNear(part.CFrame.YVector, Vector3.new(0, 1, 0))

		part:Destroy()
	end)

	t.test("flipping a brick about Right swaps the Y/Z dimensions in place", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.CFrame = CFrame.new(10, 20, 30)
		part.Parent = workspace

		doFlip(part, part.Position + Vector3.new(0.5, 0, 0), Enum.NormalId.Right)

		expectVectorNear(part.Size, Vector3.new(1, 3, 2))
		expectVectorNear(part.Position, Vector3.new(10, 20, 30))
		expectVectorNear(part.CFrame.XVector, Vector3.new(1, 0, 0))
		-- Quarter turn about +X: +Y ends up pointing at +Z
		expectVectorNear(part.CFrame.YVector, Vector3.new(0, 0, 1))

		part:Destroy()
	end)

	t.test("flipping a brick about Top cycles the side surfaces", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(2, 2, 2)
		part.FrontSurface = Enum.SurfaceType.Weld
		part.RightSurface = Enum.SurfaceType.Glue
		part.BackSurface = Enum.SurfaceType.Studs
		part.LeftSurface = Enum.SurfaceType.Inlet
		part.Parent = workspace

		doFlip(part, part.Position + Vector3.new(0, 1, 0), Enum.NormalId.Top)

		t.expect(part.FrontSurface).toBe(Enum.SurfaceType.Inlet)
		t.expect(part.RightSurface).toBe(Enum.SurfaceType.Weld)
		t.expect(part.BackSurface).toBe(Enum.SurfaceType.Glue)
		t.expect(part.LeftSurface).toBe(Enum.SurfaceType.Studs)

		part:Destroy()
	end)

	t.test("flipping a wedge exchanges its Y/Z dimensions in place", function()
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(1, 2, 3)
		wedge.CFrame = CFrame.new(5, 6, 7)
		wedge.Parent = workspace

		doFlip(wedge, wedge.Position, Enum.NormalId.Top)

		expectVectorNear(wedge.Size, Vector3.new(1, 3, 2))
		expectVectorNear(wedge.Position, Vector3.new(5, 6, 7))
		-- New top is the old front, new back is the old top
		expectVectorNear(wedge.CFrame.YVector, Vector3.new(0, 0, -1))
		expectVectorNear(wedge.CFrame.ZVector, Vector3.new(0, -1, 0))

		wedge:Destroy()
	end)

	t.test("flipping a wedge twice returns it to the original orientation", function()
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(1, 2, 3)
		wedge.CFrame = CFrame.new(5, 6, 7) * CFrame.Angles(0.3, 0.6, 0.9)
		wedge.Parent = workspace
		local originalCF = wedge.CFrame

		doFlip(wedge, wedge.Position, Enum.NormalId.Top)
		doFlip(wedge, wedge.Position, Enum.NormalId.Top)

		expectVectorNear(wedge.Size, Vector3.new(1, 2, 3))
		expectVectorNear(wedge.CFrame.XVector, originalCF.XVector)
		expectVectorNear(wedge.CFrame.YVector, originalCF.YVector)
		expectVectorNear(wedge.CFrame.ZVector, originalCF.ZVector)

		wedge:Destroy()
	end)

	t.test("flipping a ball rotates a half turn about the click axis", function()
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.Size = Vector3.new(4, 4, 4)
		ball.CFrame = CFrame.new(1, 2, 3)
		ball.Parent = workspace

		doFlip(ball, ball.Position + Vector3.new(2, 0, 0), Enum.NormalId.Right)

		expectVectorNear(ball.Position, Vector3.new(1, 2, 3))
		expectVectorNear(ball.CFrame.XVector, Vector3.new(1, 0, 0))
		-- Half turn about +X: +Y ends up pointing at -Y
		expectVectorNear(ball.CFrame.YVector, Vector3.new(0, -1, 0))

		ball:Destroy()
	end)
end

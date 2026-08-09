--!strict

local CoreGui = game:GetService("CoreGui")

local TestTypes = require("./TestTypes")
local TestHelpers = require("./TestHelpers")
local createMaterialFlipSession = require("./createMaterialFlipSession")

return function(t: TestTypes.TestContext)
	t.test("creates and destroys cleanly, managing its highlight and indicator", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())
		t.expect(session.GetHoverPart()).toBe(nil)
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeTruthy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontShaft")).toBeTruthy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontCone")).toBeTruthy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontLabel")).toBeTruthy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipRotationArc")).toBeTruthy()

		session.Destroy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipHighlight")).toBeFalsy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontShaft")).toBeFalsy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontCone")).toBeFalsy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipFrontLabel")).toBeFalsy()
		t.expect(CoreGui:FindFirstChild("MaterialFlipRotationArc")).toBeFalsy()
	end)

	t.test("hover shows the front face indicator on the hovered part", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())

		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(4, 4, 6)
		part.Parent = workspace

		session.TestSetHover(part, part.Position + Vector3.new(0, 2, 0), Vector3.yAxis)
		local cone = CoreGui:FindFirstChild("MaterialFlipFrontCone") :: ConeHandleAdornment
		local shaft = CoreGui:FindFirstChild("MaterialFlipFrontShaft") :: CylinderHandleAdornment
		local label = CoreGui:FindFirstChild("MaterialFlipFrontLabel") :: BillboardGui
		local arc = CoreGui:FindFirstChild("MaterialFlipRotationArc") :: WireframeHandleAdornment
		t.expect(cone.Adornee).toBe(part)
		t.expect(shaft.Adornee).toBe(part)
		-- The arrow comes out of the front (-Z) face: the cone's base sits
		-- beyond the face and its apex (along its local -Z) extends outward
		if cone.CFrame.Position.Z >= -part.Size.Z / 2 then
			t.fail("Cone base should be beyond the front face, got " .. tostring(cone.CFrame.Position))
		end
		if (cone.CFrame.ZVector - Vector3.new(0, 0, 1)).Magnitude > 0.001 then
			t.fail("Cone apex should extend out the front, got ZVector " .. tostring(cone.CFrame.ZVector))
		end
		-- The label is adorned to Workspace with StudsOffsetWorldSpace as its
		-- world position, past the arrow tip (size (4,4,6): arrow length 3,
		-- so the tip margin puts it at z=-6.7)
		t.expect(label.Enabled).toBeTruthy()
		t.expect(label.Adornee).toBe(workspace)
		if (label.StudsOffsetWorldSpace - Vector3.new(0, 0, -6.7)).Magnitude > 0.001 then
			t.fail("Label offset in the wrong place: " .. tostring(label.StudsOffsetWorldSpace))
		end

		-- The rotation arc draws in world space adorned to Terrain (only its
		-- vertex positions are used, so there's no placement to assert here)
		t.expect(arc.Adornee).toBe(workspace.Terrain)

		-- Visual check of the arc and arrow indicators
		local camera = workspace.CurrentCamera
		if camera then
			camera.CFrame = CFrame.lookAt(part.Position + Vector3.new(5, 9, -9), part.Position)
		end
		t.screenshot("rotation_arc_hover")

		session.TestSetHover(nil)
		t.expect(cone.Adornee).toBe(nil)
		t.expect(shaft.Adornee).toBe(nil)
		t.expect(label.Enabled).toBeFalsy()
		t.expect(session.GetHoverState()).toBe(nil)

		part:Destroy()
		session.Destroy()
	end)

	t.test("foreign MeshPart hover reports a box approximation warning", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())

		local foreign = Instance.new("MeshPart")
		foreign.Anchored = true
		foreign.Size = Vector3.new(4, 4, 4)
		foreign.Parent = workspace

		session.TestSetHover(foreign, foreign.Position + Vector3.new(0, 2, 0), Vector3.yAxis)
		local state = session.GetHoverState()
		assert(state, "expected a hover state")
		t.expect(state.ApproximatedAsBox).toBeTruthy()

		-- The front label carries a warning line for approximated parts
		local label = CoreGui:FindFirstChild("MaterialFlipFrontLabel") :: BillboardGui
		local text = label:FindFirstChildOfClass("TextLabel") :: TextLabel
		t.expect(text.Text).toBe("Front\n<font color=\"#FF8C00\">\u{26A0} Non-primitive</font>")

		-- And a primitive hover has no warning
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(4, 4, 4)
		part.Parent = workspace
		session.TestSetHover(part, part.Position + Vector3.new(0, 2, 0), Vector3.yAxis)
		local primState = session.GetHoverState()
		assert(primState)
		t.expect(primState.ApproximatedAsBox).toBeFalsy()
		t.expect(text.Text).toBe("Front")

		foreign:Destroy()
		part:Destroy()
		session.Destroy()
	end)

	t.test("no box warning for MeshParts when Allow MeshPart Rotation is on", function()
		local settings = TestHelpers.makeTestSettings()
		settings.AllowMeshPartRotation = true
		local session = createMaterialFlipSession(settings)

		local foreign = Instance.new("MeshPart")
		foreign.Anchored = true
		foreign.Size = Vector3.new(4, 4, 4)
		foreign.Parent = workspace

		session.TestSetHover(foreign, foreign.Position + Vector3.new(0, 2, 0), Vector3.yAxis)
		local state = session.GetHoverState()
		assert(state)
		t.expect(state.CsgRotatable).toBeTruthy()
		local label = CoreGui:FindFirstChild("MaterialFlipFrontLabel") :: BillboardGui
		local text = label:FindFirstChildOfClass("TextLabel") :: TextLabel
		t.expect(text.Text).toBe("Front")

		foreign:Destroy()
		session.Destroy()
	end)

	t.test("TestClick flips a flippable part and skips a locked one", function()
		local session = createMaterialFlipSession(TestHelpers.makeTestSettings())

		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.Parent = workspace
		local result = session.TestClick(part, part.Position + Vector3.new(0, 1, 0), Vector3.yAxis)
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
		local lockedResult = session.TestClick(locked, locked.Position + Vector3.new(0, 1, 0), Vector3.yAxis)
		if lockedResult ~= nil then
			t.fail("Expected locked part to be skipped")
		end
		if (locked.Size - Vector3.new(1, 2, 3)).Magnitude > 0.001 then
			t.fail(`Expected locked part to be unchanged, size is {locked.Size}`)
		end
		locked:Destroy()

		session.Destroy()
	end)

	t.test("Target Locked allows flipping locked parts", function()
		local settings = TestHelpers.makeTestSettings()
		settings.TargetLocked = true
		local session = createMaterialFlipSession(settings)

		local locked = Instance.new("Part")
		locked.Anchored = true
		locked.Locked = true
		locked.Size = Vector3.new(1, 2, 3)
		locked.Parent = workspace
		local result = session.TestClick(locked, locked.Position + Vector3.new(0, 1, 0), Vector3.yAxis)
		if result ~= locked then
			t.fail("Expected the locked part to flip")
		end
		if (locked.Size - Vector3.new(3, 2, 1)).Magnitude > 0.001 then
			t.fail(`Expected locked part to be flipped, size is {locked.Size}`)
		end
		locked:Destroy()

		session.Destroy()
	end)
end

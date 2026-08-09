--!strict

local TestTypes = require("./TestTypes")
local doFlip = require("./doFlip")
local identifyPart = require("./identifyPart")
local TestHelpers = require("./TestHelpers")

local kCW: doFlip.FlipOptions = {Clockwise = true, PreserveAttachments = true, PreserveDecals = false}
local kCCW: doFlip.FlipOptions = {Clockwise = false, PreserveAttachments = true, PreserveDecals = false}

return function(t: TestTypes.TestContext)
	local function expectVectorNear(actual: Vector3, expected: Vector3)
		if (actual - expected).Magnitude > 0.001 then
			t.fail(`Expected {expected}, got {actual}`)
		end
	end

	local function expectCFrameNear(actual: CFrame, expected: CFrame)
		expectVectorNear(actual.Position, expected.Position)
		expectVectorNear(actual.XVector, expected.XVector)
		expectVectorNear(actual.YVector, expected.YVector)
		expectVectorNear(actual.ZVector, expected.ZVector)
	end

	-- The world space characteristic points of the region a part represents
	local function regionPoints(part: BasePart): {Vector3}
		local state = identifyPart(part)
		assert(state, "part must be identifiable")
		local points = {}
		for _, p in TestHelpers.shapePoints(state.Shape, state.ShapeSize) do
			table.insert(points, state.ShapeCFrame:PointToWorldSpace(p))
		end
		return points
	end

	local function expectSameRegion(before: {Vector3}, part: BasePart)
		if not TestHelpers.samePointSets(before, regionPoints(part)) then
			t.fail("Region changed during flip")
		end
	end

	t.test("brick flips in place about Top, four times returns to start", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.CFrame = CFrame.new(10, 20, 30)
		part.Parent = workspace
		local originalCFrame = part.CFrame
		local region = regionPoints(part)

		local topPoint = Vector3.new(10, 21, 30)
		local result = doFlip(part, topPoint, Vector3.yAxis, kCW)
		t.expect(result).toBe(part) -- in place, brick stays a brick
		expectVectorNear(part.Size, Vector3.new(3, 2, 1))
		expectVectorNear(part.Position, Vector3.new(10, 20, 30))
		expectSameRegion(region, part)

		for _ = 1, 3 do
			t.expect(doFlip(part, topPoint, Vector3.yAxis, kCW)).toBe(part)
		end
		expectVectorNear(part.Size, Vector3.new(1, 2, 3))
		expectCFrameNear(part.CFrame, originalCFrame)

		part:Destroy()
	end)

	t.test("clockwise then counterclockwise restores a brick", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(1, 2, 3)
		part.CFrame = CFrame.new(10, 20, 30) * CFrame.Angles(0.3, 0.5, 0.9)
		part.Parent = workspace
		local originalCFrame = part.CFrame

		-- The region doesn't move, so the same world point clicks the same
		-- world face both times; the CCW turn undoes the CW turn
		local clickPoint = originalCFrame:PointToWorldSpace(Vector3.new(0, 1, 0))
		local clickNormal = originalCFrame:VectorToWorldSpace(Vector3.yAxis)
		doFlip(part, clickPoint, clickNormal, kCW)
		doFlip(part, clickPoint, clickNormal, kCCW)
		expectVectorNear(part.Size, Vector3.new(1, 2, 3))
		expectCFrameNear(part.CFrame, originalCFrame)

		part:Destroy()
	end)

	t.test("brick flip preserves the multiset of surfaces and restores after four", function()
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(2, 2, 2)
		part.FrontSurface = Enum.SurfaceType.Weld
		part.RightSurface = Enum.SurfaceType.Glue
		part.BackSurface = Enum.SurfaceType.Studs
		part.LeftSurface = Enum.SurfaceType.Inlet
		part.Parent = workspace

		local function surfaceCounts(): {[Enum.SurfaceType]: number}
			local counts = {}
			for _, prop in {"TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface"} do
				local surface = (part :: any)[prop] :: Enum.SurfaceType
				counts[surface] = (counts[surface] or 0) + 1
			end
			return counts
		end
		local before = surfaceCounts()
		local topBefore = part.TopSurface
		local bottomBefore = part.BottomSurface

		local topPoint = part.Position + Vector3.new(0, 1, 0)
		doFlip(part, topPoint, Vector3.yAxis, kCW)
		t.expect(surfaceCounts()).toEqual(before)
		-- Top axis flip must not disturb top/bottom
		t.expect(part.TopSurface).toBe(topBefore)
		t.expect(part.BottomSurface).toBe(bottomBefore)

		for _ = 1, 3 do
			doFlip(part, topPoint, Vector3.yAxis, kCW)
		end
		t.expect(part.FrontSurface).toBe(Enum.SurfaceType.Weld)
		t.expect(part.RightSurface).toBe(Enum.SurfaceType.Glue)
		t.expect(part.BackSurface).toBe(Enum.SurfaceType.Studs)
		t.expect(part.LeftSurface).toBe(Enum.SurfaceType.Inlet)

		part:Destroy()
	end)

	t.test("wedge converts to a mesh and back over a four flip cycle", function()
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(2, 3, 4)
		wedge.CFrame = CFrame.new(5, 10, 15) * CFrame.Angles(0.4, 0.8, 1.2)
		wedge.Parent = workspace
		local originalCFrame = wedge.CFrame
		local region = regionPoints(wedge)

		-- Click the +X side face; a quarter turn about X is never a wedge
		-- symmetry, so every intermediate state needs a mesh. The click point
		-- is a fixed world position (the region never moves): re-deriving it
		-- from the recovered shape frame would be ambiguous up to symmetry.
		local sideClickPoint = wedge.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0))
		local sideClickNormal = wedge.CFrame:VectorToWorldSpace(Vector3.xAxis)

		local current: BasePart = wedge
		for step = 1, 3 do
			local result = doFlip(current, sideClickPoint, sideClickNormal, kCW)
			if not result then
				t.fail("Flip step " .. step .. " failed")
			end
			assert(result)
			current = result
			t.expect(current:IsA("MeshPart")).toBeTruthy()
			t.expect(current.Parent).toBe(workspace)
			local state = identifyPart(current)
			assert(state, "mesh state must be identifiable")
			t.expect(state.Shape).toBe("Wedge")
			t.expect(state.IsMeshRepresentation).toBeTruthy()
			-- The recovered state is normalized to the class representative,
			-- so the size may be a symmetry-permuted variant of the original
			local sorted = {state.ShapeSize.X, state.ShapeSize.Y, state.ShapeSize.Z}
			table.sort(sorted)
			t.expect(sorted).toEqual({2, 3, 4})
			expectSameRegion(region, current)
		end
		t.expect(wedge.Parent).toBe(nil) -- replaced, not destroyed

		-- Fourth flip returns to the primitive representation
		local result = doFlip(current, sideClickPoint, sideClickNormal, kCW)
		assert(result)
		t.expect(result:IsA("WedgePart")).toBeTruthy()
		expectVectorNear(result.Size, Vector3.new(2, 3, 4))
		expectCFrameNear(result.CFrame, originalCFrame)
		expectSameRegion(region, result)

		result:Destroy()
		wedge:Destroy()
	end)

	t.test("wedge slope clicks act on one face regardless of click position", function()
		-- The slope normal is constant across the surface, so clicking near
		-- the thin front lip must do the same thing as clicking near the top.
		-- (The old closest-face rule rotated the back face at the thin end.)
		local function makeWedge(): WedgePart
			local w = Instance.new("WedgePart")
			w.Anchored = true
			w.Size = Vector3.new(2, 3, 5)
			w.CFrame = CFrame.new(0, 40, 0)
			w.Parent = workspace
			return w
		end
		-- Slope normal for size (2, 3, 5) is (0, 5, -3).Unit: leans Top
		local slopeNormal = Vector3.new(0, 5, -3).Unit

		local a = makeWedge()
		local b = makeWedge()
		local nearThinEnd = a.CFrame:PointToWorldSpace(Vector3.new(0, -1.4, -2.3))
		local nearTopEnd = b.CFrame:PointToWorldSpace(Vector3.new(0, 1.4, 2.4))
		local resultA = doFlip(a, nearThinEnd, slopeNormal, kCW)
		local resultB = doFlip(b, nearTopEnd, slopeNormal, kCW)
		assert(resultA and resultB)

		expectVectorNear(resultA.Size, resultB.Size)
		expectCFrameNear(resultA.CFrame, resultB.CFrame)

		resultA:Destroy()
		resultB:Destroy()
		a:Destroy()
		b:Destroy()
	end)

	t.test("mesh replacement preserves visual properties and children", function()
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(2, 3, 4)
		wedge.CFrame = CFrame.new(5, 10, 15)
		wedge.Material = Enum.Material.DiamondPlate
		wedge.Color = Color3.fromRGB(50, 100, 150)
		wedge.Transparency = 0.25
		wedge.Name = "MyWedge"
		wedge:SetAttribute("MyAttribute", 42)
		wedge:AddTag("MyTag")
		local marker = Instance.new("Attachment")
		marker.Name = "Marker"
		marker.Parent = wedge
		wedge.Parent = workspace

		local result = doFlip(wedge, wedge.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0)), Vector3.xAxis, kCW)
		assert(result)
		t.expect(result:IsA("MeshPart")).toBeTruthy()
		t.expect(result.Material).toBe(Enum.Material.DiamondPlate)
		t.expect(result.Color).toBe(Color3.fromRGB(50, 100, 150))
		t.expect(math.abs(result.Transparency - 0.25) < 0.001).toBeTruthy()
		t.expect(result.Name).toBe("MyWedge")
		t.expect(result:FindFirstChild("Marker")).toBeTruthy()
		t.expect(result:GetAttribute("MyAttribute")).toBe(42)
		t.expect(result:HasTag("MyTag")).toBeTruthy()

		result:Destroy()
		wedge:Destroy()
	end)

	t.test("corner wedge cycles through meshes and back", function()
		local cornerWedge = Instance.new("CornerWedgePart")
		cornerWedge.Anchored = true
		cornerWedge.Size = Vector3.new(2, 3, 4)
		cornerWedge.CFrame = CFrame.new(-5, 8, 3)
		cornerWedge.Parent = workspace
		local originalCFrame = cornerWedge.CFrame
		local region = regionPoints(cornerWedge)

		local topPoint = cornerWedge.Position + Vector3.new(0, 1.5, 0)
		local current: BasePart = cornerWedge
		for _ = 1, 3 do
			local result = doFlip(current, topPoint, Vector3.yAxis, kCW)
			assert(result)
			current = result
			t.expect(current:IsA("MeshPart")).toBeTruthy()
			expectSameRegion(region, current)
		end
		local result = doFlip(current, topPoint, Vector3.yAxis, kCW)
		assert(result)
		t.expect(result:IsA("CornerWedgePart")).toBeTruthy()
		expectCFrameNear(result.CFrame, originalCFrame)
		expectVectorNear(result.Size, Vector3.new(2, 3, 4))

		result:Destroy()
		cornerWedge:Destroy()
	end)

	t.test("cylinder stays primitive for axis turns, meshes otherwise", function()
		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		cylinder.Anchored = true
		cylinder.Size = Vector3.new(6, 4, 4)
		cylinder.CFrame = CFrame.new(7, 9, 11)
		cylinder.Parent = workspace
		local region = regionPoints(cylinder)

		-- Click the +X cap: quarter turn about the axis is a symmetry
		local capPoint = cylinder.Position + Vector3.new(3, 0, 0)
		local result = doFlip(cylinder, capPoint, Vector3.xAxis, kCW)
		t.expect(result).toBe(cylinder) -- in place
		t.expect(cylinder.Shape).toBe(Enum.PartType.Cylinder)
		expectSameRegion(region, cylinder)

		-- Click the top of the barrel: a quarter turn about a cross axis needs
		-- a mesh, but a half turn is the end-over-end flip which is a cylinder
		-- symmetry again. So four clicks of the same world face alternate
		-- mesh, primitive, mesh, primitive.
		local topPoint = cylinder.Position + Vector3.new(0, 2, 0)
		local current: BasePart = cylinder
		local expectMesh = {true, false, true, false}
		for step = 1, 4 do
			local next_ = doFlip(current, topPoint, Vector3.yAxis, kCW)
			assert(next_, "flip step " .. step .. " failed")
			current = next_
			if current:IsA("MeshPart") ~= expectMesh[step] then
				t.fail(string.format("Step %d: expected mesh=%s, got %s",
					step, tostring(expectMesh[step]), current.ClassName))
			end
			expectSameRegion(region, current)
		end
		t.expect((current :: Part).Shape).toBe(Enum.PartType.Cylinder)

		current:Destroy()
		cylinder:Destroy()
	end)

	t.test("ball always rotates in place", function()
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.Size = Vector3.new(4, 4, 4)
		ball.CFrame = CFrame.new(1, 2, 3)
		ball.Parent = workspace
		local originalCFrame = ball.CFrame

		local topPoint = ball.Position + Vector3.new(0, 2, 0)
		for _ = 1, 4 do
			local result = doFlip(ball, topPoint, Vector3.yAxis, kCW)
			t.expect(result).toBe(ball)
			t.expect(ball.Shape).toBe(Enum.PartType.Ball)
			expectVectorNear(ball.Position, Vector3.new(1, 2, 3))
		end
		expectCFrameNear(ball.CFrame, originalCFrame)

		ball:Destroy()
	end)

	t.test("attachments keep their world pose through flips", function()
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(2, 3, 4)
		wedge.CFrame = CFrame.new(8, 15, -6) * CFrame.Angles(0.3, 0.6, 0.2)
		local attachment = Instance.new("Attachment")
		attachment.CFrame = CFrame.new(1, 0.5, -1) * CFrame.Angles(0.4, 0.2, 0.9)
		attachment.Parent = wedge
		local nested = Instance.new("Attachment")
		nested.CFrame = CFrame.new(0.5, -0.25, 0.75) * CFrame.Angles(0, 0.7, 0.3)
		nested.Parent = attachment
		wedge.Parent = workspace

		local attachmentWorld = attachment.WorldCFrame
		local nestedWorld = nested.WorldCFrame

		-- Swap path: wedge converts to a mesh representation
		local result = doFlip(wedge,
			wedge.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0)),
			wedge.CFrame:VectorToWorldSpace(Vector3.xAxis), kCW)
		assert(result)
		t.expect(result:IsA("MeshPart")).toBeTruthy()
		t.expect(attachment.Parent).toBe(result)
		expectCFrameNear(attachment.WorldCFrame, attachmentWorld)
		expectCFrameNear(nested.WorldCFrame, nestedWorld)

		-- Flip the mesh representation again (same world face)
		local result2 = doFlip(result,
			wedge.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0)),
			wedge.CFrame:VectorToWorldSpace(Vector3.xAxis), kCW)
		assert(result2)
		expectCFrameNear(attachment.WorldCFrame, attachmentWorld)
		expectCFrameNear(nested.WorldCFrame, nestedWorld)

		result2:Destroy()
		if result ~= result2 then
			result:Destroy()
		end
		wedge:Destroy()
	end)

	t.test("attachments rotate with the material when preservation is off", function()
		local noPreserve: doFlip.FlipOptions = {
			Clockwise = true,
			PreserveAttachments = false,
			PreserveDecals = false,
		}
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(2, 2, 2)
		part.CFrame = CFrame.new(4, 12, 9)
		local attachment = Instance.new("Attachment")
		attachment.CFrame = CFrame.new(1, 0, 0)
		attachment.Parent = part
		part.Parent = workspace
		local before = attachment.WorldCFrame.Position

		doFlip(part, part.Position + Vector3.new(0, 1, 0), Vector3.yAxis, noPreserve)
		if (attachment.WorldCFrame.Position - before).Magnitude < 0.5 then
			t.fail("Attachment should have rotated with the part")
		end

		part:Destroy()
	end)

	t.test("decals stay on their world face when preservation is on", function()
		local withDecals: doFlip.FlipOptions = {
			Clockwise = true,
			PreserveAttachments = true,
			PreserveDecals = true,
		}
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(2, 3, 4)
		part.CFrame = CFrame.new(-3, 18, 2) * CFrame.Angles(0.2, 0.9, 0.4)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Parent = part
		part.Parent = workspace

		local worldDirBefore = part.CFrame:VectorToWorldSpace(Vector3.fromNormalId(decal.Face))
		local clickPoint = part.CFrame:PointToWorldSpace(Vector3.new(0, 1.5, 0))
		local clickNormal = part.CFrame:VectorToWorldSpace(Vector3.yAxis)

		doFlip(part, clickPoint, clickNormal, withDecals)
		local worldDirAfter = part.CFrame:VectorToWorldSpace(Vector3.fromNormalId(decal.Face))
		expectVectorNear(worldDirAfter, worldDirBefore)
		-- The flip rotated about Top, so the decal's Face must have changed
		t.expect(decal.Face == Enum.NormalId.Front).toBeFalsy()

		-- And with preservation off, the Face property is untouched
		local faceBefore = decal.Face
		doFlip(part, clickPoint, clickNormal, kCW)
		t.expect(decal.Face).toBe(faceBefore)

		part:Destroy()
	end)

	t.test("decal faces follow through a representation swap", function()
		local withDecals: doFlip.FlipOptions = {
			Clockwise = true,
			PreserveAttachments = true,
			PreserveDecals = true,
		}
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(2, 3, 4)
		wedge.CFrame = CFrame.new(7, 22, -4)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Bottom
		decal.Parent = wedge
		wedge.Parent = workspace

		local worldDirBefore = wedge.CFrame:VectorToWorldSpace(Vector3.fromNormalId(decal.Face))
		local result = doFlip(wedge,
			wedge.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0)), Vector3.xAxis, withDecals)
		assert(result)
		t.expect(decal.Parent).toBe(result)
		local worldDirAfter = result.CFrame:VectorToWorldSpace(Vector3.fromNormalId(decal.Face))
		expectVectorNear(worldDirAfter, worldDirBefore)

		result:Destroy()
		wedge:Destroy()
	end)

	t.test("foreign MeshParts flip in place with box behavior", function()
		local foreign = Instance.new("MeshPart")
		foreign.Anchored = true
		foreign.Size = Vector3.new(1, 2, 3)
		foreign.CFrame = CFrame.new(3, 25, 7)
		foreign.Parent = workspace
		local originalCFrame = foreign.CFrame

		local topPoint = foreign.Position + Vector3.new(0, 1, 0)
		local result = doFlip(foreign, topPoint, Vector3.yAxis, kCW)
		t.expect(result).toBe(foreign) -- in place, stays the same instance
		expectVectorNear(foreign.Size, Vector3.new(3, 2, 1))
		expectVectorNear(foreign.Position, Vector3.new(3, 25, 7))

		for _ = 1, 3 do
			t.expect(doFlip(foreign, topPoint, Vector3.yAxis, kCW)).toBe(foreign)
		end
		expectVectorNear(foreign.Size, Vector3.new(1, 2, 3))
		expectCFrameNear(foreign.CFrame, originalCFrame)

		foreign:Destroy()
	end)

	t.test("SpecialMesh parts only flip within their primitive's symmetries", function()
		-- A SpecialMesh wedge can't be converted to a MeshPart without losing
		-- its mesh, and no quarter turn is a wedge symmetry, so: no-op
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(2, 3, 4)
		part.CFrame = CFrame.new(4, 5, 6)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = part
		part.Parent = workspace
		local originalCFrame = part.CFrame

		local result = doFlip(part, part.Position + Vector3.new(1, 0, 0), Vector3.xAxis, kCW)
		t.expect(result).toBe(nil)
		expectCFrameNear(part.CFrame, originalCFrame)
		expectVectorNear(part.Size, Vector3.new(2, 3, 4))

		-- But a SpecialMesh brick flips fine (bricks never need meshes)
		mesh.MeshType = Enum.MeshType.Brick
		local brickResult = doFlip(part, part.Position + Vector3.new(0, 1.5, 0), Vector3.yAxis, kCW)
		t.expect(brickResult).toBe(part)
		expectVectorNear(part.Size, Vector3.new(4, 3, 2))

		part:Destroy()
	end)
end

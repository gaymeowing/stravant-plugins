local TestTypes = require("./TestTypes")
local identifyPart = require("./identifyPart")
local pickRotationFace = require("./pickRotationFace")

return function(t: TestTypes.TestContext)
	local function wedgeState(size: Vector3): identifyPart.PartState
		local wedge = Instance.new("WedgePart")
		wedge.Size = size
		wedge.CFrame = CFrame.new(0, 50, 0)
		local state = identifyPart(wedge)
		assert(state, "expected a state")
		return state
	end

	t.test("squat wedge slope clicks act on the Front axis", function()
		-- Long and squat: the slope is nearly flat, its normal nearly +Y.
		-- Alignment alone would pick Top; the slope special case picks the
		-- axis more parallel to the slope instead.
		local state = wedgeState(Vector3.new(4, 1, 8))
		local slopeNormal = Vector3.new(0, 8, -1).Unit
		local point = state.ShapeCFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
		t.expect(pickRotationFace(state, point, slopeNormal)).toBe(Enum.NormalId.Front)
		state.Part:Destroy()
	end)

	t.test("tall wedge slope clicks act on the Top axis", function()
		local state = wedgeState(Vector3.new(4, 8, 1))
		local slopeNormal = Vector3.new(0, 1, -8).Unit
		local point = state.ShapeCFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
		t.expect(pickRotationFace(state, point, slopeNormal)).toBe(Enum.NormalId.Top)
		state.Part:Destroy()
	end)

	t.test("non-slope wedge faces score normally", function()
		local state = wedgeState(Vector3.new(4, 1, 8))
		local point = state.ShapeCFrame:PointToWorldSpace(Vector3.new(0, 0, 0))
		t.expect(pickRotationFace(state, point, Vector3.new(0, -1, 0))).toBe(Enum.NormalId.Bottom)
		t.expect(pickRotationFace(state, point, Vector3.new(1, 0, 0))).toBe(Enum.NormalId.Right)
		t.expect(pickRotationFace(state, point, Vector3.new(0, 0, 1))).toBe(Enum.NormalId.Back)
		state.Part:Destroy()
	end)

	t.test("bricks are not affected by the wedge slope special case", function()
		local part = Instance.new("Part")
		part.Size = Vector3.new(4, 1, 8)
		part.CFrame = CFrame.new(0, 50, 0)
		local state = identifyPart(part)
		assert(state)
		-- A slope-like normal on a brick scores by alignment: nearly +Y -> Top
		local slopeLikeNormal = Vector3.new(0, 8, -1).Unit
		local point = part.Position
		t.expect(pickRotationFace(state, point, slopeLikeNormal)).toBe(Enum.NormalId.Top)
		part:Destroy()
	end)
end

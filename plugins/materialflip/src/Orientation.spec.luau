local TestTypes = require("./TestTypes")
local Orientation = require("./Orientation")

return function(t: TestTypes.TestContext)
	t.test("has 24 distinct orientations", function()
		t.expect(Orientation.Count).toBe(24)
		local seen = {}
		for id = 1, 24 do
			local cf = Orientation.getCFrame(id)
			local key = tostring(cf.XVector) .. tostring(cf.YVector) .. tostring(cf.ZVector)
			t.expect(seen[key]).toBeFalsy()
			seen[key] = true
		end
	end)

	t.test("identity composes as expected", function()
		for id = 1, 24 do
			t.expect(Orientation.compose(Orientation.Identity, id)).toBe(id)
			t.expect(Orientation.compose(id, Orientation.Identity)).toBe(id)
		end
	end)

	t.test("inverses compose to the identity", function()
		for id = 1, 24 do
			t.expect(Orientation.compose(Orientation.invert(id), id)).toBe(Orientation.Identity)
			t.expect(Orientation.compose(id, Orientation.invert(id))).toBe(Orientation.Identity)
		end
	end)

	t.test("fromCFrame round trips and rejects non-members", function()
		for id = 1, 24 do
			t.expect(Orientation.fromCFrame(Orientation.getCFrame(id))).toBe(id)
		end
		t.expect(Orientation.fromCFrame(CFrame.Angles(0.3, 0, 0))).toBe(nil)
	end)

	t.test("quarter turns have order 4 and opposite directions invert", function()
		for _, normalId in Enum.NormalId:GetEnumItems() do
			local cw = Orientation.quarterTurnAbout(normalId, true)
			local ccw = Orientation.quarterTurnAbout(normalId, false)
			t.expect(Orientation.invert(cw)).toBe(ccw)
			t.expect(cw == ccw).toBeFalsy()
			local r = Orientation.Identity
			for _ = 1, 4 do
				r = Orientation.compose(cw, r)
			end
			t.expect(r).toBe(Orientation.Identity)
		end
	end)

	t.test("permuteSize permutes the size axes", function()
		local topTurn = Orientation.quarterTurnAbout(Enum.NormalId.Top, true)
		t.expect(Orientation.permuteSize(topTurn, Vector3.new(1, 2, 3))).toEqual(Vector3.new(3, 2, 1))
		local rightTurn = Orientation.quarterTurnAbout(Enum.NormalId.Right, true)
		t.expect(Orientation.permuteSize(rightTurn, Vector3.new(1, 2, 3))).toEqual(Vector3.new(1, 3, 2))
	end)

	t.test("rotateNormalId is a bijection fixing the turn axis", function()
		local topTurn = Orientation.quarterTurnAbout(Enum.NormalId.Top, true)
		t.expect(Orientation.rotateNormalId(topTurn, Enum.NormalId.Top)).toBe(Enum.NormalId.Top)
		t.expect(Orientation.rotateNormalId(topTurn, Enum.NormalId.Bottom)).toBe(Enum.NormalId.Bottom)
		local seen = {}
		for _, normalId in Enum.NormalId:GetEnumItems() do
			local mapped = Orientation.rotateNormalId(topTurn, normalId)
			t.expect(seen[mapped]).toBeFalsy()
			seen[mapped] = true
		end
	end)
end

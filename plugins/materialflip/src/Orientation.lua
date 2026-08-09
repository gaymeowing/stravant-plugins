--!strict

-- The 24 rotations of the octahedral group O, represented as signed
-- permutation matrices (CFrame rotations). These are exactly the rotations
-- that map the axis-aligned bounding box family onto itself, and therefore
-- the full set of material orientations reachable by MaterialFlip.
--
-- Orientations are identified by a stable integer id (1..24). The enumeration
-- order is deterministic (sorted by matrix key), so ids are safe to persist
-- in attributes and, later, to key published mesh assets by.

export type OrientationId = number

local kNormalIds = {
	Enum.NormalId.Right, Enum.NormalId.Left,
	Enum.NormalId.Top, Enum.NormalId.Bottom,
	Enum.NormalId.Back, Enum.NormalId.Front,
}

local function keyOf(cf: CFrame): string
	local parts = {}
	for _, v in {cf.XVector, cf.YVector, cf.ZVector} do
		table.insert(parts, string.format("%d,%d,%d", math.round(v.X), math.round(v.Y), math.round(v.Z)))
	end
	return table.concat(parts, ";")
end

local function isSignedPermutation(cf: CFrame): boolean
	for _, v in {cf.XVector, cf.YVector, cf.ZVector} do
		for _, comp in {v.X, v.Y, v.Z} do
			if math.abs(comp - math.round(comp)) > 0.01 then
				return false
			end
		end
	end
	return true
end

local function buildAll(): {CFrame}
	local axes = {Vector3.xAxis, Vector3.yAxis, Vector3.zAxis}
	local perms = {{1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1}}
	local list = {}
	for _, perm in perms do
		for signBits = 0, 7 do
			local cols = {}
			for i = 1, 3 do
				local sign = if math.floor(signBits / 2 ^ (i - 1)) % 2 == 0 then 1 else -1
				cols[i] = axes[perm[i]] * sign
			end
			local det = cols[1]:Cross(cols[2]):Dot(cols[3])
			if det > 0.5 then
				table.insert(list, CFrame.fromMatrix(Vector3.zero, cols[1], cols[2], cols[3]))
			end
		end
	end
	table.sort(list, function(a, b)
		return keyOf(a) < keyOf(b)
	end)
	return list
end

local kAll = buildAll()
assert(#kAll == 24, "Expected 24 rotations")

local kKeyToId: {[string]: OrientationId} = {}
for id, cf in kAll do
	kKeyToId[keyOf(cf)] = id
end

local function fromCFrame(cf: CFrame): OrientationId?
	if not isSignedPermutation(cf) then
		return nil
	end
	return kKeyToId[keyOf(cf)]
end

local kIdentity = assert(fromCFrame(CFrame.identity))

-- Precomputed composition and inverse tables
local kCompose: {{OrientationId}} = {}
local kInverse: {OrientationId} = {}
for a = 1, 24 do
	kCompose[a] = {}
	for b = 1, 24 do
		kCompose[a][b] = assert(fromCFrame(kAll[a] * kAll[b]), "Group not closed")
	end
	kInverse[a] = assert(fromCFrame(kAll[a]:Inverse()), "Missing inverse")
end

local Orientation = {}

Orientation.Count = 24
Orientation.Identity = kIdentity

function Orientation.getCFrame(id: OrientationId): CFrame
	return kAll[id]
end

-- Snap a rotation to its orientation id. Returns nil if the rotation is not
-- (close to) a signed permutation.
function Orientation.fromCFrame(cf: CFrame): OrientationId?
	return fromCFrame(cf)
end

-- compose(a, b) = the orientation acting as "apply b, then a"
function Orientation.compose(a: OrientationId, b: OrientationId): OrientationId
	return kCompose[a][b]
end

function Orientation.invert(id: OrientationId): OrientationId
	return kInverse[id]
end

-- The quarter turn about a box face axis. Clockwise means clockwise as seen
-- by a viewer looking at that face from outside the box.
function Orientation.quarterTurnAbout(normalId: Enum.NormalId, clockwise: boolean): OrientationId
	local axis = Vector3.fromNormalId(normalId)
	local angle = if clockwise then -math.pi / 2 else math.pi / 2
	local id = assert(fromCFrame(CFrame.fromAxisAngle(axis, angle)), "Quarter turn must be in the group")
	return id -- single return value: assert() would forward its message too
end

-- The bounding box size of a box of the given size rotated by this orientation
function Orientation.permuteSize(id: OrientationId, size: Vector3): Vector3
	local v = kAll[id]:VectorToWorldSpace(size)
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- Where this orientation sends a box face
function Orientation.rotateNormalId(id: OrientationId, normalId: Enum.NormalId): Enum.NormalId
	local rotated = kAll[id]:VectorToWorldSpace(Vector3.fromNormalId(normalId))
	for _, candidate in kNormalIds do
		if (Vector3.fromNormalId(candidate) - rotated).Magnitude < 0.01 then
			return candidate
		end
	end
	error("Rotated normal is not axis aligned")
end

return Orientation

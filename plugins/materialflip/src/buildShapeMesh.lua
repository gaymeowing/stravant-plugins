--!strict

-- Builds a MeshPart whose local geometry is the given primitive shape at the
-- given size, rotated by the given orientation ("baked in"). Since built-in
-- materials render as a triplanar projection in the part's local frame,
-- baking a rotation into the geometry and compensating with the part's
-- CFrame rotates the material on a part that occupies the same region.
--
-- The geometry was validated against the real primitives (vertices, sharp vs
-- smooth normals) in the identity orientation; see the workspace notes.
--
-- This module is the source of truth for the geometry of the PUBLISHED mesh
-- assets in MeshAssets.lua: each was generated from these builders at unit
-- size and uploaded with AssetService:CreateAssetAsync. The plugin itself
-- creates MeshParts from those published assets (getMeshRepresentation.lua)
-- because in-memory EditableMesh assets do not persist through place save.
-- If this geometry ever changes, the assets must be regenerated re-uploaded,
-- and the id table updated - do not change one without the other.

local AssetService = game:GetService("AssetService")

local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")

local kCylinderSegments = 24

type Builder = {
	em: EditableMesh,
	rotation: CFrame,
	vertex: (Builder, number, number, number) -> number,
	normal: (Builder, Vector3) -> number,
	tri: (Builder, number, number, number, number, number?, number?) -> (),
	quad: (Builder, number, number, number, number, number) -> (),
}

local function newBuilder(rotation: CFrame): Builder
	local b = {}
	b.em = AssetService:CreateEditableMesh()
	b.rotation = rotation
	function b.vertex(self: Builder, x: number, y: number, z: number): number
		return self.em:AddVertex(self.rotation:PointToWorldSpace(Vector3.new(x, y, z)))
	end
	function b.normal(self: Builder, dir: Vector3): number
		return self.em:AddNormal(self.rotation:VectorToWorldSpace(dir.Unit))
	end
	function b.tri(self: Builder, v0: number, v1: number, v2: number, n0: number, n1: number?, n2: number?)
		local f = self.em:AddTriangle(v0, v1, v2)
		self.em:SetFaceNormals(f, {n0, n1 or n0, n2 or n0})
	end
	function b.quad(self: Builder, v0: number, v1: number, v2: number, v3: number, n: number)
		self:tri(v0, v1, v2, n)
		self:tri(v0, v2, v3, n)
	end
	return (b :: any) :: Builder
end

local function buildWedge(b: Builder, size: Vector3)
	local h = size / 2
	-- Bottom corners
	local A = b:vertex(-h.X, -h.Y, -h.Z)
	local B = b:vertex( h.X, -h.Y, -h.Z)
	local C = b:vertex( h.X, -h.Y,  h.Z)
	local D = b:vertex(-h.X, -h.Y,  h.Z)
	-- Top back edge
	local E = b:vertex(-h.X,  h.Y,  h.Z)
	local F = b:vertex( h.X,  h.Y,  h.Z)

	b:quad(A, B, C, D, b:normal(-Vector3.yAxis))            -- bottom
	b:quad(D, C, F, E, b:normal(Vector3.zAxis))             -- back
	b:quad(B, A, E, F, b:normal(Vector3.new(0, h.Z, -h.Y))) -- slope
	b:tri(A, D, E, b:normal(-Vector3.xAxis))                -- -X side
	b:tri(B, F, C, b:normal(Vector3.xAxis))                 -- +X side
end

local function buildCornerWedge(b: Builder, size: Vector3)
	local h = size / 2
	-- Bottom corners
	local A = b:vertex(-h.X, -h.Y, -h.Z)
	local B = b:vertex( h.X, -h.Y, -h.Z)
	local C = b:vertex(-h.X, -h.Y,  h.Z)
	local D = b:vertex( h.X, -h.Y,  h.Z)
	-- Apex above B
	local E = b:vertex( h.X,  h.Y, -h.Z)

	b:quad(A, B, D, C, b:normal(-Vector3.yAxis))            -- bottom
	b:tri(B, E, D, b:normal(Vector3.xAxis))                 -- +X vertical side
	b:tri(B, A, E, b:normal(-Vector3.zAxis))                -- -Z vertical side
	b:tri(A, C, E, b:normal(Vector3.new(-h.Y, h.X, 0)))     -- -X facing slope
	b:tri(C, D, E, b:normal(Vector3.new(0, h.Z, h.Y)))      -- +Z facing slope
end

local function buildCylinder(b: Builder, size: Vector3)
	local hx = size.X / 2
	local ry = size.Y / 2
	local rz = size.Z / 2

	local backRim = {}  -- x = -hx
	local frontRim = {} -- x = +hx
	local rimNormals = {}
	for i = 0, kCylinderSegments - 1 do
		local theta = 2 * math.pi * i / kCylinderSegments
		local c, s = math.cos(theta), math.sin(theta)
		backRim[i] = b:vertex(-hx, ry * c, rz * s)
		frontRim[i] = b:vertex(hx, ry * c, rz * s)
		-- Elliptical cross section normal is (cos/ry, sin/rz)
		rimNormals[i] = b:normal(Vector3.new(0, c / ry, s / rz))
	end

	for i = 0, kCylinderSegments - 1 do
		local j = (i + 1) % kCylinderSegments
		-- Barrel quad, smooth shaded
		b:tri(backRim[i], backRim[j], frontRim[j], rimNormals[i], rimNormals[j], rimNormals[j])
		b:tri(backRim[i], frontRim[j], frontRim[i], rimNormals[i], rimNormals[j], rimNormals[i])
	end

	-- Caps, flat shaded (normals are per-face-vertex so rim verts can be shared)
	local centerPlus = b:vertex(hx, 0, 0)
	local centerMinus = b:vertex(-hx, 0, 0)
	local nPlus = b:normal(Vector3.xAxis)
	local nMinus = b:normal(-Vector3.xAxis)
	for i = 0, kCylinderSegments - 1 do
		local j = (i + 1) % kCylinderSegments
		b:tri(centerPlus, frontRim[i], frontRim[j], nPlus)
		b:tri(centerMinus, backRim[j], backRim[i], nMinus)
	end
end

local kBuilders: {[string]: (Builder, Vector3) -> ()} = {
	Wedge = buildWedge,
	CornerWedge = buildCornerWedge,
	Cylinder = buildCylinder,
}

-- Yields (CreateMeshPartAsync). The returned MeshPart's Size is the bounding
-- box of the rotated geometry, i.e. Orientation.permuteSize(orientation, size).
local function buildShapeMesh(shape: ShapeData.ShapeName, orientation: Orientation.OrientationId, size: Vector3): MeshPart
	local builderFn = kBuilders[shape]
	assert(builderFn, "No mesh builder for shape " .. tostring(shape) .. " (it never needs one)")
	local b = newBuilder(Orientation.getCFrame(orientation))
	builderFn(b, size)
	return AssetService:CreateMeshPartAsync(Content.fromObject(b.em))
end

return buildShapeMesh

--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function isBevelablePart(part: BasePart?): boolean
	if not part then
		return false
	end
	if part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block then
		return true
	end
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") then
		return true
	end
	return false
end

-- Copy visual/physical properties, set all surfaces smooth
local function applyProperties(target: BasePart, source: BasePart)
	target.Color = source.Color
	target.Material = source.Material
	target.MaterialVariant = source.MaterialVariant
	target.Transparency = source.Transparency
	target.Reflectance = source.Reflectance
	target.Anchored = source.Anchored
	target.CanCollide = source.CanCollide
	target.CastShadow = source.CastShadow
	target.TopSurface = Enum.SurfaceType.Smooth
	target.BottomSurface = Enum.SurfaceType.Smooth
	target.FrontSurface = Enum.SurfaceType.Smooth
	target.BackSurface = Enum.SurfaceType.Smooth
	target.LeftSurface = Enum.SurfaceType.Smooth
	target.RightSurface = Enum.SurfaceType.Smooth
end

local function createBlock(model: Model, source: BasePart, cf: CFrame, size: Vector3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

local function createCylinder(model: Model, source: BasePart, cf: CFrame, length: number, radius: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, radius * 2, radius * 2)
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

local function createSphere(model: Model, source: BasePart, cf: CFrame, radius: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

--------------------------------------------------------------------------------
-- General edge/corner creation from face-plane topology
--------------------------------------------------------------------------------

type FacePlane = { n: Vector3, d: number }

-- Solve intersection of 3 planes: n_i . p = d_i
local function solve3Planes(f1: FacePlane, f2: FacePlane, f3: FacePlane): Vector3
	local cross23 = f2.n:Cross(f3.n)
	local det = f1.n:Dot(cross23)
	return (f1.d * cross23 + f2.d * f3.n:Cross(f1.n) + f3.d * f1.n:Cross(f2.n)) / det
end

-- Create a cylinder between two object-space points, transformed by partCF
local function createCylinderBetween(
	model: Model, source: BasePart, partCF: CFrame,
	p1: Vector3, p2: Vector3, radius: number
)
	local dir = p2 - p1
	local length = dir.Magnitude
	if length < 0.001 then return end
	dir = dir / length

	local worldMid = partCF:PointToWorldSpace((p1 + p2) / 2)
	local worldDir = partCF:VectorToWorldSpace(dir)

	-- CFrame where X axis = worldDir (cylinder length axis)
	local helper = if math.abs(worldDir:Dot(Vector3.yAxis)) < 0.99
		then Vector3.yAxis else Vector3.xAxis
	local fwd = worldDir:Cross(helper).Unit
	local up = fwd:Cross(worldDir).Unit

	createCylinder(model, source, CFrame.fromMatrix(worldMid, worldDir, up), length, radius)
end

-- Given face planes, vertex->face mappings, and edge->vertex mappings,
-- compute offset vertices and create all spheres and cylinders.
-- Returns the offset vertex positions (object-space).
local function createEdgesAndCorners(
	model: Model, source: BasePart, cf: CFrame,
	faces: { FacePlane },
	vertexFaces: { { number } },
	edges: { { number } },
	R: number
): { Vector3 }
	-- Offset face planes inward by R
	local off: { FacePlane } = {}
	for i, f in faces do
		off[i] = { n = f.n, d = f.d - R }
	end

	-- Compute sphere centers (offset vertices)
	local centers: { Vector3 } = {}
	for i, vf in vertexFaces do
		centers[i] = solve3Planes(off[vf[1]], off[vf[2]], off[vf[3]])
	end

	-- Create spheres
	for _, c in centers do
		createSphere(model, source, cf * CFrame.new(c), R)
	end

	-- Create cylinders
	for _, edge in edges do
		createCylinderBetween(model, source, cf, centers[edge[1]], centers[edge[2]], R)
	end

	return centers
end

--------------------------------------------------------------------------------
-- Block bevel
--------------------------------------------------------------------------------

local function doBevelBlock(part: BasePart, R: number)
	local W, H, D = part.Size.X, part.Size.Y, part.Size.Z
	local cf = part.CFrame
	local model = Instance.new("Model")
	model.Name = part.Name

	-- Body: reuse original part as slab 1, create 2 more slabs
	applyProperties(part, part)
	part.Size = Vector3.new(W, H - 2 * R, D - 2 * R)
	createBlock(model, part, cf, Vector3.new(W - 2 * R, H, D - 2 * R))
	createBlock(model, part, cf, Vector3.new(W - 2 * R, H - 2 * R, D))

	-- Face planes: outward normal n, distance d where n.p = d on the face
	local faces: { FacePlane } = {
		{ n = Vector3.new(1, 0, 0), d = W / 2 },   -- 1: right
		{ n = Vector3.new(-1, 0, 0), d = W / 2 },  -- 2: left
		{ n = Vector3.new(0, 1, 0), d = H / 2 },   -- 3: top
		{ n = Vector3.new(0, -1, 0), d = H / 2 },  -- 4: bottom
		{ n = Vector3.new(0, 0, 1), d = D / 2 },   -- 5: back
		{ n = Vector3.new(0, 0, -1), d = D / 2 },  -- 6: front
	}

	-- 8 vertices: {face1, face2, face3}
	local vertexFaces = {
		{ 1, 3, 5 }, { 1, 3, 6 }, { 1, 4, 5 }, { 1, 4, 6 },
		{ 2, 3, 5 }, { 2, 3, 6 }, { 2, 4, 5 }, { 2, 4, 6 },
	}

	-- 12 edges: {vertex1, vertex2}
	local edges = {
		{ 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 },
		{ 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 },
		{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
	}

	createEdgesAndCorners(model, part, cf, faces, vertexFaces, edges, R)

	model.Parent = part.Parent
	model.PrimaryPart = part
	part.Parent = model
end

--------------------------------------------------------------------------------
-- Wedge bevel
--------------------------------------------------------------------------------

local function doBevelWedge(part: BasePart, R: number)
	local W, H, D = part.Size.X, part.Size.Y, part.Size.Z
	local L = math.sqrt(D * D + H * H)
	local cf = part.CFrame
	local model = Instance.new("Model")
	model.Name = part.Name

	-- Body: slab 1 = original part inset from left/right
	applyProperties(part, part)
	part.Size = Vector3.new(W - 2 * R, H, D)

	-- Body: slab 2 = eroded wedge (inset from bottom/back/slope, full width)
	local He = H - R * (D + H + L) / D
	local De = D - R * (H + D + L) / H
	if He > 0.01 and De > 0.01 then
		local yOff = R * (D - H - L) / (2 * D)
		local zOff = R * (D + L - H) / (2 * H)
		local wp = Instance.new("WedgePart")
		wp.Size = Vector3.new(W, He, De)
		wp.CFrame = cf * CFrame.new(0, yOff, zOff)
		applyProperties(wp, part)
		wp.Parent = model
	end

	-- Face planes
	local nSlope = Vector3.new(0, D, -H) / L
	local faces: { FacePlane } = {
		{ n = Vector3.new(0, -1, 0), d = H / 2 },  -- 1: bottom
		{ n = Vector3.new(0, 0, 1), d = D / 2 },   -- 2: back
		{ n = Vector3.new(-1, 0, 0), d = W / 2 },  -- 3: left
		{ n = Vector3.new(1, 0, 0), d = W / 2 },   -- 4: right
		{ n = nSlope, d = 0 },                      -- 5: slope
	}

	-- 6 vertices: {face1, face2, face3}
	-- V1: bottom-front-left, V2: bottom-front-right
	-- V3: bottom-back-left,  V4: bottom-back-right
	-- V5: top-back-left,     V6: top-back-right
	local vertexFaces = {
		{ 1, 3, 5 }, -- V1
		{ 1, 4, 5 }, -- V2
		{ 1, 2, 3 }, -- V3
		{ 1, 2, 4 }, -- V4
		{ 2, 3, 5 }, -- V5
		{ 2, 4, 5 }, -- V6
	}

	-- 9 edges: {vertex1, vertex2}
	local edges = {
		{ 1, 2 }, -- bottom-front (X)
		{ 3, 4 }, -- bottom-back (X)
		{ 5, 6 }, -- top-back (X)
		{ 1, 3 }, -- bottom-left (Z)
		{ 2, 4 }, -- bottom-right (Z)
		{ 3, 5 }, -- back-left (Y)
		{ 4, 6 }, -- back-right (Y)
		{ 1, 5 }, -- slope-left (diagonal)
		{ 2, 6 }, -- slope-right (diagonal)
	}

	createEdgesAndCorners(model, part, cf, faces, vertexFaces, edges, R)

	model.Parent = part.Parent
	model.PrimaryPart = part
	part.Parent = model
end

--------------------------------------------------------------------------------
-- CornerWedge bevel
--------------------------------------------------------------------------------

local function doBevelCornerWedge(part: BasePart, R: number)
	local W, H, D = part.Size.X, part.Size.Y, part.Size.Z
	local Lf = math.sqrt(D * D + H * H) -- front-slope hypotenuse
	local Ml = math.sqrt(H * H + W * W) -- left-slope hypotenuse
	local cf = part.CFrame
	local model = Instance.new("Model")
	model.Name = part.Name

	-- Body: slab 1 = original part with bottom inset by R
	applyProperties(part, part)
	part.Size = Vector3.new(W, H - R, D)
	part.CFrame = cf * CFrame.new(0, R / 2, 0)

	-- Body: slab 2 = corner wedge inset from back and right
	if W - R > 0.01 and D - R > 0.01 then
		local cwp = Instance.new("CornerWedgePart")
		cwp.Size = Vector3.new(W - R, H, D - R)
		cwp.CFrame = cf * CFrame.new(-R / 2, 0, -R / 2)
		applyProperties(cwp, part)
		cwp.Parent = model
	end

	-- Face planes
	-- CornerWedgePart vertices:
	-- V1=(-W/2,-H/2,-D/2), V2=(W/2,-H/2,-D/2), V3=(-W/2,-H/2,D/2),
	-- V4=(W/2,-H/2,D/2), V5=(W/2,H/2,D/2)
	local nFrontSlope = Vector3.new(0, D, -H) / Lf
	local nLeftSlope = Vector3.new(-H, W, 0) / Ml
	local faces: { FacePlane } = {
		{ n = Vector3.new(0, -1, 0), d = H / 2 },  -- 1: bottom
		{ n = Vector3.new(0, 0, 1), d = D / 2 },   -- 2: back
		{ n = Vector3.new(1, 0, 0), d = W / 2 },   -- 3: right
		{ n = nFrontSlope, d = 0 },                 -- 4: front-slope
		{ n = nLeftSlope, d = 0 },                  -- 5: left-slope
	}

	-- 5 vertices: {face1, face2, face3}
	-- V5 has 4 adjacent faces; pick back/right/front-slope for the sphere
	local vertexFaces = {
		{ 1, 4, 5 }, -- V1: bottom, front-slope, left-slope
		{ 1, 3, 4 }, -- V2: bottom, right, front-slope
		{ 1, 2, 5 }, -- V3: bottom, back, left-slope
		{ 1, 2, 3 }, -- V4: bottom, back, right
		{ 2, 3, 4 }, -- V5: back, right, front-slope (omit left-slope)
	}

	-- 8 edges: {vertex1, vertex2}
	local edges = {
		{ 1, 2 }, -- bottom-front (X)
		{ 3, 4 }, -- bottom-back (X)
		{ 1, 3 }, -- bottom-left (Z)
		{ 2, 4 }, -- bottom-right (Z)
		{ 4, 5 }, -- back-right vertical (Y)
		{ 2, 5 }, -- right front-slope diagonal (YZ at x=W/2)
		{ 3, 5 }, -- back left-slope diagonal (XY at z=D/2)
		{ 1, 5 }, -- main diagonal (XYZ)
	}

	createEdgesAndCorners(model, part, cf, faces, vertexFaces, edges, R)

	model.Parent = part.Parent
	model.PrimaryPart = part
	part.Parent = model
end

--------------------------------------------------------------------------------
-- Dispatcher
--------------------------------------------------------------------------------

local function doBevel(part: BasePart, radius: number)
	local W, H, D = part.Size.X, part.Size.Y, part.Size.Z
	local maxR: number

	if part:IsA("WedgePart") then
		local L = math.sqrt(D * D + H * H)
		maxR = math.min(W / 2, H * D / (D + H + L))
	elseif part:IsA("CornerWedgePart") then
		local Lf = math.sqrt(D * D + H * H)
		maxR = math.min(W / 2, H / 2, D / 2, H * D / (D + H + Lf))
	else
		maxR = math.min(W, H, D) / 2
	end

	local R = math.clamp(radius, 0.01, maxR)

	if part:IsA("WedgePart") then
		doBevelWedge(part, R)
	elseif part:IsA("CornerWedgePart") then
		doBevelCornerWedge(part, R)
	else
		doBevelBlock(part, R)
	end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local function BevelSettings(props: ToolSettingsProps)
	local radius = props.GetSetting("Radius") :: number

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		RadiusInput = e(NumberInput, {
			Label = "Radius",
			Value = radius,
			ValueEntered = function(newValue: number)
				newValue = math.max(0.01, newValue)
				props.SetSetting("Radius", newValue)
				return newValue
			end,
			LayoutOrder = 1,
		}),
	})
end

local Bevel: ToolTypes.ToolDefinition = {
	Id = "bevel",
	Name = "Bevel",
	Description = "Replace a part with a rounded-edge model",

	DefaultSettings = {
		Radius = 0.5,
	},

	OnDeactivated = function(ctx: ToolContext)
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		if isBevelablePart(ctx.Target) then
			ctx.SetHighlight(ctx.Target)
		else
			ctx.SetHighlight(nil)
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if not ctx.Target or not isBevelablePart(ctx.Target) then
			return
		end

		local radius = ctx.GetSetting("Radius") :: number
		local id = ctx.BeginRecording("Bevel")

		doBevel(ctx.Target, radius)

		if id then
			ctx.FinishRecording(id)
		end

		ctx.SetHighlight(nil)
	end,

	RenderSettings = BevelSettings,
}

return Bevel

--!strict
local UserInputService = game:GetService("UserInputService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Checkbox = require("../PluginGui/Checkbox")
local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local NORMAL_ID_VECTORS: { [Enum.NormalId]: Vector3 } = {
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Position-based face detection (more accurate than normal-based for oblique views)
local function detectFaceFromPosition(part: BasePart, hitPosition: Vector3): Enum.NormalId
	local localDisp = part.CFrame:VectorToObjectSpace(hitPosition - part.Position)
	local halfSize = part.Size / 2
	local smallest = math.huge
	local bestFace = Enum.NormalId.Top
	if math.abs(localDisp.X - halfSize.X) < smallest then
		bestFace = Enum.NormalId.Right
		smallest = math.abs(localDisp.X - halfSize.X)
	end
	if math.abs(localDisp.X + halfSize.X) < smallest then
		bestFace = Enum.NormalId.Left
		smallest = math.abs(localDisp.X + halfSize.X)
	end
	if math.abs(localDisp.Y - halfSize.Y) < smallest then
		bestFace = Enum.NormalId.Top
		smallest = math.abs(localDisp.Y - halfSize.Y)
	end
	if math.abs(localDisp.Y + halfSize.Y) < smallest then
		bestFace = Enum.NormalId.Bottom
		smallest = math.abs(localDisp.Y + halfSize.Y)
	end
	if math.abs(localDisp.Z - halfSize.Z) < smallest then
		bestFace = Enum.NormalId.Back
		smallest = math.abs(localDisp.Z - halfSize.Z)
	end
	if math.abs(localDisp.Z + halfSize.Z) < smallest then
		bestFace = Enum.NormalId.Front
		smallest = math.abs(localDisp.Z + halfSize.Z)
	end
	return bestFace
end

--------------------------------------------------------------------------------
-- Edge threshold face selection (ported from ResizeAlign)
--------------------------------------------------------------------------------

local EDGE_THRESHOLD = 0.25

local function otherNormalIds(normalId: Enum.NormalId): (Enum.NormalId, Enum.NormalId, Enum.NormalId, Enum.NormalId)
	if normalId == Enum.NormalId.Top or normalId == Enum.NormalId.Bottom then
		return Enum.NormalId.Right, Enum.NormalId.Left, Enum.NormalId.Back, Enum.NormalId.Front
	elseif normalId == Enum.NormalId.Right or normalId == Enum.NormalId.Left then
		return Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Back, Enum.NormalId.Front
	else
		return Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Right, Enum.NormalId.Left
	end
end

local function getFaceSize(part: BasePart, normalId: Enum.NormalId): number
	local size = part.Size
	local vec = Vector3.fromNormalId(normalId)
	local x = (1 - math.abs(vec.X)) * size.X
	local y = (1 - math.abs(vec.Y)) * size.Y
	local z = (1 - math.abs(vec.Z)) * size.Z
	return (if x == 0 then 1 else x) * (if y == 0 then 1 else y) * (if z == 0 then 1 else z)
end

type ScreenEdge = {
	a: Vector2, b: Vector2,
	c: Vector2, d: Vector2,
	n: Enum.NormalId,
}

local function intersectRayRay2D(r1o: Vector2, r1d: Vector2, r2o: Vector2, r2d: Vector2): (boolean, number)
	local n =
		(r2o - r1o):Dot(r1d) * r2d:Dot(r2d) +
		(r1o - r2o):Dot(r2d) * r1d:Dot(r2d)
	local d =
		r1d:Dot(r1d) * r2d:Dot(r2d) -
		r1d:Dot(r2d) * r1d:Dot(r2d)
	if d == 0 then
		return false, 0
	else
		return true, n / d
	end
end

local function directionAndDistanceToEdge(edge: ScreenEdge, point: Vector2): (Vector2, number)
	local alongEdge = (edge.b - edge.a).Unit
	local toPoint = point - edge.a
	local pointOnEdge = edge.a + alongEdge * toPoint:Dot(alongEdge)
	local toEdge = pointOnEdge - point
	return toEdge.Unit, toEdge.Magnitude
end

local function distanceToOppositeEdge(edge: ScreenEdge, point: Vector2, direction: Vector2): number?
	local alongEdge = edge.d - edge.c
	local alongEdgeDir = alongEdge.Unit
	local intersect, t = intersectRayRay2D(edge.c, alongEdgeDir, point, direction)
	if intersect then
		local intersectPoint = edge.c + alongEdgeDir * t
		local firstTry = (intersectPoint - point).Magnitude
		local clampC = (point - edge.c).Magnitude
		local clampD = (point - edge.d).Magnitude
		return math.min(firstTry, clampC, clampD)
	else
		return nil
	end
end

local function getTargetFace(part: BasePart, hitPosition: Vector3): Enum.NormalId
	local normalId = detectFaceFromPosition(part, hitPosition)

	-- Edge threshold refinement: snap to smaller adjacent face when near an edge
	local camera = workspace.CurrentCamera
	if not camera then
		return normalId
	end

	local halfSize = 0.5 * part.Size
	local cf = part.CFrame
	local basePosition = cf:PointToWorldSpace(Vector3.fromNormalId(normalId) * halfSize)
	local x, negx, y, negy = otherNormalIds(normalId)
	local offset_x = cf:VectorToWorldSpace(Vector3.fromNormalId(x) * halfSize)
	local offset_y = cf:VectorToWorldSpace(Vector3.fromNormalId(y) * halfSize)

	local function toScreen(worldPos: Vector3): Vector2
		local screenPos = camera:WorldToScreenPoint(worldPos)
		return Vector2.new(screenPos.X, screenPos.Y)
	end

	local screenEdges: { ScreenEdge } = {
		{ a = toScreen(basePosition + offset_x + offset_y), b = toScreen(basePosition + offset_x - offset_y), c = toScreen(basePosition - offset_x + offset_y), d = toScreen(basePosition - offset_x - offset_y), n = x },
		{ a = toScreen(basePosition - offset_x + offset_y), b = toScreen(basePosition - offset_x - offset_y), c = toScreen(basePosition + offset_x + offset_y), d = toScreen(basePosition + offset_x - offset_y), n = negx },
		{ a = toScreen(basePosition + offset_y + offset_x), b = toScreen(basePosition + offset_y - offset_x), c = toScreen(basePosition - offset_y + offset_x), d = toScreen(basePosition - offset_y - offset_x), n = y },
		{ a = toScreen(basePosition - offset_y + offset_x), b = toScreen(basePosition - offset_y - offset_x), c = toScreen(basePosition + offset_y + offset_x), d = toScreen(basePosition + offset_y - offset_x), n = negy },
	}

	local mouseLocation = UserInputService:GetMouseLocation()
	local smallestFrac = 1
	local smallestFracEdge: ScreenEdge? = nil
	local hardCutoff = camera.ViewportSize.Magnitude * 0.2

	for _, edge in screenEdges do
		local dir, distToEdge = directionAndDistanceToEdge(edge, mouseLocation)
		local distToOtherEdge = distanceToOppositeEdge(edge, mouseLocation, -dir)
		if distToOtherEdge then
			local totalDist = distToOtherEdge + distToEdge
			local frac = distToEdge / totalDist
			if frac < smallestFrac and frac < EDGE_THRESHOLD and getFaceSize(part, edge.n) < getFaceSize(part, normalId) then
				if distToEdge < hardCutoff then
					smallestFrac = frac
					smallestFracEdge = edge
				end
			end
		end
	end

	return if smallestFracEdge then smallestFracEdge.n else normalId
end

local function sizeAlongNormal(size: Vector3, normalId: Enum.NormalId): number
	local axis = NORMAL_ID_VECTORS[normalId]
	return math.abs(size.X * axis.X) + math.abs(size.Y * axis.Y) + math.abs(size.Z * axis.Z)
end

local function isBlockPart(part: BasePart?): boolean
	if not part then
		return false
	end
	if part:IsA("Part") then
		return part.Shape == Enum.PartType.Block
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

-- Get the two tangent axes for a face (axes perpendicular to the normal)
local function getFaceTangents(normalId: Enum.NormalId): (Vector3, Vector3)
	local axis = NORMAL_ID_VECTORS[normalId]
	if math.abs(axis.X) > 0.5 then
		return Vector3.yAxis, Vector3.zAxis
	elseif math.abs(axis.Y) > 0.5 then
		return Vector3.xAxis, Vector3.zAxis
	else
		return Vector3.xAxis, Vector3.yAxis
	end
end

--------------------------------------------------------------------------------
-- Fill triangle with WedgeParts (simplified from GapFill's fillTriangle)
--------------------------------------------------------------------------------

local function fillTriangle(
	a: Vector3, b: Vector3, c: Vector3,
	thickness: number,
	extrudeDir: Vector3,
	source: BasePart,
	parent: Instance
)
	local ab, bc, ca = b - a, c - b, a - c
	local abm, bcm, cam = ab.Magnitude, bc.Magnitude, ca.Magnitude

	-- Skip degenerate triangles
	if abm < 0.001 or bcm < 0.001 or cam < 0.001 then
		return
	end

	local e1 = ca:Dot(ab) / (abm * abm)
	local e2 = ab:Dot(bc) / (bcm * bcm)
	local e3 = bc:Dot(ca) / (cam * cam)
	local edg1 = math.abs(0.5 + e1)
	local edg2 = math.abs(0.5 + e2)
	local edg3 = math.abs(0.5 + e3)

	-- Pick the best edge to split on
	if math.abs(e1) > 0.0001 and math.abs(e2) > 0.0001 and math.abs(e3) > 0.0001 then
		if edg1 < edg2 then
			if edg1 >= edg3 then
				a, b, c = c, a, b
				ab, bc, ca = ca, ab, bc
				abm = cam
			end
		else
			if edg2 < edg3 then
				a, b, c = b, c, a
				ab, bc, ca = bc, ca, ab
				abm = bcm
			else
				a, b, c = c, a, b
				ab, bc, ca = ca, ab, bc
				abm = cam
			end
		end
	else
		if math.abs(e1) <= 0.0001 then
			-- already good
		elseif math.abs(e2) <= 0.0001 then
			a, b, c = b, c, a
			ab, bc, ca = bc, ca, ab
			abm = bcm
		else
			a, b, c = c, a, b
			ab, bc, ca = ca, ab, bc
			abm = cam
		end
	end

	local len1 = -ca:Dot(ab) / abm
	local len2 = abm - len1
	local width = (ca + ab.Unit * len1).Magnitude

	local normal = ab:Cross(bc).Unit
	local maincf = CFrame.fromMatrix(a, normal:Cross(-ab.Unit), normal, -ab.Unit)

	-- Figure out flip direction based on extrude direction
	local flip = 1
	if normal:Dot(extrudeDir) > 0 then
		flip = -1
	end

	if len1 > 0.001 then
		local part1 = Instance.new("Part")
		part1.Shape = Enum.PartType.Wedge
		applyProperties(part1, source)
		part1.Size = Vector3.new(thickness, width, len1)
		part1.CFrame = maincf * CFrame.Angles(math.pi, 0, math.pi / 2) * CFrame.new(flip * (-thickness / 2), width / 2, len1 / 2)
		part1.Parent = parent
	end
	if len2 > 0.001 then
		local part2 = Instance.new("Part")
		part2.Shape = Enum.PartType.Wedge
		applyProperties(part2, source)
		part2.Size = Vector3.new(thickness, width, len2)
		part2.CFrame = maincf * CFrame.Angles(math.pi, math.pi, -math.pi / 2) * CFrame.new(flip * (thickness / 2), width / 2, -len1 - len2 / 2)
		part2.Parent = parent
	end
end

--------------------------------------------------------------------------------
-- OuterTouch resize (ported from ResizeAlign)
--------------------------------------------------------------------------------

local function resizePartAlongFace(part: BasePart, normalId: Enum.NormalId, amount: number)
	local localDir = NORMAL_ID_VECTORS[normalId]
	local absDir = Vector3.new(math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z))
	part.Size = part.Size + absDir * amount
	part.CFrame = part.CFrame * CFrame.new(localDir * amount / 2)
end

local function extendBlocksToTouch(
	blockA: BasePart, faceA: Enum.NormalId,
	blockB: BasePart, faceB: Enum.NormalId
)
	local function faceCorners(part: BasePart, normalId: Enum.NormalId): { Vector3 }
		local hsize = part.Size / 2
		local cf = part.CFrame
		local fDir = Vector3.fromNormalId(normalId) * hsize
		local t1, t2 = getFaceTangents(normalId)
		t1, t2 = t1 * hsize, t2 * hsize
		return {
			cf:PointToWorldSpace(fDir + t1 + t2),
			cf:PointToWorldSpace(fDir + t1 - t2),
			cf:PointToWorldSpace(fDir - t1 - t2),
			cf:PointToWorldSpace(fDir - t1 + t2),
		}
	end

	local cornersA = faceCorners(blockA, faceA)
	local cornersB = faceCorners(blockB, faceB)
	local dirA = blockA.CFrame:VectorToWorldSpace(Vector3.fromNormalId(faceA))
	local dirB = blockB.CFrame:VectorToWorldSpace(Vector3.fromNormalId(faceB))

	-- Find the corner of A most outward relative to B's face plane
	local basePtB = blockB.CFrame:PointToWorldSpace(Vector3.fromNormalId(faceB) * blockB.Size / 2)
	local maxDistA = -math.huge
	local extendPtA = cornersA[1]
	for _, pt in cornersA do
		local dist = (pt - basePtB):Dot(dirB)
		if dist > maxDistA then
			maxDistA = dist
			extendPtA = pt
		end
	end

	-- Find the corner of B most outward relative to A's face plane
	local basePtA = blockA.CFrame:PointToWorldSpace(Vector3.fromNormalId(faceA) * blockA.Size / 2)
	local maxDistB = -math.huge
	local extendPtB = cornersB[1]
	for _, pt in cornersB do
		local dist = (pt - basePtA):Dot(dirA)
		if dist > maxDistB then
			maxDistB = dist
			extendPtB = pt
		end
	end

	-- Ray-ray closest approach for extend amounts
	local a_val = dirA:Dot(dirA)
	local b_val = dirA:Dot(dirB)
	local c_val = dirB:Dot(dirB)
	local denom = a_val * c_val - b_val * b_val
	if math.abs(denom) < 0.001 then
		return
	end

	local startSep = extendPtB - extendPtA
	local d_val = dirA:Dot(startSep)
	local e_val = dirB:Dot(startSep)
	local lenA = -(b_val * e_val - c_val * d_val) / denom
	local lenB = -(a_val * e_val - b_val * d_val) / denom

	resizePartAlongFace(blockA, faceA, lenA)
	resizePartAlongFace(blockB, faceB, lenB)
end

--------------------------------------------------------------------------------
-- Core sweep algorithm
--------------------------------------------------------------------------------

local function doSweep(
	partA: BasePart, normalIdA: Enum.NormalId,
	partB: BasePart, normalIdB: Enum.NormalId,
	segmentCount: number,
	avoidZFighting: boolean
)
	-- Compute face geometry for A
	local axisA = NORMAL_ID_VECTORS[normalIdA]
	local nA = partA.CFrame:VectorToWorldSpace(axisA)
	local halfSizeA = sizeAlongNormal(partA.Size, normalIdA) / 2
	local centerA = partA.CFrame:PointToWorldSpace(axisA * halfSizeA)

	-- Compute face geometry for B
	local axisB = NORMAL_ID_VECTORS[normalIdB]
	local nB = partB.CFrame:VectorToWorldSpace(axisB)
	local halfSizeB = sizeAlongNormal(partB.Size, normalIdB) / 2
	local centerB = partB.CFrame:PointToWorldSpace(axisB * halfSizeB)

	-- Get face tangent dimensions for A (we use A's properties for the sweep)
	local tanA1, tanA2 = getFaceTangents(normalIdA)
	local tanA1_world = partA.CFrame:VectorToWorldSpace(tanA1)
	local tanA2_world = partA.CFrame:VectorToWorldSpace(tanA2)

	local tanB1, tanB2 = getFaceTangents(normalIdB)
	local tanB1_world = partB.CFrame:VectorToWorldSpace(tanB1)
	local tanB2_world = partB.CFrame:VectorToWorldSpace(tanB2)

	-- Determine hinge axis
	local crossVec = nA:Cross(nB)
	local crossMag = crossVec.Magnitude

	-- Determine the hinge axis (the axis we rotate around)
	local hingeAxis: Vector3

	if crossMag < 0.001 then
		-- Normals are parallel
		if nA:Dot(-nB) > 0.5 then
			-- Facing each other (nA ≈ -nB): straight bridge, no arc
			local model = Instance.new("Model")
			model.Name = "Sweep"

			local midpoint = (centerA + centerB) / 2
			local dist = (centerB - centerA).Magnitude
			-- Bridge direction
			local bridgeDir = if dist > 0.001 then (centerB - centerA).Unit else nA

			-- Compute face dimensions for A
			local widthA1 = math.abs(tanA1:Dot(partA.Size))
			local widthA2 = math.abs(tanA2:Dot(partA.Size))

			-- Pick hinge axis as the one most aligned with the face tangents
			local upDir = tanA1_world
			local bridgeWidth = widthA1
			local bridgeHeight = widthA2
			if math.abs(bridgeDir:Dot(tanA1_world)) > math.abs(bridgeDir:Dot(tanA2_world)) then
				upDir = tanA2_world
				bridgeWidth = widthA2
				bridgeHeight = widthA1
			end

			local block = Instance.new("Part")
			block.Shape = Enum.PartType.Block
			applyProperties(block, partA)
			block.Size = Vector3.new(bridgeWidth, bridgeHeight, dist)
			block.CFrame = CFrame.lookAt(midpoint, midpoint + bridgeDir, upDir)
			block.Parent = model

			model.Parent = partA.Parent
			return
		else
			-- Same direction (nA ≈ nB): 180-degree arc
			-- Use displacement between faces to determine arc plane
			local disp = centerB - centerA
			local dispPerp = disp - nA * disp:Dot(nA)
			if dispPerp.Magnitude < 0.001 then
				-- Centers aligned along normal, pick arbitrary perpendicular
				if math.abs(nA:Dot(Vector3.yAxis)) < 0.99 then
					dispPerp = nA:Cross(Vector3.yAxis).Unit
				else
					dispPerp = nA:Cross(Vector3.xAxis).Unit
				end
			end
			hingeAxis = nA:Cross(dispPerp.Unit).Unit
		end
	else
		hingeAxis = crossVec.Unit
	end

	-- Find face width along the hinge axis for A and B
	local widthA_axial: number
	if math.abs(tanA1_world:Dot(hingeAxis)) > math.abs(tanA2_world:Dot(hingeAxis)) then
		widthA_axial = math.abs(tanA1:Dot(partA.Size))
	else
		widthA_axial = math.abs(tanA2:Dot(partA.Size))
	end

	local widthB_axial: number
	if math.abs(tanB1_world:Dot(hingeAxis)) > math.abs(tanB2_world:Dot(hingeAxis)) then
		widthB_axial = math.abs(tanB1:Dot(partB.Size))
	else
		widthB_axial = math.abs(tanB2:Dot(partB.Size))
	end

	-- Use average axial width
	local axialWidth = (widthA_axial + widthB_axial) / 2

	-- Find face depth (radial extent) for A and B
	local depthA_radial: number
	if math.abs(tanA1_world:Dot(hingeAxis)) > math.abs(tanA2_world:Dot(hingeAxis)) then
		depthA_radial = math.abs(tanA2:Dot(partA.Size))
	else
		depthA_radial = math.abs(tanA1:Dot(partA.Size))
	end

	local depthB_radial: number
	if math.abs(tanB1_world:Dot(hingeAxis)) > math.abs(tanB2_world:Dot(hingeAxis)) then
		depthB_radial = math.abs(tanB2:Dot(partB.Size))
	else
		depthB_radial = math.abs(tanB1:Dot(partB.Size))
	end

	-- Compute Bezier control point distances via ray-ray closest approach.
	-- Ray A: centerA + s*nA, Ray B: centerB + t*nB
	local sep = centerA - centerB
	local b_coeff = nA:Dot(nB)
	local d_coeff = nA:Dot(sep)
	local e_coeff = nB:Dot(sep)
	local rayDenom = 1 - b_coeff * b_coeff

	local sParam: number
	local tParam: number
	if math.abs(rayDenom) < 0.001 then
		-- Parallel: use half the distance between centers
		local halfDist = (centerB - centerA).Magnitude / 2
		sParam = halfDist
		tParam = halfDist
	else
		sParam = (b_coeff * e_coeff - d_coeff) / rayDenom
		tParam = (e_coeff - b_coeff * d_coeff) / rayDenom
	end

	-- Scale control distances for circular arc approximation.
	-- Compute the hinge point (arc center) and radii from the closest approach,
	-- then use d = r * (4/3) * tan(arcAngle/4) for the Bezier circle formula.
	local closestOnA = centerA + nA * sParam
	local closestOnB = centerB + nB * tParam
	local hingePoint = (closestOnA + closestOnB) / 2

	local toA = centerA - hingePoint
	local radialA = toA - hingeAxis * toA:Dot(hingeAxis)
	local rA = radialA.Magnitude

	local toB = centerB - hingePoint
	local radialB = toB - hingeAxis * toB:Dot(hingeAxis)
	local rB = radialB.Magnitude

	if rA > 0.001 and rB > 0.001 then
		local arcAngle = math.acos(math.clamp(radialA.Unit:Dot(radialB.Unit), -1, 1))
		if arcAngle > 0.001 then
			local factor = (4 / 3) * math.tan(arcAngle / 4)
			sParam = math.sign(sParam) * rA * factor
			tParam = math.sign(tParam) * rB * factor
		end
	end

	-- Cubic Bezier control points: curve starts at face A center, ends at face B center,
	-- with control points extending along each face's outward normal.
	local P0 = centerA
	local P1 = centerA + nA * sParam
	local P2 = centerB + nB * tParam
	local P3 = centerB

	-- Bezier evaluation: B(f) = (1-f)^3*P0 + 3*(1-f)^2*f*P1 + 3*(1-f)*f^2*P2 + f^3*P3
	local function bezierPoint(f: number): Vector3
		local u = 1 - f
		return u * u * u * P0 + 3 * u * u * f * P1 + 3 * u * f * f * P2 + f * f * f * P3
	end

	-- Bezier derivative: B'(f) = 3*(1-f)^2*(P1-P0) + 6*(1-f)*f*(P2-P1) + 3*f^2*(P3-P2)
	local function bezierTangent(f: number): Vector3
		local u = 1 - f
		return 3 * u * u * (P1 - P0) + 6 * u * f * (P2 - P1) + 3 * f * f * (P3 - P2)
	end

	-- Generate geometry along the Bezier curve
	local model = Instance.new("Model")
	model.Name = "Sweep"

	if avoidZFighting then
		-- Wedge mode: sample at N+1 points, fill trapezoids with triangles
		type SweepSample = { inner: Vector3, outer: Vector3 }
		local samples: { SweepSample } = {}

		for i = 0, segmentCount do
			local frac = i / segmentCount
			local point = bezierPoint(frac)
			local tangent = bezierTangent(frac)
			if tangent.Magnitude < 0.001 then
				tangent = (P3 - P0)
			end
			tangent = tangent.Unit

			local radialDir = hingeAxis:Cross(tangent)
			if radialDir.Magnitude < 0.001 then
				if math.abs(tangent:Dot(Vector3.yAxis)) < 0.99 then
					radialDir = tangent:Cross(Vector3.yAxis).Unit
				else
					radialDir = tangent:Cross(Vector3.xAxis).Unit
				end
			else
				radialDir = radialDir.Unit
			end

			local depth = depthA_radial + (depthB_radial - depthA_radial) * frac
			local centered = point + hingeAxis * axialWidth / 2

			table.insert(samples, {
				inner = centered - radialDir * depth / 2,
				outer = centered + radialDir * depth / 2,
			})
		end

		for i = 1, segmentCount do
			local s0 = samples[i]
			local s1 = samples[i + 1]
			fillTriangle(s0.inner, s0.outer, s1.inner, axialWidth, hingeAxis, partA, model)
			fillTriangle(s0.outer, s1.outer, s1.inner, axialWidth, hingeAxis, partA, model)
		end
	else
		-- Box mode: place blocks along Bezier, then extend adjacent pairs to touch
		local blocks: { BasePart } = {}
		for i = 0, segmentCount - 1 do
			local frac0 = i / segmentCount
			local frac1 = (i + 1) / segmentCount
			local fracMid = (frac0 + frac1) / 2

			local p0 = bezierPoint(frac0)
			local p1 = bezierPoint(frac1)
			local midPoint = (p0 + p1) / 2

			local chord = p1 - p0
			if chord.Magnitude < 0.001 then
				continue
			end
			local chordDir = chord.Unit
			local chordLength = chord.Magnitude
			local depth = depthA_radial + (depthB_radial - depthA_radial) * fracMid

			local block = Instance.new("Part")
			block.Shape = Enum.PartType.Block
			applyProperties(block, partA)
			block.Size = Vector3.new(depth, axialWidth, chordLength)
			block.CFrame = CFrame.lookAt(midPoint, midPoint + chordDir, hingeAxis)
			block.Parent = model
			table.insert(blocks, block)
		end

		-- Extend adjacent blocks so their facing faces touch (OuterTouch)
		-- Front = -Z = chord direction (toward next), Back = +Z (toward previous)
		for i = 1, #blocks - 1 do
			extendBlocksToTouch(blocks[i], Enum.NormalId.Front, blocks[i + 1], Enum.NormalId.Back)
		end

		-- Extend first/last blocks to touch the original clicked parts
		if #blocks > 0 then
			extendBlocksToTouch(partA, normalIdA, blocks[1], Enum.NormalId.Back)
			extendBlocksToTouch(blocks[#blocks], Enum.NormalId.Front, partB, normalIdB)
		end
	end

	model.Parent = partA.Parent
end

--------------------------------------------------------------------------------
-- Face highlight (matching ResizeAlign's BoxHandleAdornment + edge cylinders)
--------------------------------------------------------------------------------

-- Given a face normal direction, return the two perpendicular tangent axes
local function otherNormals(dir: Vector3): (Vector3, Vector3)
	if math.abs(dir.X) > 0.5 then
		return Vector3.yAxis, Vector3.zAxis
	elseif math.abs(dir.Y) > 0.5 then
		return Vector3.xAxis, Vector3.zAxis
	else
		return Vector3.xAxis, Vector3.yAxis
	end
end

type FaceHighlightGroup = {
	box: BoxHandleAdornment,
	edges: { CylinderHandleAdornment },
}

local function createFaceHighlight(
	part: BasePart,
	normalId: Enum.NormalId,
	color: Color3,
	transparency: number,
	zIndexOffset: number
): FaceHighlightGroup
	local hsize = part.Size / 2
	local faceDir = Vector3.fromNormalId(normalId)
	local faceA, faceB = otherNormals(faceDir)

	-- Box covering the face
	local box = Instance.new("BoxHandleAdornment")
	box.Adornee = workspace.Terrain
	box.Size = faceA * hsize * 2 + faceB * hsize * 2 + faceDir * 0.1
	box.CFrame = part.CFrame * CFrame.new(faceDir * hsize)
	box.ZIndex = 1 + zIndexOffset
	box.AlwaysOnTop = true
	box.Transparency = transparency
	box.Color3 = color
	box.Parent = workspace.Terrain

	-- Edge CFrame bases
	local baseA = CFrame.fromMatrix(Vector3.new(), faceA:Cross(faceB).Unit, faceA)
	local baseB = CFrame.fromMatrix(Vector3.new(), faceB:Cross(faceA).Unit, faceB)
	local lenAlongB = (faceB * hsize * 2).Magnitude + 0.4
	local lenAlongA = (faceA * hsize * 2).Magnitude + 0.4

	local edges: { CylinderHandleAdornment } = {}
	local edgeDefs = {
		{ cf = baseA, sro = faceDir + faceA, height = lenAlongB },
		{ cf = baseA, sro = faceDir - faceA, height = lenAlongB },
		{ cf = baseB, sro = faceDir + faceB, height = lenAlongA },
		{ cf = baseB, sro = faceDir - faceB, height = lenAlongA },
	}
	for _, def in edgeDefs do
		local cyl = Instance.new("CylinderHandleAdornment")
		cyl.Color3 = color
		cyl.ZIndex = 2 + zIndexOffset
		cyl.Adornee = part
		cyl.Height = def.height
		cyl.AlwaysOnTop = false
		cyl.Radius = 0.05
		cyl.CFrame = def.cf
		cyl.SizeRelativeOffset = def.sro
		cyl.Parent = workspace.Terrain
		table.insert(edges, cyl)
	end

	return { box = box, edges = edges }
end

local function destroyFaceHighlight(group: FaceHighlightGroup?)
	if not group then
		return
	end
	group.box:Destroy()
	for _, edge in group.edges do
		edge:Destroy()
	end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local kColorRed = Color3.new(1, 0, 0)
local kColorBlue = Color3.new(0, 0, 1)

local mState: "idle" | "faceB" = "idle"
local mPartA: BasePart? = nil
local mNormalIdA: Enum.NormalId? = nil
local mSelectedHighlight: FaceHighlightGroup? = nil
local mHoverHighlight: FaceHighlightGroup? = nil
local mHoverPart: BasePart? = nil
local mHoverNormalId: Enum.NormalId? = nil

local function clearHover()
	destroyFaceHighlight(mHoverHighlight)
	mHoverHighlight = nil
	mHoverPart = nil
	mHoverNormalId = nil
end

local function clearState()
	mState = "idle"
	mPartA = nil
	mNormalIdA = nil
	destroyFaceHighlight(mSelectedHighlight)
	mSelectedHighlight = nil
	clearHover()
end

--------------------------------------------------------------------------------
-- Settings UI
--------------------------------------------------------------------------------

local function SweepSettings(props: ToolSettingsProps)
	local segmentCount = props.GetSetting("SegmentCount") :: number
	local avoidZFighting = props.GetSetting("AvoidZFighting") :: boolean

	local stateText = if mState == "idle"
		then "Click first face"
		else "Click second face"

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
		StatusLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = stateText,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		SegmentInput = e(NumberInput, {
			Label = "Segments",
			Value = segmentCount,
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.floor(newValue), 2, 64)
				props.SetSetting("SegmentCount", newValue)
				return newValue
			end,
			LayoutOrder = 2,
		}),
		AvoidZFightingCheckbox = e(Checkbox, {
			Label = "Avoid Z-Fighting",
			Checked = avoidZFighting,
			Changed = function(newValue: boolean)
				props.SetSetting("AvoidZFighting", newValue)
			end,
			LayoutOrder = 3,
		}),
	})
end

--------------------------------------------------------------------------------
-- Tool definition
--------------------------------------------------------------------------------

local Sweep: ToolTypes.ToolDefinition = {
	Id = "sweep",
	Name = "Sweep Arc",
	Description = "Create an arc of geometry between two faces. Disable \"Avoid Z-Fighting\" to use fewer basic Block parts to fill the space at the cost of some Z-fighting.",

	DefaultSettings = {
		SegmentCount = 6,
		AvoidZFighting = true,
	},

	OnActivated = function(ctx: ToolContext)
		clearState()
		ctx.UpdateUI()
	end,

	OnDeactivated = function(_ctx: ToolContext)
		clearState()
	end,

	OnViewChanged = function(ctx: ToolContext)
		local target = ctx.Target
		local targetPosition = ctx.TargetPosition

		if not isBlockPart(target) or not targetPosition then
			clearHover()
			return
		end

		local part = target :: BasePart
		if part.Locked then
			clearHover()
			return
		end

		local normalId = getTargetFace(part, targetPosition)

		-- Skip if hover hasn't changed
		if part == mHoverPart and normalId == mHoverNormalId then
			return
		end

		clearHover()
		mHoverPart = part
		mHoverNormalId = normalId

		local hoverColor = if mState == "idle" then kColorRed else kColorBlue
		mHoverHighlight = createFaceHighlight(part, normalId, hoverColor, 0.5, 2)
	end,

	OnClicked = function(ctx: ToolContext)
		if mState == "idle" then
			if not isBlockPart(ctx.Target) or not ctx.TargetPosition then
				return
			end
			local part = ctx.Target :: BasePart
			if part.Locked then
				return
			end
			local normalId = getTargetFace(part, ctx.TargetPosition)
			mState = "faceB"
			mPartA = part
			mNormalIdA = normalId
			destroyFaceHighlight(mSelectedHighlight)
			mSelectedHighlight = createFaceHighlight(part, normalId, kColorRed, 0, 0)
			-- Recreate hover in blue color now that we're in faceB state
			clearHover()
			ctx.UpdateUI()

		elseif mState == "faceB" then
			-- Cancel if clicking nothing, non-block, locked, or same part
			if not isBlockPart(ctx.Target) or not ctx.TargetPosition then
				clearState()
				ctx.UpdateUI()
				return
			end
			local part = ctx.Target :: BasePart
			if part.Locked or part == mPartA then
				clearState()
				ctx.UpdateUI()
				return
			end

			local partA = mPartA :: BasePart
			local normalIdA = mNormalIdA :: Enum.NormalId
			local normalIdB = getTargetFace(part, ctx.TargetPosition)
			local segmentCount = ctx.GetSetting("SegmentCount") :: number
			local avoidZFighting = ctx.GetSetting("AvoidZFighting") :: boolean

			local id = ctx.BeginRecording("Sweep")

			doSweep(partA, normalIdA, part, normalIdB, segmentCount, avoidZFighting)

			if id then
				ctx.FinishRecording(id)
			end

			clearState()
			ctx.UpdateUI()
		end
	end,

	RenderSettings = SweepSettings,
}

return Sweep

--!strict
local CoreGui = game:GetService("CoreGui")
local StudioService = game:GetService("StudioService")
local UserInputService = game:GetService("UserInputService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)
local Geometry = require(Packages.Geometry)

local Colors = require("../PluginGui/Colors")
local OperationButton = require("../PluginGui/OperationButton")
local Checkbox = require("../PluginGui/Checkbox")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Compatible type for edges returned by Geometry
type GeometryEdge = {
	id: number,
	a: Vector3,
	b: Vector3,
	direction: Vector3,
	length: number,
	edgeMargin: number,
	vertexMargin: number,
	part: BasePart,
	type: "Edge",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function perpendicularVector(v: Vector3): Vector3
	if math.abs(v:Dot(Vector3.yAxis)) < 0.9 then
		return v:Cross(Vector3.yAxis).Unit
	else
		return v:Cross(Vector3.xAxis).Unit
	end
end

-- Determine if a part has exact geometric edges via Geometry.getGeometry
local function hasGeometricEdges(part: BasePart): boolean
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") then
		return true
	end
	if part:IsA("Part") then
		local shape = (part :: Part).Shape
		return shape == Enum.PartType.Block
			or shape == Enum.PartType.Wedge
			or shape == Enum.PartType.CornerWedge
	end
	return false
end

-- Find the closest edge to the hit position
local function findClosestEdge(
	part: BasePart,
	hitPosition: Vector3,
	hitNormal: Vector3
): GeometryEdge?
	if hasGeometricEdges(part) then
		local geom = Geometry.getGeometry(part, hitPosition)
		local bestEdge: GeometryEdge? = nil
		local bestDist = math.huge
		for _, edge in geom.edges do
			local ap = hitPosition - edge.a
			local ab = edge.b - edge.a
			local t = ap:Dot(ab) / ab:Dot(ab)
			t = math.clamp(t, 0, 1)
			local closest = edge.a + ab * t
			local dist = (hitPosition - closest).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestEdge = edge
			end
		end
		return bestEdge
	else
		-- MeshPart, UnionOperation, etc. — use blackbox edge finding
		local camera = workspace.CurrentCamera
		local viewDir = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
		local fakeHit = {
			Instance = part,
			Position = hitPosition,
			Normal = hitNormal,
		}
		return Geometry.blackboxFindClosestMeshEdge(fakeHit :: any, viewDir)
	end
end

-- Snap a point along an edge to the studio grid
local function snapPointOnEdge(point: Vector3, edge: GeometryEdge): Vector3
	local gridSize = StudioService.GridSize
	local t = (point - edge.a):Dot(edge.direction)
	if gridSize > 0.01 then
		t = math.round(t / gridSize) * gridSize
	end
	t = math.clamp(t, 0, edge.length)
	return edge.a + edge.direction * t
end

-- Snap an angle to the studio rotate increment
local function snapAngle(angle: number): number
	local increment = StudioService.RotateIncrement
	if increment <= 0 then
		return angle
	end
	local incRad = math.rad(increment)
	return math.round(angle / incRad) * incRad
end

-- Intersect the mouse ray with a world-space plane
local function getMouseRayPlaneIntersection(planePoint: Vector3, planeNormal: Vector3): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local denom = ray.Direction:Dot(planeNormal)
	if math.abs(denom) < 0.0001 then
		return nil
	end
	local t = (planePoint - ray.Origin):Dot(planeNormal) / denom
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

-- Compute cut direction from mouse position on the face plane
local function computeCutDirection(
	mouseOnPlane: Vector3,
	cutPoint: Vector3,
	faceNormal: Vector3,
	edgeDir: Vector3
): Vector3
	-- Project edge direction onto face plane
	local edgeDirOnFace = edgeDir - edgeDir:Dot(faceNormal) * faceNormal
	if edgeDirOnFace.Magnitude < 0.001 then
		edgeDirOnFace = perpendicularVector(faceNormal)
	else
		edgeDirOnFace = edgeDirOnFace.Unit
	end

	local offset = mouseOnPlane - cutPoint
	if offset.Magnitude < 0.001 then
		return edgeDirOnFace
	end
	local mouseDir = offset.Unit

	-- Angle from edgeDirOnFace to mouseDir around faceNormal
	local angle = math.atan2(
		edgeDirOnFace:Cross(mouseDir):Dot(faceNormal),
		edgeDirOnFace:Dot(mouseDir)
	)
	angle = snapAngle(angle)

	return CFrame.fromAxisAngle(faceNormal, angle):VectorToWorldSpace(edgeDirOnFace)
end

--------------------------------------------------------------------------------
-- Model split helpers
--------------------------------------------------------------------------------

-- Find the target Model for model split mode
-- scope: "Parent" (first Model ancestor) or "TopLevel" (highest Model ancestor)
local function findTargetModel(part: BasePart, scope: string): Model?
	local current = part.Parent
	local lastModel: Model? = nil
	while current and not current:IsA("Workspace") do
		if current:IsA("Model") then
			if scope == "Parent" then
				return current :: Model
			end
			lastModel = current :: Model
		end
		current = current.Parent
	end
	return lastModel
end

-- Bounding box corner sign vectors
local CORNER_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1), Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
}

-- Classify a part relative to a cut plane as positive, negative, or straddling
local function classifyPart(part: BasePart, cutPoint: Vector3, cutNormal: Vector3): string
	local cf = part.ExtentsCFrame
	local halfSize = part.ExtentsSize / 2
	local hasPositive = false
	local hasNegative = false
	for _, signs in CORNER_SIGNS do
		local corner = cf:PointToWorldSpace(halfSize * signs)
		local dot = (corner - cutPoint):Dot(cutNormal)
		if dot > 0 then
			hasPositive = true
		else
			hasNegative = true
		end
		if hasPositive and hasNegative then
			return "straddling"
		end
	end
	if hasPositive then return "positive" end
	return "negative"
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local mState: "idle" | "pickAngle" = "idle"
local mCutPart: BasePart? = nil
local mCutPoint: Vector3? = nil
local mCutEdge: GeometryEdge? = nil
local mFaceNormal: Vector3? = nil
local mCutDir: Vector3? = nil
local mCutParts: {BasePart} = {} -- all parts to cut (for highlighting)
local mInitialModel: Model? = nil -- model from the clicked part (set once per pickAngle)
local mTargetModels: {Model} = {} -- all models to split (rebuilt each frame, includes initial)
local mLooseParts: {BasePart} = {} -- parts not in any model, cut individually in model mode
local mStatusMessage: string? = nil -- error message shown after a failed cut
local mStatusAlpha: number = 1 -- transparency animation (1 = visible, 0 = gone)
local mStatusThread: thread? = nil -- animation coroutine

-- Stored context refs for cancel from outside lifecycle callbacks
local mUpdateUI: (() -> ())? = nil
local mSetHighlight: ((BasePart?) -> ())? = nil

-- Input connection for right-click cancel
local mInputBeganCn: RBXScriptConnection? = nil

-- Adornments
local mSnapPoint: SphereHandleAdornment? = nil
local mCutLine: CylinderHandleAdornment? = nil
local mPartHighlights: {Highlight} = {}

local function clearPartHighlights()
	for _, h in mPartHighlights do
		h:Destroy()
	end
	mPartHighlights = {}
end

local function clearAdornments()
	if mSnapPoint then
		mSnapPoint:Destroy()
		mSnapPoint = nil
	end
	if mCutLine then
		mCutLine:Destroy()
		mCutLine = nil
	end
	clearPartHighlights()
end

local function clearStatusMessage()
	if mStatusThread then
		task.cancel(mStatusThread)
		mStatusThread = nil
	end
	mStatusMessage = nil
	mStatusAlpha = 1
end

local function showStatusMessage(message: string)
	clearStatusMessage()
	mStatusMessage = message
	mStatusAlpha = 1
	mStatusThread = task.spawn(function()
		-- Flash: 3 blinks
		for _ = 1, 3 do
			mStatusAlpha = 0
			if mUpdateUI then mUpdateUI() end
			task.wait(0.12)
			mStatusAlpha = 1
			if mUpdateUI then mUpdateUI() end
			task.wait(0.12)
		end
		-- Hold visible
		task.wait(2)
		-- Fade out over ~0.5s
		local steps = 10
		for i = 1, steps do
			mStatusAlpha = 1 - (i / steps)
			if mUpdateUI then mUpdateUI() end
			task.wait(0.05)
		end
		mStatusMessage = nil
		mStatusAlpha = 1
		mStatusThread = nil
		if mUpdateUI then mUpdateUI() end
	end)
end

local function clearState()
	mState = "idle"
	mCutPart = nil
	mCutPoint = nil
	mCutEdge = nil
	mFaceNormal = nil
	mCutDir = nil
	mCutParts = {}
	mInitialModel = nil
	mTargetModels = {}
	mLooseParts = {}
	clearStatusMessage()
	clearAdornments()
end

--------------------------------------------------------------------------------
-- Adornment updates
--------------------------------------------------------------------------------

local function updateSnapPoint(position: Vector3)
	if not mSnapPoint then
		local sphere = Instance.new("SphereHandleAdornment")
		sphere.Adornee = workspace.Terrain
		sphere.Color3 = Color3.fromRGB(255, 200, 0)
		sphere.AlwaysOnTop = true
		sphere.Radius = 0.15
		sphere.Parent = CoreGui
		mSnapPoint = sphere
	end
	mSnapPoint.CFrame = CFrame.new(position)
end

local function updateCutLine(startPoint: Vector3, direction: Vector3, length: number)
	if not mCutLine then
		local cyl = Instance.new("CylinderHandleAdornment")
		cyl.Adornee = workspace.Terrain
		cyl.Color3 = Color3.fromRGB(255, 50, 50)
		cyl.AlwaysOnTop = true
		cyl.Radius = 0.04
		cyl.Parent = CoreGui
		mCutLine = cyl
	end
	-- CylinderHandleAdornment extends symmetrically from CFrame center along LookVector
	local center = startPoint + direction * (length / 2)
	mCutLine.Height = length
	mCutLine.CFrame = CFrame.lookAt(center, center + direction)
end

local function updatePartHighlights(parts: {BasePart})
	-- Reuse existing highlights where possible, create new ones as needed
	for i, part in parts do
		local h = mPartHighlights[i]
		if not h then
			h = Instance.new("Highlight")
			h.FillTransparency = 0.75
			h.OutlineTransparency = 1
			h.FillColor = Color3.fromRGB(0, 120, 255)
			h.OutlineColor = Color3.fromRGB(0, 120, 255)
			h.Parent = CoreGui
			mPartHighlights[i] = h
		end
		h.Adornee = part
	end
	-- Destroy any extras from a previous frame
	for i = #parts + 1, #mPartHighlights do
		mPartHighlights[i]:Destroy()
		mPartHighlights[i] = nil
	end
end

local function cancelCut()
	if mState ~= "pickAngle" then
		return
	end
	clearState()
	if mSetHighlight then
		mSetHighlight(nil)
	end
	if mUpdateUI then
		mUpdateUI()
	end
end

-- Find all parts along a line segment using a region query
local function findPartsAlongLine(
	startPoint: Vector3,
	direction: Vector3,
	length: number,
	faceNormal: Vector3
): {BasePart}
	local mid = startPoint + direction * (length / 2)
	local boxCFrame = CFrame.fromMatrix(mid, direction, faceNormal)
	-- Thin box along cut direction, generous along face normal to catch part bodies
	local boxSize = Vector3.new(length, 100, 1)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}
	local found = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)
	local parts: {BasePart} = {}
	for _, inst in found do
		if inst:IsA("BasePart") and not inst.Locked then
			table.insert(parts, inst)
		end
	end
	return parts
end

--------------------------------------------------------------------------------
-- Cut execution
--------------------------------------------------------------------------------

-- Copy visual/physical properties from source to target
local function copyProperties(target: BasePart, source: BasePart)
	target.Color = source.Color
	target.Material = source.Material
	target.MaterialVariant = source.MaterialVariant
	target.Transparency = source.Transparency
	target.Reflectance = source.Reflectance
	target.Anchored = source.Anchored
	target.CanCollide = source.CanCollide
	target.CanTouch = source.CanTouch
	target.CanQuery = source.CanQuery
	target.CastShadow = source.CastShadow
	target.CollisionGroup = source.CollisionGroup
end

-- Check if cut plane normal is axis-aligned with the part's local axes
local function getAxisAligned(part: BasePart, cutNormal: Vector3): string?
	local localNormal = part.CFrame:VectorToObjectSpace(cutNormal)
	local threshold = 0.01
	if math.abs(math.abs(localNormal.X) - 1) < threshold then return "X" end
	if math.abs(math.abs(localNormal.Y) - 1) < threshold then return "Y" end
	if math.abs(math.abs(localNormal.Z) - 1) < threshold then return "Z" end
	return nil
end

-- Simple axis-aligned cut: clone + resize.
-- Returns (negHalf, posHalf) relative to cutNormal direction.
local function doSimpleCut(
	part: BasePart, cutPoint: Vector3, cutNormal: Vector3, axis: string
): (BasePart, BasePart)
	local localCutPt = part.CFrame:PointToObjectSpace(cutPoint)
	local size = part.Size

	-- Determine split position and full extent along the axis
	local splitPos: number
	local fullSize: number
	local axisIndex: number
	if axis == "X" then
		splitPos = localCutPt.X
		fullSize = size.X
		axisIndex = 1
	elseif axis == "Y" then
		splitPos = localCutPt.Y
		fullSize = size.Y
		axisIndex = 2
	else
		splitPos = localCutPt.Z
		fullSize = size.Z
		axisIndex = 3
	end

	local halfSize = fullSize / 2
	splitPos = math.clamp(splitPos, -halfSize + 0.001, halfSize - 0.001)

	-- Local-axis-negative half: from -halfSize to splitPos
	local negSize = splitPos + halfSize
	local negCenter = (-halfSize + splitPos) / 2

	-- Local-axis-positive half: from splitPos to +halfSize
	local posSize = halfSize - splitPos
	local posCenter = (splitPos + halfSize) / 2

	local function makeHalf(centerAlongAxis: number, sizeAlongAxis: number): BasePart
		local newPart = part:Clone()
		local offset = Vector3.new(
			if axisIndex == 1 then centerAlongAxis else 0,
			if axisIndex == 2 then centerAlongAxis else 0,
			if axisIndex == 3 then centerAlongAxis else 0
		)
		local newSize = Vector3.new(
			if axisIndex == 1 then sizeAlongAxis else size.X,
			if axisIndex == 2 then sizeAlongAxis else size.Y,
			if axisIndex == 3 then sizeAlongAxis else size.Z
		)
		newPart.Size = newSize
		newPart.CFrame = part.CFrame * CFrame.new(offset)
		return newPart
	end

	local parent = part.Parent
	local localNegHalf = makeHalf(negCenter, negSize)
	local localPosHalf = makeHalf(posCenter, posSize)
	localNegHalf.Parent = parent
	localPosHalf.Parent = parent
	part.Parent = nil

	-- Map local-axis halves to cut-plane halves based on cutNormal direction
	local localNormal = part.CFrame:VectorToObjectSpace(cutNormal)
	local axisSign: number
	if axis == "X" then axisSign = localNormal.X
	elseif axis == "Y" then axisSign = localNormal.Y
	else axisSign = localNormal.Z end

	if axisSign > 0 then
		return localNegHalf, localPosHalf
	else
		return localPosHalf, localNegHalf
	end
end

-- CSG cut for general (non-axis-aligned) case.
-- Returns (success, negHalf, posHalf) relative to cutNormal direction.
local function doCSGCut(
	part: BasePart, cutPoint: Vector3, cutNormal: Vector3
): (boolean, BasePart?, BasePart?)
	local perp = perpendicularVector(cutNormal)

	-- Positive side block (covers the half-space on the +cutNormal side)
	local posBlock = Instance.new("Part")
	posBlock.Size = Vector3.new(1000, 1000, 1000)
	posBlock.CFrame = CFrame.fromMatrix(cutPoint + cutNormal * 500, perp, cutNormal)
	posBlock.Anchored = true
	posBlock.CanCollide = false
	posBlock.Transparency = 1
	posBlock.Parent = workspace

	-- Negative side block
	local negBlock = Instance.new("Part")
	negBlock.Size = Vector3.new(1000, 1000, 1000)
	negBlock.CFrame = CFrame.fromMatrix(cutPoint - cutNormal * 500, perp, cutNormal)
	negBlock.Anchored = true
	negBlock.CanCollide = false
	negBlock.Transparency = 1
	negBlock.Parent = workspace

	local parent = part.Parent
	local ok, negHalf, posHalf = pcall(function()
		-- Subtract positive block → negative half remains
		local neg = part:SubtractAsync({posBlock})
		-- Subtract negative block → positive half remains
		local pos = part:SubtractAsync({negBlock})
		return neg, pos
	end)

	posBlock:Destroy()
	negBlock:Destroy()

	if ok and negHalf and posHalf then
		copyProperties(negHalf, part)
		copyProperties(posHalf, part)
		negHalf.UsePartColor = true
		posHalf.UsePartColor = true
		negHalf.Parent = parent
		posHalf.Parent = parent
		part.Parent = nil
		return true, negHalf, posHalf
	else
		warn("PartCutter: CSG cut failed for", part:GetFullName())
		return false, nil, nil
	end
end

-- Try to decompose a Block cut into native primitives (Blocks + WedgeParts) when the
-- cut plane is perpendicular to one of the block's local axes. The cross-section is split
-- into a "band" (bounding box of the two cut-line/rectangle intersections) containing two
-- complementary wedges, plus up to 2 rectangular slabs outside the band.
-- Returns ({negParts}, {posParts}) relative to cutNormal, or (nil, nil) if not applicable.
local function tryPrimitiveCut(
	part: BasePart, cutPoint: Vector3, cutNormal: Vector3
): ({BasePart}?, {BasePart}?)
	local cf = part.CFrame
	local size = part.Size
	local localCutNormal = cf:VectorToObjectSpace(cutNormal)
	local localCutPoint = cf:PointToObjectSpace(cutPoint)

	-- Find the extrude axis: the local axis with near-zero cutNormal component
	local absComps = {math.abs(localCutNormal.X), math.abs(localCutNormal.Y), math.abs(localCutNormal.Z)}
	local extrudeAxis: number? = nil
	for i, v in absComps do
		if v < 0.01 then
			if extrudeAxis then
				return nil, nil -- multiple near-zero: axis-aligned, handled elsewhere
			end
			extrudeAxis = i
		end
	end
	if not extrudeAxis then
		return nil, nil
	end

	-- Cross-section axes (the two non-extrude axes)
	local ca1, ca2: number
	if extrudeAxis == 1 then
		ca1, ca2 = 2, 3
	elseif extrudeAxis == 2 then
		ca1, ca2 = 1, 3
	else
		ca1, ca2 = 1, 2
	end

	local function comp(v: Vector3, i: number): number
		if i == 1 then return v.X elseif i == 2 then return v.Y else return v.Z end
	end

	local h1, h2 = comp(size, ca1) / 2, comp(size, ca2) / 2
	local n1, n2 = comp(localCutNormal, ca1), comp(localCutNormal, ca2)
	local p1, p2 = comp(localCutPoint, ca1), comp(localCutPoint, ca2)
	local dVal = n1 * p1 + n2 * p2
	local extrudeSize = comp(size, extrudeAxis)

	-- Find the two intersections of the cut line with the rectangle boundary
	-- Cut line: n1*i1 + n2*i2 = dVal
	local isects: {{number}} = {}
	local eps = 0.001

	local function addIsect(i1: number, i2: number)
		for _, is in isects do
			if math.abs(is[1] - i1) < eps and math.abs(is[2] - i2) < eps then
				return
			end
		end
		table.insert(isects, {i1, i2})
	end

	if math.abs(n1) > eps then
		local ti1 = (dVal - n2 * h2) / n1 -- top edge (i2 = +h2)
		if ti1 >= -h1 - eps and ti1 <= h1 + eps then
			addIsect(math.clamp(ti1, -h1, h1), h2)
		end
		local bi1 = (dVal + n2 * h2) / n1 -- bottom edge (i2 = -h2)
		if bi1 >= -h1 - eps and bi1 <= h1 + eps then
			addIsect(math.clamp(bi1, -h1, h1), -h2)
		end
	end
	if math.abs(n2) > eps then
		local ri2 = (dVal - n1 * h1) / n2 -- right edge (i1 = +h1)
		if ri2 >= -h2 - eps and ri2 <= h2 + eps then
			addIsect(h1, math.clamp(ri2, -h2, h2))
		end
		local li2 = (dVal + n1 * h1) / n2 -- left edge (i1 = -h1)
		if li2 >= -h2 - eps and li2 <= h2 + eps then
			addIsect(-h1, math.clamp(li2, -h2, h2))
		end
	end

	if #isects ~= 2 then
		return nil, nil
	end

	-- Band = bounding box of the two intersection points
	local b1lo = math.min(isects[1][1], isects[2][1])
	local b1hi = math.max(isects[1][1], isects[2][1])
	local b2lo = math.min(isects[1][2], isects[2][2])
	local b2hi = math.max(isects[1][2], isects[2][2])
	local bw1, bw2 = b1hi - b1lo, b2hi - b2lo

	if bw1 < 0.001 or bw2 < 0.001 then
		return nil, nil -- degenerate band
	end

	-- Signed distance from 2D point to cut line (positive = cutNormal side)
	local function sdist(c1: number, c2: number): number
		return n1 * (c1 - p1) + n2 * (c2 - p2)
	end

	-- World-space axis vectors
	local kAxes = {Vector3.xAxis, Vector3.yAxis, Vector3.zAxis}
	local extDir = cf:VectorToWorldSpace(kAxes[extrudeAxis])
	local cd1 = cf:VectorToWorldSpace(kAxes[ca1])
	local cd2 = cf:VectorToWorldSpace(kAxes[ca2])

	-- Build a Vector3 with components assigned by axis index
	local function makeVec(extVal: number, c1Val: number, c2Val: number): Vector3
		local v = {0, 0, 0}
		v[extrudeAxis] = extVal
		v[ca1] = c1Val
		v[ca2] = c2Val
		return Vector3.new(v[1], v[2], v[3])
	end

	local parent = part.Parent
	local negParts: {BasePart} = {}
	local posParts: {BasePart} = {}

	-- Create a Block piece at the given cross-section center/size
	local function addBlock(center1: number, center2: number, w1: number, w2: number)
		local block = Instance.new("Part")
		block.Shape = Enum.PartType.Block
		block.Size = makeVec(extrudeSize, w1, w2)
		block.CFrame = cf * CFrame.new(makeVec(0, center1, center2))
		copyProperties(block, part)
		block.Name = part.Name
		block.Parent = parent
		if sdist(center1, center2) > 0 then
			table.insert(posParts, block)
		else
			table.insert(negParts, block)
		end
	end

	-- Create a WedgePart piece in the band
	local function addWedge(
		rightAngle1: number, rightAngle2: number,
		leg1Sign: number, leg2Sign: number,
		bCenter1: number, bCenter2: number,
		legLen1: number, legLen2: number
	)
		-- WedgePart right angle at local (-W/2, -H/2, +D/2), legs along +Y and -Z
		-- Map: Y = leg along ca1, local +Z = opposite of leg along ca2
		local yDir = cd1 * leg1Sign
		local zExpected = -cd2 * leg2Sign
		local xDir = extDir
		if xDir:Cross(yDir):Dot(zExpected) < 0 then
			xDir = -xDir
		end

		local wedge = Instance.new("Part")
		wedge.Shape = Enum.PartType.Wedge
		wedge.Size = Vector3.new(extrudeSize, legLen1, legLen2)
		wedge.CFrame = CFrame.fromMatrix(
			cf.Position + cd1 * bCenter1 + cd2 * bCenter2, xDir, yDir
		)
		copyProperties(wedge, part)
		wedge.Name = part.Name
		wedge.Parent = parent
		if sdist(rightAngle1, rightAngle2) > 0 then
			table.insert(posParts, wedge)
		else
			table.insert(negParts, wedge)
		end
	end

	-- Slab blocks outside the band (non-overlapping tiling of the remainder)
	local minSlab = 0.001
	if b1lo - (-h1) > minSlab then -- left slab (full ca2 height)
		addBlock((-h1 + b1lo) / 2, 0, b1lo + h1, h2 * 2)
	end
	if h1 - b1hi > minSlab then -- right slab (full ca2 height)
		addBlock((b1hi + h1) / 2, 0, h1 - b1hi, h2 * 2)
	end
	if b2lo - (-h2) > minSlab then -- bottom slab (between ca1 slabs)
		addBlock((b1lo + b1hi) / 2, (-h2 + b2lo) / 2, bw1, b2lo + h2)
	end
	if h2 - b2hi > minSlab then -- top slab (between ca1 slabs)
		addBlock((b1lo + b1hi) / 2, (b2hi + h2) / 2, bw1, h2 - b2hi)
	end

	-- Two complementary wedges in the band
	-- Determine which diagonal the cut line follows by checking which band corner I1 is at
	local i1AtLo = math.abs(isects[1][1] - b1lo) < math.abs(isects[1][1] - b1hi)
	local i2AtLo = math.abs(isects[1][2] - b2lo) < math.abs(isects[1][2] - b2hi)
	local bandC1, bandC2 = (b1lo + b1hi) / 2, (b2lo + b2hi) / 2

	if i1AtLo == i2AtLo then
		-- Diagonal from (b1lo,b2lo) to (b1hi,b2hi)
		-- Wedge right angles at the other two corners
		addWedge(b1lo, b2hi, 1, -1, bandC1, bandC2, bw1, bw2)
		addWedge(b1hi, b2lo, -1, 1, bandC1, bandC2, bw1, bw2)
	else
		-- Diagonal from (b1lo,b2hi) to (b1hi,b2lo)
		addWedge(b1lo, b2lo, 1, 1, bandC1, bandC2, bw1, bw2)
		addWedge(b1hi, b2hi, -1, -1, bandC1, bandC2, bw1, bw2)
	end

	part.Parent = nil

	if #negParts == 0 or #posParts == 0 then
		-- Degenerate cut: undo and fall back to CSG
		for _, p in negParts do p.Parent = nil end
		for _, p in posParts do p.Parent = nil end
		part.Parent = parent
		return nil, nil
	end

	return negParts, posParts
end

-- Cut a WedgePart along the Y or Z axis, decomposing into 2 wedges + 1 block.
-- The wedge cross-section (YZ plane) is a right triangle:
--   Right angle at (-H/2, +D/2), vertices: (-H/2, -D/2), (-H/2, +D/2), (+H/2, +D/2)
--   Hypotenuse from (-H/2, -D/2) to (+H/2, +D/2)
-- All resulting wedges maintain the same orientation as the original.
-- Returns ({negParts}, {posParts}) relative to cutNormal.
local function doWedgeAxisCut(
	part: BasePart, cutPoint: Vector3, cutNormal: Vector3, axis: string
): ({BasePart}, {BasePart})
	local cf = part.CFrame
	local size = part.Size
	local W, H, D = size.X, size.Y, size.Z
	local localCutPt = cf:PointToObjectSpace(cutPoint)
	local localNormal = cf:VectorToObjectSpace(cutNormal)
	local parent = part.Parent

	local function makeWedge(sizeVec: Vector3, offset: Vector3): BasePart
		local wedge = Instance.new("Part")
		wedge.Shape = Enum.PartType.Wedge
		wedge.Size = sizeVec
		wedge.CFrame = cf * CFrame.new(offset)
		copyProperties(wedge, part)
		wedge.Name = part.Name
		wedge.Parent = parent
		return wedge
	end

	local function makeBlock(sizeVec: Vector3, offset: Vector3): BasePart
		local block = Instance.new("Part")
		block.Shape = Enum.PartType.Block
		block.Size = sizeVec
		block.CFrame = cf * CFrame.new(offset)
		copyProperties(block, part)
		block.Name = part.Name
		block.Parent = parent
		return block
	end

	local localPosParts: {BasePart}
	local localNegParts: {BasePart}

	if axis == "Y" then
		local y0 = math.clamp(localCutPt.Y, -H/2 + 0.001, H/2 - 0.001)
		-- Hypotenuse intersection: zHyp = -D/2 + (y0 + H/2) * D / H
		local zHyp = -D/2 + (y0 + H/2) * D / H

		-- Upper wedge: right angle at (y0, +D/2), same orientation
		local upperWedge = makeWedge(
			Vector3.new(W, H/2 - y0, D * (H/2 - y0) / H),
			Vector3.new(0, (y0 + H/2) / 2, (zHyp + D/2) / 2)
		)

		-- Lower block: from (-H/2, zHyp) to (y0, +D/2)
		local lowerBlock = makeBlock(
			Vector3.new(W, y0 + H/2, D/2 - zHyp),
			Vector3.new(0, (-H/2 + y0) / 2, (zHyp + D/2) / 2)
		)

		-- Lower wedge: right angle at (-H/2, zHyp), same orientation
		local lowerWedge = makeWedge(
			Vector3.new(W, y0 + H/2, (y0 + H/2) * D / H),
			Vector3.new(0, (-H/2 + y0) / 2, (-D/2 + zHyp) / 2)
		)

		localPosParts = {upperWedge}
		localNegParts = {lowerBlock, lowerWedge}
	else -- axis == "Z"
		local z0 = math.clamp(localCutPt.Z, -D/2 + 0.001, D/2 - 0.001)
		-- Hypotenuse intersection: yHyp = -H/2 + (z0 + D/2) * H / D
		local yHyp = -H/2 + (z0 + D/2) * H / D

		-- Front wedge (z < z0): right angle at (-H/2, z0), same orientation
		local frontWedge = makeWedge(
			Vector3.new(W, (z0 + D/2) * H / D, z0 + D/2),
			Vector3.new(0, (-H/2 + yHyp) / 2, (-D/2 + z0) / 2)
		)

		-- Back block: from (-H/2, z0) to (yHyp, +D/2)
		local backBlock = makeBlock(
			Vector3.new(W, (z0 + D/2) * H / D, D/2 - z0),
			Vector3.new(0, (-H/2 + yHyp) / 2, (z0 + D/2) / 2)
		)

		-- Back wedge: right angle at (yHyp, +D/2), same orientation
		local backWedge = makeWedge(
			Vector3.new(W, H * (D/2 - z0) / D, D/2 - z0),
			Vector3.new(0, (yHyp + H/2) / 2, (z0 + D/2) / 2)
		)

		localNegParts = {frontWedge}
		localPosParts = {backBlock, backWedge}
	end

	part.Parent = nil

	-- Map local-axis halves to cut-plane halves based on cutNormal direction
	local axisSign: number
	if axis == "Y" then axisSign = localNormal.Y
	else axisSign = localNormal.Z end

	if axisSign > 0 then
		return localNegParts, localPosParts
	else
		return localPosParts, localNegParts
	end
end

-- Determine whether to use simple cut or CSG, and execute.
-- Returns (errorMsg?, negParts?, posParts?) — part arrays relative to cutNormal direction.
-- On failure, errorMsg is set and part arrays are nil; the original part is unchanged.
local function executeCut(
	part: BasePart, cutPoint: Vector3, cutDir: Vector3, faceNormal: Vector3,
	avoidCSG: boolean
): (string?, {BasePart}?, {BasePart}?)
	local cutNormal = cutDir:Cross(faceNormal).Unit

	local axis = getAxisAligned(part, cutNormal)
	if axis then
		-- Simple cut works for blocks along any axis
		local isBlock = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block
		if isBlock then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, {neg}, {pos}
		end
		-- Cylinder: simple cut along X (length axis) only
		local isCylinder = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Cylinder
		if isCylinder and axis == "X" then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, {neg}, {pos}
		end
		-- Wedge: simple cut along X (width axis) only
		local isWedge = (part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Wedge)
			or part:IsA("WedgePart")
		if isWedge and axis == "X" then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, {neg}, {pos}
		end
		if avoidCSG and isWedge and (axis == "Y" or axis == "Z") then
			local negParts, posParts = doWedgeAxisCut(part, cutPoint, cutNormal, axis)
			return nil, negParts, posParts
		end
	end

	-- Try primitive decomposition for blocks with angled cuts perpendicular to one axis
	if avoidCSG and part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block then
		local negParts, posParts = tryPrimitiveCut(part, cutPoint, cutNormal)
		if negParts then
			return nil, negParts, posParts
		end
	end

	-- General case: CSG
	local ok, neg, pos = doCSGCut(part, cutPoint, cutNormal)
	if ok then
		return nil, {neg :: BasePart}, {pos :: BasePart}
	end

	if part:IsA("MeshPart") then
		return "Can't cut '" .. part.Name .. "' (CSG not supported for this MeshPart)", nil, nil
	end
	return "Cut failed for '" .. part.Name .. "'", nil, nil
end

-- Cut a straddling part and keep only the half on the specified side.
-- keepSide: "positive" or "negative"
local function cutAndKeepSide(
	part: BasePart,
	cutPoint: Vector3,
	cutDir: Vector3,
	faceNormal: Vector3,
	cutNormal: Vector3,
	keepSide: string,
	avoidCSG: boolean
): string?
	local err, negParts, posParts = executeCut(part, cutPoint, cutDir, faceNormal, avoidCSG)

	if err then
		-- Cut failed; part is still intact. Classify by center and remove if wrong side.
		local centerDot = (part.ExtentsCFrame.Position - cutPoint):Dot(cutNormal)
		if keepSide == "positive" and centerDot < 0 then
			part.Parent = nil
		elseif keepSide == "negative" and centerDot > 0 then
			part.Parent = nil
		end
		return err
	end

	-- Remove all parts on the wrong side
	if keepSide == "negative" and posParts then
		for _, p in posParts do
			p.Parent = nil
		end
	elseif keepSide == "positive" and negParts then
		for _, p in negParts do
			p.Parent = nil
		end
	end
	return nil
end

-- Execute a model split: cut straddling parts and separate into two sibling models
local function executeModelCut(
	model: Model,
	cutPoint: Vector3,
	cutDir: Vector3,
	faceNormal: Vector3,
	avoidCSG: boolean
): {string}
	local cutNormal = cutDir:Cross(faceNormal).Unit
	local errors: {string} = {}

	-- Collect all parts in the model
	local allParts: {BasePart} = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(allParts, desc)
		end
	end

	-- Classify each part
	local positiveParts: {BasePart} = {}
	local negativeParts: {BasePart} = {}
	local straddlingParts: {BasePart} = {}
	for _, part in allParts do
		local side = classifyPart(part, cutPoint, cutNormal)
		if side == "positive" then
			table.insert(positiveParts, part)
		elseif side == "negative" then
			table.insert(negativeParts, part)
		else
			table.insert(straddlingParts, part)
		end
	end

	-- If everything is on one side, no split needed
	if #positiveParts == 0 and #straddlingParts == 0 then
		return errors
	end
	if #negativeParts == 0 and #straddlingParts == 0 then
		return errors
	end

	-- Clone the model for the positive side (before any mutations)
	local newModel = model:Clone()

	-- Build mapping from original parts to cloned parts
	-- GetDescendants returns in the same order for both
	local cloneDescendants: {BasePart} = {}
	for _, desc in newModel:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(cloneDescendants, desc)
		end
	end

	local origToClone: {[BasePart]: BasePart} = {}
	for i, part in allParts do
		origToClone[part] = cloneDescendants[i]
	end

	-- Original model keeps the NEGATIVE side
	for _, part in positiveParts do
		part.Parent = nil
	end
	for _, part in straddlingParts do
		local err = cutAndKeepSide(part, cutPoint, cutDir, faceNormal, cutNormal, "negative", avoidCSG)
		if err then
			table.insert(errors, err)
		end
	end

	-- Cloned model keeps the POSITIVE side
	for _, part in negativeParts do
		local clonedPart = origToClone[part]
		if clonedPart then
			clonedPart.Parent = nil
		end
	end
	for _, part in straddlingParts do
		local clonedPart = origToClone[part]
		if clonedPart then
			local err = cutAndKeepSide(clonedPart, cutPoint, cutDir, faceNormal, cutNormal, "positive", avoidCSG)
			if err then
				table.insert(errors, err)
			end
		end
	end

	-- Parent clone as sibling of original
	newModel.Parent = model.Parent

	return errors
end

--------------------------------------------------------------------------------
-- Settings UI
--------------------------------------------------------------------------------

local function PartCutterSettings(props: ToolSettingsProps)
	local isModelMode = props.GetSetting("SplitMode") == "Model"
	local isTopLevel = props.GetSetting("ModelScope") == "TopLevel"
	local isAvoidCSG = props.GetSetting("AvoidCSG") ~= false

	local stateText = if mState == "idle"
		then "Click an edge to set cut point"
		else "Move mouse to set angle, click to cut"

	local children: {[string]: any} = {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		ModelModeCheckbox = e(Checkbox, {
			Label = "Model Mode",
			Checked = isModelMode,
			LayoutOrder = 1,
			Changed = function(checked: boolean)
				props.SetSetting("SplitMode", if checked then "Model" else "Part")
			end,
		}),
		AvoidCSGCheckbox = e(Checkbox, {
			Label = "Prefer Simple Part Types",
			Checked = isAvoidCSG,
			LayoutOrder = 3,
			Changed = function(checked: boolean)
				props.SetSetting("AvoidCSG", checked)
			end,
		}),
		StatusLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = stateText,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 10,
		}),
	}

	if isModelMode then
		children.TopLevelCheckbox = e(Checkbox, {
			Label = "Top-Level Model",
			Checked = isTopLevel,
			LayoutOrder = 2,
			Changed = function(checked: boolean)
				props.SetSetting("ModelScope", if checked then "TopLevel" else "Parent")
			end,
		})
	end

	if mState == "pickAngle" then
		children.CancelButton = e(OperationButton, {
			Text = "Cancel",
			Height = 28,
			Disabled = false,
			Color = Colors.DARK_RED,
			LayoutOrder = 11,
			OnClick = cancelCut,
		})
	end

	if mStatusMessage then
		children.ErrorLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = mStatusMessage,
			TextColor3 = Colors.WARNING_YELLOW,
			TextTransparency = 1 - mStatusAlpha,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = 12,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

--------------------------------------------------------------------------------
-- Tool definition
--------------------------------------------------------------------------------

local PartCutter: ToolTypes.ToolDefinition = {
	Id = "partCutter",
	Name = "Part Cutter",
	Description = "Cut a part into two halves along a plane",

	OnActivated = function(ctx: ToolContext)
		clearState()
		mUpdateUI = ctx.UpdateUI
		mSetHighlight = ctx.SetHighlight
		mInputBeganCn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2
				or input.KeyCode == Enum.KeyCode.Escape
			then
				cancelCut()
			end
		end)
		ctx.UpdateUI()
	end,

	OnDeactivated = function(ctx: ToolContext)
		clearState()
		ctx.SetHighlight(nil)
		if mInputBeganCn then
			mInputBeganCn:Disconnect()
			mInputBeganCn = nil
		end
		mUpdateUI = nil
		mSetHighlight = nil
	end,

	OnMouseLeaveViewport = function(ctx: ToolContext)
		if mState == "idle" then
			clearAdornments()
			ctx.SetHighlight(nil)
		end
	end,

	OnViewChanged = function(ctx: ToolContext)
		if mState == "idle" then
			-- Show edge highlight + snap point on hover
			if ctx.Target and ctx.TargetPosition and ctx.TargetNormal then
				local edge = findClosestEdge(ctx.Target, ctx.TargetPosition, ctx.TargetNormal)
				if edge then
					local snapped = snapPointOnEdge(ctx.TargetPosition, edge)
					updateSnapPoint(snapped)
					ctx.SetHighlight(ctx.Target, true)
				else
					clearAdornments()
					ctx.SetHighlight(nil)
				end
			else
				clearAdornments()
				ctx.SetHighlight(nil)
			end

		elseif mState == "pickAngle" then
			-- Update cut direction and length based on mouse ray → face plane
			if mCutPoint and mFaceNormal and mCutEdge then
				local mouseOnPlane = getMouseRayPlaneIntersection(mCutPoint, mFaceNormal)
				if mouseOnPlane then
					local cutDir = computeCutDirection(
						mouseOnPlane, mCutPoint, mFaceNormal, mCutEdge.direction
					)
					mCutDir = cutDir

					-- Distance from cut point to mouse along the cut direction
					local projDist = (mouseOnPlane - mCutPoint):Dot(cutDir)
					local lineLength = math.max(projDist, 0.5)

					if mInitialModel then
						-- Model mode: hover+region query to find additional models
						local scope = ctx.GetSetting("ModelScope")
						local modelSet: {[Model]: boolean} = {[mInitialModel] = true}
						local looseParts: {BasePart} = {}

						if ctx.Target
							and ctx.Target ~= mCutPart
							and ctx.TargetNormal
							and ctx.TargetPosition
							and mFaceNormal:Dot(ctx.TargetNormal) > 0.99
						then
							local hoveredDist = (ctx.TargetPosition - mCutPoint):Dot(cutDir)
							if hoveredDist > 0.5 then
								lineLength = math.max(lineLength, hoveredDist)
							end

							local found = findPartsAlongLine(
								mCutPoint, cutDir, lineLength, mFaceNormal
							)
							for _, part in found do
								local model = findTargetModel(part, scope)
								if model then
									modelSet[model] = true
								else
									local already = false
									for _, existing in looseParts do
										if existing == part then
											already = true
											break
										end
									end
									if not already then
										table.insert(looseParts, part)
									end
								end
							end
						end

						-- Rebuild model list and candidate parts
						mTargetModels = {}
						for model in modelSet do
							table.insert(mTargetModels, model)
						end
						mLooseParts = looseParts

						local allParts: {BasePart} = {}
						for _, model in mTargetModels do
							for _, desc in model:GetDescendants() do
								if desc:IsA("BasePart") then
									table.insert(allParts, desc)
								end
							end
						end
						for _, part in looseParts do
							table.insert(allParts, part)
						end
						mCutParts = allParts

						-- Extend line to cover all affected parts
						for _, part in mCutParts do
							local ext = (part.CFrame.Position - mCutPoint):Dot(cutDir)
								+ part.Size.Magnitude / 2
							lineLength = math.max(lineLength, ext)
						end
					else
						-- Part mode: check if hovering a matching surface on another part
						local partsTocut: {BasePart} = {mCutPart :: BasePart}
						if ctx.Target
							and ctx.Target ~= mCutPart
							and ctx.TargetNormal
							and ctx.TargetPosition
							and mFaceNormal:Dot(ctx.TargetNormal) > 0.99
						then
							-- Extend line to the hovered point
							local hoveredDist = (ctx.TargetPosition - mCutPoint):Dot(cutDir)
							if hoveredDist > 0.5 then
								lineLength = math.max(lineLength, hoveredDist)
							end

							-- Find all parts along the cut line via region query
							local found = findPartsAlongLine(
								mCutPoint, cutDir, lineLength, mFaceNormal
							)
							for _, part in found do
								-- Deduplicate
								local already = false
								for _, existing in partsTocut do
									if existing == part then
										already = true
										break
									end
								end
								if not already then
									table.insert(partsTocut, part)
								end
							end
						end

						mCutParts = partsTocut
					end

					-- Highlight all affected parts (managed by us, not shared highlight)
					ctx.SetHighlight(nil)
					updatePartHighlights(mCutParts)

					updateCutLine(mCutPoint, cutDir, lineLength)
				end
			end
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if mState == "idle" then
			-- Lock cut point on an edge
			if not ctx.Target or not ctx.TargetPosition or not ctx.TargetNormal then
				return
			end
			local edge = findClosestEdge(ctx.Target, ctx.TargetPosition, ctx.TargetNormal)
			if not edge then
				return
			end

			local snapped = snapPointOnEdge(ctx.TargetPosition, edge)

			mState = "pickAngle"
			mCutPart = ctx.Target
			mCutPoint = snapped
			mCutEdge = edge
			mFaceNormal = ctx.TargetNormal
			clearStatusMessage()

			-- Determine candidate parts based on split mode
			local splitMode = ctx.GetSetting("SplitMode")
			if splitMode == "Model" then
				local scope = ctx.GetSetting("ModelScope")
				local targetModel = findTargetModel(ctx.Target, scope)
				if targetModel then
					mInitialModel = targetModel
					mTargetModels = {targetModel}
					mLooseParts = {}
					local modelParts: {BasePart} = {}
					for _, desc in targetModel:GetDescendants() do
						if desc:IsA("BasePart") then
							table.insert(modelParts, desc)
						end
					end
					mCutParts = modelParts
				else
					-- No model found, fall back to single part
					mCutParts = {ctx.Target}
				end
			else
				mCutParts = {ctx.Target}
			end

			-- Keep edge highlight and snap point visible as locked indicators
			-- Use our own highlights instead of the shared one
			ctx.SetHighlight(nil)
			updatePartHighlights(mCutParts)
			ctx.UpdateUI()

		elseif mState == "pickAngle" then
			-- Execute the cut
			if not mCutPart or not mCutPoint or not mFaceNormal or not mCutEdge then
				clearState()
				ctx.SetHighlight(nil)
				ctx.UpdateUI()
				return
			end

			-- Compute final cut direction from current mouse position
			local cutDir = mCutDir
			if not cutDir then
				local mouseOnPlane = getMouseRayPlaneIntersection(mCutPoint, mFaceNormal)
				if mouseOnPlane then
					cutDir = computeCutDirection(
						mouseOnPlane, mCutPoint, mFaceNormal, mCutEdge.direction
					)
				end
			end

			if not cutDir then
				-- Can't determine cut direction — cancel
				clearState()
				ctx.SetHighlight(nil)
				ctx.UpdateUI()
				return
			end

			local cutPoint = mCutPoint
			local faceNormal = mFaceNormal
			local partsTocut = mCutParts
			local targetModels = mTargetModels
			local looseParts = mLooseParts

			clearState()

			local avoidCSG = ctx.GetSetting("AvoidCSG") ~= false
			local id = ctx.BeginRecording("Part Cut")
			local errors: {string} = {}
			if #targetModels > 0 then
				-- Model mode: split all affected models
				for _, model in targetModels do
					local modelErrors = executeModelCut(model, cutPoint, cutDir, faceNormal, avoidCSG)
					for _, err in modelErrors do
						table.insert(errors, err)
					end
				end
				-- Cut loose parts (not in any model) individually
				for _, part in looseParts do
					local err = executeCut(part, cutPoint, cutDir, faceNormal, avoidCSG)
					if err then
						table.insert(errors, err)
					end
				end
			else
				-- Part mode: cut individual parts
				for _, partToCut in partsTocut do
					local err = executeCut(partToCut, cutPoint, cutDir, faceNormal, avoidCSG)
					if err then
						table.insert(errors, err)
					end
				end
			end
			if id then
				ctx.FinishRecording(id)
			end

			if #errors > 0 then
				showStatusMessage(table.concat(errors, "\n"))
			end

			ctx.SetHighlight(nil)
			ctx.UpdateUI()
		end
	end,

	RenderSettings = PartCutterSettings,

	DefaultSettings = {
		SplitMode = "Part",
		ModelScope = "Parent",
		AvoidCSG = true,
	},
}

return PartCutter

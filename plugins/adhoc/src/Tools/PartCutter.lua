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
local mEdgeHighlight: CylinderHandleAdornment? = nil
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
	if mEdgeHighlight then
		mEdgeHighlight:Destroy()
		mEdgeHighlight = nil
	end
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

local function updateEdgeHighlight(edge: GeometryEdge)
	if not mEdgeHighlight then
		local cyl = Instance.new("CylinderHandleAdornment")
		cyl.Adornee = workspace.Terrain
		cyl.Color3 = Color3.fromRGB(0, 162, 255)
		cyl.AlwaysOnTop = true
		cyl.Radius = 0.06
		cyl.Parent = CoreGui
		mEdgeHighlight = cyl
	end
	local mid = (edge.a + edge.b) / 2
	local dir = (edge.b - edge.a)
	local length = dir.Magnitude
	if length < 0.001 then
		return
	end
	dir = dir / length
	mEdgeHighlight.Height = length
	mEdgeHighlight.CFrame = CFrame.lookAt(mid, mid + dir)
end

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

-- Determine whether to use simple cut or CSG, and execute.
-- Returns (errorMsg?, negHalf?, posHalf?) — negHalf/posHalf relative to cutNormal.
-- On failure, errorMsg is set and halves are nil; the original part is unchanged.
local function executeCut(
	part: BasePart, cutPoint: Vector3, cutDir: Vector3, faceNormal: Vector3
): (string?, BasePart?, BasePart?)
	local cutNormal = cutDir:Cross(faceNormal).Unit

	local axis = getAxisAligned(part, cutNormal)
	if axis then
		-- Simple cut works for blocks along any axis
		local isBlock = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block
		if isBlock then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, neg, pos
		end
		-- Cylinder: simple cut along X (length axis) only
		local isCylinder = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Cylinder
		if isCylinder and axis == "X" then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, neg, pos
		end
		-- Wedge: simple cut along X (width axis) only
		local isWedge = (part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Wedge)
			or part:IsA("WedgePart")
		if isWedge and axis == "X" then
			local neg, pos = doSimpleCut(part, cutPoint, cutNormal, axis)
			return nil, neg, pos
		end
	end

	-- General case: CSG
	local ok, neg, pos = doCSGCut(part, cutPoint, cutNormal)
	if ok then
		return nil, neg, pos
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
	keepSide: string
): string?
	local err, negHalf, posHalf = executeCut(part, cutPoint, cutDir, faceNormal)

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

	-- Remove the half on the wrong side
	if keepSide == "negative" and posHalf then
		posHalf.Parent = nil
	elseif keepSide == "positive" and negHalf then
		negHalf.Parent = nil
	end
	return nil
end

-- Execute a model split: cut straddling parts and separate into two sibling models
local function executeModelCut(
	model: Model,
	cutPoint: Vector3,
	cutDir: Vector3,
	faceNormal: Vector3
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
		local err = cutAndKeepSide(part, cutPoint, cutDir, faceNormal, cutNormal, "negative")
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
			local err = cutAndKeepSide(clonedPart, cutPoint, cutDir, faceNormal, cutNormal, "positive")
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
			Color = Colors.DISABLED_GREY,
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
					updateEdgeHighlight(edge)
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

			local id = ctx.BeginRecording("Part Cut")
			local errors: {string} = {}
			if #targetModels > 0 then
				-- Model mode: split all affected models
				for _, model in targetModels do
					local modelErrors = executeModelCut(model, cutPoint, cutDir, faceNormal)
					for _, err in modelErrors do
						table.insert(errors, err)
					end
				end
				-- Cut loose parts (not in any model) individually
				for _, part in looseParts do
					local err = executeCut(part, cutPoint, cutDir, faceNormal)
					if err then
						table.insert(errors, err)
					end
				end
			else
				-- Part mode: cut individual parts
				for _, partToCut in partsTocut do
					local err = executeCut(partToCut, cutPoint, cutDir, faceNormal)
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
	},
}

return PartCutter

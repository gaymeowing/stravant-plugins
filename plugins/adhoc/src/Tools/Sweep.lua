--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

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

local function worldNormalToNormalId(part: BasePart, worldNormal: Vector3): Enum.NormalId
	local objectNormal = part.CFrame:VectorToObjectSpace(worldNormal)
	local bestDot = -math.huge
	local bestId: Enum.NormalId = Enum.NormalId.Front
	for normalId, axis in NORMAL_ID_VECTORS do
		local dot = objectNormal:Dot(axis)
		if dot > bestDot then
			bestDot = dot
			bestId = normalId
		end
	end
	return bestId
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
-- Core sweep algorithm
--------------------------------------------------------------------------------

local function doSweep(
	partA: BasePart, normalIdA: Enum.NormalId,
	partB: BasePart, normalIdB: Enum.NormalId,
	segmentCount: number
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

	-- Find the hinge point (pivot) using ray-ray closest approach
	-- Ray A: centerA + t * nA, Ray B: centerB + s * nB
	local a_coeff = nA:Dot(nA)
	local b_coeff = nA:Dot(nB)
	local c_coeff = nB:Dot(nB)
	local sep = centerA - centerB
	local d_coeff = nA:Dot(sep)
	local e_coeff = nB:Dot(sep)

	local denom = a_coeff * c_coeff - b_coeff * b_coeff
	local hingePoint: Vector3
	if math.abs(denom) < 0.001 then
		-- Parallel case: place hinge at midpoint perpendicular to both
		hingePoint = (centerA + centerB) / 2
	else
		local tA = (b_coeff * e_coeff - c_coeff * d_coeff) / denom
		local tB = (a_coeff * e_coeff - b_coeff * d_coeff) / denom
		local closestA = centerA + nA * tA
		local closestB = centerB + nB * tB
		hingePoint = (closestA + closestB) / 2
	end

	-- Compute radial directions from hinge to face centers
	local toA = centerA - hingePoint
	local toA_axial = hingeAxis * toA:Dot(hingeAxis)
	local radialA = toA - toA_axial
	local radiusA = radialA.Magnitude

	local toB = centerB - hingePoint
	local toB_axial = hingeAxis * toB:Dot(hingeAxis)
	local radialB = toB - toB_axial
	local radiusB = radialB.Magnitude

	-- Use average radius for the arc center
	local radius = (radiusA + radiusB) / 2
	if radius < 0.001 then
		return -- Faces are coincident with hinge, can't sweep
	end

	-- Normalize radial directions
	local radialDirA = if radiusA > 0.001 then radialA.Unit else nA
	local radialDirB = if radiusB > 0.001 then radialB.Unit else nB

	-- Compute sweep angle from actual radial directions with correct sign
	local cosAngle = math.clamp(radialDirA:Dot(radialDirB), -1, 1)
	local sinAngle = hingeAxis:Dot(radialDirA:Cross(radialDirB))
	local sweepAngle = math.atan2(sinAngle, cosAngle)
	if sweepAngle < 0 then
		hingeAxis = -hingeAxis
		sweepAngle = -sweepAngle
	end
	if sweepAngle < 0.001 then
		return -- Faces are coincident, nothing to sweep
	end

	-- Inner and outer radii based on face radial depths
	local innerR = radius - depthA_radial / 2
	local outerR = radius + depthA_radial / 2
	if innerR < 0 then
		innerR = 0
	end

	-- Create model for sweep geometry
	local model = Instance.new("Model")
	model.Name = "Sweep"

	-- Generate arc segments
	for i = 0, segmentCount - 1 do
		local frac0 = i / segmentCount
		local frac1 = (i + 1) / segmentCount
		local angle0 = frac0 * sweepAngle
		local angle1 = frac1 * sweepAngle

		-- Compute radial direction at each angle by rotating radialDirA around hingeAxis
		local rot0 = CFrame.fromAxisAngle(hingeAxis, angle0)
		local rot1 = CFrame.fromAxisAngle(hingeAxis, angle1)
		local dir0 = rot0:VectorToWorldSpace(radialDirA)
		local dir1 = rot1:VectorToWorldSpace(radialDirA)

		-- Four corner points of the trapezoidal cross-section
		local inner0 = hingePoint + dir0 * innerR
		local outer0 = hingePoint + dir0 * outerR
		local inner1 = hingePoint + dir1 * innerR
		local outer1 = hingePoint + dir1 * outerR

		-- Extrude direction is along the hinge axis
		local extrudeDir = hingeAxis

		-- Split trapezoid into 2 triangles and fill each
		-- Triangle 1: inner0, outer0, inner1
		fillTriangle(inner0, outer0, inner1, axialWidth, extrudeDir, partA, model)
		-- Triangle 2: outer0, outer1, inner1
		fillTriangle(outer0, outer1, inner1, axialWidth, extrudeDir, partA, model)
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
	})
end

--------------------------------------------------------------------------------
-- Tool definition
--------------------------------------------------------------------------------

local Sweep: ToolTypes.ToolDefinition = {
	Id = "sweep",
	Name = "Sweep Arc",
	Description = "Create an arc of geometry between two faces",

	DefaultSettings = {
		SegmentCount = 6,
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
		local targetNormal = ctx.TargetNormal

		if not isBlockPart(target) or not targetNormal then
			clearHover()
			return
		end

		local part = target :: BasePart
		local normalId = worldNormalToNormalId(part, targetNormal)

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
			if not ctx.Target or not ctx.TargetNormal then
				return
			end
			if not isBlockPart(ctx.Target) then
				return
			end
			local normalId = worldNormalToNormalId(ctx.Target, ctx.TargetNormal)
			mState = "faceB"
			mPartA = ctx.Target
			mNormalIdA = normalId
			destroyFaceHighlight(mSelectedHighlight)
			mSelectedHighlight = createFaceHighlight(ctx.Target, normalId, kColorRed, 0, 0)
			-- Recreate hover in blue color now that we're in faceB state
			clearHover()
			ctx.UpdateUI()

		elseif mState == "faceB" then
			if not ctx.Target or not ctx.TargetNormal then
				return
			end
			if not isBlockPart(ctx.Target) then
				return
			end

			-- Clicking the same part reselects face A
			if ctx.Target == mPartA then
				local normalId = worldNormalToNormalId(ctx.Target, ctx.TargetNormal)
				mNormalIdA = normalId
				destroyFaceHighlight(mSelectedHighlight)
				mSelectedHighlight = createFaceHighlight(ctx.Target, normalId, kColorRed, 0, 0)
				clearHover()
				ctx.UpdateUI()
				return
			end

			local partA = mPartA :: BasePart
			local normalIdA = mNormalIdA :: Enum.NormalId
			local partB = ctx.Target
			local normalIdB = worldNormalToNormalId(partB, ctx.TargetNormal)
			local segmentCount = ctx.GetSetting("SegmentCount") :: number

			local id = ctx.BeginRecording("Sweep")

			doSweep(partA, normalIdA, partB, normalIdB, segmentCount)

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

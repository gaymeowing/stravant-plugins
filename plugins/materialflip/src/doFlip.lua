--!strict

-- Perform a material flip: rotate the material orientation of a part a
-- quarter turn about the clicked bounding box face, while the part continues
-- to occupy exactly the same region of space.
--
-- The new orientation is m' = r * m (r = the quarter turn in shape-local
-- coordinates). The new representation is chosen by which class m' falls in:
--   * The identity class (m' in the shape's symmetry group H): representable
--     by the primitive itself, with axis-permuted Size and rotated CFrame.
--     Primitives are always preferred.
--   * Any other class: a MeshPart with the rotation baked into its geometry.
-- The part instance is updated in place when its representation class
-- doesn't change, and swapped for a new instance when it does.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local identifyPart = require("./identifyPart")
local getMeshRepresentation = require("./getMeshRepresentation")
local copyPartProps = require("./copyPartProps")

local kSurfaceProps: {[Enum.NormalId]: string} = {
	[Enum.NormalId.Top] = "TopSurface",
	[Enum.NormalId.Bottom] = "BottomSurface",
	[Enum.NormalId.Right] = "RightSurface",
	[Enum.NormalId.Left] = "LeftSurface",
	[Enum.NormalId.Back] = "BackSurface",
	[Enum.NormalId.Front] = "FrontSurface",
}

-- The bounding box face of the shape frame closest to the given world point
local function closestBoxFace(state: identifyPart.PartState, worldPoint: Vector3): Enum.NormalId
	local localPoint = state.ShapeCFrame:PointToObjectSpace(worldPoint)
	local half = state.ShapeSize / 2
	local best = math.huge
	local bestFace = Enum.NormalId.Top
	local candidates: {{face: Enum.NormalId, dist: number}} = {
		{face = Enum.NormalId.Right, dist = math.abs(localPoint.X - half.X)},
		{face = Enum.NormalId.Left, dist = math.abs(localPoint.X + half.X)},
		{face = Enum.NormalId.Top, dist = math.abs(localPoint.Y - half.Y)},
		{face = Enum.NormalId.Bottom, dist = math.abs(localPoint.Y + half.Y)},
		{face = Enum.NormalId.Back, dist = math.abs(localPoint.Z - half.Z)},
		{face = Enum.NormalId.Front, dist = math.abs(localPoint.Z + half.Z)},
	}
	for _, candidate in candidates do
		if candidate.dist < best then
			best = candidate.dist
			bestFace = candidate.face
		end
	end
	return bestFace
end

local function createPrimitive(shape: ShapeData.ShapeName): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		return Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
		return part
	end
end

-- Permute the surface type properties so each world-space face keeps its
-- surface when the primitive's CFrame rotates by newM (from m = identity)
local function permuteSurfaces(part: BasePart, newM: Orientation.OrientationId)
	local old: {[Enum.NormalId]: Enum.SurfaceType} = {}
	for normalId, prop in kSurfaceProps do
		old[normalId] = (part :: any)[prop]
	end
	for normalId, prop in kSurfaceProps do
		(part :: any)[prop] = old[Orientation.rotateNormalId(newM, normalId)]
	end
end

-- Returns the part representing the result (the same part if updated in
-- place), or nil if the part isn't flippable or the flip isn't representable.
local function doFlip(part: BasePart, worldPoint: Vector3, clockwise: boolean): BasePart?
	local state = identifyPart(part)
	if not state then
		return nil
	end
	assert(state)

	local face = closestBoxFace(state, worldPoint)
	local r = Orientation.quarterTurnAbout(face, clockwise)
	local newM = Orientation.compose(r, state.Orientation)

	local targetClass = ShapeData.classRepOf(state.Shape, newM)
	local identityClass = ShapeData.identityClass(state.Shape)
	local usePrimitive = targetClass == identityClass
	if state.PrimitiveOnly and not usePrimitive then
		-- E.g. a SpecialMesh part asked for an orientation only a MeshPart
		-- could represent: converting would lose the mesh, so do nothing.
		return nil
	end

	local recording = ChangeHistoryService:TryBeginRecording("MaterialFlip", "Material Flip")

	local newCFrame = state.ShapeCFrame * Orientation.getCFrame(newM)
	local newSize = Orientation.permuteSize(Orientation.invert(newM), state.ShapeSize)

	local currentClass = if state.IsMeshRepresentation
		then ShapeData.classRepOf(state.Shape, state.Orientation)
		else identityClass
	local sameRepresentation = if usePrimitive
		then not state.IsMeshRepresentation
		else state.IsMeshRepresentation and targetClass == currentClass

	local result: BasePart
	if sameRepresentation then
		-- Update in place
		part:BreakJoints()
		if not state.IsMeshRepresentation then
			permuteSurfaces(part, newM)
			pcall(function()
				-- Legacy FormFactor parts can't freely resize without this
				(part :: any).FormFactor = Enum.FormFactor.Custom
			end)
		end
		part.Size = newSize
		part:BreakJoints() -- Needed to "unstick" hinges.
		part.CFrame = newCFrame
		result = part
	else
		-- Swap representation: build the replacement instance
		local replacement: BasePart
		if usePrimitive then
			replacement = createPrimitive(state.Shape)
			replacement.TopSurface = Enum.SurfaceType.Smooth
			replacement.BottomSurface = Enum.SurfaceType.Smooth
		else
			-- The published class mesh is the unit shape with the class
			-- rotation baked in; the permuted Size and CFrame P * newM make
			-- the part occupy P * S(s) with its material frame rotated by newM
			replacement = getMeshRepresentation(state.Shape, targetClass)
		end
		copyPartProps(part, replacement)
		replacement.Size = newSize
		replacement.CFrame = newCFrame

		part:BreakJoints()
		for _, child in part:GetChildren() do
			child.Parent = replacement
		end
		replacement.Parent = part.Parent

		-- Keep the selection on the result if the old part was selected
		local selection = Selection:Get()
		for i, selected in selection do
			if selected == part then
				selection[i] = replacement
				Selection:Set(selection)
				break
			end
		end

		-- Not :Destroy() so that undo can restore the old part
		part.Parent = nil
		result = replacement
	end

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("MaterialFlip")
	end
	return result
end

return doFlip

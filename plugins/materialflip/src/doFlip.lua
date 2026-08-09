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
local pickRotationFace = require("./pickRotationFace")
local getMeshRepresentation = require("./getMeshRepresentation")
local copyPartProps = require("./copyPartProps")

export type FlipOptions = {
	Clockwise: boolean,
	-- Keep Attachments under the part at their world pose instead of
	-- rotating along with the material
	PreserveAttachments: boolean,
	-- Reassign Decal/Texture Face so they stay on the same world face
	PreserveDecals: boolean,
}

local kSurfaceProps: {[Enum.NormalId]: string} = {
	[Enum.NormalId.Top] = "TopSurface",
	[Enum.NormalId.Bottom] = "BottomSurface",
	[Enum.NormalId.Right] = "RightSurface",
	[Enum.NormalId.Left] = "LeftSurface",
	[Enum.NormalId.Back] = "BackSurface",
	[Enum.NormalId.Front] = "FrontSurface",
}

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

-- Attachments under the part, parents before children, so restoring a
-- parent's world pose doesn't disturb an already restored child. Only
-- chains of Attachments matter: an attachment inside e.g. a child part is
-- anchored to that part, which doesn't move.
local function collectAttachmentPoses(part: BasePart): {{attachment: Attachment, worldCFrame: CFrame}}
	local poses = {}
	local function collect(instance: Instance)
		for _, child in instance:GetChildren() do
			if child:IsA("Attachment") then
				table.insert(poses, {attachment = child, worldCFrame = child.WorldCFrame})
				collect(child)
			end
		end
	end
	collect(part)
	return poses
end

-- Returns the part representing the result (the same part if updated in
-- place), or nil if the part isn't flippable or the flip isn't representable.
local function doFlip(part: BasePart, worldPoint: Vector3, worldNormal: Vector3, options: FlipOptions): BasePart?
	local state = identifyPart(part)
	if not state then
		return nil
	end
	assert(state)

	local face = pickRotationFace(state, worldPoint, worldNormal)
	local r = Orientation.quarterTurnAbout(face, options.Clockwise)
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

	-- Snapshots for content preservation, taken before any mutation
	local attachmentPoses = if options.PreserveAttachments then collectAttachmentPoses(part) else nil
	local faceInstances: {FaceInstance}? = nil
	if options.PreserveDecals then
		faceInstances = {}
		for _, child in part:GetChildren() do
			if child:IsA("FaceInstance") then
				table.insert(faceInstances :: {FaceInstance}, child)
			end
		end
	end

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

	-- Restore preserved content now that the part has its new frame
	if attachmentPoses then
		for _, entry in attachmentPoses do
			entry.attachment.WorldCFrame = entry.worldCFrame
		end
	end
	if faceInstances then
		-- Move each Decal/Texture to the local face now pointing in the world
		-- direction its old face pointed in: q = newM^-1 * oldM
		local q = Orientation.compose(Orientation.invert(newM), state.Orientation)
		for _, faceInstance in faceInstances do
			faceInstance.Face = Orientation.rotateNormalId(q, faceInstance.Face)
		end
	end

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("MaterialFlip")
	end
	return result
end

return doFlip

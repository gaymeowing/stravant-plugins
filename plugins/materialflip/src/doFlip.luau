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
local GeometryService = game:GetService("GeometryService")
local Selection = game:GetService("Selection")

local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local identifyPart = require("./identifyPart")
local pickRotationFace = require("./pickRotationFace")
local getMeshRepresentation = require("./getMeshRepresentation")
local getNegateHelper = require("./getNegateHelper")
local copyPartProps = require("./copyPartProps")
local warmRenderParts = require("./warmRenderParts")

export type FlipOptions = {
	Clockwise: boolean,
	-- Keep Attachments under the part at their world pose instead of
	-- rotating along with the material
	PreserveAttachments: boolean,
	-- Reassign Decal/Texture Face so they stay on the same world face
	PreserveDecals: boolean,
	-- Adjust PivotOffset so the world space pivot stays where it was
	PreservePivot: boolean,
	-- Rotate the material of foreign MeshParts/unions correctly by unioning
	-- via the CSG API (the first input supplies the result's material frame).
	-- Creates a unique mesh per use: significant performance cost.
	AllowMeshPartRotation: boolean,
}

-- Image space axes (U = image right, V = image down) of each box face in
-- part local space, determined empirically with a marked test image; all
-- satisfy U:Cross(V) == -normal. Decal/Texture Rotation turns the image
-- clockwise as viewed from outside the face (also empirical).
local kFaceUV: {[Enum.NormalId]: {U: Vector3, V: Vector3}} = {
	[Enum.NormalId.Front] = {U = Vector3.new(-1, 0, 0), V = Vector3.new(0, -1, 0)},
	[Enum.NormalId.Back] = {U = Vector3.new(1, 0, 0), V = Vector3.new(0, -1, 0)},
	[Enum.NormalId.Right] = {U = Vector3.new(0, 0, -1), V = Vector3.new(0, -1, 0)},
	[Enum.NormalId.Left] = {U = Vector3.new(0, 0, 1), V = Vector3.new(0, -1, 0)},
	[Enum.NormalId.Top] = {U = Vector3.new(-1, 0, 0), V = Vector3.new(0, 0, -1)},
	[Enum.NormalId.Bottom] = {U = Vector3.new(1, 0, 0), V = Vector3.new(0, 0, -1)},
}

local kSurfaceProps: {[Enum.NormalId]: string} = {
	[Enum.NormalId.Top] = "TopSurface",
	[Enum.NormalId.Bottom] = "BottomSurface",
	[Enum.NormalId.Right] = "RightSurface",
	[Enum.NormalId.Left] = "LeftSurface",
	[Enum.NormalId.Back] = "BackSurface",
	[Enum.NormalId.Front] = "FrontSurface",
}

-- Always a Part with the appropriate Shape, never the legacy WedgePart /
-- CornerWedgePart classes. This means a legacy wedge that round trips
-- through a mesh representation comes back "upgraded" to a modern
-- Part + Shape, which is desirable behavior.
local function createPrimitive(shape: ShapeData.ShapeName): BasePart
	local part = Instance.new("Part")
	if shape == "Wedge" then
		part.Shape = Enum.PartType.Wedge
	elseif shape == "CornerWedge" then
		part.Shape = Enum.PartType.CornerWedge
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	end
	return part
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
	local savedCFrame = part.CFrame
	local savedWorldPivot: CFrame? = if options.PreservePivot then part.CFrame * part.PivotOffset else nil
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
	local function swapIn(replacement: BasePart)
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

	-- Unions always take the CSG rotation path: their results persist in the
	-- place. Foreign MeshParts only take it with the Allow MeshPart Rotation
	-- setting, because MeshPart union results don't save yet (which is also
	-- why that setting is currently hidden; see MaterialFlipGui).
	local csgRotate = state.ApproximatedAsBox and state.CsgRotatable
		and (options.AllowMeshPartRotation or part:IsA("UnionOperation"))
	if csgRotate then
		-- CSG path: union a clone of the part with a tiny NEGATIVE helper
		-- that goes first and carries the rotated material frame - the CSG
		-- result's local frame (and therefore its material) comes from the
		-- first input, and negative geometry contributes nothing to the
		-- result's shape (a positive helper could show up as a visible speck
		-- when the part's center lies outside its geometry). Operating on a
		-- clone keeps the live part untouched while the async union runs (no
		-- flicker), and inputs are whitened where the visible color doesn't
		-- come from baked vertex colors, since the CSG API multiplies input
		-- colors into the bake, darkening a colored part on every flip.
		local helper = getNegateHelper()
		if not helper then
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
			end
			return nil
		end
		assert(helper)
		helper.Size = Vector3.new(0.05, 0.05, 0.05)
		helper.CFrame = newCFrame
		local wasArchivable = part.Archivable
		part.Archivable = true
		local clone = part:Clone()
		part.Archivable = wasArchivable
		clone:ClearAllChildren()
		-- Whiten the input only where the visible color doesn't come from the
		-- baked vertex colors: MeshParts, and unions showing their Part
		-- color. Unions without UsePartColor keep their input colors - the
		-- baked colors ARE their appearance.
		if part:IsA("MeshPart") or (part:IsA("UnionOperation") and part.UsePartColor) then
			clone.Color = Color3.new(1, 1, 1)
		end
		local ok, unionResults = pcall(function()
			return GeometryService:UnionAsync(helper, {clone})
		end)
		helper:Destroy()
		clone:Destroy()
		local unioned = if ok and type(unionResults) == "table" and unionResults[1]
			then unionResults[1] :: BasePart
			else nil
		if not unioned then
			warn("MaterialFlip: CSG rotation failed: " .. tostring(if ok then "no result" else unionResults))
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
			end
			return nil
		end
		assert(unioned)

		-- Warm the new mesh into graphics memory before showing it, otherwise
		-- the first frame renders with the old resident mesh against the new
		-- CFrame - a one frame wrong-orientation flicker. A throwaway clone
		-- shares the mesh resource, keeping the real result pristine.
		local warmClone = unioned:Clone()
		if warmClone then
			warmRenderParts({warmClone})
			warmClone:Destroy()
		end

		if part:IsA("MeshPart") and unioned:IsA("MeshPart") then
			-- Apply the rotated mesh back onto the live part in place: no
			-- instance swap at all (UnionAsync returns a MeshPart when a
			-- MeshPart is an operand)
			part:BreakJoints()
			part:ApplyMesh(unioned)
			part.Size = unioned.Size
			part.CFrame = newCFrame
			unioned:Destroy()
			result = part
		else
			-- Union operands produce a UnionOperation, which can't ApplyMesh:
			-- swap it in. Its geometry and CFrame are already baked in place.
			copyPartProps(part, unioned)
			if part:IsA("UnionOperation") and unioned:IsA("UnionOperation") then
				-- Preserve the color mode rather than forcing UsePartColor:
				-- flipping must work on per-input-colored unions too
				unioned.UsePartColor = part.UsePartColor
			end
			swapIn(unioned)
		end
	elseif sameRepresentation then
		-- Update in place
		part:BreakJoints()
		if not state.IsMeshRepresentation then
			permuteSurfaces(part, newM)
			pcall(function()
				-- Legacy FormFactor parts can't freely resize without this
				(part :: any).FormFactor = Enum.FormFactor.Custom
			end)
			if not state.ApproximatedAsBox then
				-- Primitive-shaped SpecialMeshes (oval cylinders,
				-- ellipsoids...) render relative to the part's local axes, so
				-- their Scale must permute like the Size and their Offset
				-- must counter-rotate for the rendered solid to keep
				-- occupying the same region. (Approximated meshes like
				-- FileMesh rotate rigidly with the part instead, so theirs
				-- are left alone.)
				for _, child in part:GetChildren() do
					if child:IsA("SpecialMesh") then
						child.Scale = Orientation.permuteSize(Orientation.invert(newM), child.Scale)
						child.Offset = Orientation.getCFrame(Orientation.invert(newM)):VectorToWorldSpace(child.Offset)
					end
				end
			end
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
		swapIn(replacement)
	end

	-- Restore preserved content now that the part has its new frame
	if savedWorldPivot then
		result.PivotOffset = result.CFrame:Inverse() * savedWorldPivot
	end
	if attachmentPoses then
		for _, entry in attachmentPoses do
			entry.attachment.WorldCFrame = entry.worldCFrame
		end
	end
	if faceInstances then
		-- Move each Decal/Texture to the local face now pointing in the world
		-- direction its old face pointed in (q = newM^-1 * oldM), and adjust
		-- Rotation to compensate for how the new face's image axes sit
		-- relative to the old face's, so the image appearance is unchanged
		local q = Orientation.compose(Orientation.invert(newM), state.Orientation)
		for _, faceInstance in faceInstances do
			local oldFace = faceInstance.Face
			local newFace = Orientation.rotateNormalId(q, oldFace)
			local oldUV = kFaceUV[oldFace]
			local newUV = kFaceUV[newFace]
			-- delta = clockwise angle from the old face's world image axes to
			-- the new face's (both perpendicular to the shared world normal)
			local oldRight = savedCFrame:VectorToWorldSpace(oldUV.U)
			local oldDown = savedCFrame:VectorToWorldSpace(oldUV.V)
			local newRight = result.CFrame:VectorToWorldSpace(newUV.U)
			local delta = math.deg(math.atan2(newRight:Dot(oldDown), newRight:Dot(oldRight)))
			faceInstance.Face = newFace
			faceInstance.Rotation = (faceInstance.Rotation - delta) % 360
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

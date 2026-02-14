--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- The six NormalId axes as unit vectors in object space
local NORMAL_ID_VECTORS: { [Enum.NormalId]: Vector3 } = {
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
}

-- Surface property names indexed by NormalId
local SURFACE_PROPS: { [Enum.NormalId]: string } = {
	[Enum.NormalId.Top] = "TopSurface",
	[Enum.NormalId.Bottom] = "BottomSurface",
	[Enum.NormalId.Front] = "FrontSurface",
	[Enum.NormalId.Back] = "BackSurface",
	[Enum.NormalId.Left] = "LeftSurface",
	[Enum.NormalId.Right] = "RightSurface",
}

-- All six NormalIds
local ALL_NORMAL_IDS: { Enum.NormalId } = {
	Enum.NormalId.Top, Enum.NormalId.Bottom,
	Enum.NormalId.Front, Enum.NormalId.Back,
	Enum.NormalId.Left, Enum.NormalId.Right,
}

-- Convert a world-space normal to the closest NormalId for a given part
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

-- Get the size component along a NormalId axis
local function sizeAlongNormal(size: Vector3, normalId: Enum.NormalId): number
	local axis = NORMAL_ID_VECTORS[normalId]
	return math.abs(size.X * axis.X) + math.abs(size.Y * axis.Y) + math.abs(size.Z * axis.Z)
end

-- Given old and new CFrames, figure out the remapped Size so the part keeps
-- the same world-space extents.
local function remapSize(oldCFrame: CFrame, newCFrame: CFrame, oldSize: Vector3): Vector3
	-- For each new local axis, find which old local axis it aligns with
	local newRight = newCFrame.RightVector
	local newUp = newCFrame.UpVector
	local newLook = -newCFrame.LookVector

	local oldRight = oldCFrame.RightVector
	local oldUp = oldCFrame.UpVector
	local oldLook = -oldCFrame.LookVector

	local function bestOldComponent(newAxis: Vector3): number
		-- Find which old axis this new axis most closely matches
		local dotRight = math.abs(newAxis:Dot(oldRight))
		local dotUp = math.abs(newAxis:Dot(oldUp))
		local dotLook = math.abs(newAxis:Dot(oldLook))
		if dotRight >= dotUp and dotRight >= dotLook then
			return oldSize.X
		elseif dotUp >= dotRight and dotUp >= dotLook then
			return oldSize.Y
		else
			return oldSize.Z
		end
	end

	return Vector3.new(
		bestOldComponent(newRight),
		bestOldComponent(newUp),
		bestOldComponent(newLook)
	)
end

-- Remap surface properties so they follow the physical faces through the rotation.
-- For each new NormalId, find which old NormalId's world direction matches it,
-- and copy that surface type.
local function remapSurfaces(part: BasePart, oldCFrame: CFrame, newCFrame: CFrame, oldSurfaces: { [Enum.NormalId]: Enum.SurfaceType })
	for _, newNormalId in ALL_NORMAL_IDS do
		-- World direction of this new face
		local newWorldDir = newCFrame:VectorToWorldSpace(NORMAL_ID_VECTORS[newNormalId])
		-- Find which old NormalId has the closest world direction
		local bestDot = -math.huge
		local bestOldId: Enum.NormalId = Enum.NormalId.Front
		for _, oldNormalId in ALL_NORMAL_IDS do
			local oldWorldDir = oldCFrame:VectorToWorldSpace(NORMAL_ID_VECTORS[oldNormalId])
			local dot = newWorldDir:Dot(oldWorldDir)
			if dot > bestDot then
				bestDot = dot
				bestOldId = oldNormalId
			end
		end
		;(part :: any)[SURFACE_PROPS[newNormalId]] = oldSurfaces[bestOldId]
	end
end

-- State
local mState: "idle" | "pickingUp" = "idle"
local mFrontPart: BasePart? = nil
local mFrontNormalId: Enum.NormalId? = nil
local mFrontArrow: ConeHandleAdornment? = nil

local function clearState()
	mState = "idle"
	mFrontPart = nil
	mFrontNormalId = nil
	if mFrontArrow then
		mFrontArrow:Destroy()
		mFrontArrow = nil
	end
end

local function createArrow(part: BasePart, normalId: Enum.NormalId): ConeHandleAdornment
	local arrow = Instance.new("ConeHandleAdornment")
	arrow.Adornee = part
	arrow.Color3 = Color3.fromRGB(0, 162, 255)
	arrow.AlwaysOnTop = true
	arrow.Height = 1.5
	arrow.Radius = 0.4

	-- Position the cone on the face surface, pointing outward.
	-- ConeHandleAdornment extends along the +Y of its CFrame (relative to adornee).
	local normal = NORMAL_ID_VECTORS[normalId]
	local faceOffset = sizeAlongNormal(part.Size, normalId) / 2
	local pos = normal * (faceOffset + arrow.Height / 2)

	-- Build a CFrame where +Y = normal direction (object space)
	local helper = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local right = normal:Cross(helper).Unit
	local forward = right:Cross(normal)
	arrow.CFrame = CFrame.fromMatrix(pos, right, normal, -forward)

	arrow.Parent = part
	return arrow
end

local function isBlockPart(part: BasePart?): boolean
	if not part then
		return false
	end
	if part:IsA("Part") then
		return part.Shape == Enum.PartType.Block
	end
	-- MeshParts and other BaseParts don't support face reorientation
	return false
end

-- Settings UI
local function FaceOrientSettings(props: ToolSettingsProps)
	-- We use a ref to track state for display purposes
	local stateText = if mState == "idle"
		then "Click a face to set as Front"
		else "Click an adjacent face to set as Up"

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		StatusLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = stateText,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local FaceOrient: ToolTypes.ToolDefinition = {
	Id = "faceOrient",
	Name = "Face Orient",
	Description = "Reorient a part by choosing front and up faces",

	OnActivated = function(ctx: ToolContext)
		clearState()
		ctx.UpdateUI()
	end,

	OnDeactivated = function(ctx: ToolContext)
		clearState()
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		if mState == "idle" then
			if isBlockPart(ctx.Target) then
				ctx.SetHighlight(ctx.Target)
			else
				ctx.SetHighlight(nil)
			end
		end
		-- In pickingUp, keep the front part highlighted (don't change)
	end,

	OnClicked = function(ctx: ToolContext)
		if mState == "idle" then
			-- Pick front face
			if not ctx.Target or not ctx.TargetNormal then
				return
			end
			if not isBlockPart(ctx.Target) then
				return
			end
			local normalId = worldNormalToNormalId(ctx.Target, ctx.TargetNormal)
			mState = "pickingUp"
			mFrontPart = ctx.Target
			mFrontNormalId = normalId
			mFrontArrow = createArrow(ctx.Target, normalId)
			ctx.SetHighlight(ctx.Target)
			ctx.UpdateUI()

		elseif mState == "pickingUp" then
			-- Pick up face
			if not ctx.Target or not ctx.TargetNormal then
				return
			end

			-- If clicking a different part, restart with that part as click 1
			if ctx.Target ~= mFrontPart then
				clearState()
				if isBlockPart(ctx.Target) then
					local normalId = worldNormalToNormalId(ctx.Target, ctx.TargetNormal)
					mState = "pickingUp"
					mFrontPart = ctx.Target
					mFrontNormalId = normalId
					mFrontArrow = createArrow(ctx.Target, normalId)
					ctx.SetHighlight(ctx.Target)
				end
				ctx.UpdateUI()
				return
			end

			local part = mFrontPart :: BasePart
			local frontNormalId = mFrontNormalId :: Enum.NormalId
			local upNormalId = worldNormalToNormalId(part, ctx.TargetNormal)

			-- Validate: up must be perpendicular to front
			local frontAxis = NORMAL_ID_VECTORS[frontNormalId]
			local upAxis = NORMAL_ID_VECTORS[upNormalId]
			if math.abs(frontAxis:Dot(upAxis)) > 0.01 then
				-- Same or opposite face - ignore click
				return
			end

			-- Apply the reorientation
			local id = ctx.BeginRecording("Face Orient")

			local oldCFrame = part.CFrame
			local oldSize = part.Size

			-- Save old surface properties
			local oldSurfaces: { [Enum.NormalId]: Enum.SurfaceType } = {}
			for _, nid in ALL_NORMAL_IDS do
				oldSurfaces[nid] = (part :: any)[SURFACE_PROPS[nid]] :: Enum.SurfaceType
			end

			-- Build new orientation:
			-- The chosen front face's world direction becomes -LookVector (Front = -Z)
			-- The chosen up face's world direction becomes UpVector (+Y)
			local worldFront = oldCFrame:VectorToWorldSpace(frontAxis)
			local worldUp = oldCFrame:VectorToWorldSpace(upAxis)

			-- CFrame.lookAt points -Z along (target - eye), so -Z = direction of worldFront
			local pos = part.Position
			local newCFrame = CFrame.lookAt(pos, pos + worldFront, worldUp)

			-- Remap size to preserve world-space shape
			part.Size = remapSize(oldCFrame, newCFrame, oldSize)
			part.CFrame = newCFrame

			-- Remap surfaces
			remapSurfaces(part, oldCFrame, newCFrame, oldSurfaces)

			if id then
				ctx.FinishRecording(id)
			end

			clearState()
			ctx.SetHighlight(nil)
			ctx.UpdateUI()
		end
	end,

	RenderSettings = FaceOrientSettings,
}

return FaceOrient

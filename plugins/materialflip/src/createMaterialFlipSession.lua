--!strict

local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local Src = script.Parent
local Packages = Src.Parent.Packages

local Signal = require(Packages.Signal)

local canFlip = require("./canFlip")
local doFlip = require("./doFlip")
local identifyPart = require("./identifyPart")
local pickRotationFace = require("./pickRotationFace")
local preloadMeshRepresentations = require("./preloadMeshRepresentations")
local Settings = require("./Settings")

export type MaterialFlipSession = {
	ChangeSignal: Signal.Signal<>,
	GetHoverPart: () -> BasePart?,
	GetHoverState: () -> identifyPart.PartState?,
	Update: () -> (),
	Destroy: () -> (),
	TestClick: (part: BasePart, point: Vector3, normal: Vector3) -> BasePart?,
	TestSetHover: (part: BasePart?, point: Vector3?, normal: Vector3?) -> (),
}

local kIndicatorColor = Color3.fromRGB(255, 0, 0)

-- Raycast the mouse into the scene, returning the hit part, hit point, and
-- hit normal. Which bounding box face the click acts on is determined by
-- pickRotationFace from the hit point and normal in the shape's frame.
local function getTarget(): (BasePart?, Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, Vector3.zero, Vector3.yAxis
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.BruteForceAllSlow = true
	raycastParams.CollisionGroup = "StudioSelectable"
	raycastParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 9999, raycastParams)
	if not result then
		return nil, Vector3.zero, Vector3.yAxis
	end

	local hit = result.Instance
	if not hit:IsA("BasePart") then
		return nil, Vector3.zero, Vector3.yAxis
	end

	return hit, result.Position, result.Normal
end

local function createMaterialFlipSession(activeSettings: Settings.MaterialFlipSettings): MaterialFlipSession
	-- Warm the mesh templates and their render content in the background so
	-- the first flip doesn't flicker (one-shot per plugin lifetime)
	preloadMeshRepresentations()

	local function flipOptions(): doFlip.FlipOptions
		return {
			Clockwise = activeSettings.RotateDirection == "Clockwise",
			PreserveAttachments = activeSettings.PreserveAttachments,
			PreserveDecals = activeSettings.PreserveDecals,
			PreservePivot = activeSettings.PreservePivot,
			AllowMeshPartRotation = activeSettings.AllowMeshPartRotation,
		}
	end

	local changeSignal = Signal.new()

	local mHoverPart: BasePart? = nil
	local mHoverState: identifyPart.PartState? = nil
	local mDestroyed = false

	local connections: {RBXScriptConnection} = {}

	local highlight = Instance.new("Highlight")
	highlight.Name = "MaterialFlipHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = (settings().Studio :: any)["Select Color"]
	highlight.Parent = CoreGui

	-- Front face direction indicator: an arrow out of the center of the
	-- hovered part's front face, so you can see the current material
	-- orientation before flipping it
	-- Note: XRay shading via the Shading property; the legacy AlwaysOnTop
	-- property doesn't render at all in this context
	local indicatorShaft = Instance.new("CylinderHandleAdornment")
	indicatorShaft.Name = "MaterialFlipFrontShaft"
	indicatorShaft.Color3 = kIndicatorColor
	indicatorShaft.Shading = Enum.AdornShading.XRay
	indicatorShaft.Parent = CoreGui

	local indicatorCone = Instance.new("ConeHandleAdornment")
	indicatorCone.Name = "MaterialFlipFrontCone"
	indicatorCone.Color3 = kIndicatorColor
	indicatorCone.Shading = Enum.AdornShading.XRay
	indicatorCone.Parent = CoreGui

	-- The label is adorned to Workspace itself, so StudsOffsetWorldSpace is
	-- simply the world space position to show it at (BillboardGui can't be
	-- adorned to a non-parented part; only HandleAdornments can)
	local indicatorLabel = Instance.new("BillboardGui")
	indicatorLabel.Name = "MaterialFlipFrontLabel"
	indicatorLabel.Size = UDim2.fromOffset(60, 18)
	indicatorLabel.AlwaysOnTop = true
	indicatorLabel.Enabled = false
	indicatorLabel.Adornee = workspace
	indicatorLabel.Parent = CoreGui
	local indicatorLabelText = Instance.new("TextLabel")
	indicatorLabelText.BackgroundTransparency = 1
	indicatorLabelText.Size = UDim2.fromScale(1, 1)
	indicatorLabelText.Font = Enum.Font.SourceSansBold
	indicatorLabelText.TextSize = 16
	indicatorLabelText.RichText = true
	indicatorLabelText.TextColor3 = kIndicatorColor
	indicatorLabelText.TextStrokeColor3 = Color3.new(0, 0, 0)
	indicatorLabelText.TextStrokeTransparency = 0.4
	indicatorLabelText.Text = "Front"
	indicatorLabelText.Parent = indicatorLabel

	-- Rotation arc: a circular arrow on the face that a click would rotate,
	-- showing the rotate direction. WireframeHandleAdornment draws in world
	-- space regardless of its adornee, so it's adorned to Terrain and
	-- positioned via its CFrame (world = shape frame).
	local rotationArc = Instance.new("WireframeHandleAdornment")
	rotationArc.Name = "MaterialFlipRotationArc"
	rotationArc.Color3 = kIndicatorColor
	rotationArc.Thickness = 3
	rotationArc.Adornee = workspace.Terrain
	rotationArc.Parent = CoreGui

	local mArcKey = ""

	local function clearRotationArc()
		if mArcKey ~= "" then
			mArcKey = ""
			rotationArc:Clear()
		end
	end

	local function updateRotationArc(worldPoint: Vector3?, worldNormal: Vector3?)
		local state = mHoverState
		if not state or not worldPoint or not worldNormal then
			clearRotationArc()
			return
		end
		assert(state and worldPoint and worldNormal)

		local face = pickRotationFace(state, worldPoint, worldNormal)
		local clockwise = activeSettings.RotateDirection == "Clockwise"
		local key = string.format("%s|%s|%s|%s",
			face.Name, tostring(clockwise), tostring(state.ShapeSize), tostring(state.ShapeCFrame))
		if key == mArcKey then
			return
		end
		mArcKey = key

		rotationArc:Clear()

		-- WireframeHandleAdornment uses only the vertex positions, in world
		-- space (its Adornee and CFrame don't transform them), so the arc is
		-- built in shape space and each point mapped through the shape frame.
		local function toWorld(p: Vector3): Vector3
			return state.ShapeCFrame:PointToWorldSpace(p)
		end

		-- Face plane basis: (u, v, n) right handed, so increasing angle is
		-- counterclockwise as seen from outside the face
		local n = Vector3.fromNormalId(face)
		local u = if math.abs(n.Y) > 0.5 then Vector3.zAxis else Vector3.yAxis
		local v = n:Cross(u).Unit
		u = v:Cross(n)

		local half = state.ShapeSize / 2
		local center = n * ((half * n):Dot(n) + 0.05)
		local sizeU = (state.ShapeSize * u):Dot(u)
		local sizeV = (state.ShapeSize * v):Dot(v)
		local radius = math.clamp(0.35 * math.min(sizeU, sizeV), 0.2, 5)
		local dirSign = if clockwise then -1 else 1

		local points = {}
		-- Offset 180 degrees so the arc's open side aligns with the front
		-- face arrow rather than pointing away from it
		local startDeg, endDeg = 200, 480
		for deg = startDeg, endDeg, 14 do
			local theta = math.rad(deg * dirSign)
			table.insert(points, toWorld(center + radius * (math.cos(theta) * u + math.sin(theta) * v)))
		end
		rotationArc:AddPath(points, false)

		-- Arrowhead at the end of the arc
		local thetaEnd = math.rad(endDeg * dirSign)
		local radial = math.cos(thetaEnd) * u + math.sin(thetaEnd) * v
		local tangent = dirSign * (-math.sin(thetaEnd) * u + math.cos(thetaEnd) * v)
		local tip = center + radius * radial
		local headLen = radius * 0.35
		rotationArc:AddLine(toWorld(tip), toWorld(tip - tangent * headLen + radial * headLen * 0.5))
		rotationArc:AddLine(toWorld(tip), toWorld(tip - tangent * headLen - radial * headLen * 0.5))
	end

	-- Sized/positioned from the hovered part every frame since flips can
	-- change the part's size while it stays hovered
	local function updateFrontIndicator()
		local part = mHoverPart
		if not part then
			indicatorShaft.Adornee = nil
			indicatorCone.Adornee = nil
			indicatorLabel.Enabled = false
			return
		end
		assert(part)
		local size = part.Size
		local length = math.clamp(math.min(size.X, size.Y, size.Z) * 0.75, 1.5, 6)
		local coneLength = length * 0.45
		local shaftLength = length - coneLength
		local halfZ = size.Z / 2
		-- Adornment CFrames are in the adornee's local space. The cylinder is
		-- centered on its CFrame; the cone's base is at its CFrame with the
		-- apex extending along its local -Z (verified empirically), which for
		-- an identity rotation is exactly out the part's front face.
		indicatorShaft.Height = shaftLength
		indicatorShaft.Radius = math.clamp(length * 0.05, 0.05, 0.25)
		indicatorShaft.CFrame = CFrame.new(0, 0, -(halfZ + shaftLength / 2))
		indicatorCone.Height = coneLength
		indicatorCone.Radius = math.clamp(length * 0.14, 0.12, 0.7)
		indicatorCone.CFrame = CFrame.new(0, 0, -(halfZ + shaftLength))
		indicatorLabel.StudsOffsetWorldSpace = (part.CFrame * CFrame.new(0, 0, -(halfZ + length + 0.7))).Position
		-- Warn on the label when the part is only approximated as a box (CSG
		-- rotatable parts rotate correctly when the setting allows it)
		local state = mHoverState
		local approximated = state ~= nil and (state :: identifyPart.PartState).ApproximatedAsBox
			and not (activeSettings.AllowMeshPartRotation and (state :: identifyPart.PartState).CsgRotatable)
		if approximated then
			indicatorLabelText.Text = "Front\n<font color=\"#FF8C00\">\u{26A0} Non-primitive</font>"
			indicatorLabel.Size = UDim2.fromOffset(110, 36)
		else
			indicatorLabelText.Text = "Front"
			indicatorLabel.Size = UDim2.fromOffset(60, 18)
		end
		indicatorShaft.Adornee = part
		indicatorCone.Adornee = part
		indicatorLabel.Enabled = true
	end

	local function setHoverPart(part: BasePart?)
		local changed = part ~= mHoverPart
		mHoverPart = part
		-- Recomputed even for the same part: in-place flips change its state
		mHoverState = if part then identifyPart(part) else nil
		if changed then
			highlight.Adornee = part
			changeSignal:Fire()
		end
		updateFrontIndicator()
	end

	local function updateHover()
		local hit, at, normal = getTarget()
		if hit and canFlip(hit, activeSettings.TargetLocked) then
			setHoverPart(hit)
			updateRotationArc(at, normal)
		else
			setHoverPart(nil)
			updateRotationArc(nil)
		end
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if mDestroyed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit, at, normal = getTarget()
			if hit and canFlip(hit, activeSettings.TargetLocked) then
				local result = doFlip(hit, at, normal, flipOptions())
				if result then
					setHoverPart(result)
				end
			end
		end
	end))

	-- Track the hover target every frame rather than only on mouse movement,
	-- because camera movement changes the target without moving the mouse.
	local hoverThread = task.spawn(function()
		while not mDestroyed do
			updateHover()
			task.wait()
		end
	end)

	local session: MaterialFlipSession = {
		ChangeSignal = changeSignal,
		GetHoverPart = function()
			return mHoverPart
		end,
		GetHoverState = function()
			return mHoverState
		end,
		Update = function()
			-- Called when settings change, nothing to do currently
		end,
		Destroy = function()
			mDestroyed = true
			for _, cn in connections do
				cn:Disconnect()
			end
			table.clear(connections)
			task.cancel(hoverThread)
			highlight:Destroy()
			indicatorShaft:Destroy()
			indicatorCone:Destroy()
			indicatorLabel:Destroy()
			rotationArc:Destroy()
			mHoverPart = nil
		end,
		TestClick = function(part: BasePart, point: Vector3, normal: Vector3): BasePart?
			if canFlip(part, activeSettings.TargetLocked) then
				return doFlip(part, point, normal, flipOptions())
			end
			return nil
		end,
		TestSetHover = function(part: BasePart?, point: Vector3?, normal: Vector3?)
			setHoverPart(part)
			updateRotationArc(point, normal)
		end,
	}
	return session
end

return createMaterialFlipSession

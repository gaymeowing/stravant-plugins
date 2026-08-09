--!strict

local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local Src = script.Parent
local Packages = Src.Parent.Packages

local Signal = require(Packages.Signal)

local canFlip = require("./canFlip")
local doFlip = require("./doFlip")
local Settings = require("./Settings")

export type MaterialFlipSession = {
	ChangeSignal: Signal.Signal<>,
	GetHoverPart: () -> BasePart?,
	Update: () -> (),
	Destroy: () -> (),
	TestClick: (part: BasePart, point: Vector3) -> BasePart?,
	TestSetHover: (part: BasePart?) -> (),
}

local kIndicatorColor = Color3.fromRGB(255, 140, 0)

-- Raycast the mouse into the scene, returning the hit part and hit point.
-- Which bounding box face the click acts on is determined by doFlip from the
-- hit point, in the shape's frame (not the raw hit surface, which matters
-- for curved and mesh-represented parts).
local function getTarget(): (BasePart?, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, Vector3.zero
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
		return nil, Vector3.zero
	end

	local hit = result.Instance
	if not hit:IsA("BasePart") then
		return nil, Vector3.zero
	end

	return hit, result.Position
end

local function createMaterialFlipSession(activeSettings: Settings.MaterialFlipSettings): MaterialFlipSession
	local changeSignal = Signal.new()

	local mHoverPart: BasePart? = nil
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
	-- Note: no AlwaysOnTop - HandleAdornments with it set don't render in
	-- this context, and the arrow extends outside the part anyway
	local indicatorShaft = Instance.new("CylinderHandleAdornment")
	indicatorShaft.Name = "MaterialFlipFrontShaft"
	indicatorShaft.Color3 = kIndicatorColor
	indicatorShaft.Parent = CoreGui

	local indicatorCone = Instance.new("ConeHandleAdornment")
	indicatorCone.Name = "MaterialFlipFrontCone"
	indicatorCone.Color3 = kIndicatorColor
	indicatorCone.Parent = CoreGui

	-- The label is adorned to Workspace itself, so StudsOffset is simply the
	-- world space position to show it at (BillboardGui can't be adorned to a
	-- non-parented part; only HandleAdornments can)
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
	indicatorLabelText.TextColor3 = kIndicatorColor
	indicatorLabelText.TextStrokeColor3 = Color3.new(0, 0, 0)
	indicatorLabelText.TextStrokeTransparency = 0.4
	indicatorLabelText.Text = "Front"
	indicatorLabelText.Parent = indicatorLabel

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
		indicatorLabel.StudsOffset = (part.CFrame * CFrame.new(0, 0, -(halfZ + length + 0.7))).Position
		indicatorShaft.Adornee = part
		indicatorCone.Adornee = part
		indicatorLabel.Enabled = true
	end

	local function setHoverPart(part: BasePart?)
		if part ~= mHoverPart then
			mHoverPart = part
			highlight.Adornee = part
			changeSignal:Fire()
		end
		updateFrontIndicator()
	end

	local function updateHover()
		local hit = getTarget()
		setHoverPart(if hit and canFlip(hit) then hit else nil)
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if mDestroyed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit, at = getTarget()
			if hit and canFlip(hit) then
				local result = doFlip(hit, at, activeSettings.RotateDirection == "Clockwise")
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
			mHoverPart = nil
		end,
		TestClick = function(part: BasePart, point: Vector3): BasePart?
			if canFlip(part) then
				return doFlip(part, point, activeSettings.RotateDirection == "Clockwise")
			end
			return nil
		end,
		TestSetHover = function(part: BasePart?)
			setHoverPart(part)
		end,
	}
	return session
end

return createMaterialFlipSession

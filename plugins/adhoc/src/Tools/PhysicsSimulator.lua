--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local SubPanel = require("../PluginGui/SubPanel")
local NumberInput = require("../PluginGui/NumberInput")
local ChipForToggle = require("../PluginGui/ChipForToggle")
local OperationButton = require("../PluginGui/OperationButton")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type EmitterData = {
	Type: string,
	Magnitude: number,
	Position: Vector3,
	Direction: Vector3, -- surface normal at placement
	PulsePeriod: number, -- period in seconds (only used by Pulse type)
	Part: BasePart, -- visualization sphere
}

type SimState = "stopped" | "running" | "paused"

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local kForceTypes = { "Wind", "Explosion", "Pulse", "Magnet" }

local kEmitterColor: { [string]: Color3 } = {
	Wind = Color3.fromRGB(100, 200, 255),
	Explosion = Color3.fromRGB(255, 100, 50),
	Pulse = Color3.fromRGB(255, 200, 50),
	Magnet = Color3.fromRGB(180, 50, 255),
}

local kHighlightRunning = Color3.fromRGB(0, 200, 50)
local kHighlightPaused = Color3.fromRGB(220, 200, 0)

--------------------------------------------------------------------------------
-- Mutable State
--------------------------------------------------------------------------------

local mSimState: SimState = "stopped"
local mSimConnection: RBXScriptConnection? = nil
local mRecordingId: string? = nil
local mSimulatedParts: { BasePart } = {}
local mOriginalAnchored: { [BasePart]: boolean } = {}
local mHighlights: { [BasePart]: Highlight } = {}
local mEmitters: { EmitterData } = {}
local mEmitterFolder: Folder? = nil
local mAttachments: { [BasePart]: Attachment } = {}
local mVectorForces: { [BasePart]: VectorForce } = {}
local mCtx: ToolContext? = nil
local mUpdateUI: (() -> ())? = nil
local mSimElapsed = 0
local mSelectionConnection: RBXScriptConnection? = nil
local mVelocityArrows: { [BasePart]: ConeHandleAdornment } = {}

-- Drag-while-paused state
local mDragPart: BasePart? = nil
local mDragPlaneNormal: Vector3 = Vector3.zAxis
local mDragPlanePoint: Vector3 = Vector3.zero
local mDragPartOffset: Vector3 = Vector3.zero

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getRayFromMouse(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	return ray.Origin, ray.Direction
end

local function rayPlaneIntersect(
	rayOrigin: Vector3, rayDir: Vector3,
	planePoint: Vector3, planeNormal: Vector3
): Vector3?
	local denom = rayDir:Dot(planeNormal)
	if math.abs(denom) < 0.0001 then
		return nil
	end
	local t = (planePoint - rayOrigin):Dot(planeNormal) / denom
	if t < 0 then
		return nil
	end
	return rayOrigin + rayDir * t
end

local function isSimulatedPart(part: BasePart): boolean
	for _, p in mSimulatedParts do
		if p == part then
			return true
		end
	end
	return false
end

local function raycastFromMouse(): (Vector3?, Vector3?, BasePart?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { mEmitterFolder :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
	if result and result.Instance:IsA("BasePart") then
		return result.Position, result.Normal, result.Instance
	end
	return nil, nil, nil
end

local function createEmitterVisual(emitter: EmitterData): BasePart
	local part = Instance.new("Part")
	part.Name = "PhysicsEmitter_" .. emitter.Type
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Position = emitter.Position
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.5
	part.Color = kEmitterColor[emitter.Type] or Colors.WHITE
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Locked = true

	-- Arrow showing direction (for Wind type)
	if emitter.Type == "Wind" then
		local arrow = Instance.new("ConeHandleAdornment")
		arrow.Adornee = part
		arrow.Color3 = kEmitterColor[emitter.Type]
		arrow.Height = 3
		arrow.Radius = 0.5
		arrow.CFrame = CFrame.lookAt(Vector3.zero, emitter.Direction) * CFrame.new(0, 0, -2.5)
		arrow.AlwaysOnTop = true
		arrow.Parent = part
	end

	-- Label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(100, 24)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.TextColor3 = kEmitterColor[emitter.Type] or Colors.WHITE
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 14
	label.TextScaled = false
	label.Text = string.format("%s (%g)", emitter.Type, emitter.Magnitude)
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label

	return part
end

local function getSelectedBaseParts(): { BasePart }
	local parts: { BasePart } = {}
	for _, obj in Selection:Get() do
		if obj:IsA("BasePart") then
			table.insert(parts, obj)
		elseif obj:IsA("Model") then
			for _, desc in obj:GetDescendants() do
				if desc:IsA("BasePart") then
					table.insert(parts, desc)
				end
			end
		end
	end
	return parts
end

local function hasSelectedBaseParts(): boolean
	for _, obj in Selection:Get() do
		if obj:IsA("BasePart") then
			return true
		elseif obj:IsA("Model") then
			for _, desc in obj:GetDescendants() do
				if desc:IsA("BasePart") then
					return true
				end
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Simulation Lifecycle
--------------------------------------------------------------------------------

local function cleanupForces()
	for part, attachment in mAttachments do
		attachment:Destroy()
	end
	mAttachments = {}
	for part, vf in mVectorForces do
		vf:Destroy()
	end
	mVectorForces = {}
end

local function cleanupHighlights()
	for _, highlight in mHighlights do
		highlight:Destroy()
	end
	mHighlights = {}
	for _, arrow in mVelocityArrows do
		arrow:Destroy()
	end
	mVelocityArrows = {}
end

local function setHighlightColor(color: Color3)
	for _, highlight in mHighlights do
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end

local function setupHighlights()
	cleanupHighlights()
	local color = if mSimState == "running" then kHighlightRunning else kHighlightPaused
	for _, part in mSimulatedParts do
		if part.Parent then
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.7
			highlight.OutlineTransparency = 0
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.Adornee = part
			highlight.Parent = part
			mHighlights[part] = highlight

			-- Velocity arrow
			local arrow = Instance.new("ConeHandleAdornment")
			arrow.Adornee = part
			arrow.Color3 = Color3.fromRGB(0, 200, 255)
			arrow.Radius = 0.3
			arrow.Height = 0
			arrow.AlwaysOnTop = true
			arrow.Transparency = 0.3
			arrow.Parent = part
			mVelocityArrows[part] = arrow
		end
	end
end

local function updateVelocityArrows()
	for part, arrow in mVelocityArrows do
		if part.Parent and arrow.Parent then
			local velocity = part.AssemblyLinearVelocity
			local speed = velocity.Magnitude
			if speed > 0.1 then
				local dir = velocity.Unit
				local len = math.min(speed * 0.15, 20)
				arrow.Height = len
				arrow.Radius = math.clamp(len * 0.15, 0.2, 0.6)
				arrow.CFrame = CFrame.lookAt(Vector3.zero, dir) * CFrame.new(0, 0, -len / 2 - 0.5)
				arrow.Visible = true
			else
				arrow.Visible = false
			end
		end
	end
end

local function setupForces()
	cleanupForces()
	for _, part in mSimulatedParts do
		if part.Parent then
			local attachment = Instance.new("Attachment")
			attachment.Parent = part
			mAttachments[part] = attachment

			local vf = Instance.new("VectorForce")
			vf.Attachment0 = attachment
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.ApplyAtCenterOfMass = true
			vf.Force = Vector3.zero
			vf.Parent = part
			mVectorForces[part] = vf
		end
	end
end

local function computeForce(part: BasePart, elapsed: number): Vector3
	local partPos = part.Position
	local totalForce = Vector3.zero

	for _, emitter in mEmitters do
		local emitterPos = emitter.Position
		local magnitude = emitter.Magnitude

		if emitter.Type == "Wind" then
			totalForce += emitter.Direction * magnitude
		elseif emitter.Type == "Explosion" then
			local delta = partPos - emitterPos
			local distSq = delta.Magnitude ^ 2
			if delta.Magnitude > 0.001 then
				totalForce += delta.Unit * magnitude / math.max(distSq, 1)
			end
		elseif emitter.Type == "Pulse" then
			-- Smooth periodic pulse: sin²(π * t / period) gives 0→1→0 per period
			local period = emitter.PulsePeriod
			local pulse = math.sin(math.pi * elapsed / period) ^ 2
			local delta = partPos - emitterPos
			local distSq = delta.Magnitude ^ 2
			if delta.Magnitude > 0.001 then
				totalForce += delta.Unit * magnitude * pulse / math.max(distSq, 1)
			end
		elseif emitter.Type == "Magnet" then
			local delta = emitterPos - partPos
			local distSq = delta.Magnitude ^ 2
			if delta.Magnitude > 0.001 then
				totalForce += delta.Unit * magnitude / math.max(distSq, 1)
			end
		end
	end

	return totalForce
end

local function startSimulation(ctx: ToolContext)
	if mSimState ~= "stopped" then
		return
	end

	local parts = getSelectedBaseParts()
	if #parts == 0 then
		return
	end

	-- Begin undo recording (fall back to SetWaypoint if TryBeginRecording fails)
	mRecordingId = ctx.BeginRecording("Physics Simulation")

	-- Capture parts and original anchored state
	mSimulatedParts = parts
	mOriginalAnchored = {}
	for _, part in parts do
		mOriginalAnchored[part] = part.Anchored
		part.Anchored = false
	end

	mSimElapsed = 0
	mSimState = "running"

	-- Setup visual feedback and forces
	setupHighlights()
	setupForces()

	-- Start simulation loop
	local speed = (ctx.GetSetting("Speed") :: number?) or 1
	mSimConnection = RunService.RenderStepped:Connect(function(dt: number)
		if mSimState ~= "running" then
			return
		end

		-- Re-read speed each frame in case it changed
		if mCtx then
			speed = (mCtx.GetSetting("Speed") :: number?) or 1
		end

		if speed <= 0 then
			return
		end

		-- Filter out parts that were deleted during simulation
		local validParts: { BasePart } = {}
		for _, part in mSimulatedParts do
			if part.Parent then
				table.insert(validParts, part)
			end
		end
		mSimulatedParts = validParts

		local simDt = dt * speed
		mSimElapsed += simDt

		-- Apply forces
		for _, part in mSimulatedParts do
			local vf = mVectorForces[part]
			if vf and vf.Parent then
				vf.Force = computeForce(part, mSimElapsed)
			end
		end

		-- Update Pulse emitter visuals
		for _, emitter in mEmitters do
			if emitter.Type == "Pulse" then
				local pulse = math.sin(math.pi * mSimElapsed / emitter.PulsePeriod) ^ 2
				local visPart = emitter.Part
				local scale = 2 + pulse * 1.5
				visPart.Size = Vector3.new(scale, scale, scale)
				visPart.Transparency = 0.7 - pulse * 0.5
			end
		end

		-- Step physics
		workspace:StepPhysics(dt * speed, mSimulatedParts)

		-- Update velocity arrows
		updateVelocityArrows()
	end)

	if mUpdateUI then
		mUpdateUI()
	end
end

local function pauseSimulation()
	if mSimState ~= "running" then
		return
	end
	mSimState = "paused"

	-- Re-anchor parts while paused so they don't fall
	for _, part in mSimulatedParts do
		if part.Parent then
			part.Anchored = true
		end
	end

	setHighlightColor(kHighlightPaused)

	if mUpdateUI then
		mUpdateUI()
	end
end

local function resumeSimulation()
	if mSimState ~= "paused" then
		return
	end
	mSimState = "running"
	mDragPart = nil

	-- Unanchor parts again
	for _, part in mSimulatedParts do
		if part.Parent then
			part.Anchored = false
		end
	end

	setHighlightColor(kHighlightRunning)

	if mUpdateUI then
		mUpdateUI()
	end
end

local function stopSimulation()
	if mSimState == "stopped" then
		return
	end

	-- Disconnect simulation loop
	if mSimConnection then
		mSimConnection:Disconnect()
		mSimConnection = nil
	end

	-- Restore original anchored state
	for part, wasAnchored in mOriginalAnchored do
		if part.Parent then
			part.Anchored = wasAnchored
		end
	end
	mOriginalAnchored = {}

	-- Clean up forces and highlights
	cleanupForces()
	cleanupHighlights()

	-- Finish recording
	if mRecordingId then
		local ctx = mCtx
		if ctx then
			ctx.FinishRecording(mRecordingId)
		end
		mRecordingId = nil
	else
		ChangeHistoryService:SetWaypoint("Physics Simulation")
	end

	mSimulatedParts = {}
	mSimElapsed = 0
	mSimState = "stopped"

	if mUpdateUI then
		mUpdateUI()
	end
end

local function clearEmitters()
	for _, emitter in mEmitters do
		emitter.Part:Destroy()
	end
	mEmitters = {}
	if mUpdateUI then
		mUpdateUI()
	end
end

local function removeEmitter(index: number)
	local emitter = mEmitters[index]
	if emitter then
		emitter.Part:Destroy()
		table.remove(mEmitters, index)
	end
	if mUpdateUI then
		mUpdateUI()
	end
end

local function placeEmitter(ctx: ToolContext)
	local folder = mEmitterFolder
	if not folder then
		return
	end

	-- Do our own raycast to get the actual hit position
	local hitPos, hitNormal, hitPart = raycastFromMouse()
	if not hitPos or not hitNormal or not hitPart then
		return
	end

	local forceType = (ctx.GetSetting("ForceType") :: string?) or "Wind"
	local magnitude = (ctx.GetSetting("Magnitude") :: number?) or 100
	local pulsePeriod = (ctx.GetSetting("PulsePeriod") :: number?) or 1

	local position = hitPos

	local emitter: EmitterData = {
		Type = forceType,
		Magnitude = magnitude,
		Position = position,
		Direction = hitNormal,
		PulsePeriod = pulsePeriod,
		Part = nil :: any,
	}

	local visPart = createEmitterVisual(emitter)
	visPart.Parent = folder
	emitter.Part = visPart

	table.insert(mEmitters, emitter)

	if mUpdateUI then
		mUpdateUI()
	end
end

--------------------------------------------------------------------------------
-- UI Components
--------------------------------------------------------------------------------

local function EmitterRow(props: {
	Index: number,
	Type: string,
	Magnitude: number,
	PulsePeriod: number?,
	OnRemove: () -> (),
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Colors.GREY,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 4),
		}),
		ColorChip = e("Frame", {
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = kEmitterColor[props.Type] or Colors.WHITE,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Label = e("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = if props.Type == "Pulse" and props.PulsePeriod
				then string.format("%s (%g, %gs)", props.Type, props.Magnitude, props.PulsePeriod)
				else string.format("%s (%g)", props.Type, props.Magnitude),
			TextColor3 = Colors.WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			LayoutOrder = 2,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		RemoveButton = e("TextButton", {
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Color3.fromRGB(180, 40, 40),
			AutoButtonColor = true,
			Text = "X",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 12,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = props.OnRemove,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

local function PhysicsSimulatorSettings(props: ToolSettingsProps)
	local forceType = (props.GetSetting("ForceType") :: string?) or "Wind"
	local magnitude = (props.GetSetting("Magnitude") :: number?) or 100
	local pulsePeriod = (props.GetSetting("PulsePeriod") :: number?) or 1
	local speed = (props.GetSetting("Speed") :: number?) or 1

	-- Track selection state for enabling/disabling Start, and auto-set magnitude
	local hasSelection, setHasSelection = React.useState(hasSelectedBaseParts)
	React.useEffect(function()
		local function onSelectionChanged()
			setHasSelection(hasSelectedBaseParts())
			-- Auto-set magnitude based on total assembly mass while stopped
			if mSimState == "stopped" then
				local parts = getSelectedBaseParts()
				local totalMass = 0
				for _, part in parts do
					totalMass += part.AssemblyMass
				end
				if totalMass > 0 then
					local suggestedMagnitude = math.ceil(totalMass * workspace.Gravity * 5)
					props.SetSetting("Magnitude", suggestedMagnitude)
				end
			end
		end
		local cn = Selection.SelectionChanged:Connect(onSelectionChanged)
		onSelectionChanged()
		return function()
			cn:Disconnect()
		end
	end, {})

	-- Status text
	local statusText: string
	local statusColor: Color3
	if mSimState == "stopped" then
		statusText = "Stopped"
		statusColor = Colors.OFFWHITE
	elseif mSimState == "running" then
		statusText = string.format("Running %d part%s", #mSimulatedParts, if #mSimulatedParts == 1 then "" else "s")
		statusColor = kHighlightRunning
	else
		statusText = string.format("Paused %d part%s", #mSimulatedParts, if #mSimulatedParts == 1 then "" else "s")
		statusColor = kHighlightPaused
	end

	-- Build emitter list children
	local emitterChildren: { [string]: any } = {}
	emitterChildren.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
	})

	for i, emitter in mEmitters do
		local index = i -- capture for closure
		emitterChildren["Emitter" .. i] = e(EmitterRow, {
			Index = i,
			Type = emitter.Type,
			Magnitude = emitter.Magnitude,
			PulsePeriod = if emitter.Type == "Pulse" then emitter.PulsePeriod else nil,
			OnRemove = function()
				removeEmitter(index)
			end,
			LayoutOrder = i,
		})
	end

	-- Force type chips (2x2 grid)
	local forceTypeChildren: { [string]: any } = {}
	forceTypeChildren.GridLayout = e("UIGridLayout", {
		CellSize = UDim2.new(0.5, -2, 0, 24),
		CellPadding = UDim2.fromOffset(3, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for i, ft in kForceTypes do
		forceTypeChildren[ft] = e(ChipForToggle, {
			Text = ft,
			IsCurrent = forceType == ft,
			LayoutOrder = i,
			OnClick = function()
				props.SetSetting("ForceType", ft)
			end,
		})
	end

	local canStart = mSimState == "stopped" and hasSelection
	local canResume = mSimState == "paused"
	local canPause = mSimState == "running"
	local canStop = mSimState ~= "stopped"

	-- Button row children
	local buttonChildren: { [string]: any } = {}
	buttonChildren.ListLayout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	if mSimState == "paused" then
		buttonChildren.Resume = e("TextButton", {
			Size = UDim2.new(0, 0, 0, 30),
			BackgroundColor3 = kHighlightRunning,
			AutoButtonColor = true,
			Text = "Resume",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			LayoutOrder = 1,
			[React.Event.MouseButton1Click] = function()
				resumeSimulation()
			end,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Grow }),
		})
	else
		local startColor = if canStart then kHighlightRunning else kHighlightRunning:Lerp(Colors.DISABLED_GREY, 0.5)
		buttonChildren.Start = e("TextButton", {
			Size = UDim2.new(0, 0, 0, 30),
			BackgroundColor3 = startColor,
			AutoButtonColor = canStart,
			Text = "Start",
			TextColor3 = if canStart then Colors.WHITE else Colors.WHITE:Lerp(Colors.DISABLED_GREY, 0.5),
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			LayoutOrder = 1,
			[React.Event.MouseButton1Click] = if canStart then function()
				if mCtx then
					startSimulation(mCtx)
				end
			end else nil,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Grow }),
		})
	end

	local pauseColor = if canPause then kHighlightPaused else kHighlightPaused:Lerp(Colors.DISABLED_GREY, 0.5)
	buttonChildren.Pause = e("TextButton", {
		Size = UDim2.new(0, 0, 0, 30),
		BackgroundColor3 = pauseColor,
		AutoButtonColor = canPause,
		Text = "Pause",
		TextColor3 = if canPause then Colors.WHITE else Colors.WHITE:Lerp(Colors.DISABLED_GREY, 0.5),
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		LayoutOrder = 2,
		[React.Event.MouseButton1Click] = if canPause then function()
			pauseSimulation()
		end else nil,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Grow }),
	})

	local stopColor = if canStop then Colors.DARK_RED else Colors.DARK_RED:Lerp(Colors.DISABLED_GREY, 0.5)
	buttonChildren.Stop = e("TextButton", {
		Size = UDim2.new(0, 0, 0, 30),
		BackgroundColor3 = stopColor,
		AutoButtonColor = canStop,
		Text = "Stop",
		TextColor3 = if canStop then Colors.WHITE else Colors.WHITE:Lerp(Colors.DISABLED_GREY, 0.5),
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		LayoutOrder = 3,
		[React.Event.MouseButton1Click] = if canStop then function()
			stopSimulation()
		end else nil,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Grow }),
	})

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		-- Simulation panel
		SimPanel = e(SubPanel, {
			Title = "Simulation",
			Padding = UDim.new(0, 4),
			LayoutOrder = 1,
		}, {
			Status = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = statusText,
				TextColor3 = statusColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.SourceSansBold,
				TextSize = 16,
				LayoutOrder = 1,
			}),
			Speed = e(NumberInput, {
				Label = "Speed",
				Value = speed,
				ValueEntered = function(newValue: number)
					newValue = math.clamp(newValue, 0, 100)
					props.SetSetting("Speed", newValue)
					return newValue
				end,
				LayoutOrder = 2,
			}),
			Buttons = e("Frame", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, buttonChildren),
			Hint = mSimState == "stopped" and not hasSelection and e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text = "Select parts to simulate",
				TextColor3 = Colors.OFFWHITE,
				Font = Enum.Font.SourceSansItalic,
				TextSize = 13,
				LayoutOrder = 4,
			}),
		}),

		-- Forces panel
		ForcesPanel = e(SubPanel, {
			Title = "Forces",
			Padding = UDim.new(0, 4),
			LayoutOrder = 2,
		}, {
			ForceTypeRow = e("Frame", {
				Size = UDim2.new(1, 0, 0, 51),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, forceTypeChildren),
			Magnitude = e(NumberInput, {
				Label = "Magnitude",
				Value = magnitude,
				ValueEntered = function(newValue: number)
					newValue = math.max(newValue, 0)
					props.SetSetting("Magnitude", newValue)
					return newValue
				end,
				LayoutOrder = 2,
			}),
			PulsePeriod = forceType == "Pulse" and e(NumberInput, {
				Label = "Period",
				Value = pulsePeriod,
				Unit = "s",
				ValueEntered = function(newValue: number)
					newValue = math.max(newValue, 0.05)
					props.SetSetting("PulsePeriod", newValue)
					return newValue
				end,
				LayoutOrder = 3,
			}),
			PlaceHint = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Text = "Click a surface to place an emitter",
				TextColor3 = Colors.OFFWHITE,
				Font = Enum.Font.SourceSansItalic,
				TextSize = 13,
				LayoutOrder = 4,
			}),
			EmitterList = #mEmitters > 0 and e("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 5,
			}, emitterChildren),
			ClearAll = #mEmitters > 0 and e(OperationButton, {
				Text = "Clear All Emitters",
				Height = 28,
				Disabled = false,
				Color = Colors.DARK_RED,
				LayoutOrder = 6,
				OnClick = function()
					clearEmitters()
				end,
			}),
		}),
	})
end

--------------------------------------------------------------------------------
-- Tool Definition
--------------------------------------------------------------------------------

local PhysicsSimulator: ToolTypes.ToolDefinition = {
	Id = "physicsSimulator",
	Name = "Physics Simulator",
	Description = "Simulate physics with placeable force emitters",

	DefaultSettings = {
		ForceType = "Wind",
		Magnitude = 100,
		Speed = 1,
		PulsePeriod = 1,
	},

	OnActivated = function(ctx: ToolContext)
		mCtx = ctx
		mUpdateUI = ctx.UpdateUI

		-- Create emitter container folder
		local folder = Instance.new("Folder")
		folder.Name = "PhysicsSimulatorEmitters"
		folder.Parent = workspace
		mEmitterFolder = folder
	end,

	OnDeactivated = function(ctx: ToolContext)
		-- Stop simulation if running
		stopSimulation()

		-- Clear all emitters
		clearEmitters()

		-- Destroy emitter folder
		if mEmitterFolder then
			mEmitterFolder:Destroy()
			mEmitterFolder = nil
		end

		-- Disconnect selection tracking
		if mSelectionConnection then
			mSelectionConnection:Disconnect()
			mSelectionConnection = nil
		end

		ctx.SetHighlight(nil)
		mCtx = nil
		mUpdateUI = nil
	end,

	OnViewChanged = function(ctx: ToolContext)
		if mSimState == "stopped" then
			ctx.SetHighlight(ctx.Target)
		elseif mSimState == "paused" and mDragPart then
			-- Drag part on view plane
			local camera = workspace.CurrentCamera
			if camera then
				local rayOrigin, rayDir = getRayFromMouse()
				local hit = rayPlaneIntersect(rayOrigin, rayDir * 10000, mDragPlanePoint, mDragPlaneNormal)
				if hit then
					mDragPart.Position = hit + mDragPartOffset
				end
			end
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if mSimState == "paused" then
			-- Check if clicking a simulated part to drag it
			local hitPos, hitNormal, hitPart = raycastFromMouse()
			if hitPart and isSimulatedPart(hitPart) then
				local camera = workspace.CurrentCamera
				if camera and hitPos then
					mDragPart = hitPart
					mDragPlaneNormal = camera.CFrame.LookVector
					mDragPlanePoint = hitPart.Position
					mDragPartOffset = hitPart.Position - hitPos
				end
				return
			end
		end
		placeEmitter(ctx)
	end,

	OnReleased = function(ctx: ToolContext)
		if mDragPart then
			mDragPart = nil
		end
	end,

	RenderSettings = PhysicsSimulatorSettings,
}

return PhysicsSimulator

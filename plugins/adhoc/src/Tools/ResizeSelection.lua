--!strict
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local PluginRoot = script.Parent.Parent.Parent
local Packages = PluginRoot.Packages
local Signal = require(Packages.Signal)

local ToolTypes = require("../ToolTypes")

-- Dragger dependencies (loaded lazily on first use)
local Roact: any = nil
local DraggerSchemaCore: any = nil
local DraggerContext_PluginImpl: any = nil
local DraggerToolComponent: any = nil
local ResizeHandles: any = nil

local function ensureDraggerLoaded()
	if Roact then return end
	Roact = require(Packages.Roact)
	local DraggerFramework = require(Packages.DraggerFramework)
	DraggerSchemaCore = require(Packages.DraggerSchemaCore)
	DraggerContext_PluginImpl = (require :: any)(DraggerFramework.Implementation.DraggerContext_PluginImpl)
	DraggerToolComponent = (require :: any)(DraggerFramework.DraggerTools.DraggerToolComponent)
	ResizeHandles = require(script.Parent.Parent.Dragger.ResizeHandles)
end

-- Dragger session state
local mDraggerHandle: any = nil
local mSelectionCn: RBXScriptConnection? = nil
local mUndoCn: RBXScriptConnection? = nil
local mRedoCn: RBXScriptConnection? = nil
local mFirstPart: BasePart? = nil
local mStartSizes: { [BasePart]: Vector3 } = {}
local mStartCFrames: { [BasePart]: CFrame } = {}
local mRecordingId: string? = nil

local function createDraggerSchema(getBoundingBoxFunc: () -> (CFrame, Vector3, Vector3))
	local schema = table.clone(DraggerSchemaCore)
	schema.getMouseTarget = function()
		return nil
	end
	schema.addUndoWaypoint = function()
		-- Noop: we manage our own undo recordings per drag
	end
	schema.SelectionInfo = {
		new = function(_context: any, _selection: any)
			return {
				isEmpty = function(_self: any)
					return mFirstPart == nil
				end,
				getBoundingBox = function(_self: any)
					return getBoundingBoxFunc()
				end,
				getAllAttachments = function(_self: any)
					return {}
				end,
				getObjectsToTransform = function(_self: any)
					return {}, {}, {}
				end,
				getBasisObject = function(_self: any)
					return nil
				end,
				getOriginalCFrameMap = function(_self: any)
					return {}
				end,
				getTransformedCopy = function(_self: any, _globalTransform: any)
					return _self
				end,
			}
		end,
	} :: any
	return schema
end

-- Find the first BasePart in the selection (descending into Models)
local function getFirstBasePart(): BasePart?
	for _, inst in Selection:Get() do
		if inst:IsA("BasePart") then
			return inst
		elseif inst:IsA("Model") then
			for _, desc in inst:GetDescendants() do
				if desc:IsA("BasePart") then
					return desc
				end
			end
		end
	end
	return nil
end

-- Collect all BaseParts from the selection (descending into Models)
local function getBaseParts(): { BasePart }
	local parts: { BasePart } = {}
	for _, inst in Selection:Get() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		elseif inst:IsA("Model") then
			for _, desc in inst:GetDescendants() do
				if desc:IsA("BasePart") then
					table.insert(parts, desc)
				end
			end
		end
	end
	return parts
end

local function destroyDraggerSession()
	if mDraggerHandle then
		Roact.unmount(mDraggerHandle)
		mDraggerHandle = nil
	end
	if mSelectionCn then
		mSelectionCn:Disconnect()
		mSelectionCn = nil
	end
	if mUndoCn then
		mUndoCn:Disconnect()
		mUndoCn = nil
	end
	if mRedoCn then
		mRedoCn:Disconnect()
		mRedoCn = nil
	end
	if mRecordingId then
		ChangeHistoryService:FinishRecording(mRecordingId, Enum.FinishRecordingOperation.Cancel)
		mRecordingId = nil
	end
	mFirstPart = nil
	mStartSizes = {}
	mStartCFrames = {}
end

local function createDraggerSession(plugin: Plugin)
	ensureDraggerLoaded()
	destroyDraggerSession()

	mFirstPart = getFirstBasePart()

	-- Create a mock selection that tracks the real selection
	local selectionChangedSignal = Signal.new()
	local mockSelection = {
		Get = function()
			return if mFirstPart then { mFirstPart } else {}
		end,
		Set = function() end,
		SelectionChanged = selectionChangedSignal,
	}

	-- Listen for real selection changes
	mSelectionCn = Selection.SelectionChanged:Connect(function()
		mFirstPart = getFirstBasePart()
		selectionChangedSignal:Fire()
	end)

	-- Resync on undo/redo
	local function onUndoRedo()
		task.defer(function()
			mFirstPart = getFirstBasePart()
			selectionChangedSignal:Fire()
		end)
	end
	mUndoCn = ChangeHistoryService.OnUndo:Connect(onUndoRedo)
	mRedoCn = ChangeHistoryService.OnRedo:Connect(onUndoRedo)

	local draggerContext = DraggerContext_PluginImpl.new(
		plugin,
		game,
		settings(),
		mockSelection
	)
	draggerContext.SetDraggingFunction = function(_isDragging: any) end
	draggerContext.DragUpdatedSignal = Signal.new()
	draggerContext.PrimaryAxis = nil
	draggerContext.UseSnapSize = false
	draggerContext.SnapSize = nil

	local function getBoundingBox()
		if mFirstPart and mFirstPart.Parent then
			local pivot = mFirstPart:GetPivot()
			local size = mFirstPart.Size
			draggerContext.EndSize = size
			draggerContext.StartCFrame = pivot
			draggerContext.StartDragCFrame = pivot
			return pivot, Vector3.zero, size
		end
		return CFrame.new(), Vector3.zero, Vector3.zero
	end

	local schema = createDraggerSchema(getBoundingBox)

	-- Drag callbacks
	local function startDrag()
		mStartSizes = {}
		mStartCFrames = {}
		for _, part in getBaseParts() do
			mStartSizes[part] = part.Size
			mStartCFrames[part] = part.CFrame
		end
		mRecordingId = ChangeHistoryService:TryBeginRecording("Resize Parts")
	end

	local function applyTransform(deltaSize: Vector3, localOffset: Vector3)
		-- deltaSize and localOffset are in the first part's local space.
		-- Each part resizes along its own matching local axis and shifts
		-- to keep the opposite face fixed.
		for part, startSize in mStartSizes do
			local startCFrame = mStartCFrames[part]
			if not startCFrame then continue end

			local newSize = (startSize + deltaSize):Max(Vector3.new(0.05, 0.05, 0.05))
			part.Size = newSize

			-- Scale offset proportionally to actual vs requested change
			local requested = deltaSize.X + deltaSize.Y + deltaSize.Z
			local scaledOffset = localOffset
			if requested ~= 0 then
				local actualDelta = newSize - startSize
				local actual = actualDelta.X + actualDelta.Y + actualDelta.Z
				scaledOffset = localOffset * (actual / requested)
			end

			part.CFrame = startCFrame + startCFrame:VectorToWorldSpace(scaledOffset)
		end
	end

	local function endDrag()
		if mRecordingId then
			ChangeHistoryService:FinishRecording(mRecordingId, Enum.FinishRecordingOperation.Commit)
			mRecordingId = nil
		end
	end

	-- Mount the dragger component
	local rootElement = Roact.createElement(DraggerToolComponent, {
		Mouse = plugin:GetMouse(),
		DraggerContext = draggerContext,
		DraggerSchema = schema,
		DraggerSettings = {
			AllowDragSelect = false,
			AnalyticsName = "ResizeSelection",
			HandlesList = {
				ResizeHandles.new(draggerContext, {
					GetBoundingBox = getBoundingBox,
					StartTransform = startDrag,
					ApplyTransform = applyTransform,
					EndTransform = endDrag,
					Visible = function()
						return mFirstPart ~= nil and mFirstPart.Parent ~= nil
					end,
				}),
			},
		},
	})

	mDraggerHandle = Roact.mount(rootElement)
end

local ResizeSelection: ToolTypes.ToolDefinition = {
	Id = "resizeSelection",
	Name = "Resize Each Part",
	Description = "Resize multiple parts along their individual axes using drag handles. Models in the selection are expanded to include all descendant parts.",

	OnActivated = function(ctx)
		createDraggerSession(ctx.Plugin)
	end,

	OnDeactivated = function(_ctx)
		destroyDraggerSession()
	end,
}

return ResizeSelection

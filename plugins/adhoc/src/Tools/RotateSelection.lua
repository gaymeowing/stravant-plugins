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
local RotateHandles: any = nil

local function ensureDraggerLoaded()
	if Roact then return end
	Roact = require(Packages.Roact)
	local DraggerFramework = require(Packages.DraggerFramework)
	DraggerSchemaCore = require(Packages.DraggerSchemaCore)
	DraggerContext_PluginImpl = (require :: any)(DraggerFramework.Implementation.DraggerContext_PluginImpl)
	DraggerToolComponent = (require :: any)(DraggerFramework.DraggerTools.DraggerToolComponent)
	RotateHandles = require(script.Parent.Parent.Dragger.RotateHandles)
end

-- Dragger session state
local mDraggerHandle: any = nil
local mSelectionCn: RBXScriptConnection? = nil
local mUndoCn: RBXScriptConnection? = nil
local mRedoCn: RBXScriptConnection? = nil
local mFirstTarget: PVInstance? = nil
local mStartPivots: { [PVInstance]: CFrame } = {}
local mRecordingId: string? = nil

local function createCFrameDraggerSchema(getBoundingBoxFunc: () -> (CFrame, Vector3, Vector3))
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
					return mFirstTarget == nil
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

local function getFirstTarget(): PVInstance?
	for _, inst in Selection:Get() do
		if inst:IsA("BasePart") or inst:IsA("Model") then
			return inst
		end
	end
	return nil
end

local function getTargets(): { PVInstance }
	local targets: { PVInstance } = {}
	for _, inst in Selection:Get() do
		if inst:IsA("BasePart") or inst:IsA("Model") then
			table.insert(targets, inst)
		end
	end
	return targets
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
	mFirstTarget = nil
	mStartPivots = {}
end

local function createDraggerSession(plugin: Plugin)
	ensureDraggerLoaded()
	destroyDraggerSession()

	mFirstTarget = getFirstTarget()

	-- Create a mock selection that tracks the real selection
	local selectionChangedSignal = Signal.new()
	local mockSelection = {
		Get = function()
			return if mFirstTarget then { mFirstTarget } else {}
		end,
		Set = function() end,
		SelectionChanged = selectionChangedSignal,
	}

	-- Listen for real selection changes
	mSelectionCn = Selection.SelectionChanged:Connect(function()
		mFirstTarget = getFirstTarget()
		selectionChangedSignal:Fire()
	end)

	-- Resync on undo/redo
	local function onUndoRedo()
		task.defer(function()
			mFirstTarget = getFirstTarget()
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
		if mFirstTarget and mFirstTarget.Parent then
			local pivot = mFirstTarget:GetPivot()
			local size = if mFirstTarget:IsA("BasePart")
				then mFirstTarget.Size
				else Vector3.zero
			draggerContext.EndSize = size
			draggerContext.StartCFrame = pivot
			draggerContext.StartDragCFrame = pivot
			return pivot, Vector3.zero, size
		end
		return CFrame.new(), Vector3.zero, Vector3.zero
	end

	local schema = createCFrameDraggerSchema(getBoundingBox)

	-- Drag callbacks
	local function startDrag()
		-- Capture all selected targets and their starting pivots
		mStartPivots = {}
		for _, target in getTargets() do
			mStartPivots[target] = target:GetPivot()
		end
		mRecordingId = ChangeHistoryService:TryBeginRecording("Rotate Parts")
	end

	local function applyTransform(localTransform: CFrame)
		if not mFirstTarget or not mStartPivots[mFirstTarget] then
			return
		end
		-- Convert local transform (in first part's space) to world-space rotation
		local firstPivot = mStartPivots[mFirstTarget]
		local firstRot = firstPivot - firstPivot.Position
		local worldRot = firstRot * localTransform * firstRot:Inverse()

		for item, startPivot in mStartPivots do
			local pos = startPivot.Position
			local rot = startPivot - pos
			;(item :: PVInstance):PivotTo(worldRot * rot + pos)
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
			AnalyticsName = "RotateSelection",
			HandlesList = {
				RotateHandles.new(draggerContext, {
					GetBoundingBox = getBoundingBox,
					StartTransform = startDrag,
					ApplyTransform = applyTransform,
					EndTransform = endDrag,
					Visible = function()
						return mFirstTarget ~= nil and mFirstTarget.Parent ~= nil
					end,
					SnapGranularityMultiplier = 1,
				}),
			},
		},
	})

	mDraggerHandle = Roact.mount(rootElement)
end

local RotateSelection: ToolTypes.ToolDefinition = {
	Id = "rotateSelection",
	Name = "Rotate Selection",
	Description = "Rotate multiple parts around their individual pivot points using drag handles.",

	OnActivated = function(ctx)
		createDraggerSession(ctx.Plugin)
	end,

	OnDeactivated = function(_ctx)
		destroyDraggerSession()
	end,
}

return RotateSelection

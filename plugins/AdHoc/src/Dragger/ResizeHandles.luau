--[[
	Resize handles for scaling parts along individual axes.
	Follows the same interface as RotateHandles for use with DraggerToolComponent.
]]

local Workspace = game:GetService("Workspace")

-- Libraries
local Packages = script.Parent.Parent.Parent.Packages
local Roact = require(Packages.Roact)
local DraggerFramework = require(Packages.DraggerFramework)

-- Dragger Framework
local Colors = require(DraggerFramework.Utility.Colors)
local Math = require(DraggerFramework.Utility.Math)
local ScaleHandleView = require(DraggerFramework.Components.ScaleHandleView)
local computeDraggedDistance = require(DraggerFramework.Utility.computeDraggedDistance)

local getEngineFeatureModelPivotVisual = require(DraggerFramework.Flags.getEngineFeatureModelPivotVisual)
local getFFlagSummonPivot = require(DraggerFramework.Flags.getFFlagSummonPivot)

local ResizeHandles = {}
ResizeHandles.__index = ResizeHandles

local NormalId = {
	X_AXIS = 1,
	Y_AXIS = 2,
	Z_AXIS = 3,
}

local ScaleHandleDefinitions = {
	MinusX = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)),
		Color = Colors.X_AXIS,
		NormalId = NormalId.X_AXIS,
	},
	PlusX = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1)),
		Color = Colors.X_AXIS,
		NormalId = NormalId.X_AXIS,
	},
	MinusY = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)),
		Color = Colors.Y_AXIS,
		NormalId = NormalId.Y_AXIS,
	},
	PlusY = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0)),
		Color = Colors.Y_AXIS,
		NormalId = NormalId.Y_AXIS,
	},
	MinusZ = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)),
		Color = Colors.Z_AXIS,
		NormalId = NormalId.Z_AXIS,
	},
	PlusZ = {
		Offset = CFrame.fromMatrix(Vector3.new(), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0)),
		Color = Colors.Z_AXIS,
		NormalId = NormalId.Z_AXIS,
	},
}

local MIN_PART_SIZE = 0.05

function ResizeHandles.new(draggerContext, props)
	local self = {}
	self._draggerContext = draggerContext
	self._handles = {}
	self._props = props or {}
	return setmetatable(self, ResizeHandles)
end

function ResizeHandles:update(draggerToolModel, selectionInfo)
	if not self._draggingHandleId then
		local cframe, offset, size = self._props.GetBoundingBox()
		self._boundingBox = {
			Size = size,
			CFrame = cframe * CFrame.new(offset),
		}
		self._basisOffset = CFrame.new(-offset)
		self._selectionInfo = selectionInfo
		self._selectionWrapper = draggerToolModel:getSelectionWrapper()
		self._schema = draggerToolModel:getSchema()
	end
	self:_updateHandles()
end

function ResizeHandles:shouldBiasTowardsObjects()
	return true
end

function ResizeHandles:hitTest(mouseRay, ignoreExtraThreshold)
	local closestHandleId, closestHandleDistance = nil, math.huge
	for handleId, handleProps in pairs(self._handles) do
		local distance = ScaleHandleView.hitTest(handleProps, mouseRay)
		if distance and distance < closestHandleDistance then
			closestHandleDistance = distance
			closestHandleId = handleId
		end
	end
	if closestHandleId then
		return closestHandleId, 0
	elseif not ignoreExtraThreshold then
		-- Second attempt using distance from handle
		closestHandleDistance = math.huge
		for handleId, handleProps in pairs(self._handles) do
			local distance = ScaleHandleView.distanceFromHandle(handleProps, mouseRay)
			if distance < closestHandleDistance then
				closestHandleDistance = distance
				closestHandleId = handleId
			end
		end
		if closestHandleDistance < 0 then
			return closestHandleId, 0
		end
	end
	return nil, 0
end

function ResizeHandles:render(hoveredHandleId)
	local children = {}

	if self._draggingHandleId and self._handles[self._draggingHandleId] then
		local handleProps = self._handles[self._draggingHandleId]
		children[self._draggingHandleId] = Roact.createElement(ScaleHandleView, {
			HandleCFrame = handleProps.HandleCFrame,
			Color = handleProps.Color,
			Scale = handleProps.Scale,
		})
		for otherHandleId, otherHandleProps in pairs(self._handles) do
			if otherHandleId ~= self._draggingHandleId then
				children[otherHandleId] = Roact.createElement(ScaleHandleView, {
					HandleCFrame = otherHandleProps.HandleCFrame,
					Color = Colors.makeDimmed(otherHandleProps.Color),
					Scale = otherHandleProps.Scale,
					Thin = true,
				})
			end
		end
	else
		for handleId, handleProps in pairs(self._handles) do
			local color = handleProps.Color
			local hovered = (handleId == hoveredHandleId)
			if not hovered then
				color = Colors.makeDimmed(color)
			end
			children[handleId] = Roact.createElement(ScaleHandleView, {
				HandleCFrame = handleProps.HandleCFrame,
				Color = color,
				Scale = handleProps.Scale,
				Hovered = hovered,
			})
		end
	end

	return Roact.createElement("Folder", {}, children)
end

function ResizeHandles:mouseDown(mouseRay, handleId)
	if not self._handles[handleId] then
		return
	end

	self._draggingHandleId = handleId
	self._handleCFrame = self._handles[handleId].HandleCFrame
	self._normalId = self._handles[handleId].NormalId
	self._originalBoundingBoxCFrame = self._boundingBox.CFrame
	self._originalBoundingBoxSize = self._boundingBox.Size

	local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)
	self._startDistance = hasDistance and distance or 0

	self._props.StartTransform()
end

function ResizeHandles:mouseDrag(mouseRay)
	if not self._draggingHandleId or not self._handles[self._draggingHandleId] then
		return
	end

	local hasDistance, distance = self:_getDistanceAlongAxis(mouseRay)
	if not hasDistance then
		return
	end

	local dragDistance = distance - self._startDistance
	local delta = self._draggerContext:snapToGridSize(dragDistance)

	local handleProps = self._handles[self._draggingHandleId]
	local axis = handleProps.Axis

	-- Build delta size vector (change along the dragged axis only)
	local sizeComponents = { 0, 0, 0 }
	sizeComponents[self._normalId] = delta
	local deltaSize = Vector3.new(sizeComponents[1], sizeComponents[2], sizeComponents[3])

	-- Clamp so parts don't go below minimum size
	local targetSize = self._originalBoundingBoxSize + deltaSize
	local clampedSize = targetSize:Max(Vector3.new(MIN_PART_SIZE, MIN_PART_SIZE, MIN_PART_SIZE))
	deltaSize = clampedSize - self._originalBoundingBoxSize

	-- Position offset: move half the delta along the axis to keep opposite face fixed
	local localOffset = axis * 0.5 * sizeComponents[self._normalId]
	-- Re-clamp the offset
	local actualDelta = deltaSize[({ "X", "Y", "Z" })[self._normalId]]
	if delta ~= 0 then
		localOffset = localOffset * (actualDelta / delta)
	end

	self._props.ApplyTransform(deltaSize, localOffset)

	-- Update bounding box for handle positions
	self._boundingBox.CFrame = self._originalBoundingBoxCFrame * CFrame.new(localOffset)
	self._boundingBox.Size = self._originalBoundingBoxSize + deltaSize
	self:_updateHandles()
end

function ResizeHandles:mouseUp(mouseRay)
	if not self._draggingHandleId then
		return
	end
	self._draggingHandleId = nil
	self._schema.addUndoWaypoint(self._draggerContext, "Resize Parts")
	self._props.EndTransform()
end

function ResizeHandles:_getDistanceAlongAxis(mouseRay)
	local dragDirection = self._handleCFrame.LookVector
	local dragStartPosition = self._originalBoundingBoxCFrame.Position
	return computeDraggedDistance(dragStartPosition, dragDirection, mouseRay)
end

function ResizeHandles:_updateHandles()
	if self._selectionInfo:isEmpty() or not self._props.Visible() then
		self._handles = {}
	else
		for handleId, handleDefinition in pairs(ScaleHandleDefinitions) do
			local offset = handleDefinition.Offset
			local localSize = offset:Inverse():VectorToWorldSpace(self._boundingBox.Size)
			local boundingBoxOffset = 0.5 * math.abs(localSize.Z)
			local handleBaseCFrame = self._boundingBox.CFrame * offset * CFrame.new(0, 0, -boundingBoxOffset)

			self._handles[handleId] = {
				Color = handleDefinition.Color,
				Axis = offset.LookVector,
				HandleCFrame = handleBaseCFrame,
				NormalId = handleDefinition.NormalId,
				Scale = self._draggerContext:getHandleScale(handleBaseCFrame.Position),
			}
		end
	end
end

return ResizeHandles

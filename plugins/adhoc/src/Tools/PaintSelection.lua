--!strict
local Selection = game:GetService("Selection")

local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext

local mRecordingId: string? = nil
local mSelectedParts: { [BasePart]: boolean } = {}

local PaintSelection: ToolTypes.ToolDefinition = {
	Id = "paintSelection",
	Name = "Paint Selection",
	Description = "Click and drag to add parts under the cursor to the selection",

	OnActivated = function(ctx: ToolContext)
		mSelectedParts = {}
	end,

	OnDeactivated = function(ctx: ToolContext)
		mSelectedParts = {}
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		ctx.SetHighlight(ctx.Target)
		if ctx.IsMouseDown and ctx.Target and not mSelectedParts[ctx.Target] then
			mSelectedParts[ctx.Target] = true
			-- Build selection from tracked parts
			local sel: { Instance } = {}
			for part in mSelectedParts do
				table.insert(sel, part)
			end
			Selection:Set(sel)
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if ctx.Target then
			local id = ctx.BeginRecording("Paint Selection")
			if id then
				mRecordingId = id
			end
			-- Start fresh selection with this part
			mSelectedParts = { [ctx.Target] = true }
			Selection:Set({ ctx.Target })
		end
	end,

	OnReleased = function(ctx: ToolContext)
		if mRecordingId then
			ctx.FinishRecording(mRecordingId)
			mRecordingId = nil
		end
		mSelectedParts = {}
	end,
}

return PaintSelection

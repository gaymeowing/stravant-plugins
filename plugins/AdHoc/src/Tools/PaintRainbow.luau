local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function PaintRainbowSettings(props: ToolSettingsProps)
	local steps = props.GetSetting("Steps") :: number
	local saturation = props.GetSetting("Saturation") :: number

	-- Build color preview swatches
	local previewChildren: { [string]: any } = {}
	previewChildren.ListLayout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	for i = 1, steps do
		local hue = (i - 1) / steps
		previewChildren["Color" .. i] = e("Frame", {
			Size = UDim2.new(1 / steps, -2, 1, 0),
			BackgroundColor3 = Color3.fromHSV(hue, saturation, 1),
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 3),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Preview = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, previewChildren),
		StepsInput = e(NumberInput, {
			Label = "Steps",
			Value = steps,
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 2, 36)
				props.SetSetting("Steps", newValue)
				return newValue
			end,
			LayoutOrder = 2,
		}),
		SaturationInput = e(NumberInput, {
			Label = "Saturation",
			Value = math.round(saturation * 100),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 100)
				props.SetSetting("Saturation", newValue / 100)
				return newValue
			end,
			LayoutOrder = 3,
		}),
	})
end

local mRecordingId: string? = nil
local mPaintedParts: { [BasePart]: boolean } = {}
local mColorIndex = 0

local function getNextColor(ctx: ToolContext): Color3
	local steps = ctx.GetSetting("Steps") :: number
	local saturation = ctx.GetSetting("Saturation") :: number
	local hue = mColorIndex / steps
	mColorIndex = (mColorIndex + 1) % steps
	return Color3.fromHSV(hue, saturation, 1)
end

local PaintRainbow: ToolTypes.ToolDefinition = {
	Id = "paintRainbow",
	Name = "Paint Rainbow",
	Description = "Paint parts cycling through saturated rainbow colors",

	DefaultSettings = {
		Steps = 6,
		Saturation = 1,
	},

	OnActivated = function(ctx: ToolContext)
		mPaintedParts = {}
		mColorIndex = 0
	end,

	OnDeactivated = function(ctx: ToolContext)
		mPaintedParts = {}
		mColorIndex = 0
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		ctx.SetHighlight(ctx.Target)
		if ctx.IsMouseDown and ctx.Target and not mPaintedParts[ctx.Target] then
			ctx.Target.Color = getNextColor(ctx)
			mPaintedParts[ctx.Target] = true
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if ctx.Target then
			local id = ctx.BeginRecording("Paint Rainbow")
			if id then
				mRecordingId = id
			end
			mPaintedParts = { [ctx.Target] = true }
			ctx.Target.Color = getNextColor(ctx)
		end
	end,

	OnReleased = function(ctx: ToolContext)
		if mRecordingId then
			ctx.FinishRecording(mRecordingId)
			mRecordingId = nil
		end
		mPaintedParts = {}
	end,

	RenderSettings = PaintRainbowSettings,
}

return PaintRainbow

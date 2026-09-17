local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("./Colors")

local e = React.createElement

local kTrackHeight = 6
local kThumbSize = 14

-- Begins a drag interaction on a slider element.
-- Creates a full-panel overlay to capture GUI-based InputChanged events during
-- the drag, avoiding UserInputService which doesn't work correctly inside a
-- DockWidgetPluginGui. Detects release via the original InputObject lifecycle.
local function beginSliderDrag(
	frame: GuiObject,
	input: InputObject,
	onUpdate: (fraction: number) -> (),
	onDragStarted: (() -> ())?,
	onDragEnded: (() -> ())?
)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local absPos = frame.AbsolutePosition
	local absSize = frame.AbsoluteSize

	local clickPos = Vector2.new(input.Position.X, input.Position.Y)
	local startFraction = (clickPos.X - absPos.X) / absSize.X

	if onDragStarted then
		onDragStarted()
	end
	onUpdate(math.clamp(startFraction, 0, 1))

	-- Full-panel overlay captures mouse movement during the drag.
	local panel = frame:FindFirstAncestorWhichIsA("DockWidgetPluginGui")
	local overlay = Instance.new("TextButton")
	overlay.Name = "SliderDragOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 1000
	overlay.Text = ""
	overlay.Active = true
	overlay.Parent = panel

	overlay.InputChanged:Connect(function(changedInput)
		if changedInput.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = Vector2.new(changedInput.Position.X, changedInput.Position.Y)
			local fraction = (pos.X - absPos.X) / absSize.X
			onUpdate(math.clamp(fraction, 0, 1))
		end
	end)

	-- Detect release via the original InputObject's lifecycle
	input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			overlay:Destroy()
			if onDragEnded then
				onDragEnded()
			end
		end
	end)
end

local function Slider(props: {
	Label: string?,
	Value: number,
	Min: number?,
	Max: number?,
	Step: number?,
	ValueChanged: (number) -> (),
	DragStarted: (() -> ())?,
	DragEnded: (() -> ())?,
	LayoutOrder: number?,
})
	local min = props.Min or 0
	local max = props.Max or 1
	local step = props.Step
	local range = max - min
	local fraction = if range > 0 then math.clamp((props.Value - min) / range, 0, 1) else 0

	local function fractionToValue(f: number): number
		local value = min + f * range
		if step and step > 0 then
			value = math.round((value - min) / step) * step + min
		end
		return math.clamp(value, min, max)
	end

	local minLabel = string.format("%g", min)
	local maxLabel = string.format("%g", max)

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Label = props.Label and e("TextLabel", {
			Text = props.Label,
			TextColor3 = Colors.OFFWHITE,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(56, 20),
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		MinLabel = e("TextLabel", {
			Text = minLabel,
			TextColor3 = Colors.OFFWHITE,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Enum.Font.SourceSans,
			TextSize = 12,
			LayoutOrder = 2,
		}),
		-- Track container: holds the track, fill, and thumb
		Track = e("TextButton", {
			Size = UDim2.new(0, 0, 0, kThumbSize + 4),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = 3,
			[React.Event.InputBegan] = function(rbx: TextButton, input: InputObject)
				beginSliderDrag(rbx, input, function(f)
					props.ValueChanged(fractionToValue(f))
				end, props.DragStarted, props.DragEnded)
			end,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
			-- Track background bar
			TrackBg = e("Frame", {
				Size = UDim2.new(1, 0, 0, kTrackHeight),
				Position = UDim2.fromScale(0, 0.5),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Colors.GREY,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, kTrackHeight / 2),
				}),
			}),
			-- Fill bar
			Fill = e("Frame", {
				Size = UDim2.new(fraction, 0, 0, kTrackHeight),
				Position = UDim2.fromScale(0, 0.5),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Colors.ACTION_BLUE,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, kTrackHeight / 2),
				}),
			}),
			-- Thumb
			Thumb = e("Frame", {
				Size = UDim2.fromOffset(kThumbSize, kThumbSize),
				Position = UDim2.fromScale(fraction, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Colors.WHITE,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
		MaxLabel = e("TextLabel", {
			Text = maxLabel,
			TextColor3 = Colors.OFFWHITE,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Enum.Font.SourceSans,
			TextSize = 12,
			LayoutOrder = 4,
		}),
	})
end

return Slider

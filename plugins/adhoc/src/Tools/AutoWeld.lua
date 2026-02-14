--!strict
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Live instance refs, not persisted
local mPart1s: { BasePart } = {}

local function getSelectedParts(): { BasePart }
	local parts: { BasePart } = {}
	for _, inst in Selection:Get() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	return parts
end

-- Filter out parts that have been destroyed
local function getValidPart1s(): { BasePart }
	local valid: { BasePart } = {}
	for _, part in mPart1s do
		if part.Parent then
			table.insert(valid, part)
		end
	end
	return valid
end

local function AutoWeldSettings(props: ToolSettingsProps)
	-- Use a counter to force re-renders when mPart1s changes
	local revision, setRevision = React.useState(0)
	local _ = revision -- suppress unused warning

	local validPart1s = getValidPart1s()

	local statusText: string
	if #validPart1s == 0 then
		statusText = "No Part1s set."
	else
		statusText = #validPart1s .. " part" .. (if #validPart1s == 1 then "" else "s") .. " ready to weld"
	end

	local children: { [string]: any } = {}

	children.Layout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	children.SetPart1sButton = e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Colors.ACTION_BLUE,
		AutoButtonColor = true,
		Text = "Set Part1s from Selection",
		TextColor3 = Colors.WHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		[React.Event.MouseButton1Click] = function()
			local parts = getSelectedParts()
			if #parts > 0 then
				mPart1s = parts
				setRevision(function(r: number) return r + 1 end)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
	})

	children.Status = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = statusText,
		TextColor3 = Colors.OFFWHITE,
		Font = Enum.Font.SourceSansItalic,
		TextSize = 14,
		LayoutOrder = 2,
	})

	if #validPart1s > 0 then
		children.WeldButton = e("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Colors.ACTION_BLUE,
			AutoButtonColor = true,
			Text = "Weld to Selection (Part0)",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			BorderSizePixel = 0,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = function()
				local selected = getSelectedParts()
				if #selected == 0 then
					return
				end
				local part0 = selected[1]
				local part1s = getValidPart1s()
				if #part1s == 0 then
					return
				end
				local id = ChangeHistoryService:TryBeginRecording("Auto Weld")
				if not id then
					return
				end
				for _, part1 in part1s do
					if part1 ~= part0 then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = part0
						weld.Part1 = part1
						weld.Parent = part0
					end
				end
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				mPart1s = {}
				setRevision(function(r: number) return r + 1 end)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})

		children.ClearButton = e("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Colors.GREY,
			AutoButtonColor = true,
			Text = "Clear Part1s",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			BorderSizePixel = 0,
			LayoutOrder = 4,
			[React.Event.MouseButton1Click] = function()
				mPart1s = {}
				setRevision(function(r: number) return r + 1 end)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local AutoWeld: ToolTypes.ToolDefinition = {
	Id = "autoWeld",
	Name = "Auto Weld",
	Description = "Quickly create WeldConstraints between parts",

	RenderSettings = AutoWeldSettings,
}

return AutoWeld

--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local InsertService = game:GetService("InsertService")

local Colors = require("../PluginGui/Colors")
local OperationButton = require("../PluginGui/OperationButton")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local ASSET_ID = 76233968067050

local function SnowflakeEyesSettings(props: ToolSettingsProps)
	local status, setStatus = React.useState("")
	local isLoading, setIsLoading = React.useState(false)

	local function insertSnowflakeEyes()
		if isLoading then
			return
		end
		setIsLoading(true)
		setStatus("")

		task.spawn(function()
			local recordingId = ChangeHistoryService:TryBeginRecording("Insert Snowflake Eyes")

			local ok, err = pcall(function()
				local model = InsertService:LoadAsset(ASSET_ID)
				model.Name = "Snowflake Eyes"
				model.Parent = workspace
			end)

			if recordingId then
				if ok then
					ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Commit)
				else
					ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Cancel)
				end
			end

			if ok then
				setStatus("Added! Check workspace.")
			else
				setStatus("Error: " .. tostring(err))
			end
			setIsLoading(false)
		end)
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		InsertButton = e(OperationButton, {
			Text = if isLoading then "LOADING..." else "ADD SNOWFLAKE EYES",
			SubText = if isLoading then nil else "snowflake eyes hype hype hype",
			Height = 50,
			Disabled = isLoading,
			Color = Colors.ACTION_BLUE,
			LayoutOrder = 1,
			OnClick = insertSnowflakeEyes,
		}),
		Status = if status ~= "" then e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = status,
			TextColor3 = if string.find(status, "Error") then Colors.WARNING_YELLOW else Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = 2,
		}) else nil,
	})
end

local SnowflakeEyes: ToolTypes.ToolDefinition = {
	Id = "snowflakeEyes",
	Name = "Snowflake Eyes",
	Description = "Add the Snowflake Eyes limited face to your game",

	RenderSettings = SnowflakeEyesSettings,
}

return SnowflakeEyes

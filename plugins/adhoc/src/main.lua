--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = script.Parent.Parent.Packages
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)
local Signal = require(Packages.Signal)

local ToolTypes = require("./ToolTypes")
local Settings = require("./Settings")
local AdhocGui = require("./AdhocGui")

type ToolDefinition = ToolTypes.ToolDefinition
type ToolContext = ToolTypes.ToolContext

local function discoverTools(): { ToolDefinition }
	local allTools: { ToolDefinition } = {}
	for _, module in script.Parent.Tools:GetChildren() do
		if module:IsA("ModuleScript") then
			local tool = require(module) :: ToolDefinition
			table.insert(allTools, tool)
		end
	end
	table.sort(allTools, function(a, b)
		return a.Name < b.Name
	end)
	return allTools
end

local function initializeToolSettings(
	settings: Settings.AdhocSettings,
	allTools: { ToolDefinition }
)
	for _, tool in allTools do
		if settings.ToolSettings[tool.Id] == nil and tool.DefaultSettings then
			settings.ToolSettings[tool.Id] = table.clone(tool.DefaultSettings)
		elseif settings.ToolSettings[tool.Id] == nil then
			settings.ToolSettings[tool.Id] = {}
		end
	end
end

return function(
	plugin: Plugin,
	panel: DockWidgetPluginGui,
	buttonClicked: Signal.Signal<>,
	setButtonActive: (active: boolean) -> ()
)
	local allTools = discoverTools()
	local activeSettings = Settings.Load(plugin)
	initializeToolSettings(activeSettings, allTools)

	local active = false
	local mActiveTool: ToolDefinition? = nil
	local mIsMouseDown = false
	local mTarget: BasePart? = nil
	local mRecordingId: string? = nil

	-- Highlight for hover preview
	local mHighlight: Highlight = Instance.new("Highlight")
	mHighlight.FillTransparency = 0.75
	mHighlight.OutlineTransparency = 0
	mHighlight.FillColor = Color3.fromRGB(0, 120, 255)
	mHighlight.OutlineColor = Color3.fromRGB(0, 120, 255)
	mHighlight.Enabled = false
	mHighlight.Parent = workspace

	local reactRoot: ReactRoblox.RootType? = nil

	-- Raycast params
	local mRaycastParams = RaycastParams.new()
	mRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	mRaycastParams.FilterDescendantsInstances = {}

	local heartbeatCn: RBXScriptConnection? = nil
	local inputBeganCn: RBXScriptConnection? = nil
	local inputEndedCn: RBXScriptConnection? = nil

	local function getToolSetting(toolId: string, key: string): any
		local toolSettings = activeSettings.ToolSettings[toolId]
		if toolSettings then
			return toolSettings[key]
		end
		return nil
	end

	local function setToolSetting(toolId: string, key: string, value: any)
		if activeSettings.ToolSettings[toolId] == nil then
			activeSettings.ToolSettings[toolId] = {}
		end
		activeSettings.ToolSettings[toolId][key] = value
	end

	local function updateUI()
		-- forward declared, filled in below
	end

	local function createToolContext(): ToolContext
		local tool = assert(mActiveTool, "No active tool")
		local toolId = tool.Id
		return {
			Target = mTarget,
			IsMouseDown = mIsMouseDown,
			GetSetting = function(key: string): any
				return getToolSetting(toolId, key)
			end,
			SetSetting = function(key: string, value: any)
				setToolSetting(toolId, key, value)
				updateUI()
			end,
			SetHighlight = function(part: BasePart?)
				if part then
					mHighlight.Adornee = part
					mHighlight.Enabled = true
				else
					mHighlight.Adornee = nil
					mHighlight.Enabled = false
				end
			end,
			BeginRecording = function(name: string): string?
				local id = ChangeHistoryService:TryBeginRecording(name)
				if id then
					mRecordingId = id
				end
				return id
			end,
			FinishRecording = function(id: string)
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				if mRecordingId == id then
					mRecordingId = nil
				end
			end,
			UpdateUI = updateUI,
		}
	end

	local function raycastFromMouse(): BasePart?
		local camera = workspace.CurrentCamera
		if not camera then
			return nil
		end
		local mouseLocation = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 10000, mRaycastParams)
		if result and result.Instance:IsA("BasePart") then
			return result.Instance
		end
		return nil
	end

	local mLastMouseLocation = Vector2.zero
	local mLastCameraCFrame = CFrame.new()

	local function connectInputHandling()
		local camera = workspace.CurrentCamera

		heartbeatCn = RunService.Heartbeat:Connect(function()
			if not mActiveTool then
				return
			end

			local mouseLocation = UserInputService:GetMouseLocation()
			local cameraCFrame = if camera then camera.CFrame else CFrame.new()

			if mouseLocation ~= mLastMouseLocation or cameraCFrame ~= mLastCameraCFrame then
				mLastMouseLocation = mouseLocation
				mLastCameraCFrame = cameraCFrame
				mTarget = raycastFromMouse()

				if mActiveTool.OnViewChanged then
					mActiveTool.OnViewChanged(createToolContext())
				end
			end
		end)

		inputBeganCn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if not mActiveTool then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				mIsMouseDown = true
				mTarget = raycastFromMouse()
				if mActiveTool.OnClicked then
					mActiveTool.OnClicked(createToolContext())
				end
			end
		end)

		inputEndedCn = UserInputService.InputEnded:Connect(function(input)
			if not mActiveTool then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				mIsMouseDown = false
				if mActiveTool.OnReleased then
					mActiveTool.OnReleased(createToolContext())
				end
			end
		end)
	end

	local function disconnectInputHandling()
		if heartbeatCn then
			heartbeatCn:Disconnect()
			heartbeatCn = nil
		end
		if inputBeganCn then
			inputBeganCn:Disconnect()
			inputBeganCn = nil
		end
		if inputEndedCn then
			inputEndedCn:Disconnect()
			inputEndedCn = nil
		end
	end

	local function deactivateTool()
		if mActiveTool then
			-- Cancel any in-progress recording
			if mRecordingId then
				ChangeHistoryService:FinishRecording(mRecordingId, Enum.FinishRecordingOperation.Cancel)
				mRecordingId = nil
			end
			if mActiveTool.OnDeactivated then
				mActiveTool.OnDeactivated(createToolContext())
			end
			mActiveTool = nil
			mIsMouseDown = false
			mTarget = nil
			mHighlight.Adornee = nil
			mHighlight.Enabled = false
		end
	end

	local function activateTool(tool: ToolDefinition)
		if mActiveTool == tool then
			return
		end
		deactivateTool()
		mActiveTool = tool
		activeSettings.LastActiveTool = tool.Id
		if tool.OnActivated then
			tool.OnActivated(createToolContext())
		end
		-- Activate the plugin so we get input
		plugin:Activate(true)
		updateUI()
	end

	local function isPinned(toolId: string): boolean
		for _, id in activeSettings.PinnedTools do
			if id == toolId then
				return true
			end
		end
		return false
	end

	local function togglePin(toolId: string)
		if isPinned(toolId) then
			local newPinned = {}
			for _, id in activeSettings.PinnedTools do
				if id ~= toolId then
					table.insert(newPinned, id)
				end
			end
			activeSettings.PinnedTools = newPinned
		else
			table.insert(activeSettings.PinnedTools, toolId)
		end
		updateUI()
	end

	function updateUI()
		if not reactRoot then
			reactRoot = ReactRoblox.createRoot(panel)
		end

		reactRoot:render(React.createElement(AdhocGui, {
			AllTools = allTools,
			ActiveToolId = if mActiveTool then mActiveTool.Id else nil,
			PinnedTools = activeSettings.PinnedTools,
			ToolSettings = activeSettings.ToolSettings,
			Active = active,
			Panelized = true, -- Always panelized for this plugin
			CurrentSettings = activeSettings,
			UpdatedSettings = function()
				updateUI()
			end,
			HandleAction = function(action: string)
				if action == "togglePanelized" then
					-- No-op for this plugin, always panelized
				end
			end,
			OnSelectTool = function(toolId: string)
				for _, tool in allTools do
					if tool.Id == toolId then
						activateTool(tool)
						return
					end
				end
			end,
			OnGoBack = function()
				deactivateTool()
				updateUI()
			end,
			OnTogglePin = togglePin,
			GetToolSetting = getToolSetting,
			SetToolSetting = function(toolId: string, key: string, value: any)
				setToolSetting(toolId, key, value)
				updateUI()
			end,
		}))
	end

	local function setActive(newActive: boolean)
		if active == newActive then
			return
		end
		active = newActive
		setButtonActive(newActive)
		if newActive then
			connectInputHandling()
			-- Restore last active tool
			if activeSettings.LastActiveTool then
				for _, tool in allTools do
					if tool.Id == activeSettings.LastActiveTool then
						mActiveTool = tool
						if tool.OnActivated then
							tool.OnActivated(createToolContext())
						end
						break
					end
				end
			end
			plugin:Activate(true)
		else
			deactivateTool()
			disconnectInputHandling()
		end
		updateUI()
	end

	local clickedCn = buttonClicked:Connect(function()
		if active then
			setActive(false)
			panel.Enabled = false
		else
			setActive(true)
			panel.Enabled = true
		end
	end)

	-- When panel is toggled via the X button
	panel:GetPropertyChangedSignal("Enabled"):Connect(function()
		if panel.Enabled then
			if not active then
				setActive(true)
			end
		else
			if active then
				setActive(false)
			end
		end
	end)

	-- Initial UI
	updateUI()

	-- When the user selects a different tool, deactivate
	plugin.Deactivation:Connect(function()
		deactivateTool()
		disconnectInputHandling()
		active = false
		updateUI()
	end)

	plugin.Unloading:Connect(function()
		deactivateTool()
		disconnectInputHandling()
		if reactRoot then
			reactRoot:unmount()
			reactRoot = nil
		end
		mHighlight:Destroy()
		Settings.Save(plugin, activeSettings)
		clickedCn:Disconnect()
	end)
end

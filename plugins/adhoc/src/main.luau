local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
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

-- Common settings applied to all tools with their defaults
local COMMON_TOOL_DEFAULTS = {
	TargetLocked = false,
}

local function initializeToolSettings(
	settings: Settings.AdhocSettings,
	allTools: { ToolDefinition }
)
	for _, tool in allTools do
		if settings.ToolSettings[tool.Id] == nil then
			settings.ToolSettings[tool.Id] = {}
		end
		-- Backfill missing keys from tool defaults
		if tool.DefaultSettings then
			for key, default in tool.DefaultSettings do
				if settings.ToolSettings[tool.Id][key] == nil then
					settings.ToolSettings[tool.Id][key] = default
				end
			end
		end
		-- Ensure common defaults are present
		for key, default in COMMON_TOOL_DEFAULTS do
			if settings.ToolSettings[tool.Id][key] == nil then
				settings.ToolSettings[tool.Id][key] = default
			end
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
	local mPluginActivated = false -- whether we called plugin:Activate(true) for the current tool
	local mIsMouseDown = false
	local mTarget: BasePart? = nil
	local mTargetNormal: Vector3? = nil
	local mTargetPosition: Vector3? = nil
	local mRecordingId: string? = nil

	-- Highlight for hover preview (created lazily, only parented when in use)
	local mHighlight: Highlight? = nil

	local function getHighlight(): Highlight
		if not mHighlight then
			local h = Instance.new("Highlight")
			h.FillTransparency = 0.75
			h.OutlineTransparency = 0
			h.FillColor = Color3.fromRGB(0, 120, 255)
			h.OutlineColor = Color3.fromRGB(0, 120, 255)
			h.Enabled = false
			mHighlight = h
		end
		return mHighlight
	end

	local reactRoot: ReactRoblox.RootType? = nil

	-- Track whether the mouse is over the 3D viewport (vs the panel or off-screen).
	-- We detect this by checking if GetMouseLocation() is within camera.ViewportSize,
	-- since DockWidgetPluginGui MouseEnter/MouseLeave events don't work reliably.
	local mMouseInViewport = true

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
			Plugin = plugin,
			Target = mTarget,
			TargetNormal = mTargetNormal,
			TargetPosition = mTargetPosition,
			IsMouseDown = mIsMouseDown,
			GetSetting = function(key: string): any
				return getToolSetting(toolId, key)
			end,
			SetSetting = function(key: string, value: any)
				setToolSetting(toolId, key, value)
				updateUI()
			end,
			SetHighlight = function(part: BasePart?, hideOutline: boolean?)
				if part then
					local highlight = getHighlight()
					highlight.Adornee = part
					highlight.OutlineTransparency = if hideOutline then 1 else 0
					highlight.Enabled = true
					highlight.Parent = CoreGui
				elseif mHighlight then
					mHighlight.Adornee = nil
					mHighlight.Enabled = false
					mHighlight.Parent = nil
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
				if ChangeHistoryService:IsRecordingInProgress() then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				else
					ChangeHistoryService:SetWaypoint(id)
				end
				if mRecordingId == id then
					mRecordingId = nil
				end
			end,
			UpdateUI = updateUI,
		}
	end

	local function raycastFromMouse(): (BasePart?, Vector3?, Vector3?)
		local camera = workspace.CurrentCamera
		if not camera then
			return nil, nil, nil
		end
		local mouseLocation = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		local origin = ray.Origin
		local direction = ray.Direction * 10000

		local skipLocked = mActiveTool ~= nil
			and not getToolSetting(mActiveTool.Id, "TargetLocked")
		local ignored: { Instance }? = nil

		for _ = 1, 50 do
			local params = mRaycastParams
			if ignored then
				params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = ignored
			end

			local result = workspace:Raycast(origin, direction, params)
			if not result or not result.Instance:IsA("BasePart") then
				return nil, nil, nil
			end
			if not skipLocked or not result.Instance.Locked then
				return result.Instance, result.Normal, result.Position
			end
			-- Skip this locked part and try again
			if not ignored then
				ignored = { result.Instance }
			else
				table.insert(ignored, result.Instance)
			end
		end
		return nil, nil, nil
	end

	local mLastMouseLocation = Vector2.zero
	local mLastCameraCFrame = CFrame.new()

	local function connectInputHandling()
		heartbeatCn = RunService.Heartbeat:Connect(function()
			if not mActiveTool then
				return
			end

			local camera = workspace.CurrentCamera
			local mouseLocation = UserInputService:GetMouseLocation()

			-- Check if mouse is within the 3D viewport bounds.
			-- When the mouse is over the panel or off-screen, GetMouseLocation
			-- returns coordinates outside the viewport.
			local inViewport = false
			if camera then
				local vps = camera.ViewportSize
				inViewport = mouseLocation.X >= 0
					and mouseLocation.Y >= 0
					and mouseLocation.X <= vps.X
					and mouseLocation.Y <= vps.Y
			end

			-- Handle viewport enter/leave transitions
			if inViewport and not mMouseInViewport then
				mMouseInViewport = true
				if mActiveTool.OnMouseEnterViewport then
					mActiveTool.OnMouseEnterViewport(createToolContext())
				end
			elseif not inViewport and mMouseInViewport then
				mMouseInViewport = false
				mTarget = nil
				mTargetNormal = nil
				mTargetPosition = nil
				if mHighlight then
					mHighlight.Adornee = nil
					mHighlight.Enabled = false
					mHighlight.Parent = nil
				end
				if mActiveTool.OnMouseLeaveViewport then
					mActiveTool.OnMouseLeaveViewport(createToolContext())
				end
			end

			if not mMouseInViewport then
				return
			end

			local cameraCFrame = if camera then camera.CFrame else CFrame.new()

			if mouseLocation ~= mLastMouseLocation or cameraCFrame ~= mLastCameraCFrame then
				mLastMouseLocation = mouseLocation
				mLastCameraCFrame = cameraCFrame
				mTarget, mTargetNormal, mTargetPosition = raycastFromMouse()

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
				mTarget, mTargetNormal, mTargetPosition = raycastFromMouse()
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

	local function deactivateTool(selectRibbonTool: boolean?)
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
			mTargetNormal = nil
			mTargetPosition = nil
			if mHighlight then
				mHighlight.Adornee = nil
				mHighlight.Enabled = false
				mHighlight.Parent = nil
			end
			if selectRibbonTool ~= false and mPluginActivated then
				-- Re-select the built-in Select tool to work around a Studio bug
				-- where deactivating a plugin leaves no tool selected
				plugin:Activate(false)
				plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())
			end
			mPluginActivated = false
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
		-- Only activate the plugin (taking over input) if the tool uses the viewport
		if tool.OnClicked or tool.OnViewChanged or tool.OnActivated then
			mPluginActivated = true
			plugin:Activate(true)
		end
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

	-- If the panel is already open (Studio remembered dock state), activate now
	if panel.Enabled then
		setActive(true)
	end

	-- Initial UI
	updateUI()

	-- When another plugin takes focus, deactivate the current tool but keep
	-- the panel open so the user can re-select a tool (which calls plugin:Activate).
	-- Don't override the ribbon tool — something else already claimed focus.
	plugin.Deactivation:Connect(function()
		deactivateTool(false)
		updateUI()
	end)

	plugin.Unloading:Connect(function()
		deactivateTool()
		disconnectInputHandling()
		if reactRoot then
			reactRoot:unmount()
			reactRoot = nil
		end
		if mHighlight then
			mHighlight:Destroy()
		end
		Settings.Save(plugin, activeSettings)
		clickedCn:Disconnect()
	end)
end

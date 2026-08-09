--!strict

local CoreGui = game:GetService("CoreGui")

local Packages = script.Parent.Parent.Packages
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)
local Signal = require(Packages.Signal)

local createMaterialFlipSession = require("./createMaterialFlipSession")
local Settings = require("./Settings")
local MaterialFlipGui = require("./MaterialFlipGui")
local PluginGuiTypes = require("./PluginGui/Types")

return function(plugin: Plugin, panel: DockWidgetPluginGui, buttonClicked: Signal.Signal<>, setButtonActive: (active: boolean) -> ())
	local mSession: createMaterialFlipSession.MaterialFlipSession? = nil

	local mActive = false

	local activeSettings = Settings.Load(plugin)

	local mPluginActive = false

	local mReactRoot: ReactRoblox.RootType? = nil
	local mReactScreenGui: LayerCollector? = nil

	local handleAction: (string) -> () = nil

	local function destroyReactRoot()
		if mReactRoot then
			mReactRoot:unmount()
			mReactRoot = nil
		end
		if mReactScreenGui then
			mReactScreenGui:Destroy()
			mReactScreenGui = nil
		end
	end
	local function createReactRoot()
		if panel.Enabled then
			mReactRoot = ReactRoblox.createRoot(panel)
		else
			local screen = Instance.new("ScreenGui")
			screen.Name = "MaterialFlipMainGui"
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.Parent = CoreGui
			mReactScreenGui = screen
			mReactRoot = ReactRoblox.createRoot(screen)
		end
	end

	local function getGuiState(): PluginGuiTypes.PluginGuiMode
		return if mActive then "active" else "inactive"
	end

	-- The status only changes for the box approximation warning; showing
	-- hover info here too made the UI shift around annoyingly
	local function getStatus(): (string, boolean)
		local state = if mSession then mSession.GetHoverState() else nil
		if state and state.ApproximatedAsBox then
			return "This part is not a primitive shape. It will be rotated as if it were a box.", true
		end
		return "Hover over a part to rotate its material.", false
	end

	local function updateUI()
		local needsUI = mActive or panel.Enabled
		if needsUI then
			if not mReactRoot then
				createReactRoot()
			elseif panel.Enabled and mReactScreenGui ~= nil then
				destroyReactRoot()
				createReactRoot()
			elseif not panel.Enabled and mReactScreenGui == nil then
				destroyReactRoot()
				createReactRoot()
			end

			assert(mReactRoot, "We just created it")
			local statusText, statusIsWarning = getStatus()
			mReactRoot:render(React.createElement(MaterialFlipGui, {
				GuiState = getGuiState(),
				CurrentSettings = activeSettings,
				UpdatedSettings = function()
					if mSession then
						mSession.Update()
					end
					updateUI()
				end,
				HandleAction = handleAction,
				Panelized = panel.Enabled,
				StatusText = statusText,
				StatusIsWarning = statusIsWarning,
			}))
		elseif mReactRoot then
			destroyReactRoot()
		end
	end

	local function destroySession()
		if mSession then
			mSession.Destroy()
			mSession = nil
		end
	end

	local function createSession()
		if not mSession then
			local newSession = createMaterialFlipSession(activeSettings)
			newSession.ChangeSignal:Connect(updateUI)
			mSession = newSession
		end
	end

	local function setActive(newActive: boolean)
		if mActive == newActive then
			return
		end
		setButtonActive(newActive)
		mActive = newActive
		if newActive then
			if not mPluginActive then
				plugin:Activate(true)
				mPluginActive = true
			end
			createSession()
		else
			destroySession()
		end
		updateUI()
	end

	local function closeRequested()
		setActive(false)
		plugin:Deactivate()
	end

	local function doReset()
		destroySession()
		setActive(true)
	end

	function handleAction(action: string)
		if action == "cancel" then
			closeRequested()
		elseif action == "reset" then
			doReset()
		elseif action == "togglePanelized" then
			panel.Enabled = not panel.Enabled
			updateUI()
		else
			warn("MaterialFlip: Unknown action: "..action)
		end
	end

	local clickedCn = buttonClicked:Connect(function()
		if mActive then
			setActive(false)
		else
			doReset()
		end
	end)

	-- Initial UI show in the case where we're in Panelized mode
	updateUI()

	plugin.Deactivation:Connect(function()
		mPluginActive = false
		setActive(false)
	end)

	plugin.Unloading:Connect(function()
		destroySession()
		setActive(false)
		destroyReactRoot()
		Settings.Save(plugin, activeSettings)
		clickedCn:Disconnect()
	end)
end

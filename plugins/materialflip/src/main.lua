--!strict

local Packages = script.Parent.Parent.Packages
local Signal = require(Packages.Signal)

local createMaterialFlipSession = require("./createMaterialFlipSession")

return function(plugin: Plugin, buttonClicked: Signal.Signal<>, setButtonActive: (active: boolean) -> ())
	local mSession: createMaterialFlipSession.MaterialFlipSession? = nil

	local mActive = false
	local mPluginActive = false

	local function destroySession()
		if mSession then
			mSession.Destroy()
			mSession = nil
		end
	end

	local function createSession()
		if not mSession then
			mSession = createMaterialFlipSession()
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
	end

	local clickedCn = buttonClicked:Connect(function()
		setActive(not mActive)
	end)

	plugin.Deactivation:Connect(function()
		mPluginActive = false
		setActive(false)
	end)

	plugin.Unloading:Connect(function()
		destroySession()
		setActive(false)
		clickedCn:Disconnect()
	end)
end

--!strict

local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local Src = script.Parent
local Packages = Src.Parent.Packages

local Signal = require(Packages.Signal)

local canFlip = require("./canFlip")
local doFlip = require("./doFlip")
local Settings = require("./Settings")

export type MaterialFlipSession = {
	ChangeSignal: Signal.Signal<>,
	GetHoverPart: () -> BasePart?,
	Update: () -> (),
	Destroy: () -> (),
	TestClick: (part: BasePart, point: Vector3) -> BasePart?,
}

-- Raycast the mouse into the scene, returning the hit part and hit point.
-- Which bounding box face the click acts on is determined by doFlip from the
-- hit point, in the shape's frame (not the raw hit surface, which matters
-- for curved and mesh-represented parts).
local function getTarget(): (BasePart?, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, Vector3.zero
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.BruteForceAllSlow = true
	raycastParams.CollisionGroup = "StudioSelectable"
	raycastParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(ray.Origin, ray.Direction * 9999, raycastParams)
	if not result then
		return nil, Vector3.zero
	end

	local hit = result.Instance
	if not hit:IsA("BasePart") then
		return nil, Vector3.zero
	end

	return hit, result.Position
end

local function createMaterialFlipSession(activeSettings: Settings.MaterialFlipSettings): MaterialFlipSession
	local changeSignal = Signal.new()

	local mHoverPart: BasePart? = nil
	local mDestroyed = false

	local connections: {RBXScriptConnection} = {}

	local highlight = Instance.new("Highlight")
	highlight.Name = "MaterialFlipHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = (settings().Studio :: any)["Select Color"]
	highlight.Parent = CoreGui

	local function setHoverPart(part: BasePart?)
		if part ~= mHoverPart then
			mHoverPart = part
			highlight.Adornee = part
			changeSignal:Fire()
		end
	end

	local function updateHover()
		local hit = getTarget()
		setHoverPart(if hit and canFlip(hit) then hit else nil)
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if mDestroyed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit, at = getTarget()
			if hit and canFlip(hit) then
				local result = doFlip(hit, at, activeSettings.RotateDirection == "Clockwise")
				if result then
					setHoverPart(result)
				end
			end
		end
	end))

	-- Track the hover target every frame rather than only on mouse movement,
	-- because camera movement changes the target without moving the mouse.
	local hoverThread = task.spawn(function()
		while not mDestroyed do
			updateHover()
			task.wait()
		end
	end)

	local session: MaterialFlipSession = {
		ChangeSignal = changeSignal,
		GetHoverPart = function()
			return mHoverPart
		end,
		Update = function()
			-- Called when settings change, nothing to do currently
		end,
		Destroy = function()
			mDestroyed = true
			for _, cn in connections do
				cn:Disconnect()
			end
			table.clear(connections)
			task.cancel(hoverThread)
			highlight:Destroy()
			mHoverPart = nil
		end,
		TestClick = function(part: BasePart, point: Vector3): BasePart?
			if canFlip(part) then
				return doFlip(part, point, activeSettings.RotateDirection == "Clockwise")
			end
			return nil
		end,
	}
	return session
end

return createMaterialFlipSession

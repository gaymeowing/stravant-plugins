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
	TestClick: (part: BasePart, point: Vector3, normalId: Enum.NormalId) -> (),
}

-- Raycast the mouse into the scene, returning the hit part, the hit point,
-- and the box face of the part that the hit point is closest to.
local function getTarget(): (BasePart?, Vector3, Enum.NormalId)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, Vector3.zero, Enum.NormalId.Top
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
		return nil, Vector3.zero, Enum.NormalId.Top
	end

	local hit = result.Instance
	if not hit:IsA("BasePart") then
		return nil, Vector3.zero, Enum.NormalId.Top
	end

	local at = result.Position
	local localDisp = hit.CFrame:VectorToObjectSpace(at - hit.Position)
	local halfSize = hit.Size / 2
	local smallest = math.huge
	local targetSurface = Enum.NormalId.Top

	local candidates = {
		{Enum.NormalId.Right, math.abs(localDisp.X - halfSize.X)},
		{Enum.NormalId.Left, math.abs(localDisp.X + halfSize.X)},
		{Enum.NormalId.Top, math.abs(localDisp.Y - halfSize.Y)},
		{Enum.NormalId.Bottom, math.abs(localDisp.Y + halfSize.Y)},
		{Enum.NormalId.Back, math.abs(localDisp.Z - halfSize.Z)},
		{Enum.NormalId.Front, math.abs(localDisp.Z + halfSize.Z)},
	}
	for _, candidate in candidates do
		local normalId = candidate[1] :: Enum.NormalId
		local dist = candidate[2] :: number
		if dist < smallest then
			smallest = dist
			targetSurface = normalId
		end
	end

	return hit, at, targetSurface
end

local function createMaterialFlipSession(activeSettings: Settings.MaterialFlipSettings): MaterialFlipSession
	local _ = activeSettings -- Not used yet: RotateDirection behavior comes later
	local changeSignal = Signal.new()

	local mHoverPart: BasePart? = nil
	local mDestroyed = false

	local connections: {RBXScriptConnection} = {}

	local highlight = Instance.new("Highlight")
	highlight.Name = "MaterialFlipHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = (settings().Studio :: any)["Select Color"]
	highlight.Parent = CoreGui

	local function updateHover()
		local hit = getTarget()
		local newHoverPart = if hit and canFlip(hit) then hit else nil
		if newHoverPart ~= mHoverPart then
			mHoverPart = newHoverPart
			highlight.Adornee = newHoverPart
			changeSignal:Fire()
		end
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if mDestroyed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit, at, normalId = getTarget()
			if hit and canFlip(hit) then
				doFlip(hit, at, normalId)
				updateHover()
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
		TestClick = function(part: BasePart, point: Vector3, normalId: Enum.NormalId)
			if canFlip(part) then
				doFlip(part, point, normalId)
			end
		end,
	}
	return session
end

return createMaterialFlipSession

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local InsertService = game:GetService("InsertService")

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local ASSET_ID = 76233968067050

-- Map a world-space normal to the NormalId of the closest face on a part
local function normalToFace(part: BasePart, worldNormal: Vector3): Enum.NormalId
	local localNormal = part.CFrame:VectorToObjectSpace(worldNormal)
	local bestFace = Enum.NormalId.Front
	local bestDot = -math.huge
	local axes = {
		{ Enum.NormalId.Right, Vector3.xAxis },
		{ Enum.NormalId.Left, -Vector3.xAxis },
		{ Enum.NormalId.Top, Vector3.yAxis },
		{ Enum.NormalId.Bottom, -Vector3.yAxis },
		{ Enum.NormalId.Back, Vector3.zAxis },
		{ Enum.NormalId.Front, -Vector3.zAxis },
	}
	for _, pair in axes do
		local dot = localNormal:Dot(pair[2] :: Vector3)
		if dot > bestDot then
			bestDot = dot
			bestFace = pair[1] :: Enum.NormalId
		end
	end
	return bestFace
end

-- Cached decal template (loaded once on first use)
local mDecalTemplate: Decal? = nil
local mLoadError: string? = nil
local mLoading = false

local function ensureDecalLoaded(callback: (decal: Decal?, err: string?) -> ())
	if mDecalTemplate then
		callback(mDecalTemplate, nil)
		return
	end
	if mLoadError then
		callback(nil, mLoadError)
		return
	end
	if mLoading then
		-- Already loading, just wait
		task.spawn(function()
			while mLoading do
				task.wait()
			end
			callback(mDecalTemplate, mLoadError)
		end)
		return
	end

	mLoading = true
	task.spawn(function()
		local ok, result = pcall(function()
			return InsertService:LoadAsset(ASSET_ID)
		end)
		if ok then
			local model = result :: Instance
			local decal = model:FindFirstChildWhichIsA("Decal", true)
			if decal then
				mDecalTemplate = decal
			else
				mLoadError = "No Decal found in asset"
			end
			model:Destroy()
		else
			mLoadError = tostring(result)
		end
		mLoading = false
		callback(mDecalTemplate, mLoadError)
	end)
end

local mStatusText = ""
local mUpdateUI: (() -> ())? = nil

-- Surface highlight: a SurfaceGui with a translucent blue frame
local mSurfaceGui: SurfaceGui? = nil

local function createSurfaceGui(): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SnowflakeEyesPreview"
	gui.AlwaysOnTop = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
	frame.BackgroundTransparency = 0.7
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return gui
end

local function updateSurfaceHighlight(target: BasePart?, face: Enum.NormalId?)
	if not target or not face then
		if mSurfaceGui then
			mSurfaceGui.Adornee = nil
			mSurfaceGui.Enabled = false
		end
		return
	end
	if not mSurfaceGui then
		mSurfaceGui = createSurfaceGui()
		mSurfaceGui.Parent = game:GetService("CoreGui")
	end
	mSurfaceGui.Adornee = target
	mSurfaceGui.Face = face
	mSurfaceGui.Enabled = true
end

local function onViewChanged(ctx: ToolContext)
	if ctx.Target and ctx.TargetNormal then
		local face = normalToFace(ctx.Target, ctx.TargetNormal)
		updateSurfaceHighlight(ctx.Target, face)
	else
		updateSurfaceHighlight(nil, nil)
	end
end

local function onClicked(ctx: ToolContext)
	local target = ctx.Target
	local normal = ctx.TargetNormal
	if not target or not normal then
		return
	end

	local face = normalToFace(target, normal)

	ensureDecalLoaded(function(decal, err)
		if err then
			mStatusText = "Error: " .. err
			if mUpdateUI then
				mUpdateUI()
			end
			return
		end
		if not decal then
			return
		end

		local recordingId = ctx.BeginRecording("Add Snowflake Eyes")
		local clone = decal:Clone()
		clone.Face = face
		clone.Parent = target
		if recordingId then
			ctx.FinishRecording(recordingId)
		end

		mStatusText = "Placed on " .. face.Name .. " face!"
		if mUpdateUI then
			mUpdateUI()
		end
	end)
end

local function onDeactivated(_ctx: ToolContext)
	updateSurfaceHighlight(nil, nil)
	if mSurfaceGui then
		mSurfaceGui:Destroy()
		mSurfaceGui = nil
	end
	mStatusText = ""
	mUpdateUI = nil
end

local function SnowflakeEyesSettings(props: ToolSettingsProps)
	-- Keep a ref to force re-renders when status changes from async callbacks
	local _, setRenderCount = React.useState(0)
	React.useEffect(function()
		mUpdateUI = function()
			setRenderCount(function(c)
				return c + 1
			end)
		end
		return function()
			mUpdateUI = nil
		end
	end, {})

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
		Instructions = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "Click a surface to place Snowflake Eyes",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextWrapped = true,
			LayoutOrder = 1,
		}),
		Status = if mStatusText ~= "" then e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = mStatusText,
			TextColor3 = if string.find(mStatusText, "Error") then Colors.WARNING_YELLOW else Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = 2,
		}) else nil,
	})
end

local SnowflakeEyes: ToolTypes.ToolDefinition = {
	Id = "snowflakeEyes",
	Name = "Snowflake Eyes",
	Description = "Place the Snowflake Eyes limited face on surfaces",

	OnViewChanged = onViewChanged,
	OnClicked = onClicked,
	OnDeactivated = onDeactivated,

	RenderSettings = SnowflakeEyesSettings,
}

return SnowflakeEyes

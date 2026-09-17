local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local OperationButton = require("../PluginGui/OperationButton")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

type AnimalEntry = { Name: string, Image: string }

local kAnimals: { AnimalEntry } = {
	{ Name = "Cat", Image = "rbxassetid://8073107221" },
	{ Name = "Dog", Image = "rbxassetid://315644481" },
	{ Name = "Penguin", Image = "rbxassetid://5399142150" },
	{ Name = "Owl", Image = "rbxassetid://9258910501" },
	{ Name = "Frog", Image = "rbxassetid://1073301339" },
	{ Name = "Bunny", Image = "rbxassetid://8231210" },
	{ Name = "Fox", Image = "rbxassetid://198137958" },
	{ Name = "Panda", Image = "rbxassetid://2010754979" },
	{ Name = "Hamster", Image = "rbxassetid://6734889750" },
	{ Name = "Duck", Image = "rbxassetid://4759703774" },
}

local kQuotes: { string } = {
	"Believe you can and you're halfway there.",
	"Every day is a new adventure!",
	"You're doing amazing sweetie.",
	"Be the person your pet thinks you are.",
	"The best time to start was yesterday. The second best time is now.",
	"You miss 100% of the shots you don't take.",
	"Stay pawsitive!",
	"Life is short. Smile while you still have teeth.",
	"Be yourself; everyone else is already taken.",
	"The only impossible journey is the one you never begin.",
	"You are enough. Always have been, always will be.",
	"Keep going. Everything you need will come to you.",
	"Dream big, work hard, stay focused.",
	"Happiness is a warm puppy.",
	"Today is going to be a great day!",
}

local kCorners = {
	{ AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 20, 0, 20) },
	{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 20) },
	{ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -20) },
	{ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20) },
}

--------------------------------------------------------------------------------
-- Mutable state
--------------------------------------------------------------------------------

local mScreenGui: ScreenGui? = nil
local mDelayThread: thread? = nil
local mFadeThread: thread? = nil
local mPopupCanvas: CanvasGroup? = nil
local mLastAnimal: AnimalEntry? = nil
local mLastQuote: string? = nil
local mGetSetting: ((string) -> any)? = nil
local mUpdateUI: (() -> ())? = nil

--------------------------------------------------------------------------------
-- Popup logic (imperative, lives in CoreGui)
--------------------------------------------------------------------------------

local function destroyPopup()
	if mFadeThread then
		task.cancel(mFadeThread)
		mFadeThread = nil
	end
	if mPopupCanvas then
		mPopupCanvas:Destroy()
		mPopupCanvas = nil
	end
end

local function showPopup()
	destroyPopup()

	if not mScreenGui then
		return
	end

	-- Pick random animal, quote, and corner
	local animal = kAnimals[math.random(1, #kAnimals)]
	local quote = kQuotes[math.random(1, #kQuotes)]
	local corner = kCorners[math.random(1, #kCorners)]

	mLastAnimal = animal
	mLastQuote = quote
	if mUpdateUI then
		mUpdateUI()
	end

	-- CanvasGroup for GroupTransparency fade
	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "PopupCanvas"
	canvas.Size = UDim2.fromOffset(200, 190)
	canvas.AnchorPoint = corner.AnchorPoint
	canvas.Position = corner.Position
	canvas.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	canvas.BackgroundTransparency = 0.05
	canvas.BorderSizePixel = 0
	canvas.GroupTransparency = 1

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 12)
	uiCorner.Parent = canvas

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.fromRGB(80, 80, 120)
	uiStroke.Thickness = 1
	uiStroke.Parent = canvas

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = canvas

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = canvas

	-- Animal image
	local image = Instance.new("ImageLabel")
	image.Name = "AnimalImage"
	image.Size = UDim2.fromOffset(80, 80)
	image.BackgroundTransparency = 1
	image.Image = animal.Image
	image.ScaleType = Enum.ScaleType.Fit
	image.LayoutOrder = 1
	image.Parent = canvas

	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0, 8)
	imageCorner.Parent = image

	-- Quote text
	local quoteLabel = Instance.new("TextLabel")
	quoteLabel.Name = "QuoteLabel"
	quoteLabel.Size = UDim2.new(1, 0, 0, 0)
	quoteLabel.AutomaticSize = Enum.AutomaticSize.Y
	quoteLabel.BackgroundTransparency = 1
	quoteLabel.Text = "\u{201C}" .. quote .. "\u{201D}"
	quoteLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	quoteLabel.Font = Enum.Font.SourceSansItalic
	quoteLabel.TextSize = 14
	quoteLabel.TextWrapped = true
	quoteLabel.LayoutOrder = 2
	quoteLabel.Parent = canvas

	-- Animal name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "AnimalName"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "\u{2014} " .. animal.Name
	nameLabel.TextColor3 = Color3.fromRGB(160, 160, 190)
	nameLabel.Font = Enum.Font.SourceSansItalic
	nameLabel.TextSize = 13
	nameLabel.LayoutOrder = 3
	nameLabel.Parent = canvas

	canvas.Parent = mScreenGui
	mPopupCanvas = canvas

	-- Fade in
	TweenService:Create(
		canvas,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	):Play()

	-- After 4 seconds, fade out and destroy
	mFadeThread = task.delay(4, function()
		if mPopupCanvas ~= canvas then
			return
		end
		local fadeOut = TweenService:Create(
			canvas,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()
		if mPopupCanvas == canvas then
			canvas:Destroy()
			mPopupCanvas = nil
			mFadeThread = nil
		end
	end)
end

local function scheduleNextPopup()
	local minInterval = if mGetSetting then (mGetSetting("MinInterval") :: number) else 8
	local maxInterval = if mGetSetting then (mGetSetting("MaxInterval") :: number) else 20
	local interval = minInterval + math.random() * (maxInterval - minInterval)
	mDelayThread = task.delay(interval, function()
		mDelayThread = nil
		showPopup()
		scheduleNextPopup()
	end)
end

local function stopPopupLoop()
	if mDelayThread then
		task.cancel(mDelayThread)
		mDelayThread = nil
	end
	destroyPopup()
	if mScreenGui then
		mScreenGui:Destroy()
		mScreenGui = nil
	end
	mGetSetting = nil
	mUpdateUI = nil
	mLastAnimal = nil
	mLastQuote = nil
end

--------------------------------------------------------------------------------
-- Settings panel (React)
--------------------------------------------------------------------------------

local function AnimalQuotesSettings(props: ToolSettingsProps)
	local minInterval = props.GetSetting("MinInterval") :: number
	local maxInterval = props.GetSetting("MaxInterval") :: number

	local lastInfo: string? = nil
	if mLastAnimal and mLastQuote then
		lastInfo = mLastAnimal.Name .. ": \u{201C}" .. mLastQuote :: string .. "\u{201D}"
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		StatusLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = if mDelayThread then "Waiting for next popup..." else "Not running",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		MinIntervalInput = e(NumberInput, {
			Label = "Min Interval",
			Value = minInterval,
			Unit = "s",
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 2, 120)
				if newValue > maxInterval then
					newValue = maxInterval
				end
				props.SetSetting("MinInterval", newValue)
				return newValue
			end,
			LayoutOrder = 2,
		}),
		MaxIntervalInput = e(NumberInput, {
			Label = "Max Interval",
			Value = maxInterval,
			Unit = "s",
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 2, 120)
				if newValue < minInterval then
					newValue = minInterval
				end
				props.SetSetting("MaxInterval", newValue)
				return newValue
			end,
			LayoutOrder = 3,
		}),
		ShowNowButton = e(OperationButton, {
			Text = "Show Now",
			Height = 30,
			Disabled = mScreenGui == nil,
			Color = Colors.ACTION_BLUE,
			LayoutOrder = 4,
			OnClick = function()
				showPopup()
			end,
		}),
		LastShown = lastInfo and e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = "Last: " .. lastInfo,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 5,
		}),
	})
end

--------------------------------------------------------------------------------
-- Tool definition
--------------------------------------------------------------------------------

local AnimalQuotes: ToolTypes.ToolDefinition = {
	Id = "animalQuotes",
	Name = "Animal Quotes",
	Description = "Random animal pictures with inspirational quotes",

	DefaultSettings = {
		MinInterval = 8,
		MaxInterval = 20,
	},

	OnActivated = function(ctx: ToolContext)
		mGetSetting = ctx.GetSetting
		mUpdateUI = ctx.UpdateUI
		mScreenGui = Instance.new("ScreenGui")
		mScreenGui.Name = "AnimalQuotePopup"
		mScreenGui.IgnoreGuiInset = true
		mScreenGui.DisplayOrder = 999
		mScreenGui.Parent = CoreGui
		scheduleNextPopup()
	end,

	OnDeactivated = function(_ctx: ToolContext)
		stopPopupLoop()
	end,

	RenderSettings = AnimalQuotesSettings,
}

return AnimalQuotes

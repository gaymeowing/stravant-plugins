--!strict

export type ToolContext = {
	Plugin: Plugin,
	Target: BasePart?,
	TargetNormal: Vector3?,
	TargetPosition: Vector3?,
	IsMouseDown: boolean,
	GetSetting: (key: string) -> any,
	SetSetting: (key: string, value: any) -> (),
	SetHighlight: (part: BasePart?, hideOutline: boolean?) -> (),
	BeginRecording: (name: string) -> string?,
	FinishRecording: (id: string) -> (),
	UpdateUI: () -> (),
}

export type ToolSettingsProps = {
	GetSetting: (key: string) -> any,
	SetSetting: (key: string, value: any) -> (),
	LayoutOrder: number?,
}

export type ToolDefinition = {
	Id: string,
	Name: string,
	Description: string,

	-- Lifecycle (all optional, called by main.lua)
	OnActivated: ((ctx: ToolContext) -> ())?,
	OnDeactivated: ((ctx: ToolContext) -> ())?,
	OnViewChanged: ((ctx: ToolContext) -> ())?,
	OnClicked: ((ctx: ToolContext) -> ())?,
	OnReleased: ((ctx: ToolContext) -> ())?,
	OnMouseEnterViewport: ((ctx: ToolContext) -> ())?,
	OnMouseLeaveViewport: ((ctx: ToolContext) -> ())?,

	-- UI: React component for tool-specific settings panel
	RenderSettings: ((props: ToolSettingsProps) -> any)?,

	-- Default persisted settings for this tool
	DefaultSettings: { [string]: any }?,
}

return {}

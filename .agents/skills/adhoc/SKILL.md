---
name: adhoc
description: >-
  Guidance for the AdHoc (Adhoc Tools) Studio plugin: micro-tool discovery, ToolDefinition lifecycle, settings, and React UI. Use when working on plugins/AdHoc or Adhoc Tools.
---

# AdHoc

## Project Overview

Adhoc Tools is a Roblox Studio plugin that serves as a container for small, community-requested tools. Unlike other GeomTools plugins which each implement a single operation, Adhoc dynamically discovers and manages a collection of independent micro-tools from `plugins/AdHoc/src/Tools/`. It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# From repo root
lute scripts/build.luau AdHoc
lute scripts/build.luau AdHoc --watch
lute run scripts/test AdHoc
```

Shared toolchain is root `foreman.toml` / `wally.toml`. PluginGui lives in `libraries/PluginGui` (required as `Src.PluginGui`).


## Architecture

Tool-based variant of the three-layer design:

1. **Functionality layer** — Tool modules with lifecycle callbacks.
   - `plugins/AdHoc/src/Tools/*.luau` — Each tool is a self-contained module returning a `ToolDefinition` with Id, Name, Description, and lifecycle callbacks (OnActivated/Deactivated/ViewChanged/Clicked/Released).
   - `plugins/AdHoc/src/ToolTypes.luau` — Type definitions for ToolDefinition and ToolContext.
   - `plugins/AdHoc/src/Dragger/` — 3D handle implementations for RotateSelection tool.

2. **Settings layer** — Persistent configuration via `plugin:GetSetting`/`SetSetting`.
   - `plugins/AdHoc/src/Settings.luau` — Settings key `"adhocToolsState"`. Stores pinned tools, per-tool settings, last active tool.

3. **UI layer** — React components.
   - `plugins/AdHoc/src/AdhocGui.luau` — Tool list, active tool view with settings panel, pinning UI.
   - `libraries/PluginGui/` — Shared reusable UI components (mapped as `Src.PluginGui`).

**Entry point:** `plugins/AdHoc/loader.server.luau` creates the toolbar button and dock widget, then lazy-loads `plugins/AdHoc/src/main.luau` on first activation. `plugins/AdHoc/src/main.luau` dynamically discovers all tools from `plugins/AdHoc/src/Tools/`, manages tool activation/deactivation, handles viewport input (raycasting, mouse events), and mounts the React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking) and many use `--!native` (native codegen).
- Types are defined with `export type` and collected in `libraries/PluginGui/Types.luau` for UI-related types.
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Tools are auto-discovered from `plugins/AdHoc/src/Tools/` — no hardcoded tool list.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints.

## Dependencies (via Wally)

- **React / ReactRoblox / RoactCompat** — UI framework
- **DraggerFramework / DraggerSchemaCore** — 3D handle/manipulator system (authored by stravant)
- **Roact** — Used by DraggerToolComponent for handle rendering
- **Signal (GoodSignal)** — Event system
- **Geometry** — Geometric utilities
- **createSharedToolbar** — Optional toolbar combining with other plugins


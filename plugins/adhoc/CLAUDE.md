# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Adhoc Tools is a Roblox Studio plugin that serves as a container for small, community-requested tools. Unlike other GeomTools plugins which each implement a single operation, Adhoc dynamically discovers and manages a collection of independent micro-tools from `src/Tools/`. It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# Build the plugin (default build task)
rojo build -p "Adhoc Tools v1.0.rbxmx"

# Run tests (*.spec.lua files in the Src folder)
# Tests can call t.screenshot("name") to capture the viewport (use Read tool to view the output)
# For UI tests: mount into ScreenGui parented to CoreGui, use ReactRoblox.act to flush rendering
python runtests.py

# Install dependencies (must fix the Luau types after installing)
wally install
rojo sourcemap default.project.json --output sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages
```

Tools are managed via Aftman (`aftman.toml`): Rojo 7.6.1. Dependencies are managed via Wally (`wally.toml`).

## Architecture

Tool-based variant of the three-layer design:

1. **Functionality layer** — Tool modules with lifecycle callbacks.
   - `src/Tools/*.lua` — Each tool is a self-contained module returning a `ToolDefinition` with Id, Name, Description, and lifecycle callbacks (OnActivated/Deactivated/ViewChanged/Clicked/Released).
   - `src/ToolTypes.lua` — Type definitions for ToolDefinition and ToolContext.
   - `src/Dragger/` — 3D handle implementations for RotateSelection tool.

2. **Settings layer** — Persistent configuration via `plugin:GetSetting`/`SetSetting`.
   - `src/Settings.lua` — Settings key `"adhocToolsState"`. Stores pinned tools, per-tool settings, last active tool.

3. **UI layer** — React components.
   - `src/AdhocGui.lua` — Tool list, active tool view with settings panel, pinning UI.
   - `src/PluginGui/` — Shared reusable components (copied verbatim across plugins).

**Entry point:** `loader.server.lua` creates the toolbar button and dock widget, then lazy-loads `src/main.lua` on first activation. `src/main.lua` dynamically discovers all tools from `src/Tools/`, manages tool activation/deactivation, handles viewport input (raycasting, mouse events), and mounts the React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking) and many use `--!native` (native codegen).
- Types are defined with `export type` and collected in `src/PluginGui/Types.lua` for UI-related types.
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Tools are auto-discovered from `src/Tools/` — no hardcoded tool list.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints.

## Dependencies (via Wally)

- **React / ReactRoblox / RoactCompat** — UI framework
- **DraggerFramework / DraggerSchemaCore** — 3D handle/manipulator system (authored by stravant)
- **Roact** — Used by DraggerToolComponent for handle rendering
- **Signal (GoodSignal)** — Event system
- **Geometry** — Geometric utilities
- **createSharedToolbar** — Optional toolbar combining with other plugins

---
name: resizealign
description: >-
  Guidance for the ResizeAlign Studio plugin: face selection, resize modes, doExtend, and React UI. Use when working on plugins/ResizeAlign or resize align.
---

# ResizeAlign

## Project Overview

ResizeAlign is a Roblox Studio plugin which allows the user to click two faces of parts in 3D space, and have the plugin resize/extend those parts so the faces meet. Seven resize modes are supported: OuterTouch, InnerTouch, WedgeJoin, RoundedJoin, ButtJoint, ExtendUpTo, and ExtendInto.
It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# From repo root
# DO NOT build using rojo build -o. Use lute scripts/build.luau (rojo -p under the hood).
lute scripts/build.luau ResizeAlign
lute scripts/build.luau ResizeAlign --watch
lute run scripts/test ResizeAlign
```

Shared toolchain is root `foreman.toml` / `wally.toml`. PluginGui lives in `libraries/PluginGui` (required as `Src.PluginGui`).


## Architecture

Three-layer design:

1. **Functionality layer** — Face selection, raycasting, resize geometry.
   - `plugins/ResizeAlign/src/createResizeAlignSession.luau` — Session lifecycle: face selection FSM (FaceA → FaceB), input handling via UserInputService, edge-threshold smart face detection, DraggerHandler for Ctrl+click mode.
   - `plugins/ResizeAlign/src/doExtend.luau` — Core resize algorithm: computes how to resize two parts so their selected faces meet according to the chosen mode. Integrates with ChangeHistoryService and JointMaker.
   - `plugins/ResizeAlign/src/FaceHighlight.luau` — React component rendering face adornments (BoxHandleAdornment + CylinderHandleAdornments) for hover/selected faces.
   - `plugins/ResizeAlign/src/copyPartProps.luau` — Copies physical/visual properties when creating new parts (used by RoundedJoin fill).
   - `plugins/ResizeAlign/src/TestTypes.luau` — Types definition of the testing framework, spec files take in a type from here.

2. **Settings layer** — Persistent configuration that the functionality layer reads.
   - `plugins/ResizeAlign/src/Settings.luau` — Reads/writes plugin settings (key: `"resizeAlignState"`), exposes ResizeMode, SelectionThreshold, and ClassicUI options.

3. **UI layer** — React components that modify settings and trigger operations.
   - `plugins/ResizeAlign/src/ResizeAlignGui.luau` — Main settings panel (React) with modern (ChipForToggle) and classic (OperationButton) UI modes. Includes AdornmentOverlay that portals face highlights to CoreGui.
   - `libraries/PluginGui/` — Shared reusable UI components (mapped as `Src.PluginGui`).

**Entry point:** `plugins/ResizeAlign/loader.server.luau` creates the toolbar button and dock widget, then lazy-loads `plugins/ResizeAlign/src/main.luau` on first activation. `plugins/ResizeAlign/src/main.luau` orchestrates the three layers — it manages the active session, and mounts the React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking) and many use `--!native` (native codegen).
- Types are defined with `export type` and collected in `libraries/PluginGui/Types.luau` for UI-related types.
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Modules typically `return` a single function (e.g., `createResizeAlignSession`, `doExtend`) rather than a table of exports.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints (`TryBeginRecording`/`FinishRecording`).

## Dependencies (via Wally)

- **React / ReactRoblox** — UI framework
- **DraggerFramework** — 3D handle/manipulator system (authored by stravant)
- **DraggerHandler** — Simple wrapper around DraggerFramework to activate a basic dragger tool that can move selected objects.
- **Signal (GoodSignal)** — Event system
- **Geometry** — Geometric utility library
- **createSharedToolbar** — Optional toolbar combining with other plugins


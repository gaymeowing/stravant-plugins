---
name: polymap
description: >-
  Guidance for the PolyMap Studio plugin: triangle mesh editing modes, sessions, overlays, and React UI. Use when working on plugins/PolyMap or polymap terrain meshes.
---

# PolyMap

## Project Overview

PolyMap is a Roblox Studio plugin that provides a terrain mesh editor. Users can create, edit, and paint triangle meshes built from thin wedge parts. It supports multiple editing modes: Select, Move, Rotate, Add, Delete, Paint, and Generate (grid generation). It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# From repo root
lute scripts/build.luau PolyMap
lute scripts/build.luau PolyMap --watch
lute run scripts/test PolyMap
```

Shared toolchain is root `foreman.toml` / `wally.toml`. PluginGui lives in `libraries/PluginGui` (required as `Src.PluginGui`).


## Architecture

Three-layer design:

1. **Functionality layer** — Session lifecycle, mesh editing, 3D handles.
   - `plugins/PolyMap/src/createPolyMapSession.luau` — Session lifecycle: manages triangle mesh state, vertex selection, 6 editing modes, marquee selection, stroke operations, input handling via UserInputService.
   - `plugins/PolyMap/src/TriangleMesh.luau` — Data structure managing triangle mesh topology (vertices, triangles, edges), including workspace discovery/scanning.
   - `plugins/PolyMap/src/fillTriangle.luau` — Creates 1-2 thin wedge parts from 3 vertices.
   - `plugins/PolyMap/src/generateGrid.luau` — Generates square or triangular grids.
   - `plugins/PolyMap/src/getWedgeVertices.luau` — Extracts triangle vertices from thin wedge parts.
   - `plugins/PolyMap/src/Dragger/` — 3D handle implementations (Move, Rotate) built on DraggerFramework, with influence radius/falloff.

2. **Settings layer** — Persistent configuration via `plugin:GetSetting`/`SetSetting`.
   - `plugins/PolyMap/src/Settings.luau` — Settings key `"polyMapState"`. Stores mode, thickness, influence radius/falloff, grid params, paint color/material.

3. **UI layer** — React components.
   - `plugins/PolyMap/src/PolyMapGui.luau` — Main settings panel with mode selection and per-mode settings.
   - `plugins/PolyMap/src/MeshOverlay.luau` — React component rendering selected/hovered vertex markers and wireframe outlines.
   - `plugins/PolyMap/src/VertexMarker.luau` — SphereHandleAdornment for vertex visualization.
   - `libraries/PluginGui/` — Shared reusable UI components (mapped as `Src.PluginGui`).

**Entry point:** `plugins/PolyMap/loader.server.luau` creates the toolbar button and dock widget, then lazy-loads `plugins/PolyMap/src/main.luau` on first activation. `plugins/PolyMap/src/main.luau` orchestrates session management and mounts the React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking) and many use `--!native` (native codegen).
- Types are defined with `export type` and collected in `libraries/PluginGui/Types.luau` for UI-related types.
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Modules typically `return` a single function rather than a table of exports.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints.

## Dependencies (via Wally)

- **React / ReactRoblox / RoactCompat** — UI framework
- **DraggerFramework / DraggerSchemaCore** — 3D handle/manipulator system (authored by stravant)
- **DraggerHandler** — Simple wrapper around DraggerFramework
- **Roact** — Used by DraggerToolComponent for handle rendering
- **Signal (GoodSignal)** — Event system
- **Geometry** — Geometric utilities
- **createSharedToolbar** — Optional toolbar combining with other plugins


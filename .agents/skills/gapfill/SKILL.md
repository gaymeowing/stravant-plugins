---
name: gapfill
description: >
  Guidance for the GapFill Studio plugin: edge picking, gap-fill geometry, sessions, and React UI. Use when working on plugins/GapFill or gap fill.
---

# GapFill

## Project Overview

GapFill is a Roblox Studio plugin which allows the user to click edges of two parts in 3d space, and

Build/test/deps: see the `plugin` skill.
have the plugin generate geometry that "fills the gap" between those edges. The user can choose a
thickness for the generated geometry.

## Architecture

Three-layer design:

1. **Functionality layer** — Scene manipulation, handle rendering, ghost previews, final placement.
   - `plugins/GapFill/src/createGapFillSession.luau` — Session lifecycle: creates/updates/commits duplicated geometry, manages undo waypoints.
   - `plugins/GapFill/src/doFill.luau` — Generate geometry that fills the gap between two edges.
   - `plugins/GapFill/src/Dragger/` — 3D handle implementations (Move, Rotate, Scale) built on DraggerFramework.
   - `plugins/GapFill/src/TestTypes.luau` — Types definition of the testing framework, spec files take in a type from here.

2. **Settings layer** — Persistent configuration that the functionality layer reads.
   - `plugins/GapFill/src/Settings.luau` — Reads/writes plugin settings, exposes current configuration state.

3. **UI layer** — React components that modify settings and trigger operations.
   - `plugins/GapFill/src/GapFillGui.luau` — Main settings panel (React).
   - `libraries/PluginGui/` — Shared reusable UI components (mapped as `Src.PluginGui`).

**Entry point:** `plugins/GapFill/loader.server.luau` creates the toolbar button and dock widget, then lazy-loads `plugins/GapFill/src/main.luau` on first activation. `plugins/GapFill/src/main.luau` orchestrates the three layers — it listens for selection changes, manages the active model refect session, and mounts the React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking) and many use `--!native` (native codegen).
- Types are defined with `export type` and collected in `libraries/PluginGui/Types.luau` for UI-related types.
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Modules typically `return` a single function (e.g., `createGapFillSession`, `doFill`) rather than a table of exports.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints

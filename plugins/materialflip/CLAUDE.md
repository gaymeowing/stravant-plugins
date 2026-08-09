# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MaterialFlip is a Roblox Studio plugin that lets users flip and rotate material orientation on parts by clicking them. It highlights flippable parts on hover and rotates their surfaces/dimensions on click, keeping the part occupying the same space. It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# Build the plugin to the plugins directory (default build task)
# DO NOT build using rojo build -o. -p was added recently for plugins and is what we need.
rojo build -p "MaterialFlip v2.0.rbxmx"

# Run tests (*.spec.lua files in the src folder)
# Tests can call t.screenshot("name") to capture the viewport (use Read tool to view the output)
python runtests.py

# Install dependencies (must fix the Luau types after installing)
wally install
rojo sourcemap default.project.json --output sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages
```

Tools are managed via Aftman (`aftman.toml`): Rojo 7.6.1. Dependencies are managed via Wally (`wally.toml`).

## Architecture

MaterialFlip follows the modern GeomTools three-layer plugin architecture (see GapFill / ResizeAlign). The tool itself is a one-shot effect on click with hover feedback, so there is no multi-step session state.

1. **Functionality layer** — Targeting, hover feedback, the flip operation.
   - `src/Orientation.lua` — The 24-element octahedral rotation group as signed permutation matrices, with stable integer ids, composition/inverse tables, quarter turn constructors, and size permutation helpers.
   - `src/ShapeData.lua` — Per-shape symmetry groups H (Brick/Ball: 24, Cylinder: 8, Wedge: 2, CornerWedge: 1) and orientation class (right coset) bookkeeping. Class count = 24/|H| = number of distinct baked meshes a shape needs.
   - `src/getShape.lua` — Classifies a part's primitive shape (Brick, Wedge, CornerWedge, Cylinder, Ball, Terrain), honoring SpecialMesh children.
   - `src/identifyPart.lua` — Reverse lookup of a part's flip state (shape, material orientation m, shape frame P, shape size). Primitives are always m = identity; MeshPart representations are identified by the MeshId of the published assets, recovering the class representative (equivalent modulo the shape's symmetry group - all downstream behavior is invariant to this).
   - `src/canFlip.lua` — Whether a part is flippable (identifiable and not locked).
   - `src/doFlip.lua` — The flip: a quarter turn about the clicked bounding box face (clockwise or counterclockwise per settings). Computes m' = r * m, then represents m' with the primitive when m' is in H (always preferred), else a MeshPart from the published orientation class meshes. Updates in place when the representation class is unchanged, otherwise swaps the instance (preserving properties, children, selection, and undo).
   - `src/MeshAssets.lua` — The published mesh asset id table: one unit mesh per (shape, non-identity orientation class): 11 Wedge + 23 CornerWedge + 2 Cylinder. Also the MeshId reverse lookup. Orientation ids are pinned by these tables; Orientation.lua's enumeration must stay deterministic.
   - `src/getMeshRepresentation.lua` — Creates MeshParts from the published assets (cached templates, Hull collision).
   - `src/buildShapeMesh.lua` — EditableMesh builders for Wedge/CornerWedge/Cylinder with a baked orientation; the source of truth the published assets were generated from (via `AssetService:CreateAssetAsync` at unit size). If geometry changes, assets must be regenerated and MeshAssets.lua updated together.
   - `src/copyPartProps.lua` — Property copying for representation swaps.
   - `src/createMaterialFlipSession.lua` — Session lifecycle: raycast targeting, hover highlight via a `Highlight` instance in CoreGui, click-to-flip via UserInputService. Face selection uses the closest bounding box face in the shape's frame (not the hit surface), which matters for curved and mesh-represented parts.
   - `src/TestTypes.lua` — Types definition of the testing framework, spec files take in a type from here.

**Key rendering facts (verified empirically):**
- Built-in materials on MeshParts ignore UVs entirely; they are a triplanar projection in the part's local frame. Baking a rotation into mesh geometry (with compensating CFrame) is what rotates the material.
- Primitives use special per-face material mappings on sloped faces (e.g. a wedge primitive runs planks up the slope) which triplanar MeshParts cannot reproduce, so the primitive <-> mesh transition is visible on sloped faces. Unavoidable; primitives are preferred wherever possible.

2. **Settings layer** — Persistent configuration that the functionality layer reads.
   - `src/Settings.lua` — Reads/writes plugin settings (key: `"materialFlipState"`). `RotateDirection` (Clockwise / CounterClockwise) selects the quarter turn direction, plus the standard window state.

3. **UI layer** — React components that modify settings and trigger operations.
   - `src/MaterialFlipGui.lua` — Main settings panel (React): rotate direction chips and a close button.
   - `src/PluginGui/` — Reusable UI components shared with the other GeomTools plugins (PluginGui window frame, SubPanel, ChipForToggle, OperationButton, HelpGui, Colors, Types).

**Entry point:** `loader.server.lua` creates the toolbar button and dock widget, then lazy-loads `src/main.lua` on first activation. `src/main.lua` orchestrates the three layers — it manages the active session and mounts the React UI (in the dock panel when Panelized, otherwise in a floating window in CoreGui).
- `src/define.lua` — Plugin name/icon/tooltip needed by the loader before main is loaded.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking).
- React components use `React.createElement` (aliased as `e`) — not JSX.
- Input is via `UserInputService` (never the deprecated plugin mouse API).
- The Signal library (`Packages.Signal`) is used for custom events.
- Modules returning a single function are lowerCamelCase (e.g., `createMaterialFlipSession`, `doFlip`); modules returning a table are UpperCamelCase (e.g., `Settings`).
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints (`TryBeginRecording`/`FinishRecording`, with a `SetWaypoint` fallback).
- Tests are `*.spec.lua` files in `src/`, excluded from builds via `globIgnorePaths`.

## Dependencies (via Wally)

- **React / ReactRoblox** — UI framework
- **Signal (GoodSignal)** — Event system
- **createSharedToolbar** — Optional toolbar combining with other plugins

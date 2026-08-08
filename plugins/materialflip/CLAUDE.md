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

MaterialFlip follows the modern GeomTools plugin architecture (see GapFill / ResizeAlign), minus the layers it doesn't need: it has no settings and no React UI panel — the tool is a one-shot effect on click with hover feedback, so there is no multi-step session state.

- `loader.server.lua` — Entry point: creates the toolbar button, then lazy-loads `src/main.lua` on first activation.
- `src/define.lua` — Plugin name/icon/tooltip needed by the loader before main is loaded.
- `src/main.lua` — Activation state: toggles the session on toolbar click, handles plugin Deactivation/Unloading.
- `src/createMaterialFlipSession.lua` — Session lifecycle: raycast-based targeting (closest box face), hover highlight via a `Highlight` instance in CoreGui, click-to-flip via UserInputService.
- `src/getShape.lua` — Classifies a part's shape (Brick, Wedge, CornerWedge, Round, Terrain), honoring SpecialMesh children.
- `src/canFlip.lua` — Whether a part is flippable (unlocked Brick/Wedge/Round).
- `src/doFlip.lua` — The one-shot flip operation: rotates CFrame, swaps dimensions and surface types per shape, as a single undoable recording.
- `src/TestTypes.lua` — Types definition of the testing framework, spec files take in a type from here.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking).
- Input is via `UserInputService` (never the deprecated plugin mouse API).
- The Signal library (`Packages.Signal`) is used for custom events.
- Modules return a single function (e.g., `createMaterialFlipSession`, `doFlip`, `getShape`).
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints (`TryBeginRecording`/`FinishRecording`, with a `SetWaypoint` fallback).
- Tests are `*.spec.lua` files in `src/`, excluded from builds via `globIgnorePaths`.

## Dependencies (via Wally)

- **Signal (GoodSignal)** — Event system
- **createSharedToolbar** — Optional toolbar combining with other plugins

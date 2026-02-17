# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MaterialFlip is a Roblox Studio plugin that lets users flip and rotate material orientation on parts by clicking them. It highlights flippable parts on hover and rotates their surfaces/dimensions on click. It outputs a `.rbxmx` plugin file built via Rojo.

## Build Commands

```bash
# Build the plugin (default build task)
rojo build -p "MaterialFlip v1.1.0.rbxmx"

# Install dependencies
wally install
```

Tools are managed via Aftman (`aftman.toml`): Rojo 7.3.0. Dependencies are managed via Wally (`wally.toml`).

## Architecture

**Single-file plugin** — all logic lives in `src/main.server.lua`. Unlike other GeomTools plugins, MaterialFlip does not use the three-layer modular architecture. There is no UI panel, no React, no separate Settings module.

- `src/main.server.lua` — Complete implementation: toolbar setup, mouse input, part shape detection, surface rotation logic, highlight feedback, settings helpers.
- `extra/` — Contains the toolbar button entry point (referenced by default.project.json tree root).

**Key functionality:**
- Detects part shapes (Brick, Wedge, CornerWedge, Round, Terrain)
- Highlights flippable parts on hover via a `Highlight` instance
- Rotates surface properties and adjusts part dimensions on click
- Settings stored via `plugin:SetSetting()` with `"MaterialFlip"` key prefix

## Key Conventions

- Uses `SetWaypoint()` for undo (legacy — other plugins use `TryBeginRecording`/`FinishRecording`)
- Uses mouse API for input (legacy — other plugins use `UserInputService`)
- No test infrastructure

## Dependencies (via Wally)

- **createSharedToolbar** — Optional toolbar combining with other plugins

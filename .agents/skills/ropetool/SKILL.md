---
name: ropetool
description: >
  Guidance for the RopeTool Studio plugin: implicit rope discovery, Add/Move/Color modes, ropeCurve, and React UI. Use when working on plugins/RopeTool or rope editing.
---

# RopeTool

## Project Overview

RopeTool is a Roblox Studio plugin for creating and editing "ropes": contiguous chains of
elongated parts (boxes or cylinders) laid end to end, e.g. hanging ropes strung between two
attachment points. Like PolyMap, the rope structure is *implicitly discovered* from the parts in
the scene rather than stored anywhere: a discovered rope is a list of vertices joined by edges,
where each edge remembers which side of it its part sits on.

Modes:
- **Add** — click two attachment points (snapping to part corners/edges, including mesh edges via
  the Geometry package's `blackboxFindClosestMeshEdge`) to build a sagging rope between them.
- **Move** — hover/click to select a rope (discovered by walking matching adjacent parts), then
  drag its endpoints (axis arrows, or the endpoint sphere for a free drag with Add-style
  snapping) or the middle handle cluster (vertical pair = sag, horizontal pair perpendicular to
  the chord = sway). Panel edits (segments, type, diameter, sag, sway) apply to the selected
  rope.
- **Color** — the appearance tool: same hover/click rope selection as Move (the selection is
  shared between the two), but no drag handles; the Color and Material panels live here and
  apply to the selected rope.
- **Settings** — global options: the Snapping section ("Other Ropes" / "Geometry Edges"
  checkboxes) gates the two snap tiers used by Add clicks and Move's endpoint grab drags.

Build/test/deps: see the `plugin` skill.

## Architecture

Three-layer design:

1. **Functionality layer** — Session lifecycle, rope discovery/building, 3D handles.
   - `plugins/RopeTool/src/createRopeSession.luau` — Session lifecycle: Move/Add tools, hover + selection UX,
     endpoint/sag draggers, add-point snapping, undo/redo via ChangeHistoryService recordings.
   - `plugins/RopeTool/src/RopeGraph.luau` — Implicit discovery: vertices + edges walked from a seed part via
     endpoint adjacency and a property-overlap heuristic (shape / cross-section / color / material).
     The chain is trimmed at curvature discontinuities (a joint whose bend reverses against its
     neighbours, e.g. the middle of a W where two ropes meet, or any bend over 60°). Sphere
     endcaps on the chain's end vertices are discovered too (and work as seeds).
   - `plugins/RopeTool/src/buildRope.luau` — Builds/updates the segment parts along the curve, reusing parts in
     place during drags.
   - `plugins/RopeTool/src/ropeCurve.luau` — The parabolic curve: point generation and sag/sway estimation
     (inverse). Sag droops vertically; sway bows horizontally perpendicular to the chord.
   - `plugins/RopeTool/src/Dragger/` — MoveHandles (with optional axis filter for the vertical-only sag handle)
     and GrabPointHandle (the freely-draggable endpoint sphere with Add-style snapping), built
     on DraggerFramework.

2. **Settings layer** — Persistent configuration via `plugin:GetSetting`/`SetSetting`.
   - `plugins/RopeTool/src/Settings.luau` — Settings key `"ropeToolState"`. Stores mode, segments, segment type,
     grouping, sag, sway, diameter, endcaps, rope color/material, recent colors/materials.
   - Settings are saved only once, on `plugin.Unloading` (see `plugins/RopeTool/src/main.luau`). This is
     intentional: the settings are relatively transient, so saving once at shutdown is
     preferable to writing on every edit — losing them to a hard Studio crash is acceptable.

3. **UI layer** — React components.
   - `plugins/RopeTool/src/RopeToolGui.luau` — Main settings panel: mode chips, rope parameters, and the
     color/material selection UX (shared design with PolyMap's paint panels).
   - `plugins/RopeTool/src/RopeOverlay.luau` — Viewport overlay: hover/selected rope polylines, add-point markers,
     preview curve.
   - `libraries/PluginGui/` — Shared reusable UI components (mapped as `Src.PluginGui`); don't change unless asked.

**Entry point:** `plugins/RopeTool/loader.server.luau` creates the toolbar button and dock widget, then lazy-loads
`plugins/RopeTool/src/main.luau` on first activation. `plugins/RopeTool/src/main.luau` orchestrates session management and mounts the
React UI.

## Key Conventions

- All source files use `--!strict` (Luau strict type checking).
- React components use `React.createElement` (aliased as `e`) — not JSX.
- The Signal library (`Packages.Signal`) is used for custom events throughout.
- Modules typically `return` a single function rather than a table of exports.
- Undo/redo integrates with `ChangeHistoryService` using recording-based waypoints; on undo/redo
  the selection is re-resolved by re-discovering the rope from a surviving part (discovery is
  stateless, so there is no mesh rebuild machinery like PolyMap's).

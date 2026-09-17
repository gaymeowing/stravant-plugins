---
name: roadhelper
description: >
  Guidance for the RoadHelper Studio plugin: procedural road endpoints, handles, RoadMath, and React UI. Use when working on plugins/RoadHelper or procedural roads.
---

# RoadHelper

## Project Overview

RoadHelper is a Roblox Studio plugin (based on the Redupe plugin's architecture) for working
with procedural road segments — `ProceduralModel` instances containing a
`StraightRoadGenerator` or `CurveRoadGenerator` ModuleScript, as found in the ProceduralCarts
place. The core mechanic is selecting and manipulating road segment *endpoints*:

- An endpoint is one end of a segment: **blue** (start/entry) or **red** (end/exit),
  matching the road generators' `AdjustBlue*`/`AdjustRed*` attribute naming.
- An endpoint is **open** (no adjacent road) or **closed** (two segment ends joined).
- Selected endpoints get **move handles** (repositions the endpoint by editing the segment's
  Size/pivot/Flip — both segments for a closed joint) and **rotate handles** (edits the
  `AdjustBlue/RedDir/Grade/Bank` attributes — both sides of a closed joint stay continuous).
- Open endpoints additionally get three **add handles** (left turn / straight / right turn):
  click to append a new segment, click-drag to place its far endpoint following the cursor.
- The UI panel shows the selected endpoint's angles for numeric editing, plus an Add section
  with Straight/Curve buttons that add a segment in front of the camera.

Build/test/deps: see the `plugin` skill.

## Architecture

**Entry point:** `plugins/RoadHelper/loader.server.luau` creates the toolbar button and dock widget, then
lazy-loads `plugins/RoadHelper/src/main.luau` on first activation.

- `plugins/RoadHelper/src/main.luau` — Orchestrator: plugin activation lifecycle, React UI root, session management.
- `plugins/RoadHelper/src/RoadMath.luau` — Pure math: segment descriptors from a ProceduralModel's Size/attributes/
  pivot, blue/red endpoint world frames, endpoint-move solving (Size + pivot + Flip), joint
  detection, and Adjust-attribute sign mapping for rotations at either end color.
- `plugins/RoadHelper/src/createRoadSession.luau` — Active tool session: mounts a DraggerFramework
  DraggerToolComponent with a custom handle list, tracks the selected endpoint, applies edits
  with ChangeHistoryService recordings.
- `plugins/RoadHelper/src/Handles/` — Handle implementations following the DraggerFramework handles protocol
  (`update`/`hitTest`/`render`/`mouseDown`/`mouseDrag`/`mouseUp`):
  - `EndpointPickHandles.luau` — clickable markers on every road endpoint.
  - `EndpointMoveHandles.luau` — arrow handles moving the selected endpoint (adapted from Redupe).
  - `EndpointRotateHandles.luau` — arc handles editing Adjust angles (adapted from Redupe).
  - `AddHandles.luau` — left/straight/right segment-append handles on open endpoints.
- `plugins/RoadHelper/src/Dragger/` — handle view components (arrows/arcs) carried over from Redupe.
- `plugins/RoadHelper/src/RoadHelperGui.luau` + `libraries/PluginGui/` — React settings panel and shared UI.

## Key Facts About Road Segments

- `ProceduralModel` is a Model subclass with a `Size` Vector3 property; the generated geometry
  regenerates automatically when Size or attributes change. Move it with `PivotTo()`; the pivot
  is the center of the nominal bounding box that the generator works in.
- Road width is derived: `width = LaneCount*LaneWidth + 2*SidewalkWidth`.
- StraightRoad endpoints (local): blue `(∓sway, -Y/2, -Z/2)` outward -Z, red `(±sway, +Y/2, +Z/2)`
  outward +Z, where `sway = max((X - width)/2, 0)` and the sign pair mirrors with `Flip`.
- CurveRoad endpoints (local): blue `(-X/2 + width/2, ·, -Z/2)` outward -Z, red
  `(X/2, ·, Z/2 - width/2)` outward +X; `Flip` mirrors the climb only (blue at top when Flip).
- The Adjust dir/grade/bank rotations all pivot about the endpoint centre point, so endpoint
  *positions* are invariant under angle edits — only move edits Size/pivot.

## Key Conventions

Same as Redupe: `--!strict`, React via `React.createElement` (aliased `e`), Signal library for
events, modules returning a single function, undo via ChangeHistoryService recordings.

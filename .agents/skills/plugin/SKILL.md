---
name: plugin
description:
  Shared build, test, conventions, and Wally dependencies for Studio plugins in
  this monorepo. Use when building, testing, or working under plugins/,
  libraries/PluginGui, scripts/build, or scripts/test.
---

# Plugin development

## Wally

From repo root, after dependency changes:

```bash
wally install
wally-package-types --sourcemap sourcemap.json Packages
```

Luau LSP already maintains `sourcemap.json` — don't run `rojo sourcemap` yourself.

## Build

Do **not** call `rojo build -o` directly. Use the lute wrapper (`rojo build -p` under the hood for Studio Plugins installs):

```bash
lute scripts/build.luau generate              # write gitignored Rojo project files
lute scripts/build.luau generate --watch      # regenerate only projects touched by each change
lute scripts/build.luau <PluginName>          # e.g. ResizeAlign → ResizeAlign.rbxmx
lute scripts/build.luau <PluginName> --watch  # rebuild that plugin when it (or shared libs) change
lute scripts/build.luau all                   # build every plugin once
lute scripts/build.luau all --watch           # rebuild only dirty plugins per change
lute scripts/build.luau all --out build       # write rbxmx files into a directory (CI/release)
```

Plugins are PascalCase dirs under `plugins/`. Generation writes gitignored:

- `default.project.json` — all plugins (Folder tree for Luau LSP / typecheck)
- `plugins/<Name>/default.project.json` — single-plugin `.rbxmx` build
- `plugins/<Name>/test.project.json` — per-plugin test harness (when specs exist)
- `scripts/test/test.project.json` — combined multi-plugin RunTests project (written by the test script)

Opening the folder in VS Code/Cursor runs **Generate Rojo projects** once (`runOn: folderOpen`). Use **Generate Rojo projects (watch)** or `generate --watch` if you're adding/removing plugins. Elsewhere, run `generate` when those files are missing.

Enable **Reload Plugins on File Changed** in Studio so rebuilt `.rbxmx` reloads.

## Test

```bash
lute run scripts/test                 # every plugin that has specs
lute run scripts/test all             # same
lute run scripts/test RoadHelper
lute run scripts/test RopeTool ResizeAlign redupe
```

Builds `RunTests.rbxmx` once, installs it into the Studio Plugins folder, then waits on a local websocket. Open any place in Studio (Reload Plugins on File Changed works). Names are case-insensitive.

Specs are `*.spec.luau` under each plugin `src/`. Output is grouped by plugin → suite → case. Specs can call `t.screenshot("name")`. For UI: mount into a `ScreenGui` under `CoreGui`, flush with `ReactRoblox.act`.

## Layout

| Path | Role |
| --- | --- |
| `plugins/<Name>/` | Plugin sources + `loader.server.luau` |
| `libraries/PluginGui/` | Shared UI widgets (`Src.PluginGui` in each plugin project) |
| `Packages/` | Root Wally installs (gitignored) |
| `foreman.toml` | Toolchain pins |
| `wally.toml` | Shared deps for every plugin |

Per-plugin architecture is in `.agents/skills/<plugin>/` (e.g. `resizealign`, `gapfill`). Prefer those for behavior; use this skill for build/test/deps.

## Shared conventions

- `--!strict`; many modules also use `--!native`
- React via `React.createElement` (aliased `e`) — not JSX
- `Packages.Signal` (GoodSignal) for events
- Prefer modules that `return` a single function (lowerCamelCase) vs table exports (UpperCamelCase)
- Undo via `ChangeHistoryService` recordings (`TryBeginRecording` / `FinishRecording`)
- Input via `UserInputService` (not the deprecated plugin mouse API)
- Don't edit `libraries/PluginGui` unless asked — shared across plugins

## Dependencies (Wally)

From root `wally.toml` (required as `Packages.<Name>`):

| Package | Purpose |
| --- | --- |
| `react` / `react-roblox` / `roact-compat` | UI |
| `Roact` | DraggerToolComponent handle rendering |
| `Signal` (GoodSignal) | Events |
| `DraggerFramework` / `DraggerSchemaCore` / `DraggerHandler` | 3D handles / selection tools |
| `Geometry` | Geometric utilities |
| `createSharedToolbar` | Optional shared Studio toolbar |

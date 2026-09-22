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

Do **not** use `rojo build -o`. Use the lute wrapper (rojo `-p` under the hood):

```bash
lute scripts/build.luau generate          # write gitignored Rojo projects only
lute scripts/build.luau <PluginName>      # e.g. ResizeAlign
lute scripts/build.luau all
lute scripts/build.luau <PluginName> --watch
lute scripts/build.luau all --out build
```

Plugins are PascalCase dirs under `plugins/`. Build writes gitignored:

- root `default.project.json` — all plugins (Folder layout for typecheck)
- `plugins/<Name>/default.project.json` — single-plugin `.rbxmx` build

When this repo is opened in a VS Code–based editor, `.vscode/tasks.json` auto-runs `lute scripts/build.luau generate`. Elsewhere, run that command when those project files are missing.

Enable **Reload Plugins on File Changed** in Studio so rebuilt `.rbxmx` reloads.

## Test

```bash
lute run scripts/test <PluginName>
lute run scripts/test all
lute run scripts/test <PluginName> <SpecFilter>
```

Builds `RunTests.rbxmx` and waits for Studio over a local websocket. Load that plugin in Studio (Reload Plugins on File Changed works), then open any place.

Specs are `*.spec.luau` under each plugin `src/`. They can call `t.screenshot("name")`. UI tests: mount into `ScreenGui` under `CoreGui`, flush with `ReactRoblox.act`.

## Layout

| Path | Role |
| --- | --- |
| `plugins/<Name>/` | Plugin sources + `loader.server.luau` |
| `libraries/PluginGui/` | Shared UI widgets; mapped as `Src.PluginGui` in each plugin project |
| `Packages/` | Root Wally installs (gitignored) |
| `foreman.toml` | Toolchain pins |
| `wally.toml` | Shared dependencies for every plugin |

Per-plugin architecture lives in `.agents/skills/<plugin>/` (e.g. `resizealign`, `gapfill`). Prefer those for plugin-specific behavior; use this skill for build/test/deps.

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

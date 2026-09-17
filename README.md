# stravant-plugins

Monorepo for stravant's Roblox Studio plugins. Each plugin's history was imported from its original repo.

| Plugin | Path | Source |
| --- | --- | --- |
| ResizeAlign | `plugins/ResizeAlign` | [stravant/roblox-resizealign](https://github.com/stravant/roblox-resizealign) |
| GapFill | `plugins/GapFill` | [stravant/roblox-gapfill](https://github.com/stravant/roblox-gapfill) |
| RopeTool | `plugins/RopeTool` | [stravant/roblox-ropetool](https://github.com/stravant/roblox-ropetool) |
| MaterialFlip | `plugins/MaterialFlip` | [stravant/roblox-materialflip](https://github.com/stravant/roblox-materialflip) |
| AdHoc | `plugins/AdHoc` | [stravant/roblox-adhoc](https://github.com/stravant/roblox-adhoc) |
| PolyMap | `plugins/PolyMap` | [stravant/roblox-polymap](https://github.com/stravant/roblox-polymap) |
| ReDupe | `plugins/ReDupe` | [stravant/roblox-redupe](https://github.com/stravant/roblox-redupe) |
| RoadHelper | `plugins/RoadHelper` | [stravant/roblox-roadhelper](https://github.com/stravant/roblox-roadhelper) |

Shared UI widgets live in `libraries/PluginGui` and are mapped into each plugin as `Src.PluginGui`. Shared Wally deps live in the root `wally.toml` / `Packages`.

## Setup

Install [Foreman](https://github.com/Roblox/foreman) using the instructions in that repo, then:

```bash
foreman install
wally install
```

### VS Code

Install [Luau Language Server](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) (JohnnyMorganz).

This repo already has:

- `.vscode/settings.json` — luau-lsp sourcemap from `default.project.json`, `PluginSecurity`, automatic tasks on
- `.vscode/tasks.json` — **Build all**, per-plugin build/watch, **Generate Rojo projects** (`runOn: folderOpen`)

Opening the folder runs **Generate Rojo projects** (needs workspace trust / Allow Automatic Tasks). That writes gitignored `default.project.json` so Luau LSP has a sourcemap.

## Build

```bash
lute scripts/build.luau generate
lute scripts/build.luau ResizeAlign
lute scripts/build.luau all
lute scripts/build.luau ResizeAlign --watch
```

Plugins are discovered from PascalCase dirs under `plugins/`. `scripts/build.luau` writes gitignored Rojo projects: `default.project.json` at the repo root (every plugin, same Folder layout as a plugin project) and `plugins/<Name>/default.project.json` for the `.rbxmx`. `--watch` regenerates those projects and rebuilds.

Enable **Reload Plugins on File Changed** in Studio so the built `.rbxmx` reloads automatically.

## Test

```bash
lute run scripts/test RoadHelper
lute run scripts/test all
lute run scripts/test ResizeAlign Settings
```

Locally that starts a websocket server and builds `RunTests.rbxmx` for Studio (place name must be `runtests`). In GitHub Actions (`GITHUB_ACTIONS`) it uses `rocale-cli` instead.

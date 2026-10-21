# IPC and the `mosaic` command

The service (`MosaicService.qml`) registers one `IpcHandler` with target
`pym.mosaic`, so it answers whether or not the widget is on the bar. Call it
as `omarchy-shell pym.mosaic <function> [args…]`. `bin/mosaic` wraps it in
the old CLI's command line. The user-facing walkthrough is in the
[command-line guide](../guide/command-line.md).

## Calling conventions

- Every argument must be passed; use `""` for none.
- Lists of targets travel as one argument, one item per line (web app names
  can contain spaces): `omarchy-shell pym.mosaic add $'twitch\nkick' streams "" ""`.
- `TILE` is a list number (`index` in [`list`](files.md#list-version-1)) or
  a window address (`0x…`).
- `omarchy-shell` gives up on a call after about 2 s, so long actions are
  **jobs**: they answer `started N` at once, or `error: REASON`. `result N`
  then answers `running`, or `done` followed by a newline and the message,
  or `error` followed by a newline and the reason, or `unknown` for a number
  that is not the latest job's. A job counts as running until 500 ms after
  it ends, so a `list` right after `done` shows its effect.
- Only one job runs at a time; another one answers
  `error: Still busy: …`.
- Quick setters answer `""` on success or `error: REASON`.

## Functions

### Reading

| Function | Answer |
| --- | --- |
| `list` | Version 1 list JSON ([format](files.md#list-version-1)). |
| `listText` | The list as text, like `mosaic list`. |
| `webapps` | Version 1 web app JSON ([format](files.md#webapps-version-1)). |
| `webappsText` | The web apps as text. |
| `monitors` | Active monitors: logical size after scale and rotation, and work area. |
| `version` | `mosaic` plus the plugin's version. |
| `layouts` | Workspaces with a layout, and the custom layouts, as text. |
| `saved` | Saved sessions as JSON ([format](files.md#savedjson-version-1)). |
| `savedText` | Saved sessions as text. |
| `streams` | Each tile's stream state, the recent recoveries, and pending fullscreen restores, as text. |
| `extension` | The extension's setup and connection as JSON (`mosaic-native-host status` plus the connected browsers). |
| `result(job)` | How job `job` went (above). |

### Jobs (answer `started N`)

| Function | Does |
| --- | --- |
| `add(targets, session, monitor, browser)` | Opens 1–9 URLs or web app names as tiles in `session` (default `default`), on the session's workspace, else `monitor`'s or the focused monitor's current workspace. All targets are resolved before any opens. `browser` overrides the widget's **Browser** setting. |
| `replace(tile, target, browser)` | Opens `target` in `tile`'s place: in the same tab when the extension can navigate it, else a new window in the old one's slot. |
| `saveApp(tile, name)` | Saves a tile no web app matches as an Omarchy web app for its site root (`name` defaults to the last part of the page title). |
| `remove(tiles)` | Closes tiles (one per line). |
| `focus(tile)` | Focuses a tile, switching to its workspace. |
| `close(session)` | Closes a session's tiles, or every tile for `""`. |
| `contain(session)` | Re-applies fullscreen state `0/2` to uncontained tiles, of one session or all. |
| `layout(workspace, name)` | Sets a workspace's layout: `grid`, `stack`, `main`, `fit`, a custom layout's name or slug, or `default`. |
| `sessionLayout(session, name)` | The same, for the workspace the session's first tiled tile is on. |
| `layoutSave(slug, definition)` | Saves a custom layout from JSON ([format](layouts.md#custom-layouts)), replacing `slug` if given. |
| `layoutDelete(slug)` | Deletes a custom layout; workspaces using it get their own layout back. |
| `restore(name, browser)` | Opens a saved session's tiles that aren't open, where it was saved, then its layout, volumes and mutes. |
| `restartBrowser(browser)` | Closes the tiles' browser with SIGTERM, waits up to 15 s, and starts it again. |

### Quick setters (answer `""` or `error: …`)

| Function | Does |
| --- | --- |
| `save(session)` | Saves a live session under its name. |
| `forget(name)` | Deletes a saved session. |
| `login(name, state)` | `on` or `off`: open the saved session at login. |

### Tile controls (need the browser extension)

| Function | Answer |
| --- | --- |
| `mute(tile, state)` | `on`, `off` or `toggle`; answers `ok` or `error: …`. |
| `volume(tile, level)` | A percentage (`40`) or a step (`+10`, `-10`); answers the new level (`40%`) or `error: …`. At 100% the site's own control is in charge again. |
| `media(tile, action)` | `play`, `pause` or `toggle`; answers `ok` or `error: …`. |
| `reloadTile(tile)` | Reloads the tile's page in place, and gives a stalled tile its recovery tries back; answers `ok` or `error: …`. |

### Other

| Function | Does |
| --- | --- |
| `swap()` | Opens the swap card over the focused tile; answers what it did, or why not (the focused window is not a tile, or a job runs). The swap key runs this. |
| `extensionEnable()` | Runs `mosaic-native-host setup` ([ADR 9](../adr/0009-install-the-extension-through-flags-files.md)); answers `started` or an error. |
| `extensionDisable()` | Runs `mosaic-native-host remove`; answers `started` or an error. |
| `extensionVerify()` | Pings every connected browser and matches tiles; answers `started`, read the outcome from `extension`. |

## `bin/mosaic`

A bash wrapper that keeps the Rust CLI's arguments, messages and exit codes
([ADR 3](../adr/0003-plugin-replaces-the-rust-cli.md)). It validates
arguments itself, forwards them quoted, polls `result` for jobs (every
0.1 s, up to 150 s), prints the job's message, and exits 1 with
`mosaic: REASON` on an error or when the shell can't be reached.

| Command | IPC |
| --- | --- |
| `mosaic [add] [--session S] [--monitor M] [--browser B] TARGET…` | `add` (1–9 targets) |
| `mosaic list [--json]` | `listText` / `list` |
| `mosaic remove TILE…` | `remove` |
| `mosaic focus TILE` | `focus` |
| `mosaic close [--session S]` | `close` |
| `mosaic contain [--session S]` | `contain` |
| `mosaic layout` | `layouts` |
| `mosaic layout --workspace N LAYOUT` | `layout` (`N` is 1–9999) |
| `mosaic layout [--session S] LAYOUT` | `sessionLayout` (session defaults to `default`) |
| `mosaic save SESSION` | `save` |
| `mosaic restore [--browser B] NAME` | `restore` |
| `mosaic saved [--json]` | `savedText` / `saved` |
| `mosaic forget NAME` | `forget` |
| `mosaic login NAME on\|off` | `login` |
| `mosaic reload TILE` | `reloadTile` |
| `mosaic save-app TILE [NAME]` | `saveApp` |
| `mosaic streams` | `streams` |
| `mosaic webapps [--json]` | `webappsText` / `webapps` |
| `mosaic monitors` | `monitors` |
| `mosaic --version` | `version` |

Session names given to the wrapper must match `^[a-z0-9_-]{1,32}$`, an
option that doesn't apply to a command is refused, and targets can't contain
line breaks.

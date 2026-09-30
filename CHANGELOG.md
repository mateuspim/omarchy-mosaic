# Changelog

## Unreleased

- **Layouts per workspace, and your own**: layouts now belong to
  workspaces (workspace 8 on Grid, 9 on a layout of yours), set from the
  panel's new **Layouts** tab (a dropdown per workspace) or a session's
  header. Design layouts there with the mouse, like PowerToys FancyZones:
  start from a preset, drag the lines between zones, split a zone beside or
  below, remove one, and pick the main zone that fills first (say 25 / 50
  / 25 with the middle one main). `mosaic layout --workspace
  N LAYOUT`; new IPC `sessionLayout`, `layoutSave`, `layoutDelete`.
  `layouts.json` is version 2; session layouts from version 1 move to
  their workspaces.

- **Volume follows the site**: a tile's volume changed with the page's own
  control (YouTube's slider, arrow keys) is now kept and shown on the
  panel's slider, instead of being reset to the level last set in Mosaic
  at the next video. The last change wins, from either side. Needs
  extension 0.4.0 (`background-4.js`, one browser restart: B on the
  Extension tab), which also keeps levels when the browser stops its
  worker.

- **Layouts**: Grid, Stack, Main + small, and 16:9 fit. They are Hyprland
  Lua tiling layouts (`layouts.lua`), so tiles stay tiled and swappable,
  and they follow portrait monitors. The choice is saved in `layouts.json`
  next to `tiles.json` and applied again after a config reload, with each
  tile's fullscreen containment kept. New IPC: `layout`, `layouts`.

- **Audio on the Tiles tab**: "Only the focused tile plays" (F) sits above
  the sessions, next to each tile's own slider and mute button. The setup
  tab is now **Extension**, for enabling and checking the extension only.
- **Per-tile volume**: a slider under each tile the extension found (like
  the shell's audio panel for apps; right-click mutes), − and + on a
  tile, or the mouse wheel over its speaker button. New IPC: `volume`, `media`
  (play, pause, toggle), and `reloadTile`. Extension 0.3.0 also carries
  in-place navigation, reloading, media control, and favicons, and says
  what it can do (`features`), so later panel features need no browser
  restart.
- **Per-tile mute**: a speaker button on each tile row (and M) shows
  whether the tile is playing, silent, or muted, and mutes or unmutes it.
  **Mute every tile but the focused one** follows Hyprland focus. New IPC: `mute TILE on|off|toggle`. Needs extension
  0.2.0; the Extension tab asks for a browser restart while a browser runs an
  older copy of it, which it tells from the worker script's name.
- **Browser extension for audio control**, the groundwork for per-tile
  audio. The panel's new Extension tab sets it up (Enable, restart the browser,
  Verify) and the Tiles tab warns while it's missing. The extension reports
  the browser's app windows through a native messaging host,
  `bin/mosaic-native-host`, and a socket the service listens on
  (`$XDG_RUNTIME_DIR/pym-mosaic.sock`). New IPC: `extension`,
  `extensionEnable`, `extensionVerify`, `extensionDisable`.

## 1.0.0 (2026-09-27)

The first release as the whole of Omarchy Mosaic. The plugin now does
everything the Rust `mosaic` CLI did, without it.

- **Engine in the shell.** A service builds the tile list from Hyprland's
  window tags and `~/.local/state/mosaic/tiles.json`, and the web app list
  from the desktop entries, and it adds, focuses, removes, closes, and
  contains tiles itself. Tiles the CLI opened carry over.
- **Fullscreen containment** as before: a page's video fullscreen fills only
  its tile. A tile keeps its state when it moves between workspaces, where
  Hyprland's own record would go stale.
- **Swap a tile's web app** in the same slot: press S on a tile in the panel,
  or press Super+Shift+S on the tile itself for a card with your web apps
  and its address, ready to edit. The key is a setting.
- **Hidden web apps**: right-click a button to hide it; a tab lists them.
- **Command line**: `omarchy-shell pym.mosaic …`, and `bin/mosaic` keeps the
  CLI's `mosaic` command, arguments, and output (`list` and `webapps` JSON
  are version 1, unchanged).
- **Settings**: Browser (a Chromium-family command instead of the default
  browser), Swap key, and Hidden web apps. The old "mosaic command" setting
  is gone.
- The cursor stays put when a new tile opens.

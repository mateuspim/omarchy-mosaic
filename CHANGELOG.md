# Changelog

## Unreleased

- **Keep fullscreen in tiles**: a new switch on the Tiles tab (Shift+C)
  contains tiles on its own. A tile that loses its containment is
  contained again right away, and a tile made truly fullscreen (Super+F,
  or a video that escaped) stays big only while it has focus: once another
  window takes focus, it goes back into its tile.
- **Tile rows that show what's in them**: each tile has its web app's icon
  (or the site's favicon, or its first letter), its name, and what sets it
  apart from the others: the page's title without unread counts or the
  site's name, or its address's path. A warning, like "fullscreen not
  contained", comes first so it is never cut off.
- **Quieter Tiles tab**: the volume slider shows only on the tile under
  the cursor; the others show their level next to the mute button. The
  monitor and workspace moved to the session's header when all its tiles
  share them.
- **Layouts drawn in the session header**: the layout button is a small
  picture of where the session's tiles go, at the monitor's shape, beside
  the layout's name.

## 1.1.1 (2026-10-02)

- **A nicer swap card** (Super+Shift+S on a tile): the site's logo and
  address up top, an "In place" or "New window" chip, the web apps as a
  grid of tiles with their icons and number keys (the one it already
  shows dimmed), and the keys as key caps.
- **Tiles on the same site stay told apart**: the tab each tile was
  matched to is remembered across shell restarts, and two look-alike tiles
  never matched before are paired as soon as you focus one of them.

## 1.1.0 (2026-10-02)

- **Swaps change the page in place**: with the browser extension
  connected, swapping a tile (S in the panel, Super+Shift+S on the tile,
  `mosaic replace`) now loads the new address in the tile's own window
  instead of opening a new one and closing the old, so nothing flickers,
  moves, or warps the cursor, and the tile keeps its mute and volume.
  Without the extension it opens a new window in the slot, as before. In
  the panel, the picker now opens on the tile's own card, with its address
  ready to edit and the web app it already shows dimmed, instead of a
  notice at the top and the Add tile section turned into "Replace with".
  While the new page loads, the tile shows the Omarchy logo with a
  progress bar, like the boot screen, in your theme's colours.
  Tiles also keep the browser tab they were matched to, so two tiles on
  the same site (say, after swapping one to YouTube) stay told apart.

- **Layouts per workspace, and your own**: layouts now belong to
  workspaces (workspace 8 on Grid, 9 on a layout of yours), set from the
  panel's new **Layouts** tab (a dropdown per workspace) or a session's
  header. Design layouts there with the mouse, like PowerToys FancyZones:
  start from a preset, drag the lines between zones, split a zone beside or
  below, remove one, and pick the main zone that fills first (say 25 / 50
  / 25 with the middle one main). `mosaic layout --workspace
  N LAYOUT`; new IPC `sessionLayout`, `layoutSave`, `layoutDelete`.
  `layouts.json` is version 2; session layouts from version 1 move to
  their workspaces. The tab lists only workspaces with windows or a layout
  of their own, plus the focused one; **Show all workspaces** (W) lists
  the rest.

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

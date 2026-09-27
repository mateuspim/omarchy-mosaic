# Changelog

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

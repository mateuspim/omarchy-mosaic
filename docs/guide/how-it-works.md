# How it works

Web apps such as Twitch, Kick, and YouTube, tiled as a mosaic on Hyprland,
where a video's fullscreen stays inside its tile. It's an Omarchy shell
plugin: a service plus a bar widget. The panel lists your mosaic sessions and
their tiles, and lets you add one of your installed web apps (such as the ones
Omarchy's web app installer creates) or any URL as a tile, focus or remove a
tile, close a session, and turn fullscreen containment back on. The icon dims
when no tiles are open.

The service reads Hyprland's window tags and
`~/.local/state/mosaic/tiles.json`, the same sources the older `mosaic` CLI
used, so the bar, the CLI, and ordinary Hyprland bindings always agree. It
refreshes when Hyprland opens, closes, moves, floats, fullscreens, or
retitles a window. Tiles open in your default browser, which must be
Chromium-based (Chromium, Chrome, Brave, Edge, Opera, Vivaldi, or Helium);
the widget's **Browser** setting picks another Chromium-family command.

## Fullscreen stays in its tile

Each tile is an ordinary Chromium-family `--app` window that Hyprland
tiles. Mosaic gives it Hyprland's fullscreen state `internal = 0, client = 2`,
so the browser believes the window is already fullscreen while the
compositor keeps it at its tile size: a page's video fullscreen then fills
only the tile. The evidence, the edge cases and the containment check are in
[the architecture notes](../architecture.md#fullscreen-containment), and the
choice is [ADR 1](../adr/0001-contain-fullscreen-with-hyprland-state.md).

## Compatibility

The service builds the version 1 `mosaic list --json` and `mosaic webapps
--json` formats itself, and it adds, focuses, removes, closes, and contains
tiles through Hyprland; it doesn't need the `mosaic` CLI. Tiles the CLI
opened carry over, since both use the same tags and `tiles.json`.

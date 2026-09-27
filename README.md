# Mosaic for Omarchy

An Omarchy shell bar widget for [omarchy-mosaic](https://github.com/mateuspim/omarchy-mosaic).
It lists your mosaic sessions and their tiles, and lets you add one of your
installed web apps (such as the ones Omarchy's web app installer creates) or
any URL as a tile, focus or remove a tile, close a session, and turn fullscreen
containment back on. The icon dims when no tiles are open.

The plugin is being ported from the `mosaic` CLI into the shell. Its service
builds the tile list itself from Hyprland's window tags and
`~/.local/state/mosaic/tiles.json`, the same sources the CLI reads, so the
bar, the CLI, and ordinary Hyprland bindings always agree. It refreshes when
Hyprland opens, closes, moves, floats, fullscreens, or retitles a window.
Changes still go through the `mosaic` command until they are ported.

## Install

1. Install `mosaic` where the shell can find it. `omarchy-shell` has
   `~/.local/bin` on its PATH but not `~/.cargo/bin`:

   ```bash
   cargo install --path ~/Projects/omarchy-mosaic --root ~/.local
   ```

   Or set the widget's **mosaic command** setting to the binary's full path.

2. Add and enable the plugin:

   ```bash
   omarchy plugin add file:///home/pym/Projects/omarchy-mosaic-plugin --enable --yes
   ```

## Use

Click the icon, or middle-click it to refresh.

| Key | Action |
| --- | --- |
| ↑ ↓ or J K | Select a tile (or a hidden web app) |
| ← → or H L | Switch between the Tiles and Hidden web apps tabs |
| Enter | Focus the selected tile, or show the selected hidden web app again |
| X or D | Remove the selected tile |
| Shift+D | Close the selected tile's session |
| 1–9 | Add that web app to the session |
| A | Type a URL or web app name to add (Enter adds, Esc returns to the list) |
| C | Turn fullscreen containment back on |
| R | Refresh the tiles |
| Esc | Close the panel |

The web app buttons are the installed web apps, and they update as web apps
are installed or removed. Right-click a button to hide that web app, or list names in the
widget's **Hidden web apps** setting (for example `Tailscale, WhatsApp`).
The panel's **Hidden web apps** tab lists them; select one there to bring its
button back. Typing a web app's name in the
address field works for hidden ones too. A bare
host such as `twitch.tv/name` gets `https://`. Tiles go to the session in the
session field, or else the selected tile's session, or else `default`. New tiles join the workspace where that session already has
tiles, and otherwise go to the focused monitor.

## Compatibility

The service builds the version 1 `mosaic list --json` and `mosaic webapps
--json` formats itself, and it focuses, removes, closes, and contains tiles
through Hyprland. Until the engine can open tiles, the widget runs the
mosaic CLI's `add` subcommand.

## Development

For development, symlink the checkout instead of installing a copy:

```bash
ln -s ~/Projects/omarchy-mosaic-plugin ~/.config/omarchy/plugins/pym.mosaic
omarchy-shell shell rescanPlugins && omarchy plugin enable pym.mosaic
scripts/dev-watch      # reload the widget on every save
```

The shell's own file watcher does not follow symlinks, which is what
`scripts/dev-watch` makes up for. With a symlink, avoid a bare
`omarchy plugin update`: it treats every git plugin as its own checkout and
would fetch and fast-forward this repository. Pass plugin ids instead.

`git config core.hooksPath .githooks` enables hooks that keep the installed
widget current after commits, pulls, rebases, and checkouts on `master`. A
symlinked install is reloaded, and a copy from `omarchy plugin add` is updated
with `omarchy plugin update pym.mosaic --yes` (log:
`~/.local/state/mosaic/plugin-update.log`; `MOSAIC_NO_INSTALL=1` skips it).

```bash
npm test                               # Model.js unit tests
omarchy plugin validate .              # manifest check
omarchy-shell shell rescanPlugins      # reload after edits to an installed copy
```

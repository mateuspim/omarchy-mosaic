# Mosaic for Omarchy

An Omarchy shell bar widget for [omarchy-mosaic](https://github.com/mateuspim/omarchy-mosaic).
It lists your mosaic sessions and their tiles, and lets you add one of your
installed web apps (such as the ones Omarchy's web app installer creates) or
any URL as a tile, focus or remove a tile, close a session, and turn fullscreen
containment back on. The icon dims when no tiles are open.

The widget holds no state of its own. It reads `mosaic list --json` and makes
every change through the `mosaic` command, so the bar, the CLI, and ordinary
Hyprland bindings always agree. It refreshes when Hyprland opens, closes,
moves, floats, or fullscreens a window.

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
| ↑ ↓ or J K | Select a tile |
| Enter | Focus the selected tile |
| X or D | Remove the selected tile |
| Shift+D | Close the selected tile's session |
| 1–9 | Add that web app to the session |
| A | Type a URL or web app name to add (Enter adds, Esc returns to the list) |
| C | Turn fullscreen containment back on |
| R | Refresh tiles and web apps |
| Esc | Close the panel |

The web app buttons come from `mosaic webapps --json`, read each time the
panel opens. Typing a web app's name in the address field also works. A bare
host such as `twitch.tv/name` gets `https://`. Tiles go to the session in the
session field, or else the selected tile's session, or else `default`. New tiles join the workspace where that session already has
tiles, and otherwise go to the focused monitor.

## Compatibility

The widget accepts `mosaic list --json` and `mosaic webapps --json` version 1 and shows an "update"
notice for any other version. It uses the `add`, `remove`, `focus`, `close`,
and `contain` subcommands. Without `mosaic webapps` (older builds), the web
app buttons are hidden and everything else works.

## Development

To have the installed widget follow this checkout, run
`git config core.hooksPath .githooks`. Every commit, pull, or rebase on
`master` then runs `omarchy plugin update pym.mosaic --yes`, which also
reloads the shell's plugins (log: `~/.local/state/mosaic/plugin-update.log`;
`MOSAIC_NO_INSTALL=1` skips it).

```bash
npm test                               # Model.js unit tests
omarchy plugin validate .              # manifest check
omarchy-shell shell rescanPlugins      # reload after edits to an installed copy
```

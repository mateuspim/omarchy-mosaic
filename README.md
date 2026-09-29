# Mosaic for Omarchy

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

## Install

Mosaic needs Omarchy with Hyprland's Lua config (tested on Hyprland 0.56.2)
and a Chromium-family browser. Add and enable the plugin, then add the
**Mosaic** widget to the bar in the shell's settings:

```bash
omarchy plugin add https://github.com/mateuspim/omarchy-mosaic.git --enable --yes
```

For the `mosaic` command, link the wrapper onto your PATH:

```bash
ln -s ~/.config/omarchy/plugins/pym.mosaic/bin/mosaic ~/.local/bin/mosaic
```

## Use

Click the icon, or middle-click it to refresh.

| Key | Action |
| --- | --- |
| ↑ ↓ or J K | Select a tile (or a hidden web app) |
| ← → or H L | Switch between the Tiles, Hidden, and Extension tabs |
| Enter | Focus the selected tile, or show the selected hidden web app again |
| M | Mute or unmute the selected tile (needs the browser extension) |
| F | Turn "Only the focused tile plays" on or off |
| − and + (or =) | Turn the selected tile's volume down or up by 10% |
| G | Cycle the selected tile's session through the layouts: Grid, Stack, Main + small, 16:9 fit, and back to Hyprland's own |
| S | Swap the selected tile's web app: pick a web app (1–9) or type an address (A), and it replaces the tile in place. Esc cancels |
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

To swap the tile you're looking at without opening the bar first, press
**Super+Shift+S** on it. A card opens over the tile with your web apps
(1–9) and the tile's address, ready to edit (A, then Enter), so you can
switch to another site or just another channel; Esc or a click on the tile
closes it. Errors arrive as a notification.
Change the key in the widget's **Swap key** setting (written like
`SUPER + SHIFT + S`), or clear it to have none; a key another binding
already uses is refused, and the panel says why. The key runs
`omarchy-shell pym.mosaic swap`, which you can also call yourself; the
panel's own swap mode (S) works as before. The
replacement keeps the old tile's session, workspace, slot, and place in the
list.

## Layouts

Each session header shows its layout; click the grid button there, or press
**G** on a tile, to switch to the next one:

- **Grid**: a balanced grid; a short last row stretches across.
- **Stack**: one row on a landscape monitor, one column on a portrait one.
- **Main + small**: the first tile takes 70% of the monitor, the rest line
  up beside it (or below it, on a portrait monitor). Swap a tile into the
  first slot with Omarchy's swap keys.
- **16:9 fit**: the largest 16:9 tiles that fit, centered.
- **Hyprland**: the workspace's own layout again.

The layout belongs to the session and applies to the workspace its tiles
are on, including any other windows there. Tiles stay tiled, so Omarchy's
window bindings keep working. Mosaic remembers the choice and applies it
again after a Hyprland config reload or when the tiles move to another
workspace.

## Audio

Each tile row has a speaker button showing whether the tile is playing
(󰕾, or 󰖀 when turned down), silent (󰕿), or muted (󰖁); click it or press
**M** to mute or unmute. Under it, a slider sets the tile's own volume
(right-click the slider to mute), as the shell's audio panel does for apps;
scrolling over the speaker button, or **−** and **+**, work too. At 100% the
site's own volume control is in charge again. The level holds when the
page reloads or a new video starts, but the site's volume slider can
change it until then.
At the top of the Tiles tab, **Only the focused tile plays** (F) makes the
tile you focus the only one you hear: focusing another tile unmutes it and
mutes the rest, and focusing any other window leaves them as they are.
Turning it off unmutes every tile. From scripts: `omarchy-shell pym.mosaic
mute TILE on|off|toggle`, `volume TILE 40` (or `+10`, `-10`), `media TILE
play|pause|toggle`, and `reloadTile TILE`.

## The browser extension (for audio control)

Audio control needs a small browser extension,
`extension/`. Every tile shares one browser process and one audio stream
source, so PipeWire can't tell tiles apart; the extension can, from inside
the browser. It talks to the plugin through a native messaging host,
`bin/mosaic-native-host` (Python 3, which Omarchy already has).

Open the panel's **Extension** tab (the Tiles tab warns while it's missing):

1. **Enable** (E) registers the host with every Chromium-family browser
   profile it finds under `~/.config`, and adds the extension to the
   `--load-extension=` line of each browser flags file there, such as
   `brave-origin-flags.conf`. That's how Omarchy loads its own browser
   extensions, so there is nothing to click in the browser.
2. **Restart the browser.** Closing it also closes its tiles.
3. The tab then checks on its own that the extension finds every tile,
   again whenever tiles or the browser's windows change. **Verify** (V)
   also checks that it still answers.

Without a flags file, load the extension by hand: open the browser's
extensions page, turn on Developer mode, choose Load unpacked, and pick the
extension folder (the tab copies its path). **Turn off** undoes Enable; do
that before removing the plugin, so the browser isn't left loading a folder
that's gone. When the plugin brings a newer extension, or the browser is
still running an old copy of it, the Extension tab says so, and the browser
loads the current one on its next restart (the tab's Restart button,
B). The same steps are in the IPC: `omarchy-shell pym.mosaic
extension` (status as JSON), `extensionEnable`, `extensionVerify`, and
`extensionDisable`.

## Compatibility

The service builds the version 1 `mosaic list --json` and `mosaic webapps
--json` formats itself, and it adds, focuses, removes, closes, and contains
tiles through Hyprland; it doesn't need the `mosaic` CLI. Tiles the CLI
opened carry over, since both use the same tags and `tiles.json`.

## Command line

The plugin answers `omarchy-shell pym.mosaic <function>`; `bin/mosaic` in
this repository wraps that in the old `mosaic` command, with the same
arguments and output:

```bash
mosaic add --session streams twitch kick.com/somechannel
mosaic list            # or: mosaic list --json
mosaic remove 2
mosaic focus 1
mosaic close --session streams
mosaic contain
mosaic layout                          # each session's layout
mosaic layout --session streams grid   # grid, stack, main, fit, or default
mosaic webapps         # or: mosaic webapps --json
mosaic monitors
```

The list and web app JSON are the version 1 formats the CLI printed. To call
the plugin directly, pass every argument (`""` for none), with targets one
per line: `omarchy-shell pym.mosaic add $'twitch\nkick' streams "" ""`
answers `started N` right away, and `omarchy-shell pym.mosaic result N`
reports how it went.

## Development

For development, symlink the checkout instead of installing a copy:

```bash
ln -s ~/Projects/omarchy-mosaic ~/.config/omarchy/plugins/pym.mosaic
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
npm test                               # Model.js and native host tests
omarchy plugin validate .              # manifest check
omarchy-shell shell rescanPlugins      # reload after edits to an installed copy
```

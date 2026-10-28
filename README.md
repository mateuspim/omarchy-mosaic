# <img src="icon.svg" alt="" width="32" height="32" align="top"> Mosaic

![Mosaic: every stream in its place. On the right, a monitor shows workspace 8 in a three-zone layout: a wide Twitch tile in the middle whose video is fullscreen inside the tile, with Kick and a muted YouTube tile letterboxed beside it. In front, two offscreen renders of the Mosaic panel with sample tiles: the Tiles tab with two sessions, per-tile volume, a recovered stream and the audio, containment, recovery and "new tiles here" switches, and the Layouts tab with a layout per workspace and a custom "Three" layout](preview.png)

**Twitch, Kick, YouTube and any other web app, tiled as a monitor-aware
mosaic on Hyprland, where a video's fullscreen stays inside its tile.**

## Quick start

```bash
omarchy plugin add https://github.com/mateuspim/omarchy-mosaic.git --enable --yes
```

Add the **Mosaic** widget to the bar in the shell's settings, click its
icon, then press `1`–`9` to open one of your web apps as a tile, or `A` to
type any address.

## Features

- **Fullscreen in its tile**: a video's fullscreen fills its tile, not the
  monitor, and Mosaic can put it back when something takes it away.
- **A keyboard-first panel** in the Omarchy bar: sessions and their tiles;
  add, focus, swap, reload and remove tiles, move them between sessions
  or monitors, and open new ones on the workspace you're on; in your
  theme's colours.
- **Swap a tile in place** with a card over the tile (`Super+Shift+S`):
  another web app or another address, same slot.
- **Layouts per workspace**: Grid, Stack, Main + small, 16:9 fit, or your
  own zone layouts drawn on the panel. They stay real Hyprland tiles, so
  Omarchy's window bindings keep working.
- **Per-tile audio**: mute, volume, and "only the focused tile plays",
  through a small browser extension.
- **Dropped streams come back**: a frozen or failed Twitch or Kick stream
  is reloaded, and goes fullscreen again if it was.
- **Saved sessions** that reopen where they were, by key or at login.
- **Save a tile as a web app**, with the site's icon.
- **Scriptable**: `omarchy-shell pym.mosaic …` and the `mosaic` command.

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

For audio control and stream recovery, set up the
[browser extension](docs/guide/browser-extension.md) from the panel's
**Extension** tab.

## Remove

Turn the extension off first (**Turn off** on the **Extension** tab), so
the browser isn't left loading a folder that's gone, then:

```bash
omarchy plugin remove pym.mosaic
rm ~/.local/bin/mosaic   # if you linked it
```

Mosaic's state stays in `~/.local/state/mosaic/` (tiles, layouts, saved
sessions); delete that folder to forget it.

## Security and privileges

Mosaic runs as your user in the Omarchy shell, never as root, and installs
no packages. It launches your browser and talks to Hyprland with argument
lists, never through a shell. The optional extension can read and control
tiles on any site and reports only to the local shell; enabling it writes
to your browser's config. The details and the privilege model are in
[SECURITY.md](SECURITY.md).

## Using Mosaic

- [The panel](docs/guide/panel.md): every key, adding tiles, the web app
  buttons, and swapping a tile with the swap card.
- [Layouts](docs/guide/layouts.md): a layout per workspace, and designing
  your own.
- [Saved sessions](docs/guide/saved-sessions.md): keep a session and open
  it again, by key or at login.
- [Audio](docs/guide/audio.md): mute, volume, and "only the focused tile
  plays".
- [Dropped streams](docs/guide/dropped-streams.md): how a stalled stream is
  noticed and reloaded.
- [The browser extension](docs/guide/browser-extension.md): what it is for,
  and setting it up.
- [Command line](docs/guide/command-line.md): `mosaic` and
  `omarchy-shell pym.mosaic`.
- [How it works](docs/guide/how-it-works.md): tags, `tiles.json`,
  fullscreen containment, and compatibility with the old CLI.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell` and Hyprland's Lua
  config (tested on Hyprland 0.56.2)
- A Chromium-family browser: Chromium, Chrome, Brave, Edge, Opera, Vivaldi
  or Helium (Firefox has no `--app` mode)
- Python 3 for the extension's native host (Omarchy already has it)

## Documentation

- [Documentation index](docs/README.md): the user guide, architecture,
  decisions, specs and runbooks.
- [Troubleshooting](docs/runbooks/troubleshooting.md).
- [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).
- [Changelog](CHANGELOG.md).

## Development

Symlink a checkout to `~/.config/omarchy/plugins/pym.mosaic`, then run
`npm test` and `omarchy plugin validate .`. Check panel changes offscreen
with `tests/preview.sh`. Setup, the containment check, test shells and
releases are in the [development runbook](docs/runbooks/development.md).

## License

MIT. See [LICENSE](LICENSE).

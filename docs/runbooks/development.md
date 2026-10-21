# Development runbook

## Prepare a checkout

Mosaic needs Omarchy with its Quickshell shell and Hyprland's Lua config,
a Chromium-family browser, and for the tests Node 22 or newer, `lua` (any
of 5.1/LuaJIT, 5.4 or 5.5 passes) and Python 3. There is no build step and
no npm dependency.

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

The live install is a symlink to the checkout, so **every saved file runs in
your shell**. Edit in a branch or a git worktree when you don't want that,
and try risky QML in a throwaway instance first (below). A plugin rescan
has been seen to keep running the old service code; when a service change
seems ignored, restart the shell (`omarchy-restart-shell`), then check that
only one shell runs (`pgrep -a quickshell`).

Read the live log without touching the shell:

```bash
quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i mosaic
journalctl --user -b | grep -i 'Mosaic:'     # stream recovery events
```

## Run the tests

```bash
npm test                     # the three suites below; CI runs the same
omarchy plugin validate .    # the manifest, as the marketplace checks it
```

| Test | Covers |
| --- | --- |
| `node tests/model.test.js` | `Model.js`: validation, list and web app shaping, every planner (add, replace, remove, contain, layouts, restore, recovery, auto-contain), Lua builders, extension matching, audio, saved sessions. |
| `lua tests/layouts_test.lua` | `layouts.lua`: one box per window, inside the area without overlaps, for every layout on landscape and portrait areas, plus zone layouts. |
| `python3 tests/native_host_test.py` | `bin/mosaic-native-host`: framing limits, flags-file edits, setup, remove and status in a scratch `XDG_CONFIG_HOME`. |

Put logic that can live without QML in `Model.js` and test it there. A bug
fix gets a regression test.

## Make a change

1. Read the [guide](../guide/) page for the feature, then
   [architecture](../architecture.md) and the relevant
   [ADR](../adr/README.md) or [spec](../specs/).
2. Keep the change focused; update the guide page, the spec it touches and
   `CHANGELOG.md` under **Unreleased**.
3. Run `npm test` and `omarchy plugin validate .`.
4. For a panel change, render it offscreen (below). For an engine change,
   try it in a throwaway shell. Re-run the containment check after any
   change to how tiles are launched or tiled.
5. A durable design choice gets a new ADR.

## Render the panel offscreen

`tests/preview.sh` draws the panel with Qt's offscreen platform and a fake
service, one PNG per scene (Tiles, Layouts, Saved, Extension):

```bash
MOSAIC_PREVIEW_DIR=/tmp/mosaic-preview bash tests/preview.sh
```

It copies `Panel.qml`, `Model.js` and `manifest.json` into a temporary
folder with `Commons` and `Ui` linked from `/usr/share/omarchy/shell`, swaps
`KeyboardPanel` for the Item stand-in in `tests/offscreen/`, turns the large
editor's layer surface into a plain window, and runs `tests/Preview.qml`
with a throwaway `HOME`, state and runtime directory, Hyprland's signature
unset and the bridge socket pointed into the temporary folder. The sample
data is in `tests/offscreen/FakeService.qml`; the sample theme (slate-teal
accent) is `tests/offscreen/colors.toml`, and `MOSAIC_PREVIEW_COLORS` picks
another `colors.toml`. `QT_SCALE_FACTOR` defaults to 2. The script fails on
QML errors and binding warnings.

The service is not loaded, so nothing reaches Hyprland, the browser or the
running shell. Never screenshot the desktop or inject input to check a
change; render it here, deploy, and look at it by hand.

## Test the engine in a throwaway shell

Changes to `MosaicService.qml` run against the live Hyprland, so test them
in a separate Quickshell instance, never in the running shell:

- Build a scratch folder with symlinks to
  `/usr/share/omarchy/shell/{Commons,Ui,services}` (the service needs `Ui`
  for `SwapCard.qml`) and a `shell.qml` that creates the service the way
  the host does (`Qt.createComponent(url, Component.PreferSynchronous)`,
  then `createObject(null)`). To test the panel with it, give the panel a
  fake `bar` whose `shell` has `serviceFor(id)` and an
  `updateEntryInline(id, settings)` that logs instead of writing
  `shell.json`. `qs.*` imports resolve only from a file named `shell.qml`.
- Run it with `quickshell -n -p <dir>/shell.qml`. `-n` refuses a second
  copy of the same config, so stop an old harness by PID first.
- Always set `XDG_STATE_HOME` to a scratch folder (a harness without the
  login marker restores the `login` sessions of whatever `saved.json` it
  reads), `MOSAIC_BRIDGE_SOCKET` to a scratch path (otherwise its socket
  server takes over the live shell's), and the widget's `swapKey` to `""`
  (otherwise it binds and unbinds a real key).
- The harness sees your live tiles. Never run an action that plans against
  live clients (close, contain, remove, restart the browser) unless no live
  tile or window can match; use a scratch session name such as `zzprobe` on
  a hidden workspace, and act on probe windows by address. Restarting the
  browser from a harness once closed the real browser.
- For a tile without opening a browser, tag one of your own windows with
  `hl.dsp.window.tag({ window = "address:0x…", tag = "+mosaic" })` and
  `+mosaic-zzprobe`, call the service's `refresh()` (tags emit no event),
  and remove the tags afterwards.
- For real tiles, point the **Browser** setting at a throwaway-profile
  wrapper like the one in the header of `examples/cdp-eval.mjs` (use
  `/usr/bin/chromium`: a fresh Brave profile opens a startup page instead of
  the `--app` URL), and mute it (`--mute-audio`). Never drive your everyday
  browser profile. Afterwards check `hyprctl -j monitors`: new tiles can
  briefly switch a monitor to the test workspace.

## Containment check

Fullscreen containment is the core requirement
([ADR 1](../adr/0001-contain-fullscreen-with-hyprland-state.md)). Re-run
this after any change to how tiles are launched or tiled, with the
throwaway-profile browser wrapper from `examples/cdp-eval.mjs`:

```sh
ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i testsrc2=size=640x360:rate=24 -t 30 -c:v libvpx-vp9 /tmp/mosaic-probe.webm
page="file://$PWD/examples/fullscreen-test.html?video=/tmp/mosaic-probe.webm"
# open "$page" twice as tiles in a scratch session, then:
node examples/cdp-eval.mjs fullscreen-test.html 0 \
  'video.requestFullscreen().then(() => new Promise(r => setTimeout(r, 1500))).then(() => innerWidth + "x" + innerHeight)'
hyprctl -j clients | jq -c '.[] | select(.title | test("Mosaic fullscreen test")) | {at, size, floating, fullscreen, fullscreenClient}'
```

Containment holds when the page size equals the tile size and each window
shows `fullscreen 0`, `fullscreenClient 2` at an unchanged position. Test on
a **visible** workspace: windows on hidden ones get no frame callbacks.
Close the test tiles afterwards and check `hyprctl -j monitors`. Read what
the browser believes with `matchMedia("(display-mode: fullscreen)")`, not
from `clients`, since Hyprland's record can go stale
([ADR 13](../adr/0013-reapply-fullscreen-state-after-moves-and-layout-switches.md)).
The full evidence is in
[architecture.md](../architecture.md#containment-check).

## Refresh the preview

The README hero is `preview.png` at the repository root (3840×2160; the
marketplace shows it too). Its editable source is
[`docs/brand/preview.svg`](../brand/preview.svg), which draws the monitor
and its tiles and places two offscreen captures:

| Capture | From |
| --- | --- |
| `docs/brand/captures/tiles.png` | `tests/preview.sh`, scene `tiles` |
| `docs/brand/captures/layouts.png` | `tests/preview.sh`, scene `layouts` |

To refresh:

1. Render the captures and copy the two over `docs/brand/captures/`. Look
   at each one; they show the version from `manifest.json`, so refresh them
   after a version bump.

   ```bash
   MOSAIC_PREVIEW_DIR=/tmp/mosaic-preview bash tests/preview.sh
   cp /tmp/mosaic-preview/{tiles,layouts}.png docs/brand/captures/
   ```

2. Edit `docs/brand/preview.svg` if the layout or text changes. Keep the
   inlined mark in sync with `icon.svg`.
3. Render and look at the result:

   ```bash
   rsvg-convert -o preview.png docs/brand/preview.svg
   ```

4. Keep the README's alt text accurate.

The SVG asks for JetBrainsMono Nerd Font (Omarchy's default font); the chip
icons are its glyphs. The current `preview.png` was rendered with librsvg
2.63.3 with that font installed. Other fonts change spacing and drop the
icons, so inspect the output after rendering. Check every capture for real
channel names, accounts, paths or addresses before it goes into the
repository.

## Release

1. Bump `version` in `manifest.json` and `package.json`.
2. Turn **Unreleased** in `CHANGELOG.md` into `## X.Y.Z (YYYY-MM-DD)`. If
   the extension changed, say which worker script and version it needs.
3. Check the README and the guide pages cover the change, and refresh the
   preview captures (they show the version).
4. `npm test` and `omarchy plugin validate .`.
5. Commit `Release X.Y.Z` and add an annotated tag:
   `git tag -a vX.Y.Z -m "Mosaic X.Y.Z"`.
6. Ask the owner before pushing the commit and the tag, and before
   publishing a GitHub release.

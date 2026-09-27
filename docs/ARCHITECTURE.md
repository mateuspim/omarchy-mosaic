# Architecture notes

## Where things stand

The plugin is a service (`MosaicService.qml`) plus a bar widget
(`Panel.qml`), with pure logic in `Model.js`. The service builds the tile list
from Hyprland and `tiles.json` and the web app list from `DesktopEntries`,
and it adds, replaces, focuses, removes, closes, and contains tiles through `hyprctl`,
without the Rust `mosaic` CLI. `docs/HANDOFF.md` has the plan and the parity
checklist; the IPC and the `mosaic` wrapper are what parity still lacks.

## Target shape

- **One plugin, two kinds.** `manifest.json` declares `kinds: ["service",
  "bar-widget"]`. The service (`MosaicService.qml`) is the engine: the tile
  model, the store, the launch-and-tile sequence, and an `IpcHandler` with
  target `pym.mosaic`. It runs whether or not the widget is on the bar.
  `Panel.qml` is UI only. There must never be two engines, two IPC handlers,
  or two launch sequences at once, including across plugin hot reloads.
- **Pure logic in `Model.js`**, tested with `node tests/model.test.js`:
  session and address validation, web app URL extraction, list shaping, and
  the containment state.
- **Hyprland is the source of truth.** Tags decide which windows are tiles.
  The store only adds URLs and order. Nothing watches for lost containment
  (see below); the engine only reacts to Hyprland events to refresh its model.
- **How the widget reaches the service.** Through the host's own-service
  facade: `bar.shell.serviceFor("pym.mosaic")`, held in a typed `QtObject`
  property that resets to null when the service is destroyed, and looked up
  again on a timer while it is missing. Not a `qmldir` singleton: a singleton
  lives outside the host's lifecycle, so it survives plugin reloads and
  disabling (an `IpcHandler` in it would stay registered). The service must
  not set `keepLoaded`, so disabling or reloading the plugin tears it down.
- **Refreshing.** `lastIpcObject` changes only on `Hyprland.refreshToplevels()`,
  and adding or removing a tag emits no Hyprland event. The service refreshes
  (debounced) on window events and on `tiles.json` changes, and rebuilds the
  list when any toplevel's `lastIpcObject` changes. Anything that tags a
  window must call `refresh()` afterwards.
- **Command line.** `omarchy-shell pym.mosaic <command> …` reaches the
  `IpcHandler`. A small `bin/mosaic` wrapper keeps the `mosaic` command name.

| The CLI did | The plugin uses |
| --- | --- |
| `hyprctl -j clients` and `monitors` | `Hyprland.toplevels` (`lastIpcObject` is the raw client JSON, refreshed only by `Hyprland.refreshToplevels()`) and `Hyprland.monitors` |
| `hyprctl dispatch 'hl.dsp…'` | a `Process` running `hyprctl dispatch` where the `ok` reply matters, else `Hyprland.dispatch` |
| polling for the new app window | `Hyprland.rawEvent` `openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE`, with a `Timer` timeout |
| default browser from `xdg-settings` | a `Process`, then `DesktopEntries.byId(id).command[0]` |
| `uwsm-app -- <browser> --app=URL` | `Quickshell.execDetached([...])`, an argv list with no shell |
| parsing `.desktop` files | `DesktopEntries.applications` |
| `tiles.json` | `FileView`, same file and format |

## Sessions and the store

Every tile carries two static Hyprland tags: `mosaic`, and
`mosaic-<session>`. Session names match `^[a-z0-9_-]{1,32}$` because they
are interpolated into Lua strings, and window addresses must be `0x` plus
hex for the same reason. Tags decide membership.

`$XDG_STATE_HOME/mosaic/tiles.json` (default `~/.local/state`) records each
tile's address, session, and URL in the order the tiles were added:

```json
{ "tiles": [ { "address": "0x…", "session": "streams", "url": "https://…" } ] }
```

It is written atomically, pruned against live windows on `add`, and ignored
where it disagrees with the tags. Keep this file and format so tiles opened by
the Rust CLI carry over.

`list` returns the v1 JSON that the widget already reads:

```json
{"version":1,"sessions":[{"name":"streams","tiles":[{"index":1,"address":"0x…","url":"https://…",
  "title":"…","monitor":"DP-4","workspace":10,"state":"contained"}]}]}
```

Sessions are sorted by name (tiles without a session tag go to `default`),
and tiles by store order. `index` is 1-based across all sessions. `state` is
`contained`, `uncontained`, `floating`, or `fullscreen`. `version` changes
only on incompatible changes; adding a field doesn't bump it.

## Web apps

`webapps` returns
`{"version":1,"webapps":[{"id":"Twitch","name":"Twitch","url":"https://twitch.tv","icon":"twitch"}]}`.
A web app is a desktop entry whose command runs `omarchy-launch-webapp URL`
(what Omarchy's web app installer writes), or a browser with `--app=URL`.
Only http and https URLs count, and `Hidden` or `NoDisplay` entries are
skipped. A user entry hides a system entry with the same id.
`/usr/share/omarchy/applications` is not read, because it holds templates
that Omarchy copies into `~/.local/share/applications`; reading it would
bring back web apps the user removed. `add` accepts a web app's name or id
(case-insensitive) in place of a URL, and resolves every target before
opening any tile.

The service builds this list from Quickshell's `DesktopEntries`, which
already applies the rules above: it reads `$XDG_DATA_HOME` and
`$XDG_DATA_DIRS` (not the Omarchy templates), lets a user entry hide a
system entry with the same id, including a `Hidden` one, and leaves out
`NoDisplay` entries. Ids are desktop file ids, so they match the Rust CLI's
file names. One difference: entries in subdirectories of `applications`
also count, with the id `dir-name` that the specification gives them.
`DesktopEntries` scans asynchronously and reports each entry it adds, so the
service rebuilds the list after `valuesChanged` settles.

## Browser selection

The default browser is resolved the way Omarchy's `omarchy-launch-webapp`
does it: `xdg-settings get default-web-browser`, then the program from that
desktop entry's `Exec`. Only Chromium-family browsers are accepted
(Chromium, Chrome, Brave, Edge, Opera, Vivaldi, Helium), because Firefox has
no `--app` mode. The widget's **Browser** setting overrides the default, which is also how
tests point the plugin at a throwaway profile. Launches go through
`uwsm-app --`, as an argv list. Unlike the CLI, the plugin doesn't fall back
to launching the browser directly, since Omarchy always has `uwsm-app`.

## Finding each tile's window

Chromium-family browsers reuse a running browser process, so the spawned
process ID doesn't identify the window. A Chromium app window's class is
`<browser>-<host>__<path>-<profile>`, for example
`brave-www.twitch.tv__-Default`. The engine launches one URL at a time and
takes the first new window, announced by Hyprland's `openwindow` event,
whose class contains `__`; that skips normal windows a cold browser start
may restore. The class is already final in the event (checked with
Chromium, 2026-09-27). A window the user opens during the
wait could still be mistaken for a tile.

## Fullscreen containment

Each tile window is moved to the target workspace (`follow = false`), set to
tiled with `hl.dsp.window.float({ action = "disable", … })`, made opaque with
`set_prop opaque 1`, and then given Hyprland fullscreen state `internal = 0,
client = 2`:

```sh
hyprctl dispatch 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x…" })'
```

The compositor keeps the window at its tile size while the browser believes
it is already fullscreen. When a page calls `requestFullscreen()`, Chromium
needs no window change and renders the fullscreen element inside the tile.
Omarchy's own **Super+Ctrl+F** toggle uses the same state pair. The state is
applied last, because switching between floating and tiled resets it.

Dispatch facts (Hyprland 0.56.2, Lua config):

- `hl.dsp.window.float` only understands `enable`, `disable`, and `toggle`.
  Any other value is **silently a toggle**.
- Omarchy's rules make unfocused browsers translucent unless `opaque` is set.
- `hl.dsp.window.tag({ window = "address:…", tag = "+name" })` adds a tag,
  `-name` removes it. Static tags show in `clients` without a `*`; rule-set
  tags like `default-opacity*` have one.
- Dispatches reply `ok` on success.

### Evidence, 2026-09-27

Tested with Brave Origin, a throwaway profile, and a local WebM video,
triggering fullscreen through the DevTools protocol with `userGesture: true`.

| Mode | Page during fullscreen | Hyprland window | Result |
| --- | --- | --- | --- |
| Plain `--app` windows | 2048×1152 (whole output) | moved to the output, fullscreen `2/2` | Video covers the monitor |
| Preset `internal 0, client 2` | 1024×1126 (the tile) | unchanged, fullscreen `0/2` | Video fills only its tile |

| Action on a `0/2` tile | State afterwards | Event on `.socket2.sock` |
| --- | --- | --- |
| Float, then tile again | `0/0` while floating, `0/2` once tiled | `changefloatingmode` |
| Super+F on, then off | `2/2`, then back to `0/2` | `fullscreen>>1`, `fullscreen>>0` |
| Page `requestFullscreen()`, then `exitFullscreen()` | `0/2` throughout | none |
| Super+Ctrl+F, or `fullscreen_state` `0/0` | `0/0` | none |
| Swap with another tile | `0/2` | — |

### Hyprland's record goes stale after a workspace move, 2026-09-27

Tested with Chromium (`/usr/bin/chromium`, a throwaway profile, the test
page on hidden workspaces 42–44). Brave Origin opens a startup page for a
fresh profile, so it can't be probed this way. `display-mode: fullscreen`
reads what the browser believes without requesting fullscreen.

| Tile | Hyprland record | Browser believes fullscreen | Video fullscreen |
| --- | --- | --- | --- |
| Contained on its workspace | `0/2` | yes | fills the tile |
| After `hyprctl reload` | `0/2` | yes | fills the tile |
| Contained, then `window.move` to another workspace | **`0/0`** | **yes** | fills the tile |
| Released (`0/2`, then `0/0` directly) | `0/0` | no | covers the monitor (`2/2`) |
| Released, then moved to another workspace | sometimes **`0/2`** | **no** | — |

- A move leaves Hyprland's `fullscreenClient` stale in either direction and
  tells the browser nothing, so `clients` can't tell a moved tile from a
  released one. Which value comes out after a move isn't understood; it
  seemed to depend on the tile's history on the target workspace.
- The user's YouTube tile on workspace 10 showed the first case: `0/0` in
  Hyprland, yet its video fullscreen stayed in the tile, and no fullscreen
  event or state change reached Hyprland.
- A `fullscreen_state` dispatch that matches the stale record is a no-op,
  and one that differs makes Hyprland tell the browser. Re-applying the
  state a tile already has changes nothing about the window or the page.
- A Super+F round trip on a hidden workspace left the browser mid-resize and
  a fullscreen request hanging, probably because hidden windows get no frame
  callbacks. Test Super+F only on a visible workspace.

**What the service does about it:** on every `movewindowv2` for a tile, it
re-applies the state the tile had before the move, from its own list:
`0/2` for a contained tile, `0/0` for an uncontained one
(`Model.restoreAfterMove`). Floating and truly fullscreen tiles are left
alone. Checked live on the same setup: contained tiles moved across three
workspaces stayed `0/2` with the browser fullscreen, and a released tile
moved across three stayed `0/0` with the browser not fullscreen, so the
panel's labels were right every time. Tiles that were already stale before
this change need one `contain` (`C`). Known limit: Super+Ctrl+F emits no
event, so if a tile is released and then moved before anything refreshes
the service's list, the move contains it again.

Hyprland restores the earlier state after a float or fullscreen round trip.
Containment is lost only when the state is set directly, which emits no
event, so a watcher would add nothing. `contain` re-applies `0/2` on request,
and only to tagged tiles in the `uncontained` state.

### Known side effects

- Brave briefly shows its "press Esc to exit full screen" toast when a tile
  opens.
- While a tile floats, its video fullscreen covers the monitor. Containment
  comes back when it is tiled again.
- Tiles share the workspace with any windows already on it, and Hyprland's
  layout (dwindle by default) decides their sizes.
- The user confirmed containment on the Twitch and YouTube home pages. Real
  players (fullscreen button, `f`, double-click, theater mode) still need a
  check per site before the site is called supported.

## Compared approaches

| Approach | Fullscreen control | Tradeoff |
| --- | --- | --- |
| Chromium-family `--app` windows, tiled by Hyprland, with `fullscreen_state 0/2` (**chosen**) | Proven with a local video in Brave | Uses the user's real browser, profile, logins, codecs, and DRM. One window per tile. |
| Embedded WebKitGTK views in one window | Proven with a local video | Crashed on video sites without `gst-plugins-good`, and has no access to the user's logins. |

Floating windows in a computed grid were tried and rejected: they hid
Omarchy's swap bindings, and dragging one reset its containment. Ask the user
before bringing floating geometry back.

## Containment check

Use the throwaway-profile browser wrapper from the header of
`examples/cdp-eval.mjs`, never the everyday profile.

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
shows `fullscreen 0`, `fullscreenClient 2` at an unchanged position. Close
the test tiles afterwards and check `hyprctl -j monitors`, since new tiles
can briefly reshuffle or switch the user's workspace.

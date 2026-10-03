# Architecture notes

## Where things stand

The plugin is a service (`MosaicService.qml`) plus a bar widget
(`Panel.qml`), with pure logic in `Model.js`. The service builds the tile list
from Hyprland and `tiles.json` and the web app list from `DesktopEntries`,
and it adds, replaces, focuses, removes, closes, and contains tiles through `hyprctl`,
without the Rust `mosaic` CLI. The IPC target `pym.mosaic` and the
`bin/mosaic` wrapper cover every CLI command, so the plugin has parity with
the CLI.

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

## The browser extension

Per-tile audio needs to know which audio belongs to which tile, and PipeWire
can't say: every `--app` window shares the browser's one process, and
Chromium plays every tab through one audio service process, so each stream
has the same PID, `application.name`, and `media.name` ("Playback").
Separate browser instances per tile would fix that at the cost of separate
logins and memory; the user chose an extension instead.

- **Pieces.** `extension/` (Manifest V3, with a fixed `key`, so its ID is
  always `ibcnbknhphdnlpfglnhelicnpnnmepbo`), the native messaging host
  `bin/mosaic-native-host` (Python 3, standard library only), and a
  Quickshell `SocketServer` in the service at `$XDG_RUNTIME_DIR/pym-mosaic.sock`
  (`MOSAIC_BRIDGE_SOCKET` overrides it for both sides, for test shells).
- **Flow.** The extension calls `connectNative("pym.mosaic")`; the browser
  starts the host, which connects to the socket (again every 2 s while the
  shell is down) and relays: length-prefixed JSON on stdio for the
  browser, one JSON object per line for the shell. The host sends `host`
  (the browser's executable, from its parent process) first, and replays
  the extension's last `hello` and `windows` to a new shell. The service
  sends `ping { id }`; the extension answers `windows { id, windows }` with
  its app and popup windows (never normal browsing windows) and pushes
  `windows` on its own when titles, audio, or windows change.
- **Install.** Browsers only load extensions silently by policy (root) or
  by command line. Omarchy already loads its own with `--load-extension=`
  in `~/.config/<browser>-flags.conf`, which Arch's launchers read, so
  `mosaic-native-host setup DIR` adds DIR there (only to flags files that
  exist; symlinks followed, mode kept) and writes
  `NativeMessagingHosts/pym.mosaic.json` into each browser profile folder
  that exists. `remove` undoes both; `status` reports them as JSON. The
  panel's Extension tab runs these, and Google Chrome, which ignores
  `--load-extension` since 137, needs Load unpacked.
- **Mute.** The service sends `mute { tab, muted }`; the extension only
  mutes tabs in app windows (`chrome.tabs.update`) and its next `windows`
  report carries the change, which `Model.tileAudio` turns into each tile's
  state. Focus mode (`audioFollowsFocus`, a widget setting) reacts to
  `activewindowv2` for tiles and re-applies after every check, so a new
  tile starts muted.
- **Commands (extension 0.3.0 and later).** `mute`, `volume { level }` (0 to 1;
  an injected isolated-world script sets every media element and again on
  each `play` and `loadeddata` while below 1, and the worker sets it again
  when the page finishes loading), `navigate { url }` (http and https
  only), `reload`, and `media { action }`. Each only touches tabs in app
  windows, may carry an `id` answered by `done { id, error }`, and shows its
  effect in the next `windows` report (tabs now carry `favIconUrl` and
  `volume`). `hello.features` lists them; the service checks
  `Model.bridgeHas` before sending. Permissions include `scripting` and
  `<all_urls>`, taken now so later features need no restart.
- **Volume follows the page (extension 0.4.0, `background-4.js`,
  feature `follow`).** The last change wins: the page script watches
  `volumechange`, and a change made within 1.5 s of trusted input in the
  page (pointer, key, wheel), such as YouTube's own slider or arrow keys,
  becomes the tab's level and is reported (`pageVolume` message to the
  worker). A change a player makes on its own is undone at the next
  `play` or `loadeddata`, as before. The worker injects the watcher into
  every tile page on load, so it follows pages the service never set, and
  keeps levels in `chrome.storage.session` (permission `storage`), which
  outlives the worker being stopped. The service then mirrors reports
  (`Model.reconcileVolumes`), keeping its own level only for 3 s after
  the user sets one. With an older extension it still sends its level
  again when a report disagrees, because those workers lose it.
  Checked 2026-09-29 with a headless Chromium on a localhost video.
  Clicking a new video counts as input, so the volume a site applies on
  that load is followed too.
- **Updates.** There is no automatic reload: after `chrome.runtime.reload()`
  the service worker wasn't started again (46 s in a test), which would
  leave the browser disconnected. Nor is a version check enough: after a
  restart, Brave Origin 153 reported the new manifest's version while still
  running its cached copy of the old worker script (pings answered, `mute`
  ignored), until Developer mode was switched on, which reloads unpacked
  extensions. So the worker script is named per change (`background-2.js`,
  as Omarchy's Copy URL uses `background-4.js`), `hello` carries the
  script's own name, and the service compares it with the manifest's
  `service_worker` (`extensionOutdated`); the panel then asks for a browser
  restart, and `mute` needs a script that reports its name
  (`Model.canMute`). **Rename the worker on every extension change.**
- **Swap in place.** `replace` (the panel's S, the swap card, `mosaic
  replace`) sends `navigate { url }` when the extension has found the tile
  and can navigate, then rewrites only the tile's store record's URL. The
  window, its slot, containment, mute, and volume stay, and no window
  opens, so no cursor warp or screen jump. Without the extension, or for
  a tile it hasn't found, a new window still opens in the old one's slot.
  While the page loads, `SwapVeil.qml` covers the tile with a click-through
  overlay layer (`pym-mosaic-veil`, no keyboard): the Omarchy wordmark
  (`$OMARCHY_PATH/logo.svg`, tinted to the theme) over a bar like the boot
  screen's, lifted once the extension reports the tab on the new site with a
  title of its own (`Model.navigationSettled`), after 0.9 s at least and 6 s
  at most.
  The window keeps the Hyprland class from its first URL (Chromium names
  app windows after it), and nothing in Mosaic reads that class.
- **Finding tiles.** A tile keeps the tab it was matched to while that
  tab exists (a swap in place can leave two tiles on one site with one
  title); else it is the extension window whose one tab has the tile's
  Hyprland title (`Model.matchTiles`), else the one left on its site. Verify reports how many tiles were found.
- **Quickshell facts.** A `SocketServer` makes one handler `Socket` per
  connection; writes before `connected` turns true are lost; a closed
  handler socket is never destroyed and `destroy()` refuses it
  ("indestructible object"), so the service drops its references. The
  server deletes a stale socket file itself. Unix socket paths are limited
  to 108 bytes.

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

## Layouts

`layouts.lua` defines four Hyprland **Lua tiling layouts** (Hyprland 0.56's
`hl.layout.register`): `mosaic-grid` (balanced grid, a short last line
stretched), `mosaic-stack` (one row on a landscape area, one column on a
portrait one), `mosaic-main` (the first tile takes 70% of the long side,
the rest share a line beside or below it), and `mosaic-fit` (the grid
whose 16:9 tiles come out largest, centered). Custom layouts are zones,
`mosaic-c-<slug>`. They are real tiled layouts: Hyprland applies the gaps,
and swaps (Omarchy's bindings, `hl.dsp.window.swap`) move windows between
slots. Floating geometry stays rejected (see "Compared approaches").

- **Layouts belong to workspaces** (the user's choice, 2026-09-29), like
  Hyprland's own: workspace 8 can be Grid and 9 a custom layout, for every
  window there. A session's header button sets the layout of the workspace
  its first tiled tile is on.
- The service loads the file with `hyprctl eval 'dofile("…/layouts.lua")'`
  and sets a layout per workspace with `hl.workspace_rule({ workspace =
  "N", layout = "lua:mosaic-grid" })`. The **`lua:` prefix** is required;
  an unknown name silently falls back to dwindle. A rule works before the
  workspace exists.
- Hyprland refuses a name registered twice and can't unregister one, so
  names are registered once per Lua state (`MosaicRegistered`) and call the
  code in the global `MosaicLayouts`, which every load replaces. Custom
  zones live in `MosaicCustom`, set by `MosaicLayouts.define(slug, zones)`.
  A deleted layout's name stays registered, unused, until a reload.
- **Custom layouts** (`Model.normalizeCustom`) are a tree of splits: a
  zone is `{}`, a split is `{ split: "row" | "column", sizes, children }`
  with percent `sizes` (at least 5% each, adding up to 100), up to 6
  children, 4 levels, and 16 zones; plus a `main` zone (1-based, depth
  first). Windows fill the main zone first, then the others in visual
  order; extra windows share the last zone, split along its longer side.
  The first form (a `columns`, `rows`, or `grid` template) is read as a
  tree. The panel's Layouts tab edits them: presets to start from, lines
  between zones dragged on the preview (`Model.zoneDividers`,
  `withDivider`), and split, main, and remove buttons on each zone (the
  user asked for mouse editing "like PowerToys"; a full-screen editor on
  the monitor could come later on the same format).
- Changing a custom layout's zones doesn't lay out a workspace that uses
  it, and neither does setting the same rule again; switching it to
  dwindle and back does, so a save does that for each workspace using it.
- `$XDG_STATE_HOME/mosaic/layouts.json`: `{ "version": 2, "workspaces": {
  "8": { "layout": "grid", "before": "dwindle" }, "9": { "layout":
  "custom:three", "before": "" } }, "custom": { "three": { "name": "Three",
  "tree": { "split": "row", "sizes": [25, 50, 25], "children": [{}, {},
  {}] }, "main": 2 } } }`, where
  `before` is the workspace's layout before Mosaic changed it, which
  `default` puts back. Version 1 (unreleased, one day old) kept layouts per
  session; they move to their sessions' workspaces on the first sync.
- Runtime rules and registrations are gone after a config reload, so the
  service applies everything saved again at start and on
  `configreloaded` (`Model.planSyncLayouts`).
- **Switching a workspace's layout resets `fullscreenClient` 2 → 0** for
  its tiles (seen for dwindle → master and master → Lua; a relayout within
  one layout keeps it). So every switch is followed by re-applying each
  tile's state from the list read before the switch; after a reload, from
  states saved at the `configreloaded` event.
- `hyprctl -j workspaces` reports every Lua layout under the first name
  registered in that Hyprland session (a Hyprland bug, 0.56.2), so the
  service can tell a Lua layout from dwindle but not which one; the saved
  choice is what the panel shows.

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
- Tiles share the workspace with any windows already on it, and the
  workspace's layout (dwindle by default, or a Mosaic layout; see
  "Layouts") decides their sizes.
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

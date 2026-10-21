# Native messaging: extension, host and service

Three pieces carry messages between the browser and the shell
([ADR 8](../adr/0008-per-tile-audio-through-a-browser-extension.md)):

```
extension/ (worker)  ⇄  bin/mosaic-native-host  ⇄  MosaicService.qml
 connectNative          length-prefixed stdio        one JSON object per line
 "pym.mosaic"           ↔ Unix socket                on $XDG_RUNTIME_DIR/pym-mosaic.sock
```

## The extension

Manifest V3, name "Omarchy Mosaic", with a fixed `key`, so its ID is always
`ibcnbknhphdnlpfglnhelicnpnnmepbo`. Permissions: `nativeMessaging`, `tabs`,
`alarms`, `scripting`, `storage`, and host permission `<all_urls>`. The
worker script's file name changes with every extension change
([ADR 10](../adr/0010-rename-the-extension-worker-on-every-change.md)); today
it is `background-10.js`, version 0.5.5.

It connects with `chrome.runtime.connectNative("pym.mosaic")`, retries with
backoff from 1 s to 60 s, and a one-minute alarm wakes the worker if the
browser stopped it.

## The host manifest

`mosaic-native-host setup DIR` writes this to
`~/.config/<profile folder>/NativeMessagingHosts/pym.mosaic.json` in every
known Chromium-family profile folder that exists:

```json
{ "name": "pym.mosaic",
  "description": "Omarchy Mosaic bridge to the Omarchy shell",
  "path": "<absolute path of bin/mosaic-native-host>",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://ibcnbknhphdnlpfglnhelicnpnnmepbo/"] }
```

It also adds `DIR` to the last `--load-extension=` line of each known
`~/.config/*-flags.conf` that exists (or appends that line), dropping older
Mosaic entries. `remove DIR` takes Mosaic's entries off the flags files and
deletes a host manifest only if it still equals Mosaic's. `status [DIR]`
prints, and `setup` and `remove` also print afterwards:

```json
{ "extensionId": "ibcnbknhphdnlpfglnhelicnpnnmepbo", "extension": "DIR",
  "host": "<host path>", "socket": "<socket path>",
  "browsers": [ { "name": "Chromium", "folder": "chromium", "registered": true } ],
  "flags": [ { "file": "<path>/chromium-flags.conf", "loaded": true } ] }
```

`DIR` must be absolute, contain no comma or line break, and hold a
`manifest.json`; otherwise the host exits with `error: …`.

## Framing

- **Browser ⇄ host**: Chromium native messaging: a 4-byte little-endian
  length, then that many bytes of UTF-8 JSON. Frames over 1 MiB end the
  relay at once, before the body is read; frames the host would send over
  1 MiB are dropped. A body that is not a JSON object is skipped.
- **Host ⇄ service**: one compact JSON object per line on the Unix socket
  (`MOSAIC_BRIDGE_SOCKET` overrides the path for both sides). Lines that
  are not JSON objects are skipped; an unterminated buffer over 1 MiB is
  discarded.

The host relays objects unchanged, with two additions. When it connects to
the shell, it first sends `host` and then replays the extension's last
`hello` and last unsolicited `windows`, so a restarted shell learns the
state at once. While the shell is down it retries every 2 s.

## Messages

Every message is a JSON object with a `type`.

### To the service

| Type | Fields | Meaning |
| --- | --- | --- |
| `host` | `pid`, `browser` | From the host: the browser's PID and executable (`/proc/<ppid>/exe`). |
| `hello` | `extension`, `script`, `features` | The extension's version, its worker's file name, and what it can do: `mute`, `volume`, `follow`, `navigate`, `reload`, `media`, `favicon`, `stream`, `extensions`, `fullscreen`. |
| `windows` | `windows`, optional `id` | The browser's app and popup windows (never normal ones), pushed when they change (debounced 250 ms) and in answer to `ping` (with its `id`). |
| `done` | `id`, `error` | How a command that carried an `id` went; `error` is `""` on success. |

A `windows` entry is `{ id, type, focused, tabs }`, and each tab is
`{ id, url, title, favIconUrl, audible, muted, volume, stream }`. `volume`
is 0 to 1 (1 means the site's own level). `stream` is `null` or
`{ state: "playing" | "idle" | "dropped", reason, detail, since,
fullscreen }`, reported by the page watcher only when it changes and
forgotten when the tab loads a new page.

### From the service

| Type | Fields | Effect |
| --- | --- | --- |
| `ping` | `id` | Answered by `windows` with the same `id`. |
| `mute` | `tab`, `muted` (boolean) | `chrome.tabs.update` muted. |
| `volume` | `tab`, `level` (0–1) | Sets every media element's volume in the tab and keeps it on `play` and `loadeddata` until the page's own controls change it. |
| `navigate` | `tab`, `url` | Loads an `http` or `https` address in the tab (swap in place). |
| `reload` | `tab` | Reloads the tab. |
| `media` | `tab`, `action` | `play`, `pause` or `toggle` on the page's media; a pause from here counts as a pause by hand. |
| `extensions` | — | Opens `chrome://extensions/` in a new window. |

Commands may carry an `id`, answered by `done`. Tab commands act only on tabs
in app or popup windows; anything else fails with an error. Their effect
shows in the next `windows` report. The service checks `features`
(`Model.bridgeHas`) before sending a command, and compares `script` with the
manifest's `service_worker` to tell the user when the browser runs an old
copy.

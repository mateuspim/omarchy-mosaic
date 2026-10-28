# Widget settings and manifest

`manifest.json` declares one plugin, `pym.mosaic`, of two kinds: a
`service` (`MosaicService.qml`, the engine) and a `bar-widget`
(`Panel.qml`, the panel), category Windows, one instance, default section
right. `omarchy plugin validate .` checks it.

Settings belong to the bar widget's entry in the shell's `shell.json`. The
panel reads them with `setting(name, fallback)`, saves changes it makes
itself with `bar.shell.updateEntryInline`, and binds them onto the service,
so the service follows them even for IPC calls.

## In the shell's settings UI (manifest schema)

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `browser` | string | `""` | A Chromium-family command to open tiles with (`~/` is expanded). Empty: the default browser, which must be Chromium-based. |
| `swapKey` | string | `SUPER + SHIFT + S` | The key that opens the swap card over the focused tile, written like `SUPER + SHIFT + S` (modifier names and one key name, or `code:N`). Empty binds none. A key another bind uses is refused with a notification. |
| `hiddenWebapps` | string | `""` | Web app names or ids, comma-separated, matched without case, that get no button. Right-clicking a button adds one; the Hidden tab removes them. |
| `recoverSites` | string | `twitch.tv, kick.com` | Sites, comma-separated, whose dropped streams are reloaded; subdomains count. |

## Set from the panel only

These have defaults in the manifest but no schema entry; the panel's
switches save them.

| Key | Default | Panel | Meaning |
| --- | --- | --- | --- |
| `audioFollowsFocus` | `false` | **Only the focused tile plays** (F) | Mute every tile but the focused one; focusing a non-tile window changes nothing. Turning it off unmutes every tile. |
| `recoverStreams` | `true` | **Recover dropped streams** (Shift+R) | Reload dropped streams on `recoverSites`. |
| `addOnFocusedWorkspace` | `false` | **New tiles open on the focused workspace** (O) | An add with no session joins the session tiled on the focused (or `--monitor`) workspace; the panel passes the monitor it is open on, else `default` when it has no tiles, else a new `ws-N` (`ws-N-2`, … when taken); see `Model.focusedSession`. |
| `autoContain` | `false` (not in the manifest's defaults) | **Keep fullscreen in tiles** (Shift+C) | Contain tiles without being asked: at once when uncontained, and a truly fullscreen tile once another window takes focus. |

# The browser extension (for audio control)

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
still running an old copy of it, the Extension tab says so. Load the
current one without closing your tiles: **Open the extensions page** (O)
and press Reload on Omarchy Mosaic (turn on Developer mode if there's no
Reload button). An extension older than 0.5.2 can't open the page, so the
button copies `chrome://extensions/` for the address bar instead. Or
restart the browser (the tab's Restart button, B), which also loads it. The same steps are in the IPC: `omarchy-shell pym.mosaic
extension` (status as JSON), `extensionEnable`, `extensionVerify`, and
`extensionDisable`.

# Audio

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

Audio control needs the [browser extension](browser-extension.md).

# The panel

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
| S | Swap the selected tile's web app: the tile's card opens a picker: a web app (1–9), or its address to edit (A, then Enter). Esc cancels |
| I | Save the selected tile as a web app, when no web app matches it (a tile opened from a typed address, such as `music.youtube.com`): its card asks for the name, prefilled from the page title, and Enter installs an Omarchy web app for the site with its icon. Esc cancels |
| T | Move the selected tile to another session: its card lists the other sessions (1–9, with their workspaces), then a new session on each other monitor whose workspace has none, or N types a new name (Enter moves). It joins that session's workspace; a monitor choice moves it to that monitor's workspace; a typed new session keeps it where it is. Esc cancels |
| X or D | Remove the selected tile |
| Shift+D | Close the selected tile's session |
| 1–9 | Add that web app to the session |
| A | Type a URL or web app name to add (Enter adds, Esc returns to the list) |
| C | Turn fullscreen containment back on |
| Shift+R | Turn "Recover dropped streams" on or off |
| O | Turn "New tiles open on the focused workspace" on or off |

The switches for the whole mosaic sit two to a line under the tabs, each
with a short name, on or off, and its key; hovering one says more.
| P | Reload the selected tile's page (needs the browser extension) |
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

With **New tiles open on the focused workspace** (O) on, an empty session
field means "where I am" instead: a new tile joins the session already
tiled on the focused workspace, or else `default` if it has no tiles yet,
or else a new session named after the workspace (`ws-10`). Each session
still stays on one workspace, so its layout, save and restore keep
working. `mosaic add` without `--session` follows the switch too.

A tile already in the wrong session doesn't need reopening: select it and
press **T** to move it to another session (`mosaic move TILE SESSION`).
To send it to another display, pick that monitor's chip (such as
`ws-3 · HDMI-A-2 · workspace 3`): the tile starts a session on the
workspace that monitor shows, named the way **New tiles here** would.

To swap the tile you're looking at without opening the bar first, press
**Super+Shift+S** on it. A card opens over the tile with your web apps
(1–9) and the tile's address, ready to edit (A, then Enter), so you can
switch to another site or just another channel; Esc or a click on the tile
closes it. Errors arrive as a notification.
Change the key in the widget's **Swap key** setting (written like
`SUPER + SHIFT + S`), or clear it to have none; a key another binding
already uses is refused, and a notification and the panel say why. The key
runs `omarchy-shell pym.mosaic swap`. To keep the bind in your own config
instead, clear the setting and add it to `~/.config/hypr/bindings.lua`:

```lua
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("omarchy-shell pym.mosaic swap"), { description = "Mosaic: swap tile" })
```

The panel's own swap mode (S) opens the same picker on the tile's card. With
the browser extension connected, the tile's page just changes in place: same
window, slot, mute, and volume. Without it, a new window opens and takes
the old tile's session, workspace, slot, and place in the list.

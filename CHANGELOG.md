# Changelog

## 1.7.1 (2026-10-29)

- **Fixed**: a tile on a site outside "Stream recovery sites", such as
  YouTube Music, could say **stream dropped** while it played, after a
  song ended or with its player hidden. Only recovered sites show a
  stream warning now; `mosaic streams` still shows every tile's state.

## 1.7.0 (2026-10-27)

- **Move a tile to another monitor**: the move picker (T) now also lists
  each other monitor whose workspace has no session. Choosing one moves
  the tile there in a new session, named as "New tiles here" would name
  it (`default` when free, else `ws-N`); before, a new session stayed on
  the tile's workspace beside the old one.

## 1.6.1 (2026-10-27)

- **Fixed**: a Twitch tile that a recovery reload brought back to the
  "network error (#2000)" screen stayed there, since the page had no
  video to watch. A reload that doesn't play again within 45 seconds
  now counts as a failed try and is retried, within the usual three.
- **Fixed**: with "New tiles here" on, a tile added from the panel on
  another monitor opened where Hyprland's focus was, not on that monitor,
  and a session the field had filled in earlier kept winning until the
  panel reopened. The panel now sends its own monitor and leaves the
  session field empty.
- **Fixed**: the panel stopped at 620 pixels and scrolled with a laggy
  fling; it now grows to the screen's free height, scrolls a fixed step
  per wheel notch, and brings the add form into view when it opens.

## 1.6.0 (2026-10-26)

- **New tiles open on the focused workspace**: a switch ("New tiles here") on the Tiles tab
  (O). With it on and no session typed, a new tile joins the session on
  the workspace you're on, or starts one there (`ws-10`), instead of going
  back to the workspace the selected tile's session is on. `mosaic add`
  without `--session` follows it too.
- **Move a tile to another session**: T on a tile lists the other sessions
  (1–9) or takes a new name (N), and the tile joins that session's
  workspace, with no reopening. Also `mosaic move TILE SESSION`.
- **A shorter panel**: the switches for the whole mosaic are a two-column
  grid of labelled chips (name, on or off, key), instead of a line each.

## 1.5.3 (2026-10-21)

- **Fixed**: the native host waited for the body of an oversized message
  before refusing it; it now rejects a frame over 1 MiB from its header
  and closes the port.
- **Fixed**: **Turn off** on the Extension tab removed the `pym.mosaic`
  native-host registration even when another program had replaced it; it
  now removes only Mosaic's own.
- **A new README** and preview: a short landing page with a hero built from
  real offscreen renders of the panel, and the full manual in
  [`docs/guide/`](docs/guide/), one page per feature.
- **Security**: [SECURITY.md](SECURITY.md) describes what Mosaic runs,
  reads and writes, the extension's permissions and the local state, with
  the [2026-10-19 security review](docs/security-review.md).
- **For contributors**: decision records, specs for the IPC and the
  `mosaic` command, the JSON files, `layouts.lua` and the native-messaging
  protocol, development and troubleshooting runbooks, an offscreen panel
  preview (`tests/preview.sh`), contributor and agent guides, and CI that
  runs `npm test`.
- The name is **Mosaic**, with a new icon and wordmarks from the same
  slate-teal mosaic.

## 1.5.2 (2026-10-18)

- **Fixed**: tiles failed to open with "the default browser is not
  Chromium-based" after Omarchy began listing its `omarchy-browser`
  link wrapper as the default browser; Mosaic now finds the browser
  behind it, as Omarchy's own launchers do.

## 1.5.1 (2026-10-17)

- **Fixed**: the panel's tab row was still cut off at the Extension tab;
  the panel's width now counts its padding and border too.
- **The Extension tab's actions are rows with their keys**, like Add tile:
  Open the extensions page (O), Verify (V), Enable (E), and Restart the
  browser (B). Turn off comes last and has no key. Once the extension is
  connected, its notice is a quiet line instead of a box.
- **Saved sessions label their switch** "at login".
- **The key bar shows H/L (tabs) under ?** on every tab, instead of on
  some.

## 1.5.0 (2026-10-15)

- **Recover streams the player gave up on**: a Twitch tile frozen on the
  player's loading spinner wasn't reloaded, since the player had stopped
  its video itself and Mosaic took that for a pause. Now a video that
  played and then ended or was paused, not by hand (a click or a key in
  the tile, or a `mosaic` media command), counts as dropped after 20
  seconds, and so does a video that never starts, such as after a reload
  that hangs. Media keys and playerctl look like the player's own pause,
  so a tile paused that way is reloaded too. `mosaic streams` also says
  why an idle tile is idle.
- **Fullscreen comes back after a reload**: a tile whose video was
  fullscreen inside it goes fullscreen again once the reloaded stream
  plays, by pressing its f (Twitch, YouTube, and Kick's fullscreen key)
  as real input. That briefly focuses the tile, so it waits until the
  tile's workspace is on screen, and focus and the cursor go back where
  they were. This works for recovery and for P.
- **Reload the extension without restarting the browser**: the Extension
  tab's **Open the extensions page** (O) opens the browser's extensions
  page, where Reload on Omarchy Mosaic loads a newer extension and keeps
  your tiles open. Until the browser runs 0.5.2, the button copies the
  page's address for the address bar instead.
- **Fixed**: a tile page re-reported its stream every 2 seconds after the
  extension started or the page loaded, each time as if it had just
  changed.
- **Fixed**: the panel's last tab (Extension) was cut off; the panel now
  widens to fit its tabs.
- These need extension 0.5.5 (`background-10.js`): reload it on the
  extensions page (O on the Extension tab) or restart the browser.

## 1.4.1 (2026-10-15)

- **A taken swap key is reported**: when the swap key can't be bound,
  say because another binding already uses it, a notification says so,
  not only the panel. Clear the **Swap key** setting to bind
  `omarchy-shell pym.mosaic swap` in your own Hyprland config instead; the
  README shows how.

## 1.4.0 (2026-10-15)

- **Save a tile as a web app**: a tile opened from a typed address, such
  as `music.youtube.com`, shows its site as its name. Press I on it (or
  its 󰆓 button) and name it, prefilled from the page title, to install an
  Omarchy web app for the site, with its icon: the tile takes the app's
  name and icon, and the app gets a button in Add tile and a launcher.
  From scripts: `mosaic save-app TILE [NAME]`.

## 1.3.0 (2026-10-15)

- **Saved sessions**: save a session (its 󰆓 button, or W) to keep its
  tiles, their monitor and workspace, the workspace's layout, and each
  tile's volume and mute. The new **Saved** tab opens them again (Enter),
  opening only the tiles that aren't open yet, and each has an **Open at
  login** switch (O). From scripts: `mosaic save`, `restore`, `saved`,
  `forget`, and `login`. They are kept in
  `~/.local/state/mosaic/saved.json`.
- **Recover dropped streams**: when a Twitch or Kick tile's stream drops
  (its video fails with a decode error, the player shows its error, or the
  picture stands still), Mosaic reloads the tile's page. It retries after
  30 seconds and 2 minutes, then marks the tile **stream stalled** after
  three tries in ten minutes. A switch on the Tiles tab (Shift+R) turns it
  off, P reloads a tile by hand, and the **Stream recovery sites** setting
  picks the sites. `mosaic streams` shows each tile's stream and the
  recent recoveries, and `mosaic reload TILE` reloads one. Needs extension
  0.5.1 (`background-6.js`): restart the browser once (B on the Extension
  tab).
- **Fixed**: with a plain web app window open on the same site as a tile,
  Mosaic could take that window's tab for the tile's and keep it, so the
  tile's stream status and volume showed the other window, and swapping
  the tile changed the other window's page instead. A tab showing another
  window's title is no longer paired with a tile.

## 1.2.0 (2026-10-03)

- **Keep fullscreen in tiles**: a new switch on the Tiles tab (Shift+C)
  contains tiles on its own. A tile that loses its containment is
  contained again right away, and a tile made truly fullscreen (Super+F,
  or a video that escaped) stays big only while it has focus: once another
  window takes focus, it goes back into its tile.
- **Tile rows that show what's in them**: each tile has its web app's icon
  (or the site's favicon, or its first letter), its name, and what sets it
  apart from the others: the page's title without unread counts or the
  site's name, or its address's path. A warning, like "fullscreen not
  contained", comes first so it is never cut off.
- **Quieter Tiles tab**: the volume slider shows only on the tile under
  the cursor; the others show their level next to the mute button. The
  monitor and workspace moved to the session's header when all its tiles
  share them.
- **Add tile folds away**: it is one row until A or a click opens it (it
  stays open while there are no tiles), and its web apps are an even grid
  with their number keys, the same grid that swapping a tile shows.
- **A key bar instead of a key list**: the panel's footer shows the main
  keys for what's on screen as key caps, on one line; ? shows the rest.
  The Tiles tab's switches show their keys the same way.
- **The Hidden tab matches**: the same icons as the tile rows, the site
  instead of the whole address, and no leftover notice from another tab.
- **The Layouts and Extension tabs match**: each workspace row shows a
  small picture of its layout at its monitor's shape, New layout is a row
  like Add tile, and the Extension tab says how it stands in a chip
  ("Connected", "Restart needed", "Not set up"). Buttons no longer carry
  their keys in their labels; the key bar shows them.
- **Layouts drawn in the session header**: the layout button is a small
  picture of where the session's tiles go, at the monitor's shape, beside
  the layout's name.

## 1.1.1 (2026-10-02)

- **A nicer swap card** (Super+Shift+S on a tile): the site's logo and
  address up top, an "In place" or "New window" chip, the web apps as a
  grid of tiles with their icons and number keys (the one it already
  shows dimmed), and the keys as key caps.
- **Tiles on the same site stay told apart**: the tab each tile was
  matched to is remembered across shell restarts, and two look-alike tiles
  never matched before are paired as soon as you focus one of them.

## 1.1.0 (2026-10-02)

- **Swaps change the page in place**: with the browser extension
  connected, swapping a tile (S in the panel, Super+Shift+S on the tile,
  `mosaic replace`) now loads the new address in the tile's own window
  instead of opening a new one and closing the old, so nothing flickers,
  moves, or warps the cursor, and the tile keeps its mute and volume.
  Without the extension it opens a new window in the slot, as before. In
  the panel, the picker now opens on the tile's own card, with its address
  ready to edit and the web app it already shows dimmed, instead of a
  notice at the top and the Add tile section turned into "Replace with".
  While the new page loads, the tile shows the Omarchy logo with a
  progress bar, like the boot screen, in your theme's colours.
  Tiles also keep the browser tab they were matched to, so two tiles on
  the same site (say, after swapping one to YouTube) stay told apart.

- **Layouts per workspace, and your own**: layouts now belong to
  workspaces (workspace 8 on Grid, 9 on a layout of yours), set from the
  panel's new **Layouts** tab (a dropdown per workspace) or a session's
  header. Design layouts there with the mouse, like PowerToys FancyZones:
  start from a preset, drag the lines between zones, split a zone beside or
  below, remove one, and pick the main zone that fills first (say 25 / 50
  / 25 with the middle one main). `mosaic layout --workspace
  N LAYOUT`; new IPC `sessionLayout`, `layoutSave`, `layoutDelete`.
  `layouts.json` is version 2; session layouts from version 1 move to
  their workspaces. The tab lists only workspaces with windows or a layout
  of their own, plus the focused one; **Show all workspaces** (W) lists
  the rest.

- **Volume follows the site**: a tile's volume changed with the page's own
  control (YouTube's slider, arrow keys) is now kept and shown on the
  panel's slider, instead of being reset to the level last set in Mosaic
  at the next video. The last change wins, from either side. Needs
  extension 0.4.0 (`background-4.js`, one browser restart: B on the
  Extension tab), which also keeps levels when the browser stops its
  worker.

- **Layouts**: Grid, Stack, Main + small, and 16:9 fit. They are Hyprland
  Lua tiling layouts (`layouts.lua`), so tiles stay tiled and swappable,
  and they follow portrait monitors. The choice is saved in `layouts.json`
  next to `tiles.json` and applied again after a config reload, with each
  tile's fullscreen containment kept. New IPC: `layout`, `layouts`.

- **Audio on the Tiles tab**: "Only the focused tile plays" (F) sits above
  the sessions, next to each tile's own slider and mute button. The setup
  tab is now **Extension**, for enabling and checking the extension only.
- **Per-tile volume**: a slider under each tile the extension found (like
  the shell's audio panel for apps; right-click mutes), − and + on a
  tile, or the mouse wheel over its speaker button. New IPC: `volume`, `media`
  (play, pause, toggle), and `reloadTile`. Extension 0.3.0 also carries
  in-place navigation, reloading, media control, and favicons, and says
  what it can do (`features`), so later panel features need no browser
  restart.
- **Per-tile mute**: a speaker button on each tile row (and M) shows
  whether the tile is playing, silent, or muted, and mutes or unmutes it.
  **Mute every tile but the focused one** follows Hyprland focus. New IPC: `mute TILE on|off|toggle`. Needs extension
  0.2.0; the Extension tab asks for a browser restart while a browser runs an
  older copy of it, which it tells from the worker script's name.
- **Browser extension for audio control**, the groundwork for per-tile
  audio. The panel's new Extension tab sets it up (Enable, restart the browser,
  Verify) and the Tiles tab warns while it's missing. The extension reports
  the browser's app windows through a native messaging host,
  `bin/mosaic-native-host`, and a socket the service listens on
  (`$XDG_RUNTIME_DIR/pym-mosaic.sock`). New IPC: `extension`,
  `extensionEnable`, `extensionVerify`, `extensionDisable`.

## 1.0.0 (2026-09-27)

The first release as the whole of Omarchy Mosaic. The plugin now does
everything the Rust `mosaic` CLI did, without it.

- **Engine in the shell.** A service builds the tile list from Hyprland's
  window tags and `~/.local/state/mosaic/tiles.json`, and the web app list
  from the desktop entries, and it adds, focuses, removes, closes, and
  contains tiles itself. Tiles the CLI opened carry over.
- **Fullscreen containment** as before: a page's video fullscreen fills only
  its tile. A tile keeps its state when it moves between workspaces, where
  Hyprland's own record would go stale.
- **Swap a tile's web app** in the same slot: press S on a tile in the panel,
  or press Super+Shift+S on the tile itself for a card with your web apps
  and its address, ready to edit. The key is a setting.
- **Hidden web apps**: right-click a button to hide it; a tab lists them.
- **Command line**: `omarchy-shell pym.mosaic …`, and `bin/mosaic` keeps the
  CLI's `mosaic` command, arguments, and output (`list` and `webapps` JSON
  are version 1, unchanged).
- **Settings**: Browser (a Chromium-family command instead of the default
  browser), Swap key, and Hidden web apps. The old "mosaic command" setting
  is gone.
- The cursor stays put when a new tile opens.

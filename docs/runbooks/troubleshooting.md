# Troubleshooting

Symptom, likely cause, fix. Read the shell's log first:

```bash
quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i mosaic
```

## The panel says "The Mosaic service is not running"

- **Cause**: the plugin's service is not loaded: the plugin is disabled, or
  its QML failed to load.
- **Fix**: `omarchy plugin enable pym.mosaic`, then
  `omarchy-shell shell rescanPlugins`; if it persists, look for QML errors
  in the log and restart the shell (`omarchy-restart-shell`).

## `mosaic: Cannot reach the Omarchy shell`

- **Cause**: `omarchy-shell` could not call the plugin: the shell is not
  running, or the plugin is disabled.
- **Fix**: as above. `omarchy-shell pym.mosaic version` should answer.

## Tiles don't open: "The default browser (…) is not Chromium-based"

- **Cause**: the default browser is Firefox or another browser without an
  `--app` mode, or the browser couldn't be resolved.
- **Fix**: set a Chromium-family default browser, or the widget's
  **Browser** setting to a command such as `chromium` or `brave`
  ([ADR 11](../adr/0011-chromium-family-browsers-only.md)). Mosaic 1.5.2 and
  later look past Omarchy's `omarchy-browser` link wrapper.

## "No browser app window appeared for …"

- **Cause**: the browser started but no new app window (a class containing
  `__`) appeared within 15 s, for example because the profile opened a
  startup or sign-in page instead.
- **Fix**: open the browser once by hand and finish its first-run pages, or
  point **Browser** at a profile that opens `--app` windows directly.

## A video's fullscreen covers the whole monitor

- **Cause**: the tile is **uncontained** (its row says so, `mosaic list`
  shows `(uncontained)`), for example after Omarchy's Super+Ctrl+F, or it is
  floating.
- **Fix**: press **C** in the panel (or `mosaic contain`), or turn on
  **Keep fullscreen in tiles** (Shift+C). Tile a floating tile again; its
  containment comes back by itself.

## The Extension tab says to restart the browser, or audio buttons are missing

- **Cause**: the extension is set up but the browser hasn't loaded it, or
  the browser runs an older copy (`extensionOutdated`). Brave has kept a
  cached worker script across restarts.
- **Fix**: **Open the extensions page** (O) and press Reload on Omarchy
  Mosaic (turn on Developer mode if there's no Reload button), or restart
  the browser (B). See the
  [browser extension guide](../guide/browser-extension.md).

## Google Chrome never loads the extension

- **Cause**: Chrome ignores `--load-extension` since version 137, and some
  browsers have no flags file for Mosaic to edit.
- **Fix**: load it by hand: extensions page, Developer mode, Load unpacked,
  and pick the extension folder (the Extension tab copies its path).

## Verify says some tiles weren't found

- **Cause**: the extension matches tiles by title and site; two fresh tiles
  with the same title on the same site are ambiguous until one is focused.
- **Fix**: focus each look-alike tile once, then verify (V) again.

## The swap key does nothing, or a notification says it is taken

- **Cause**: another Hyprland bind already uses the key, so Mosaic refused
  to bind it ([ADR 14](../adr/0014-swap-key-as-a-checked-runtime-bind.md)).
- **Fix**: pick another key in the widget's **Swap key** setting, or clear
  it and bind `omarchy-shell pym.mosaic swap` in your own config (see the
  [panel guide](../guide/panel.md)).

## A dropped stream isn't reloaded

- **Cause**: recovery is off, the site isn't in **Stream recovery sites**,
  the extension isn't connected, or the tile stalled after three tries in
  ten minutes.
- **Fix**: `mosaic streams` shows each tile's stream, why an idle tile is
  idle, and the recent recoveries. Turn on **Recover dropped streams**
  (Shift+R), add the site, or press **P** on a stalled tile, which also gives
  its tries back.

## A saved web app doesn't show up

- **Cause**: `~/.local/share/applications` didn't exist when the shell
  started, so the shell can't watch it for new launchers.
- **Fix**: restart the shell once (`omarchy-restart-shell`).

## Layouts look wrong after a Hyprland config reload

- **Cause**: runtime layout rules and registrations are dropped by a
  reload; the service applies them again on `configreloaded`.
- **Fix**: wait a moment, or set the workspace's layout again on the
  Layouts tab. If a layout switch left tiles uncontained, press **C**.

## A code change doesn't take effect (development)

- **Cause**: the shell's file watcher doesn't follow the development
  symlink, and a plugin rescan has been seen running old service code.
- **Fix**: run `scripts/dev-watch` while editing; after service changes,
  `omarchy-restart-shell`, then `pgrep -a quickshell` to check that only one
  shell runs (two shells fight over the bridge socket).

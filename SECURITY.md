# Security

## Reporting a vulnerability

Please report privately through GitHub's
[security advisories](https://github.com/mateuspim/omarchy-mosaic/security/advisories/new)
rather than a public issue. Include the version (`manifest.json`, or the
version line at the bottom of the panel), steps to reproduce and impact. You
can expect a reply within a week.

## Supported versions

Only the latest release on `master` receives fixes.

## Summary

Mosaic runs as your user in the Omarchy shell. It does not use `sudo` or install
packages. Tiles load the sites you choose in your
Chromium-family browser; those sites make their usual network requests.

- **Browser access:** the optional extension requests `tabs`, `scripting`,
  `nativeMessaging`, `storage`, and access to all URLs because Mosaic accepts
  arbitrary web apps and watches their video and volume. It reports app-window
  tab URLs, titles, favicons, audio and stream state to the local shell; it
  does not send them to a Mosaic server. The native host accepts only the
  extension ID in `extension/manifest.json`.
- **Local changes:** enabling the extension registers `pym.mosaic` as a native
  messaging host in browser profiles found under `~/.config` and adds its
  folder to existing browser flags files. Turn off removes Mosaic's own host
  registration and its flags entry. The plugin also stores tile URLs in
  `~/.local/state/mosaic/tiles.json`, saved sessions and their URLs in
  `saved.json`, and layouts in `layouts.json` (or under `$XDG_STATE_HOME`).
  Do not save a URL containing a private token if you do not want that token
  stored in these files. The bridge socket and tab mapping live under
  `$XDG_RUNTIME_DIR`.
- **Commands:** Mosaic launches the selected Chromium-family browser through
  `uwsm-app`, runs `hyprctl` for tile and layout actions, and uses
  `omarchy-webapp-install` only when you save a tile as a web app. Processes
  receive argument lists; user input is not passed through a shell. The
  web-app installer fetches a site's icon when you request a save.

## Privilege model

Omarchy plugins run unsandboxed inside `omarchy-shell` as your user. This is
what Mosaic does with that access:

- **Runs** (always as argument lists, never through a shell):
  - `hyprctl` to read clients, monitors, workspaces, workspace rules,
    binds and the cursor position; to dispatch the tile actions (tag, move,
    float off, `set_prop opaque`, fullscreen state, swap, focus, close,
    cursor move); and to `eval` Lua that loads `layouts.lua`, sets workspace
    layouts, binds or unbinds the swap key, and presses a recovered tile's
    `f`. Every value put into that Lua is checked first: window addresses
    must be `0x` plus hex, session names `^[a-z0-9_-]{1,32}$`, workspaces
    integers, keys modifier names plus one plain key name
    ([ADR 4](docs/adr/0004-argv-launches-and-validated-lua.md)).
  - `uwsm-app -- BROWSER --app=URL` to open a tile, and
    `uwsm-app -- BROWSER` after **Restart the browser**.
  - `xdg-settings` and `xdg-mime` to find the default browser.
  - `kill -TERM` on the tiles' browser processes and
    `timeout 15 tail --pid …` to wait for them, only for **Restart the
    browser** (B on the Extension tab, or IPC `restartBrowser`).
  - `omarchy-webapp-install NAME URL ""` and `test -e` on the launcher path,
    only when you save a tile as a web app (I, or `mosaic save-app`).
  - `bin/mosaic-native-host status | setup DIR | remove DIR` from the
    Extension tab, `notify-send` for errors, and `wl-copy` for the copy
    buttons.
- **Reads**: Hyprland's state, desktop entries (Quickshell's
  `DesktopEntries`), its own state files below, the extension's
  `manifest.json`, and the browser flags files and native-host manifests
  under `~/.config` that setup manages.
- **Writes**: `$XDG_STATE_HOME/mosaic/` (default `~/.local/state/mosaic/`):
  `tiles.json`, `layouts.json`, `saved.json`, `plugin-update.log` (written
  only by the optional git hooks); in `$XDG_RUNTIME_DIR`: the bridge socket
  `pym-mosaic.sock`, `pym-mosaic-tabs.json` and the login marker
  `pym-mosaic-login`. Enabling the extension writes
  `NativeMessagingHosts/pym.mosaic.json` into each Chromium-family profile
  folder that exists and adds the extension to existing
  `*-flags.conf` files; **Turn off** removes both, and only removes a host
  manifest that is still Mosaic's. Saving a tile as a web app writes a
  launcher through Omarchy's installer. Widget settings are saved by the
  shell in its own `shell.json`.
- **Root**: never. No `sudo`, no packages installed.
- **Network**: Mosaic itself makes no requests. The tiles load the sites you
  open, and the web-app installer fetches a site's icon when you ask for a
  save.
- **Browser**: the extension (Manifest V3, fixed ID
  `ibcnbknhphdnlpfglnhelicnpnnmepbo`) asks for `tabs`, `scripting`,
  `nativeMessaging`, `storage`, `alarms` and `<all_urls>`. It reports app and
  popup windows only, never normal browsing windows, and only acts on tabs in
  those windows; `navigate` accepts only http and https addresses.
- **Local bridge**: the native host caps frames at 1 MiB both ways, rejects
  an oversized header before reading its body, and its manifest allows only
  the extension's ID. The socket lives in the owner-only
  `$XDG_RUNTIME_DIR`. Any process running as you can talk to that socket,
  as it can to the shell's IPC; that is the trust boundary. Without
  `$XDG_RUNTIME_DIR` the service falls back to `/tmp/pym-mosaic.sock`, which
  lacks that boundary (an open finding in the review).
- **Secrets**: none are stored on purpose. Tile URLs are stored as given,
  query strings included, in `tiles.json` and `saved.json`.

It never changes configuration outside its own files on load: the browser
config changes only through **Enable** and **Turn off**, the swap key is a
runtime bind (nothing is written to your Hyprland config), and layouts are
runtime workspace rules.

## Reviews

- [Security review, 2026-10-19](docs/security-review.md): a source review of
  the native host, extension, wrapper, service and install steps, with its
  findings and their dispositions.

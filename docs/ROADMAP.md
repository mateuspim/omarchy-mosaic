# Roadmap

## Done

- Proved fullscreen containment with Chromium-family `--app` windows and
  Hyprland fullscreen state `0/2` (see `docs/ARCHITECTURE.md`).
- Rust CLI `mosaic` with live sessions: `add`, `list`, `remove`, `focus`,
  `close`, `contain`, `webapps`, `monitors`.
- This bar widget: lists sessions, adds web apps or URLs, focuses and removes
  tiles, closes sessions, and re-contains, all through the CLI.
- The plugin's own engine (`MosaicService.qml`) for the tile list, the web
  apps, and adding, focusing, removing, closing, and containing tiles; the
  plugin no longer needs the CLI.
- Hiding web apps from the panel, and a Hidden web apps tab to bring them
  back.

## 1. Parity: the plugin does everything the CLI did (done 2026-09-27)

The read-only engine, web apps, simple actions, `add`, the IPC, and the
`mosaic` wrapper, each checked against the CLI.
Beyond the CLI: **swapping a tile's web app** in the same slot, from the
panel or from a card over the tile opened by a changeable key.

## 2. Retire the CLI and publish

- ~~Remove `~/.local/bin/mosaic` and the Rust repository's hooks. Rename that
  repository to `omarchy-mosaic-cli`, point its README here, and archive it.~~
  Done 2026-09-27; `mosaic` is now this repository's `bin/mosaic`.
- ~~Rename this repository to `omarchy-mosaic` (the plugin id stays
  `pym.mosaic`), and update the development symlink.~~ Done.
- ~~Publish on GitHub with an `omarchy plugin add` install line, a
  `CHANGELOG.md`, and a version bump.~~ Done: 1.0.0 at
  `https://github.com/mateuspim/omarchy-mosaic`.

## 3. Beyond parity

The user wants a much broader product once parity is reached. Candidates,
roughly in order of value; confirm priorities with the user before starting:

- **Real players.** Check YouTube, Twitch, and Kick fullscreen buttons, `f`,
  double-click, and theater modes; then 4–6 simultaneous streams for CPU/GPU
  load. Record results per site.
- **Layouts.** A dedicated workspace per session, and layouts the user picks:
  balanced grid, vertical stack, one large plus several small, and a 16:9
  fit. Prefer Hyprland layout settings or split ratios over floating
  geometry, which was rejected.
- **Audio.** Mute every tile but the focused one, per-tile volume, and an
  audio indicator in the panel. PipeWire can't do it: every tile belongs to
  one browser process, and Chromium plays every tab through one audio
  service process, so its streams are identical ("Chromium", "Playback",
  the audio service's PID; checked 2026-09-28). The route is a browser
  extension instead (see "The browser extension" in `docs/ARCHITECTURE.md`).
  **Done:** the extension, the native host and bridge, and the setup
  (Enable, restart, Verify) with a warning in the panel. **Next:** per-tile
  mute (`chrome.tabs.update({ muted })`), mute all but the focused tile,
  the audible indicator from `tab.audible`, then per-tile volume (a content
  script setting media element volume, since the tab API only mutes).
- **Saved sessions.** Name, monitor, layout, and apps; restore with one key
  or at login. Keep personal URLs out of the repository.
- **Monitor awareness.** Reflow on monitor changes, portrait-friendly
  layouts, and moving a whole session between monitors.
- **Richer panel.** Per-tile loading and error status, titles and favicons,
  reordering, a session switcher, and stream-specific details such as a live
  indicator.
- **Scripting.** Every panel action over IPC, suitable for Hyprland
  keybindings.

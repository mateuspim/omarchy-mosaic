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

## 1. Parity: the plugin does everything the CLI did

Follow `docs/HANDOFF.md` ("Suggested order" and "Parity checklist"): the
read-only engine, web apps, simple actions, `add`, then IPC and the `mosaic`
wrapper. The widget works before and after every step.

Right after `add` is ported: **swap a tile's web app** from the panel, for
example turning a YouTube tile into Kick in the same slot (requested by the
user; see "Next feature: swap a tile" in `docs/HANDOFF.md`).

## 2. Retire the CLI and publish

- Remove `~/.local/bin/mosaic` and the Rust repository's hooks. Rename that
  repository to `omarchy-mosaic-cli`, point its README here, and archive it.
- Rename this repository to `omarchy-mosaic` (the plugin id stays
  `pym.mosaic`), and update the development symlink.
- Publish on GitHub with an `omarchy plugin add` install line, a
  `CHANGELOG.md`, and a version bump.

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
  audio indicator in the panel (PipeWire, through the shell's audio service).
- **Saved sessions.** Name, monitor, layout, and apps; restore with one key
  or at login. Keep personal URLs out of the repository.
- **Monitor awareness.** Reflow on monitor changes, portrait-friendly
  layouts, and moving a whole session between monitors.
- **Richer panel.** Per-tile loading and error status, titles and favicons,
  reordering, a session switcher, and stream-specific details such as a live
  indicator.
- **Scripting.** Every panel action over IPC, suitable for Hyprland
  keybindings.

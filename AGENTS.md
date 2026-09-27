# Agent instructions

`pym.mosaic` is the Omarchy shell bar widget for Omarchy Mosaic: web apps
such as Twitch, Kick, and YouTube tiled as a monitor-aware mosaic on
Hyprland, where video fullscreen stays inside its tile.

**Start with `docs/HANDOFF.md`.** This repository is taking over the whole
project from the Rust CLI in `~/Projects/omarchy-mosaic`. The handoff has the
plan, the facts learned the hard way, and the decisions still open.

## Working conventions

- Use `master` as the default branch.
- Keep the panel keyboard-first and visually cohesive with Omarchy. Build it
  from the shell's `qs.Ui` components and `Style`/`Color`, the way the
  built-in panels in `/usr/share/omarchy/shell/plugins/panels/` do.
- Keep pure logic in `Model.js` and test it with `node tests/model.test.js`.
  Validate the manifest with `omarchy plugin validate .`.
- Detect monitors at runtime. Don't check in personal stream URLs or
  machine-specific settings.
- The live install is a symlink to this checkout, so every saved file runs in
  the user's shell. Test risky QML in a throwaway `quickshell -n` instance
  first (see the handoff). Never drive the user's everyday browser profile.

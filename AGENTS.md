# Agent instructions

`pym.mosaic` is Omarchy Mosaic: web apps such as Twitch, Kick, and YouTube
tiled as a monitor-aware mosaic on Hyprland, where video fullscreen stays
inside its tile. It is an Omarchy shell plugin, a service plus a bar widget,
and it took over the whole project from the Rust CLI, now retired in
`~/Projects/omarchy-mosaic-cli`; `mosaic` on the PATH is this repository's
`bin/mosaic` wrapper.

**Start with `docs/HANDOFF.md`** for the plan, the parity checklist, and how
to verify. Read `docs/PROJECT.md`, `docs/ARCHITECTURE.md`, and
`docs/ROADMAP.md` before making architectural choices.

## Decisions (settled with the user, 2026-09-27)

- This repository is the official project, `omarchy-mosaic`, published at
  `https://github.com/mateuspim/omarchy-mosaic`. The Rust repository is
  `omarchy-mosaic-cli`, archived now that the plugin has parity.
- The plugin id stays `pym.mosaic`.
- The command line is `omarchy-shell pym.mosaic …`, plus a small `bin/mosaic`
  wrapper that keeps the `mosaic` command name.
- The bar panel replaces the planned terminal UI for good.
- Parity with the CLI comes first. After that the scope is meant to grow a
  lot (see `docs/ROADMAP.md`, "Beyond parity").

## Working conventions

- Use `master` as the default branch.
- The fullscreen-containment behavior in `docs/ARCHITECTURE.md` is the core
  requirement. Re-run the containment check after any change to how tiles
  are launched or tiled.
- Keep the panel keyboard-first and visually cohesive with Omarchy. Build it
  from the shell's `qs.Ui` components and `Style`/`Color`, the way the
  built-in panels in `/usr/share/omarchy/shell/plugins/panels/` do.
- Keep pure logic in `Model.js` and test it with `node tests/model.test.js`.
  Validate the manifest with `omarchy plugin validate .`.
- Hyprland is the source of truth: tags decide membership. Keep
  `~/.local/state/mosaic/tiles.json` and the v1 `list`/`webapps` JSON
  compatible.
- Anything interpolated into a Hyprland Lua dispatch must be validated
  (`0x` + hex addresses, `^[a-z0-9_-]{1,32}$` session names). Launch
  processes with argv lists, never through a shell.
- Never block the shell: no synchronous waits, and time out every wait.
- Detect monitors at runtime. Don't check in personal stream URLs or
  machine-specific settings.
- The live install is a symlink to this checkout, so every saved file runs in
  the user's shell. Test risky QML in a throwaway `quickshell -n` instance
  first (see the handoff). Never drive the user's everyday browser profile.
- Update the docs when a decision changes the supported browsers, the
  fullscreen strategy, the store or JSON formats, or the platform scope.

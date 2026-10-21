# Mosaic agent instructions

Mosaic tiles web apps such as Twitch, Kick and YouTube as a monitor-aware
mosaic on Hyprland, where video fullscreen stays inside its tile. It is an
Omarchy shell plugin (Quickshell/QML), a service plus a bar widget, with a
Python native host and a browser extension for audio. Plugin id
`pym.mosaic`; public at https://github.com/mateuspim/omarchy-mosaic. It
took over the whole project from the Rust CLI, now retired as
`omarchy-mosaic-cli`; `mosaic` on the PATH is this repository's
`bin/mosaic` wrapper.

The README is the landing page; the user manual is `docs/guide/` (one page
per feature area), so read the guide page before changing a feature. Read
`docs/project.md`, `docs/architecture.md` and `docs/roadmap.md` before making
architectural choices: `docs/architecture.md` says how the parts fit and
holds the evidence, `docs/adr/` why, `docs/specs/` what the contracts are
(IPC and `mosaic`, file formats, `layouts.lua`, native messaging,
settings). `docs/README.md` indexes the rest; update the spec a change
touches.

If the main checkout has a local `docs/HANDOFF.md`, read it first for where
to pick up, the hard-won facts and how to verify. It is a working note kept
out of git (`.gitignore`): update it as work goes, but never commit it.

## Decisions (settled with the owner, 2026-09-27 and 2026-10-21)

- This repository is the official project, `omarchy-mosaic`. The Rust
  repository is `omarchy-mosaic-cli`, archived now that the plugin has
  parity (ADR 3).
- The name is **Mosaic** (not "Omarchy Mosaic" or "Mosaic for Omarchy"),
  the plugin id stays `pym.mosaic`, and there is no rename or migration. The
  browser extension keeps the name "Omarchy Mosaic", which the native host
  matches.
- The command line is `omarchy-shell pym.mosaic …`, plus the small
  `bin/mosaic` wrapper that keeps the `mosaic` command name.
- The bar panel replaces the planned terminal UI for good.
- Parity with the CLI came first. Beyond it the scope is meant to grow a lot
  (`docs/roadmap.md`, "Beyond parity"); confirm priorities with the owner
  before starting a roadmap item.

## Project

- Layout: QML entry points at the root, `MosaicService.qml` (the
  `service`, the one engine and IPC handler) and `Panel.qml` (the
  `bar-widget`, UI only), with `SwapCard.qml`, `SwapVeil.qml` and
  `SwapVeilArt.qml` beside them. Pure logic in `Model.js`; Hyprland layouts
  in `layouts.lua`; the `mosaic` wrapper and the native host in `bin/`; the
  browser extension in `extension/`; containment probes in `examples/`;
  tests and the offscreen harness in `tests/`; git hooks in `.githooks/`;
  brand sources in `docs/brand/`. Don't add QML subfolders, and keep new
  components inline in the file that uses them: a new sibling QML file was
  not found as a type by the panel (ADR 7).
- Naming: plugin id and IPC target `pym.mosaic`; tags `mosaic` and
  `mosaic-<session>`; state in `$XDG_STATE_HOME/mosaic/`; runtime files
  `$XDG_RUNTIME_DIR/pym-mosaic*`; layer namespaces `pym-mosaic-*`; Hyprland
  layouts `mosaic-*`; env vars `MOSAIC_*`; journal prefix `Mosaic:`.
- The widget reaches the service through `bar.shell.serviceFor("pym.mosaic")`,
  never a `qmldir` singleton; there must never be two engines, IPC handlers
  or launch sequences, including across plugin reloads (ADR 7).
- The fullscreen-containment behaviour in `docs/architecture.md` is the core
  requirement (ADR 1). Re-run the containment check
  (`docs/runbooks/development.md#containment-check`) after any change to how
  tiles are launched or tiled. Floating geometry stays rejected; ask the
  owner before bringing it back.
- Hyprland is the source of truth: tags decide membership (ADR 2). Keep
  `~/.local/state/mosaic/tiles.json` and the v1 `list`/`webapps` JSON
  compatible (ADR 6, `docs/specs/files.md`).
- Anything interpolated into a Hyprland Lua dispatch must be validated
  (`0x` + hex addresses, `^[a-z0-9_-]{1,32}$` session names, integer
  workspaces, checked key specs). Launch processes with argv lists, never
  through a shell (ADR 4).
- Never block the shell: no synchronous waits, and time out every wait
  (ADR 5).
- Detect monitors at runtime. Don't check in personal stream URLs or
  machine-specific settings.
- Keep the panel keyboard-first and visually cohesive with Omarchy. Build it
  from the shell's `qs.Ui` components and `Style`/`Color`, the way the
  built-in panels in `/usr/share/omarchy/shell/plugins/panels/` do.
  `Panel.qml` uses the bare `Color` from `qs.Commons` and renders correctly
  on Qt 6.12 (checked offscreen); the sibling plugins write
  `import qs.Commons as Commons` and `Commons.Color.x`, which new code should
  prefer.
- Every extension change renames its worker script (`background-N.js`),
  with `manifest.json` and `SCRIPT` updated together, and bundles everything
  foreseeable, since each change costs the user a reload or their tiles
  (ADR 10).
- Treat `/usr/share/omarchy/` as read-only reference; never edit packaged
  files. Validate the repository root with `omarchy plugin validate .`
  after any change to `manifest.json` or the entry points.

## Code style

- Match the surrounding file: 2-space QML and JS without semicolons, typed
  QML properties where the shape is known; Python standard library only;
  bash with `set -uo pipefail`.
- Functions small and single-purpose. `Panel.qml`, `MosaicService.qml` and
  `Model.js` are already large; split by responsibility rather than growing
  them further, within the no-new-QML-file limit above.
- Names specific and greppable. Early returns over nested ifs. No
  duplication: pure logic goes in `Model.js` so Node can test it; the
  service and panel call it.
- Error messages say what failed with the offending value, in the plain
  sentence style the panel and `mosaic` already use.

## Comments

- Keep existing comments; they carry intent and provenance (Hyprland and
  Quickshell behaviour, dates things were checked).
- Write WHY, not WHAT. Name the upstream constraint or bug a line exists for.

## Tests

- `npm test` runs `node tests/model.test.js`, `lua tests/layouts_test.lua`
  and `python3 tests/native_host_test.py`; CI runs the same.
- Every new pure function gets a test; bug fixes get a regression test.
  Tests never touch the live Hyprland, browser profiles or the user's state.
- Visual checks offscreen only (ADR 17):
  `MOSAIC_PREVIEW_DIR=<abs dir> bash tests/preview.sh` renders the panel
  with the fake service in `tests/offscreen/`.
- The live install is a symlink to the main checkout, so every saved file
  there runs in the user's shell. Test risky QML and every engine change in
  a throwaway `quickshell -n` instance first, with a scratch
  `XDG_STATE_HOME`, `MOSAIC_BRIDGE_SOCKET` and `swapKey: ""`
  (`docs/runbooks/development.md`). Never run an action that plans against
  live clients (close, contain, remove, restart the browser) in a harness
  unless no live tile or window can match.
- Never drive the user's everyday browser profile; use a throwaway-profile
  wrapper (`examples/cdp-eval.mjs`). Never screenshot (`grim`) or inject
  input on the user's monitors.
- Live shell log (read-only):
  `quickshell log -p /usr/share/omarchy/shell -t 200 | grep -i mosaic`.
  Ask before restarting the user's shell or changing their Hyprland config.

## Dependencies

- Runtime: Omarchy's `omarchy-shell` (`qs.Ui`, `qs.Commons`), Quickshell's
  Hyprland, Io and Wayland modules, Hyprland 0.56 with its Lua config,
  `uwsm-app`, `xdg-settings`, a Chromium-family browser, and Python 3 for the
  native host. Optional: `omarchy-webapp-install`, `notify-send`, `wl-copy`,
  `inotifywait` (for `scripts/dev-watch`).
- Tests: Node 22+, any `lua` (5.1/LuaJIT, 5.4 and 5.5 pass), Python 3. No
  npm runtime dependencies; don't add any.

## Public-repo hygiene

- No `/home/...` paths, personal stream URLs, real device names, serials or
  LAN addresses in tracked files. Examples use site roots, `DP-4`/`DP-5` and
  made-up titles.
- The privilege model lives in `SECURITY.md`; update it when Mosaic runs,
  reads or writes something new.
- Never modify user config on load. The browser config changes only through
  the Extension tab's Enable and Turn off; the swap key is a runtime bind;
  layouts are runtime workspace rules.
- `docs/HANDOFF.md` is local-only and stays gitignored; never copy it into
  tracked files.

## Commits and releases

- Branch `master`. Commit subjects are plain imperative sentences with a
  body that says why. The owner reviews features live before they are
  committed. Ask the owner before pushing commits or tags, and before
  publishing a GitHub release.
- Update the docs when a decision changes the supported browsers, the
  fullscreen strategy, the store or JSON formats, or the platform scope.
- Release: bump `version` in `manifest.json` and `package.json`, turn
  **Unreleased** in `CHANGELOG.md` into `## X.Y.Z (YYYY-MM-DD)`, check the
  README and guide cover the change, refresh the preview captures, run
  `npm test` and `omarchy plugin validate .`, commit `Release X.Y.Z`, and
  add an annotated tag `vX.Y.Z` ("Mosaic X.Y.Z"). The steps are in
  `docs/runbooks/development.md#release`.

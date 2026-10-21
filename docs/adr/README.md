# Architecture Decision Records

Each record describes one durable decision in Mosaic's design: the context
that led to it, what was decided, and what follows from it. They use Michael
Nygard's format (Context, Decision, Consequences) and are numbered in the
order they were recorded. For how the parts fit together today, see the
[architecture notes](../architecture.md).

All records were documented from the code on 2026-10-21. Their dates and
commit ids are those of the commits that introduced the behaviour, taken from
the git history; the reasoning comes from the code, the architecture notes
and the decisions recorded with the owner at the time, not from new
interviews. Record 17 describes work on the branch that wrote these records.

| # | Decision | Date | Status |
| --- | --- | --- | --- |
| [1](0001-contain-fullscreen-with-hyprland-state.md) | Contain fullscreen with Hyprland's `0/2` fullscreen state on tiled app windows | 2026-09-27 | Accepted |
| [2](0002-hyprland-tags-are-the-source-of-truth.md) | Hyprland tags decide which windows are tiles | 2026-09-27 | Accepted |
| [3](0003-plugin-replaces-the-rust-cli.md) | The shell plugin is the whole product; the Rust CLI is retired | 2026-09-27 | Accepted |
| [4](0004-argv-launches-and-validated-lua.md) | Launch with argument lists and validate everything put into Lua | 2026-09-27 | Accepted |
| [5](0005-never-block-the-shell.md) | Never block the shell; bound every wait | 2026-09-27 | Accepted |
| [6](0006-keep-tiles-json-and-v1-json-compatible.md) | Keep `tiles.json` and the version 1 list and web-app JSON compatible | 2026-09-27 | Accepted |
| [7](0007-one-engine-in-a-host-created-service.md) | One engine, in a host-created service; the panel is UI only | 2026-09-27 | Accepted |
| [8](0008-per-tile-audio-through-a-browser-extension.md) | Control per-tile audio through a browser extension and a native host | 2026-09-28 | Accepted |
| [9](0009-install-the-extension-through-flags-files.md) | Load the extension from existing browser flags files | 2026-09-28 | Accepted |
| [10](0010-rename-the-extension-worker-on-every-change.md) | Rename the extension's worker script on every change | 2026-09-28 | Accepted |
| [11](0011-chromium-family-browsers-only.md) | Support only Chromium-family browsers, found the way Omarchy finds them | 2026-09-27 | Accepted |
| [12](0012-layouts-as-hyprland-lua-tiling-layouts.md) | Lay out workspaces with Hyprland Lua tiling layouts | 2026-09-29 | Accepted |
| [13](0013-reapply-fullscreen-state-after-moves-and-layout-switches.md) | Re-apply each tile's fullscreen state after moves and layout switches | 2026-09-27 | Accepted |
| [14](0014-swap-key-as-a-checked-runtime-bind.md) | Bind the swap key at runtime, and refuse a taken key | 2026-09-27 | Accepted |
| [15](0015-swap-in-place-through-the-extension.md) | Swap a tile in place through the extension when it can | 2026-10-02 | Accepted |
| [16](0016-recover-dropped-streams-with-backoff.md) | Detect dropped streams in the page and reload them with backoff | 2026-10-15 | Accepted |
| [17](0017-offscreen-preview-harness.md) | Check the panel and render the hero offscreen with a fake service | 2026-10-21 | Accepted |

## Rules

- Add a record for a durable choice: a backend, a boundary, a safety rule,
  or something Mosaic deliberately refuses to do.
- Never rewrite an accepted record. To change a decision, add a new record,
  set the old one's status to "Superseded by N" with a link to the new
  record, and link back from the new one.
- Write "(unverified)" for anything you cannot confirm from the code or the
  history.

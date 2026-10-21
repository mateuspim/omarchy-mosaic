# 6. Keep `tiles.json` and the version 1 list and web-app JSON compatible

- Status: Accepted
- Date: 2026-09-27 (introduced in `904f875`, `22df2b8`; documented from the code on 2026-10-21)

## Context

Tiles opened by the Rust CLI had to carry over to the plugin, and scripts
read `mosaic list --json` and `mosaic webapps --json`.

## Decision

`$XDG_STATE_HOME/mosaic/tiles.json` keeps the CLI's file and format,
written atomically. `list` and `webapps` produce the version 1 JSON; a new
field may be added without a bump, and `version` changes only on an
incompatible change. The formats are specified in
[specs/files.md](../specs/files.md).

## Consequences

Old tiles and scripts keep working. Format changes need a version bump,
an update to the spec, and care for readers that only know version 1.

# 3. The shell plugin is the whole product; the Rust CLI is retired

- Status: Accepted
- Date: 2026-09-27 (introduced in `55819bb`, `f683318`; documented from the code on 2026-10-21)

## Context

Mosaic started as a Rust CLI, `mosaic`, with a bar widget that shelled
out to it and a planned terminal UI. Everything the CLI did has a
Quickshell equivalent inside `omarchy-shell` (Hyprland toplevels and events,
`DesktopEntries`, `FileView`, `IpcHandler`), and two programs meant two
installs and two sources of behaviour. Settled with the owner on
2026-09-27.

## Decision

The plugin (`pym.mosaic`, repository `omarchy-mosaic`) does all the work
itself and needs no separate binary. The bar panel replaces the terminal UI
for good. The command line is `omarchy-shell pym.mosaic <function>`, plus
`bin/mosaic`, a bash wrapper that keeps the old command name, arguments,
messages and exit codes. The Rust repository was renamed
`omarchy-mosaic-cli` and left archived.

## Consequences

Users install one thing with `omarchy plugin add`. Scripts that called
`mosaic` keep working once the wrapper is on the PATH. Actions now depend
on the shell running; the wrapper says so when it can't reach it. The
compatibility promise is recorded in
[ADR 6](0006-keep-tiles-json-and-v1-json-compatible.md).

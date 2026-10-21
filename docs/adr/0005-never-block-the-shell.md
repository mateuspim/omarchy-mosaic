# 5. Never block the shell; bound every wait

- Status: Accepted
- Date: 2026-09-27 (introduced in `55819bb`, `bdf85ca`; documented from the code on 2026-10-21)

## Context

The plugin runs inside the user's desktop shell; a synchronous wait
freezes the bar, and a crash takes it down. Adding a tile involves a browser
start and waiting for its window, which can take seconds or never happen.
`omarchy-shell` also gives up on an IPC call after about 2 s.

## Decision

All external work is asynchronous: one action at a time runs through a
phase machine of `Process` steps, each with its own timeout (5 s by
default, 15 s for a new window, 45 s for the web-app installer); a new
window is detected from Hyprland's `openwindow` event with a `Timer`, never
by polling in a loop. A second action while one runs is refused ("Still
busy: …"). IPC actions answer `started N` at once, and `result N` reports
`running`, `done` or `error`; the wrapper polls it.

## Consequences

The bar stays responsive and every failure ends with a message instead of
a hang. Callers of the IPC must poll for results. Quickshell never reports
`exited` for a command that can't start, so steps also track `started`.

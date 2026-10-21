# 4. Launch with argument lists and validate everything put into Lua

- Status: Accepted
- Date: 2026-09-27 (introduced in `3157f1e`, `55819bb`; documented from the code on 2026-10-21)

## Context

Mosaic opens arbitrary URLs and web app names the user types, and drives
Hyprland through Lua expressions (`hyprctl dispatch`, `hyprctl eval`).
String interpolation into a shell command or a Lua chunk would let a URL, a
session name or a key spec run code.

## Decision

Every process starts from an argv list (`Quickshell.execDetached`,
`Process.command`), never through a shell. Every Lua expression is built in
`Model.js` from checked values: window addresses must be `0x` plus hex,
session names match `^[a-z0-9_-]{1,32}$`, workspaces are integers, swap keys
pass `Model.parseKeySpec` (modifier names plus one plain key name or
`code:N`), and custom layout names are slugs. Targets are resolved and
validated before anything runs, so a typo opens or closes nothing.
`bin/mosaic` repeats the session-name check and forwards arguments quoted.

## Consequences

URLs can contain anything without risk to the shell or Hyprland. Adding
a new dispatch means adding its validation and a test in
`tests/model.test.js`. The [security review](../security-review.md) checked
these boundaries.

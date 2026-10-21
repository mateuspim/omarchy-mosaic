# 13. Re-apply each tile's fullscreen state after moves and layout switches

- Status: Accepted
- Date: 2026-09-27 (introduced in `3b2c04b`; documented from the code on 2026-10-21)

## Context

Moving a window to another workspace leaves Hyprland's
`fullscreenClient` stale in either direction without telling the browser,
and switching a workspace's layout resets it from 2 to 0. The panel's
labels and later contain actions would then be wrong.

## Decision

On every `movewindowv2` for a tile, the service re-applies the state the
tile had before the move, from its own list (`Model.restoreAfterMove`):
`0/2` for contained, `0/0` for uncontained; floating and truly fullscreen
tiles are left alone. Every layout switch is followed by re-applying each
tile's state read before the switch, and after a config reload from states
saved at `configreloaded`.

## Consequences

Contained tiles stay contained across moves and layout changes. A tile
released with Super+Ctrl+F and moved before any refresh is contained again
(known limit; that shortcut emits no event).

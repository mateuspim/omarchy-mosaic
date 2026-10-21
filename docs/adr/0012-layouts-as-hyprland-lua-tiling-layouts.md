# 12. Lay out workspaces with Hyprland Lua tiling layouts

- Status: Accepted
- Date: 2026-09-29 (introduced in `61c696b`, `c8ffd6e`; documented from the code on 2026-10-21)

## Context

Users wanted grid, stack, main + small and 16:9 layouts, then their own.
Floating geometry was already rejected
([ADR 1](0001-contain-fullscreen-with-hyprland-state.md)). Hyprland 0.56
registers Lua tiling layouts at runtime.

## Decision

`layouts.lua` registers `mosaic-grid`, `mosaic-stack`, `mosaic-main`,
`mosaic-fit` and one `mosaic-c-<slug>` per custom zone layout, once per Lua
state, with the code kept in the replaceable global `MosaicLayouts`. A
layout belongs to a workspace (the owner's choice, 2026-09-29) and is set
with `hl.workspace_rule({ workspace = "N", layout = "lua:…" })`. Choices
live in `layouts.json` and are applied again at start and on
`configreloaded`, since runtime rules don't survive a reload. Custom layouts
are split trees validated by `Model.normalizeCustom`.

## Consequences

Tiles stay real tiled windows: gaps and swaps work. A layout switch
resets containment, handled by
[ADR 13](0013-reapply-fullscreen-state-after-moves-and-layout-switches.md).
Hyprland reports every Lua layout under one name (0.56.2), so the saved
choice is what the panel shows. A deleted layout's name stays registered
until a reload.

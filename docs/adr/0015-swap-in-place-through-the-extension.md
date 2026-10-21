# 15. Swap a tile in place through the extension when it can

- Status: Accepted
- Date: 2026-10-02 (introduced in `ee7d624`; documented from the code on 2026-10-21)

## Context

Swapping by opening a new window and closing the old one moves focus,
warps the cursor and loses the tile's mute and volume.

## Decision

`replace` sends `navigate { url }` (http and https only) when the
extension has found the tile and lists `navigate`, and rewrites only the
tile's URL in `tiles.json`. A click-through veil (`SwapVeil.qml`) covers the
tile until the page settles, 0.9 s at least and 6 s at most. Without the
extension, a new window opens and takes the old tile's session, workspace,
slot and list position.

## Consequences

Swaps keep the window, slot, containment and audio. The window keeps the
Hyprland class of its first URL, which nothing in Mosaic reads. Tile-to-tab
matching (`Model.matchTiles`) has to be right, or the wrong window
navigates; it keeps pairings and refuses tabs that belong to non-tile
windows.

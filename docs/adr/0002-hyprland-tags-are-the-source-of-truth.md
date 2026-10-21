# 2. Hyprland tags decide which windows are tiles

- Status: Accepted
- Date: 2026-09-27 (introduced in `904f875`; documented from the code on 2026-10-21)

## Context

Mosaic tiles are ordinary windows that the user can also move, close or
swap with Hyprland bindings, and that the older Rust CLI also managed. A
separate session database would drift from what is really on screen.

## Decision

Every tile carries two static Hyprland tags, `mosaic` and
`mosaic-<session>`. Membership comes only from those tags; `tiles.json`
adds each tile's URL and order and is ignored where it disagrees. The
service rebuilds its list from `Hyprland.toplevels` on window events and
refreshes after anything that tags a window, since a tag change emits no
event. Every action plans against a fresh `hyprctl -j clients`, not the
cached list.

## Consequences

The bar, the `mosaic` command and plain Hyprland bindings always agree,
and a window closed outside Mosaic just disappears from the list. Tiles
without a session tag fall into `default`. Session names are limited to
`^[a-z0-9_-]{1,32}$` because they end up in tags and Lua
([ADR 4](0004-argv-launches-and-validated-lua.md)).

# 14. Bind the swap key at runtime, and refuse a taken key

- Status: Accepted
- Date: 2026-09-27 (introduced in `6254443`, `ed77393`; documented from the code on 2026-10-21)

## Context

The owner wanted to swap the focused tile with a key they can change.
Omarchy has no plugin key-binding API, and writing to the user's Hyprland
config would change files outside the plugin.

## Decision

The service binds the widget's **Swap key** setting (default
`SUPER + SHIFT + S`) with `hyprctl eval 'hl.bind(…)'` to `omarchy-shell
pym.mosaic swap`, marked by its description. A key another bind uses
(`Model.bindConflict` over `hyprctl -j binds`) is refused, shown in the
panel and sent as a notification. It binds again on `configreloaded` and
unbinds on a setting change and when it goes away. An empty setting binds
nothing, for users who keep the bind in their own config.

## Consequences

Nothing is written to the user's config, and Mosaic never steals a key.
Test shells must set `swapKey: ""` or they bind and unbind a real key.

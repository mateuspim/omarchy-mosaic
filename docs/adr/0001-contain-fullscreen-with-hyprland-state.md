# 1. Contain fullscreen with Hyprland's `0/2` fullscreen state on tiled app windows

- Status: Accepted
- Date: 2026-09-27 (introduced in `55819bb`; documented from the code on 2026-10-21)

## Context

A video's fullscreen in a normal browser window makes the compositor grow
that window over the whole monitor, which breaks a wall of several streams.
This is the problem the project exists for ([project brief](../project.md)).
Three approaches were tried before the plugin existed: plain Chromium
`--app` windows (the video covered the monitor), embedded WebKitGTK views in
one window (worked with a local video, but crashed on video sites without
`gst-plugins-good` and had none of the user's logins), and floating windows
in a computed grid (hid Omarchy's swap bindings, and dragging one reset its
containment). The measurements are in
[architecture.md](../architecture.md#fullscreen-containment).

## Decision

Each tile is a Chromium-family `--app` window in the user's own browser
and profile, tiled by Hyprland. After moving it to its workspace, setting it
tiled and opaque, Mosaic applies `hl.dsp.window.fullscreen_state({ internal
= 0, client = 2 })` last: the browser believes it is fullscreen while the
compositor keeps the window at its tile size, so a page's
`requestFullscreen()` renders inside the tile. `contain` re-applies `0/2`
only to tagged tiles in the `uncontained` state; the optional **Keep
fullscreen in tiles** setting does so on its own (`Model.planAutoContain`).
Floating geometry stays rejected.

## Consequences

Tiles keep the user's logins, codecs and DRM, and Omarchy's own window
bindings keep working on them. Containment can be lost without an event (a
direct `fullscreen_state` change such as Super+Ctrl+F), so it needs a manual
or opt-in re-contain rather than a watcher. A floating tile's video covers
the monitor until it is tiled again. Any change to how tiles are launched or
tiled must re-run the containment check in the
[development runbook](../runbooks/development.md#containment-check).

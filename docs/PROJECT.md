# Project brief

## Problem

When a video is fullscreened in a normal browser window, the compositor can
make that window cover the monitor. That interrupts a multi-stream setup where
the user wants several web apps visible at once and wants fullscreen to apply
only to the selected app's region.

## Goal

Omarchy Mosaic launches and manages web apps, typically several Twitch, Kick,
and YouTube streams, as a monitor-aware mosaic on Omarchy. Video fullscreen
must stay bounded to the app's tile. The whole product is this Omarchy shell
plugin (`pym.mosaic`): a service that does the work and a bar widget panel
that is its keyboard-first UI. It needs no separate binary.

This repository replaces the earlier Rust CLI and its planned terminal UI
(`~/Projects/omarchy-mosaic-cli`). The bar panel is the UI for good.

## Intended users and platform

- Omarchy users running Linux with Wayland and Hyprland.
- People monitoring several live streams or other web apps at once.
- Keyboard users who want to add, remove, focus, and rearrange apps quickly.

## Requirements

1. Add web apps by URL or by installed web app name, and give each a useful
   display name.
2. Select a target monitor and inspect its current dimensions and orientation.
3. Offer practical layouts, including a single app, balanced grids, and a
   vertical stack. Reflow when app count or monitor geometry changes.
4. Keep each app's content, including video fullscreen, inside its assigned
   tile.
5. Fit tiles to available monitor space. Provide a 16:9 video-oriented option
   while handling unused space cleanly when the geometry does not match.
6. Make app focus, audio focus and muting, and session changes manageable from
   the keyboard.
7. Persist named sessions and user configuration without storing secrets.
8. Offer a scriptable command line (`mosaic`, over the shell's IPC) for
   keybindings and other tools.

The first milestone is parity with the Rust CLI. After that the scope is
intentionally broad; see `docs/ROADMAP.md`.

## Out of scope

- A general-purpose desktop or window manager.
- Replacing the user's browser for ordinary browsing.
- Cloud sync, accounts, or remote control.
- Promising DRM-protected playback on a site before its player has been
  checked.

## Product principles

- A stream wall should be understandable at a glance.
- Layouts should respond to actual monitor geometry, not assume landscape.
- Fullscreen containment is fundamental behavior, not a cosmetic enhancement.
- Hyprland is the source of truth. Mosaic tiles are ordinary windows, so
  Omarchy's own bindings keep working on them.
- Never block or crash the user's shell.

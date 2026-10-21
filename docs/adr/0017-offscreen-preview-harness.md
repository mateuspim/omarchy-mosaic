# 17. Check the panel and render the hero offscreen with a fake service

- Status: Accepted
- Date: 2026-10-21 (introduced in `52df3ca`; documented from the code on 2026-10-21)

## Context

The live install is a symlink to the checkout, so every saved file runs in
the user's shell; screenshots of the desktop capture personal content, and
a test service sees the live Hyprland (one harness once closed the user's
real browser).

## Decision

`tests/preview.sh` runs a copy of `Panel.qml` with Qt's offscreen
platform, the `KeyboardPanel` stand-in and `tests/offscreen/FakeService.qml`,
in a throwaway `HOME`, state and runtime directory, with Hyprland's
signature unset and the bridge socket pointed into it. It saves one PNG per
scene. The README hero's captures come from it.

## Consequences

Panel changes can be looked at without touching the desktop, and the hero
contains only sample data. The service itself is not exercised: engine
changes still need a throwaway `quickshell -n` instance (see the
[development runbook](../runbooks/development.md)).

# 11. Support only Chromium-family browsers, found the way Omarchy finds them

- Status: Accepted
- Date: 2026-09-27 (introduced in `55819bb`, `b7d94e0`; documented from the code on 2026-10-21)

## Context

Tiles need an app-mode window per URL, which Firefox lacks. The default
browser must be resolved the same way Omarchy's launchers do, and Omarchy
later began listing its `omarchy-browser.desktop` link wrapper as the
default.

## Decision

Only Chromium, Chrome, Brave, Edge, Opera, Vivaldi and Helium are
accepted (`Model.CHROMIUM_FAMILY`). The default comes from `xdg-settings get
default-web-browser` (then `xdg-mime`), run with `BROWSER` and
`XDG_CURRENT_DESKTOP` unset as `omarchy-cmd-default-browser` does, so the
wrapper never counts, and the program is that entry's `Exec`. The widget's
**Browser** setting overrides it. Launches go through `uwsm-app --`, with no
direct fallback.

## Consequences

A Firefox default fails with a clear message. The **Browser** setting is
also how tests point Mosaic at a throwaway profile.

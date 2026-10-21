# 7. One engine, in a host-created service; the panel is UI only

- Status: Accepted
- Date: 2026-09-27 (introduced in `904f875`; documented from the code on 2026-10-21)

## Context

The plugin is both a service and a bar widget. The engine (tile model,
store, launch sequence, IPC handler) must exist exactly once, survive the
widget being absent, and go away when the plugin is disabled or reloaded.
A `qmldir` singleton was tested in a throwaway shell and survives reloads
and disabling, which would leave its `IpcHandler` registered.

## Decision

`manifest.json` declares `kinds: ["service", "bar-widget"]`.
`MosaicService.qml` is the engine and holds the `IpcHandler`; it does not
set `keepLoaded`. `Panel.qml` finds it with
`bar.shell.serviceFor("pym.mosaic")`, holds it in a typed property that
resets to null when the service is destroyed, and looks again on a timer.
Pure logic lives in `Model.js` so Node can test it.

## Consequences

There are never two engines, IPC handlers or launch sequences, including
across reloads. Service changes may need `omarchy-restart-shell`, since a
plugin rescan was seen running the old service code. New components stay
inline in the file that uses them: a new sibling QML file was not found as a
type by the panel.

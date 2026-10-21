# Mosaic documentation

## Use Mosaic

- [README](../README.md): features, install and remove.
- [The panel](guide/panel.md): every key, adding tiles, web app buttons,
  and swapping a tile with the swap card.
- [Layouts](guide/layouts.md): a layout per workspace, and designing your
  own.
- [Saved sessions](guide/saved-sessions.md): keep a session and open it
  again, by key or at login.
- [Audio](guide/audio.md): per-tile mute and volume, and "only the focused
  tile plays".
- [Dropped streams](guide/dropped-streams.md): how a stalled stream is
  noticed and reloaded.
- [The browser extension](guide/browser-extension.md): what it is for, and
  setting it up.
- [Command line](guide/command-line.md): `mosaic` and
  `omarchy-shell pym.mosaic`.
- [How it works](guide/how-it-works.md): tags, `tiles.json`, fullscreen
  containment, compatibility with the old CLI.
- [Troubleshooting](runbooks/troubleshooting.md): symptom, cause, fix.
- [Security and privileges](../SECURITY.md): what it runs, reads and
  writes; the [2026-10-19 security review](security-review.md).
- [Brand assets](branding.md): icon, wordmarks, colours and README hero.

## Develop Mosaic

- [Project brief](project.md): the problem, goals, requirements and what is
  out of scope.
- [Architecture](architecture.md): components, data flow, and the evidence
  behind fullscreen containment, the extension, recovery and layouts.
- [Architecture decisions](adr/README.md): durable tradeoffs.
- [Specs](specs/): the [IPC and `mosaic` command](specs/ipc.md),
  [files and JSON formats](specs/files.md) (`tiles.json`, `list`,
  `webapps`, `layouts.json`, `saved.json`),
  [`layouts.lua` and custom layouts](specs/layouts.md), the
  [native-messaging protocol](specs/native-messaging.md), and
  [widget settings](specs/settings.md).
- [Roadmap](roadmap.md): what is done and what may come next.
- [Development runbook](runbooks/development.md): setup, tests, offscreen
  renders, throwaway shells, the containment check, refreshing the hero,
  releases.
- [Contributing](../CONTRIBUTING.md) and [agent instructions](../AGENTS.md).
- [Changelog](../CHANGELOG.md).

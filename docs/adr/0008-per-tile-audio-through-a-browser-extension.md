# 8. Control per-tile audio through a browser extension and a native host

- Status: Accepted
- Date: 2026-09-28 (introduced in `ffb0f98`; documented from the code on 2026-10-21)

## Context

Per-tile mute and volume need to know which audio belongs to which tile.
PipeWire can't tell: every `--app` window shares one browser process, and
Chromium plays every tab through one audio service process, so all streams
look identical (checked 2026-09-28). Separate browser instances per tile
would cost separate logins and memory; the owner chose an extension.

## Decision

`extension/` (Manifest V3 with a fixed `key`, so its ID is always
`ibcnbknhphdnlpfglnhelicnpnnmepbo`) talks through native messaging to
`bin/mosaic-native-host` (Python 3, standard library only), which relays to
a `SocketServer` in the service at `$XDG_RUNTIME_DIR/pym-mosaic.sock`. The
extension reports only app and popup windows and acts only on their tabs.
Its commands (mute, volume, navigate, reload, media, extensions) also carry
later features: in-place swaps and stream recovery. The protocol is in
[specs/native-messaging.md](../specs/native-messaging.md).

## Consequences

Audio, swap in place and recovery work without touching PipeWire. The
extension has broad permissions (`<all_urls>`, `scripting`), documented in
[SECURITY.md](../../SECURITY.md). Each extension change costs the user a
browser restart or a Reload on the extensions page
([ADR 10](0010-rename-the-extension-worker-on-every-change.md)).

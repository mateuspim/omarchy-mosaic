# 16. Detect dropped streams in the page and reload them with backoff

- Status: Accepted
- Date: 2026-10-15 (introduced in `8dec6c6`, `45d95a6`; documented from the code on 2026-10-21)

## Context

Twitch streams sometimes freeze or fail for good (the owner's report,
2026-10-07), and only a reload brings them back. The browser can see the
video; the shell cannot.

## Decision

The extension injects a watcher into each tile's main frame that reports
`playing`, `idle` or `dropped` with a reason (error, player overlay,
frozen, stopped, stuck, gone) after thresholds of 4, 12 or 20 s.
`Model.planRecovery` in the service reloads a dropped tile only on the sites
in **Stream recovery sites** (`twitch.tv, kick.com` by default): at once,
then after 30 s and 2 min, at most three tries in ten minutes, then
`stalled` until a hand reload. A tile that was fullscreen gets its `f`
pressed through Hyprland once its stream plays, only while its workspace is
shown, with focus and cursor put back.

## Consequences

Drops recover without the user, bounded so an offline channel can't
loop. A pause by media key or playerctl reads as the player's and is
reloaded too (accepted trade-off). Not checked on a real Twitch drop; see
[architecture.md](../architecture.md#stream-recovery).

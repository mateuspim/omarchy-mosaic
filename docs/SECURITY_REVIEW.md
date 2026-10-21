# Security review (2026-10-19)

Scope: `bin/mosaic`, `bin/mosaic-native-host`, `extension/`, `Model.js`,
`MosaicService.qml`, the manifest, and install instructions. This is a source
review and local test run, not a penetration test of Chromium, Hyprland, or
Omarchy. No third-party runtime package is bundled in this repository.

## Findings

| Severity | Finding | Disposition |
| --- | --- | --- |
| Medium | The native host read a frame body before rejecting a length over its 1 MiB limit. A malformed browser-side message could make the host wait for a huge body. | Fixed: reject the header immediately and close the port. Covered by a header-only input test. |
| Low | Extension **Turn off** unlinked the `pym.mosaic` native-host manifest even if another program had replaced that file since Mosaic setup. | Fixed: remove only when the file still equals Mosaic's manifest. Covered by a replacement test. |
| Informational | `tiles.json` and `saved.json` preserve full URLs, including query strings. A URL containing a token remains in those files and in command output. | Documented in the README. Avoid saving token-bearing URLs. Changing the format or removing query strings would break saved destinations and needs a separate product decision. |
| Informational | The extension requests access to all URLs so it can control user-selected web apps on arbitrary sites. It reports app-window tab metadata to the local shell. | Documented in the README. The worker limits commands to app or popup windows, and the native host allows only this extension ID. |
| Low | The service falls back to a predictable `/tmp/pym-mosaic.sock` if `$XDG_RUNTIME_DIR` is missing. That directory lacks the normal owner-only parent boundary. | Open for nonstandard launches. Omarchy's user session supplies `$XDG_RUNTIME_DIR`; keep the shell in that session. A future change should make the runtime directory mandatory, including a safe replacement for the login marker. |

## Boundaries checked

- `bin/mosaic` forwards quoted arguments to Omarchy IPC. Service process
  launches use argv lists. Hyprland Lua expressions validate window addresses
  as `0x` plus hex and session names as lowercase letters, digits, `-`, or
  `_` before interpolation.
- The browser extension has no outbound request to a Mosaic service. It reads
  app-window tabs, injects media and stream watchers into chosen app pages,
  and sends reports through Chromium native messaging to a Unix socket.
- The native host caps messages at 1 MiB in both directions. Its manifest
  accepts a single fixed extension ID. The service socket normally lives in
  the owner-only `$XDG_RUNTIME_DIR` (verified as mode `0700` on the review
  machine); the socket itself was mode `0755`, so the parent directory is the
  access boundary. A local process running as the same user can impersonate
  the extension over that socket, as it can also call the user's Omarchy IPC.
- Enabling the extension changes existing Chromium-family flags files and
  registers a native host under the user's browser config. No root privilege
  is requested. The optional save-as-web-app action runs Omarchy's installer
  for the selected site and asks it to fetch the site's icon.

## Verification

`npm test` passed (Model, layouts, and 13 native-host tests),
`omarchy plugin validate .` passed, and `git diff --check` passed. No live
browser profile or running tile was changed during this review.

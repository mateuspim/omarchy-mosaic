# 9. Load the extension from existing browser flags files

- Status: Accepted
- Date: 2026-09-28 (introduced in `ffb0f98`; documented from the code on 2026-10-21)

## Context

Browsers load an extension silently only by policy (root) or by command
line. Omarchy already loads its own extensions with `--load-extension=` in
`~/.config/<browser>-flags.conf`, which Arch's launchers read.

## Decision

**Enable** runs `mosaic-native-host setup DIR`: it adds the extension
folder to the last `--load-extension=` line of each flags file that already
exists (following symlinks, keeping the mode), and writes the native-host
manifest into each Chromium-family profile folder that exists. **Turn off**
(`remove`) undoes both and removes a host manifest only if it is still
Mosaic's. Nothing runs as root, and no new flags file is created.

## Consequences

Setup is one key plus a browser restart. Google Chrome ignores
`--load-extension` since version 137, so it needs Load unpacked; browsers
without a flags file too. Users should turn the extension off before
removing the plugin.

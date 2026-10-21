# 10. Rename the extension's worker script on every change

- Status: Accepted
- Date: 2026-09-28 (introduced in `0a4eaf2`; documented from the code on 2026-10-21)

## Context

After a browser restart, Brave reported a new manifest version while
still running its cached copy of the old worker script (pings answered,
`mute` ignored). An automatic `chrome.runtime.reload()` was tried and left
the worker stopped and disconnected.

## Decision

The worker file is named per change (`background-10.js` today), `hello`
reports the script's own name and a `features` list, and the service
compares the script with the manifest's `service_worker`
(`extensionOutdated`) and checks `Model.bridgeHas` before sending a command.
There is no reload message; the panel asks for a browser restart or, since
0.5.2, opens the extensions page where Reload loads the new worker.

## Consequences

Every extension change renames the worker, updates `manifest.json` and
`SCRIPT` together, and should bundle everything foreseeable, since each one
costs the user a reload or their tiles.

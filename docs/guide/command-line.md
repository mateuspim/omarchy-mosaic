# Command line

The plugin answers `omarchy-shell pym.mosaic <function>`; `bin/mosaic` in
this repository wraps that in the old `mosaic` command, with the same
arguments and output:

```bash
mosaic add --session streams twitch kick.com/somechannel
mosaic list            # or: mosaic list --json
mosaic remove 2
mosaic focus 1
mosaic close --session streams
mosaic contain
mosaic layout                          # workspaces' layouts and your own
mosaic layout --workspace 8 grid       # grid, stack, main, fit, yours, default
mosaic layout --session streams three  # the workspace the session is on
mosaic save streams                    # keep the session to open it later
mosaic restore streams                 # open its tiles that aren't open
mosaic saved           # or: mosaic saved --json
mosaic login streams on                # open it at login (or off)
mosaic forget streams
mosaic reload 2                        # reload a tile's page
mosaic save-app 3 "YouTube Music"      # save a tile as a web app
mosaic streams                         # each tile's stream, recent recoveries
mosaic webapps         # or: mosaic webapps --json
mosaic monitors
```

The list and web app JSON are the version 1 formats the CLI printed. To call
the plugin directly, pass every argument (`""` for none), with targets one
per line: `omarchy-shell pym.mosaic add $'twitch\nkick' streams "" ""`
answers `started N` right away, and `omarchy-shell pym.mosaic result N`
reports how it went.
